`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_fetch_error_timing;
  localparam int SCENARIO_NONE        = 0;
  localparam int SCENARIO_CONSECUTIVE = 1;
  localparam int SCENARIO_REDIRECT    = 2;
  localparam int SCENARIO_STALL       = 3;

  localparam logic [31:0] INVALID_PC = 32'h0000_0100;
  localparam logic [31:0] HANDLER_PC = 32'h0000_0080;
  localparam logic [31:0] REDIRECT_TARGET_PC = 32'h0000_0020;

  logic clk;
  logic rst_n;
  integer scenario_q;

  logic instr_ren;
  logic [31:0] instr_addr;
  logic [31:0] instr_rdata;
  logic instr_fetch_error;
  logic response_valid_q;
  logic [31:0] response_pc_q;

  logic data_req_valid;
  logic data_req_ready;
  core_bus_req_t data_req;
  logic data_rsp_valid;
  core_bus_rsp_t data_rsp;
  logic data_pending_q;
  integer data_delay_q;

  trap_entry_t trap_entry;
  commit_pkt_t commit;

  logic stall_error_hold_q;
  logic stall_error_armed_q;
  logic [31:0] stall_fault_pc_q;
  integer stall_hold_cycles_q;
  logic stall_fault_packet_seen_q;

  logic redirect_error_presented_q;
  integer trap_count_q;
  integer handler_commit_count_q;
  integer redirect_target_commit_count_q;
  logic test_pass;

  id_ex_pkt_t expected_fault_pkt;

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  riscv dut (
    .clk_i               (clk),
    .rst_ni              (rst_n),
    .instr_ren_o         (instr_ren),
    .instr_addr_o        (instr_addr),
    .instr_rdata_i       (instr_rdata),
    .instr_fetch_error_i (instr_fetch_error),
    .data_req_valid_o    (data_req_valid),
    .data_req_ready_i    (data_req_ready),
    .data_req_o          (data_req),
    .data_rsp_valid_i    (data_rsp_valid),
    .data_rsp_i          (data_rsp),
    .irq_mti_i           (1'b0),
    .wfi_wait_o          (),
    .trap_entry_o        (trap_entry),
    .dbg_x3_o            (),
    .dbg_x10_o           (),
    .dbg_x11_o           (),
    .illegal_instr_o     (),
    .exception_o         (),
    .commit_o            (commit)
  );

  function automatic logic [31:0] instruction_at(
    input integer scenario,
    input logic [31:0] addr
  );
    begin
      instruction_at = 32'h0000_0013; // nop
      case (scenario)
        SCENARIO_CONSECUTIVE: begin
          case (addr)
            32'h0000_0000: instruction_at = 32'h0800_0093; // addi x1,x0,0x80
            32'h0000_0004: instruction_at = 32'h3050_9073; // csrw mtvec,x1
            32'h0000_0008: instruction_at = 32'h1000_0113; // addi x2,x0,0x100
            32'h0000_000c: instruction_at = 32'h0001_0067; // jalr x0,0(x2)
            default: begin
              if (addr >= INVALID_PC)
                instruction_at = 32'h0231_40b3; // DIV replacement data
            end
          endcase
        end

        SCENARIO_REDIRECT: begin
          case (addr)
            32'h0000_0000: instruction_at = 32'h0200_0063; // beq x0,x0,+0x20
            32'h0000_0004,
            32'h0000_0008,
            32'h0000_000c,
            32'h0000_0010,
            32'h0000_0014,
            32'h0000_0018,
            32'h0000_001c: instruction_at = 32'h0013_8393; // addi x7,x7,1
            32'h0000_0020: instruction_at = 32'h0010_0293; // addi x5,x0,1
            default: ;
          endcase
        end

        SCENARIO_STALL: begin
          case (addr)
            32'h0000_0000: instruction_at = 32'h0800_0093; // addi x1,x0,0x80
            32'h0000_0004: instruction_at = 32'h3050_9073; // csrw mtvec,x1
            32'h0000_0008: instruction_at = 32'h0000_2183; // lw x3,0(x0)
            default: ;
          endcase
        end

        default: ;
      endcase
    end
  endfunction

  // Model the fixed one-cycle instruction response assumed by the core.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      response_valid_q <= 1'b0;
      response_pc_q    <= '0;
    end else if (instr_ren) begin
      // Like prog_ram, retain the registered response while ren is low.
      response_valid_q <= 1'b1;
      response_pc_q    <= instr_addr;
    end
  end

  always_comb begin
    instr_rdata = instruction_at(scenario_q, response_pc_q);
    instr_fetch_error = 1'b0;
    case (scenario_q)
      SCENARIO_CONSECUTIVE:
        instr_fetch_error = response_valid_q && response_pc_q >= INVALID_PC;
      SCENARIO_REDIRECT:
        // Exercise both the immediate redirect flush and its delayed fetch kill.
        instr_fetch_error = response_valid_q &&
                            (dut.ex_redirect_en || dut.u_core_ctrl.fetch_kill_q);
      SCENARIO_STALL:
        instr_fetch_error = response_valid_q && stall_error_hold_q;
      default:
        instr_fetch_error = 1'b0;
    endcase
  end

  // Accept the load immediately, then delay its response long enough to hold
  // ID/EX and IF/ID while an errored instruction response is presented.
  assign data_req_ready = 1'b1;
  assign data_rsp_valid = data_pending_q && data_delay_q == 0;
  always_comb begin
    data_rsp = '0;
    data_rsp.rdata = 32'ha5a5_5a5a;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_pending_q <= 1'b0;
      data_delay_q   <= 0;
    end else begin
      if (data_req_valid && data_req_ready) begin
        assert (!data_pending_q)
          else $fatal(1, "core issued more than one outstanding data request");
        data_pending_q <= 1'b1;
        data_delay_q   <= 4;
      end else if (data_pending_q && data_delay_q != 0) begin
        data_delay_q <= data_delay_q - 1;
      end

      if (data_rsp_valid)
        data_pending_q <= 1'b0;
    end
  end

  // Hold one error response throughout the LSU stall and release it only after
  // IF/ID can capture it. The response PC must remain paired with the error.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      stall_error_hold_q    <= 1'b0;
      stall_error_armed_q   <= 1'b0;
      stall_fault_pc_q      <= '0;
      stall_hold_cycles_q   <= 0;
    end else if (scenario_q == SCENARIO_STALL) begin
      if (!stall_error_armed_q && dut.lsu_busy) begin
        stall_error_hold_q  <= 1'b1;
        stall_error_armed_q <= 1'b1;
        stall_fault_pc_q    <= response_pc_q;
      end else if (stall_error_hold_q && !dut.u_core_ctrl.ifid_stall) begin
        stall_error_hold_q <= 1'b0;
      end

      if (stall_error_hold_q && dut.u_core_ctrl.ifid_stall)
        stall_hold_cycles_q <= stall_hold_cycles_q + 1;
    end else begin
      stall_error_hold_q  <= 1'b0;
      stall_error_armed_q <= 1'b0;
      stall_hold_cycles_q <= 0;
    end
  end

  always_comb begin
    expected_fault_pkt = ID_EX_PKT_BUBBLE;
    expected_fault_pkt.valid = 1'b1;
    expected_fault_pkt.pc = dut.id2ex_pkt_out.pc;
    expected_fault_pkt.exc.instr_access_fault = 1'b1;
  end

  // Architectural and microarchitectural scoreboards shared by the scenarios.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      redirect_error_presented_q    <= 1'b0;
      trap_count_q                   <= 0;
      handler_commit_count_q         <= 0;
      redirect_target_commit_count_q <= 0;
      stall_fault_packet_seen_q      <= 1'b0;
    end else begin
      if (scenario_q == SCENARIO_REDIRECT && instr_fetch_error)
        redirect_error_presented_q <= 1'b1;

      if (trap_entry.valid) begin
        trap_count_q <= trap_count_q + 1;
        assert (!trap_entry.interrupt &&
                trap_entry.cause == MCAUSE_INST_ACCESS)
          else $fatal(1, "fetch corner produced wrong trap type/cause");
        if (scenario_q == SCENARIO_CONSECUTIVE) begin
          assert (trap_entry.pc == INVALID_PC &&
                  trap_entry.tval == INVALID_PC)
            else $fatal(1, "consecutive fetch fault reported wrong PC/value");
        end else if (scenario_q == SCENARIO_STALL) begin
          assert (trap_entry.pc == stall_fault_pc_q &&
                  trap_entry.tval == stall_fault_pc_q)
            else $fatal(1, "stalled fetch fault lost its response PC pairing");
        end else begin
          $fatal(1, "stale redirected fetch response generated a trap");
        end
      end

      if (commit.valid) begin
        if (commit.trap) begin
          assert (!commit.rd_we && !commit.mem_valid &&
                  commit.trap_cause == MCAUSE_INST_ACCESS)
            else $fatal(1, "fetch fault retained a normal commit side effect");
        end

        if (commit.pc >= HANDLER_PC && commit.pc < INVALID_PC)
          handler_commit_count_q <= handler_commit_count_q + 1;

        if (scenario_q == SCENARIO_REDIRECT) begin
          assert (!(commit.pc >= 32'h0000_0004 &&
                    commit.pc < REDIRECT_TARGET_PC))
            else $fatal(1, "wrong-path instruction committed after redirect");
          if (commit.pc >= REDIRECT_TARGET_PC)
            redirect_target_commit_count_q <=
                redirect_target_commit_count_q + 1;
        end
      end

      if (scenario_q == SCENARIO_STALL &&
          dut.if2id_pkt_out.valid && dut.if2id_pkt_out.error) begin
        stall_fault_packet_seen_q <= 1'b1;
        assert (dut.if2id_pkt_out.pc == stall_fault_pc_q)
          else $fatal(1, "IF/ID fetch error lost its held response PC");
      end
    end
  end

  // Check the canonical fault-only packet after clocked pipeline state settles.
  always @(negedge clk) begin
    if (rst_n && stall_error_hold_q && dut.u_core_ctrl.ifid_stall) begin
      assert (response_pc_q == stall_fault_pc_q)
        else $fatal(1, "instruction response PC changed while fetch error was stalled");
    end
    if (rst_n && dut.id2ex_pkt_out.valid &&
        dut.id2ex_pkt_out.exc.instr_access_fault) begin
      assert (dut.id2ex_pkt_out === expected_fault_pkt)
        else $fatal(1, "fetch error entered ID/EX with non-canonical controls");
    end
  end

  task automatic start_scenario(input integer scenario);
    begin
      @(negedge clk);
      rst_n = 1'b0;
      scenario_q = scenario;
      repeat (4) @(posedge clk);
      @(negedge clk);
      rst_n = 1'b1;
    end
  endtask

  task automatic check_fetch_fault_csrs(input logic [31:0] expected_pc);
    begin
      assert (dut.csr_mepc == expected_pc)
        else $fatal(1, "fetch fault wrote the wrong mepc");
      assert (dut.u_csr_regfile.mcause_q == MCAUSE_INST_ACCESS)
        else $fatal(1, "fetch fault wrote the wrong mcause");
      assert (dut.u_csr_regfile.mtval_q == expected_pc)
        else $fatal(1, "fetch fault wrote the wrong mtval");
    end
  endtask

  task automatic run_redirect_case;
    integer cycles;
    begin
      start_scenario(SCENARIO_REDIRECT);
      for (cycles = 0;
           cycles < 100 && redirect_target_commit_count_q < 4;
           cycles = cycles + 1)
        @(negedge clk);
      assert (redirect_error_presented_q)
        else $fatal(1, "redirect case never presented a stale error response");
      assert (redirect_target_commit_count_q >= 4 && trap_count_q == 0)
        else $fatal(1, "redirect case did not reach target cleanly");
      $display("[FETCH-ERROR-TIMING-TB] redirect stale-response: PASS");
    end
  endtask

  task automatic run_consecutive_case;
    integer cycles;
    begin
      start_scenario(SCENARIO_CONSECUTIVE);
      for (cycles = 0;
           cycles < 200 && (trap_count_q < 1 || handler_commit_count_q < 4);
           cycles = cycles + 1)
        @(negedge clk);
      assert (trap_count_q == 1 && handler_commit_count_q >= 4)
        else $fatal(1, "consecutive invalid fetches did not produce one precise trap");
      check_fetch_fault_csrs(INVALID_PC);
      repeat (12) @(negedge clk);
      assert (trap_count_q == 1)
        else $fatal(1, "younger consecutive invalid response trapped twice");
      $display("[FETCH-ERROR-TIMING-TB] consecutive invalid fetches: PASS");
    end
  endtask

  task automatic run_stall_case;
    integer cycles;
    begin
      start_scenario(SCENARIO_STALL);
      for (cycles = 0;
           cycles < 200 && (trap_count_q < 1 || handler_commit_count_q < 4);
           cycles = cycles + 1)
        @(negedge clk);
      assert (stall_error_armed_q && stall_hold_cycles_q >= 2)
        else $fatal(1, "fetch error did not overlap a sustained LSU stall");
      assert (stall_fault_packet_seen_q)
        else $fatal(1, "held fetch error never entered IF/ID after stall release");
      assert (trap_count_q == 1 && handler_commit_count_q >= 4)
        else $fatal(1, "stalled fetch error did not produce one precise trap");
      check_fetch_fault_csrs(stall_fault_pc_q);
      repeat (12) @(negedge clk);
      assert (trap_count_q == 1)
        else $fatal(1, "stalled fetch error trapped more than once");
      $display("[FETCH-ERROR-TIMING-TB] fault during LSU stall: PASS");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    scenario_q = SCENARIO_NONE;
    test_pass = 1'b0;
    run_redirect_case();
    run_consecutive_case();
    run_stall_case();
    test_pass = 1'b1;
    $display("[FETCH-ERROR-TIMING-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
