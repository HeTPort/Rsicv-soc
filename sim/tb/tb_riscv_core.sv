`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: tb_riscv
// Description:
//   Simple top-level testbench for the reconstructed RV32IM CPU.
// ============================================================
module tb_riscv_core #(
  parameter string PROGRAM_FILE = "../testdata/prog.hex",
  parameter string DATA_FILE = "",
  parameter bit TRACE_ENABLE = 1'b0,
  parameter bit DUMP_WAVES = 1'b0,
  parameter int TIMEOUT_CYCLES = 20000,
  parameter logic [31:0] TOHOST_ADDR = 32'h0000_1000,
  parameter int PROG_RAM_DEPTH = 4096,
  parameter int DATA_RAM_DEPTH = 4096,
  parameter int DATA_REQ_WAIT_CYCLES = 0,
  parameter int DATA_RSP_WAIT_CYCLES = 0
);
  localparam int AW = 32;
  localparam int DW = 32;
  localparam int CLK_PERIOD_NS = 10;

  // ------------------------------------------------------------
  // Clock / reset
  // ------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS / 2) clk = ~clk;
  end
  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  // ------------------------------------------------------------
  // Instruction interface between CPU and prog_ram
  // ------------------------------------------------------------
  logic          instr_ren;
  logic [AW-1:0] instr_addr;
  logic [DW-1:0] instr_rdata;
  logic          data_req_valid;
  logic          data_req_ready;
  core_bus_req_t data_req;
  logic          data_rsp_valid;
  core_bus_rsp_t data_rsp;

  // ------------------------------------------------------------
  // Debug outputs
  // ------------------------------------------------------------
  logic [DW-1:0] dbg_x3;
  logic [DW-1:0] dbg_x10;
  logic [DW-1:0] dbg_x11;
  logic halt;
  logic illegal_instr;
  logic exception;
  commit_pkt_t commit;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv #(
    .AW(AW),
    .DW(DW)
  ) u_riscv (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .instr_ren_o     (instr_ren),
    .instr_addr_o    (instr_addr),
    .instr_rdata_i   (instr_rdata),
    .data_req_valid_o(data_req_valid),
    .data_req_ready_i(data_req_ready),
    .data_req_o      (data_req),
    .data_rsp_valid_i(data_rsp_valid),
    .data_rsp_i      (data_rsp),
    .dbg_x3_o        (dbg_x3),
    .dbg_x10_o       (dbg_x10),
    .dbg_x11_o       (dbg_x11),
    .halt_o          (halt),
    .illegal_instr_o (illegal_instr),
    .exception_o     (exception),
    .commit_o        (commit)
  );

  // ------------------------------------------------------------
  // Program RAM
  // ------------------------------------------------------------
  prog_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(PROG_RAM_DEPTH),
    .FILE(PROGRAM_FILE),
    .INVALID_RDATA(32'h0010_0073) // ebreak on invalid fetch
  ) u_prog_ram (
    .clk_i        (clk),
    .ren_i        (instr_ren),
    .instr_addr_i (instr_addr),
    .instr_data_o (instr_rdata),
    .wen_i        (1'b0),
    .waddr_i      ('0),
    .wdata_i      ('0)
  );

  // ------------------------------------------------------------
  // Data target outside the CPU boundary
  // ------------------------------------------------------------
  core_bus_data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DATA_RAM_DEPTH),
    .INIT_FILE(DATA_FILE),
    .REQ_WAIT_CYCLES(DATA_REQ_WAIT_CYCLES),
    .RSP_WAIT_CYCLES(DATA_RSP_WAIT_CYCLES)
  ) u_data_target (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .req_valid_i (data_req_valid),
    .req_ready_o (data_req_ready),
    .req_i       (data_req),
    .rsp_valid_o (data_rsp_valid),
    .rsp_o       (data_rsp)
  );

  // ------------------------------------------------------------
  // Wave dump
  // ------------------------------------------------------------
  initial begin
    if (DUMP_WAVES) begin
      $dumpfile("tb_riscv.vcd");
      $dumpvars(0, tb_riscv_core);
    end
  end

  // ------------------------------------------------------------
  // Timeout watchdog
  // ------------------------------------------------------------
  integer cycle_count;
  logic [63:0] expected_commit_order;
  integer accepted_request_count;
  integer response_count;
  integer memory_commit_count;
  logic data_outstanding;
  logic data_req_stalled_q;
  core_bus_req_t stalled_data_req_q;
  core_bus_req_t accepted_data_req_q;
  core_bus_req_t completed_data_req_q;
  initial begin
    #1ns;
    $display("[TB] Check program RAM content");
    $display("[TB] u_prog_ram.mem[0] = 0x%08h", u_prog_ram.mem[0]);
    $display("[TB] u_prog_ram.mem[1] = 0x%08h", u_prog_ram.mem[1]);
    $display("[TB] u_prog_ram.mem[2] = 0x%08h", u_prog_ram.mem[2]);
    $display("[TB] u_prog_ram.mem[3] = 0x%08h", u_prog_ram.mem[3]);
    $display("[TB] u_prog_ram.mem[4] = 0x%08h", u_prog_ram.mem[4]);
    $display("[TB] u_prog_ram.mem[5] = 0x%08h", u_prog_ram.mem[5]);
    $display("[TB] u_prog_ram.mem[6] = 0x%08h", u_prog_ram.mem[6]);
    $display("[TB] u_prog_ram.mem[7] = 0x%08h", u_prog_ram.mem[7]);
    $display("[TB] u_prog_ram.mem[253] = 0x%08h", u_prog_ram.mem[253]);
  end

  // ------------------------------------------------------------
  // Architectural commit interface checks
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      expected_commit_order <= '0;
    end else if (commit.valid) begin
      assert (commit.order == expected_commit_order)
        else $fatal(1, "Commit order mismatch: got=%0d expected=%0d",
                    commit.order, expected_commit_order);
      assert (commit.pc[1:0] == 2'b00)
        else $fatal(1, "Committed PC is misaligned: pc=0x%08h", commit.pc);
      assert (!commit.rd_we || (commit.rd_addr != 5'd0))
        else $fatal(1, "Commit interface attempted to write x0");
      assert (!commit.trap || !commit.rd_we)
        else $fatal(1, "Trapping instruction reported a register write");
      assert (!commit.mem_we || (commit.mem_wmask != '0))
        else $fatal(1, "Committed store has an empty write mask");
      assert (!commit.mem_valid || commit.mem_we || (commit.mem_rmask != '0))
        else $fatal(1, "Committed load has an empty read mask");
      assert (!(commit.mem_rmask != '0 && commit.mem_wmask != '0))
        else $fatal(1, "Commit record reports a simultaneous load and store");

      expected_commit_order <= expected_commit_order + 64'd1;

      if (TRACE_ENABLE) begin
        $display("[COMMIT] order=%0d pc=0x%08h instr=0x%08h rd_we=%0b rd=%0d data=0x%08h mem=%0b/%0b addr=0x%08h trap=%0b cause=0x%08h",
                 commit.order, commit.pc, commit.instr,
                 commit.rd_we, commit.rd_addr, commit.rd_data,
                 commit.mem_valid, commit.mem_we, commit.mem_addr,
                 commit.trap, commit.trap_cause);
      end
    end
  end

  // ------------------------------------------------------------
  // Data-bus protocol and exactly-once memory retirement checks
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accepted_request_count <= 0;
      response_count         <= 0;
      memory_commit_count    <= 0;
      data_outstanding       <= 1'b0;
      data_req_stalled_q     <= 1'b0;
      stalled_data_req_q     <= '0;
      accepted_data_req_q    <= '0;
      completed_data_req_q   <= '0;
    end else begin
      if (data_req_stalled_q && data_req_valid) begin
        assert (data_req === stalled_data_req_q)
          else $fatal(1, "Data request payload changed under back-pressure");
      end

      if (data_req_valid && data_req_ready) begin
        assert (!data_outstanding)
          else $fatal(1, "A second data request was accepted while one was outstanding");
        data_outstanding       <= 1'b1;
        accepted_request_count <= accepted_request_count + 1;
        accepted_data_req_q    <= data_req;
      end

      if (data_rsp_valid) begin
        assert (data_outstanding)
          else $fatal(1, "Data response arrived without an accepted request");
        data_outstanding    <= 1'b0;
        response_count      <= response_count + 1;
        completed_data_req_q <= accepted_data_req_q;
      end

      if (commit.valid && commit.mem_valid) begin
        assert (response_count > memory_commit_count)
          else $fatal(1, "Memory instruction retired without an unmatched response");
        assert (commit.mem_we == completed_data_req_q.write &&
                commit.mem_addr == completed_data_req_q.addr)
          else $fatal(1, "Retired memory operation does not match its completed request");
        if (commit.mem_we) begin
          assert (commit.mem_wmask == completed_data_req_q.wstrb &&
                  commit.mem_wdata == completed_data_req_q.wdata)
            else $fatal(1, "Retired store payload does not match its completed request");
        end
        memory_commit_count <= memory_commit_count + 1;
      end

      data_req_stalled_q <= data_req_valid && !data_req_ready;
      if (data_req_valid && !data_req_ready)
        stalled_data_req_q <= data_req;
    end
  end
  initial begin
    cycle_count = 0;
    wait (rst_n == 1'b1);
    forever begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("============================================================");
        $display("[TB] TIMEOUT");
        $display("[TB] cycle     = %0d", cycle_count);
        $display("[TB] instr_addr= 0x%08h", instr_addr);
        $display("[TB] dbg_x3    = 0x%08h", dbg_x3);
        $display("[TB] dbg_x10   = 0x%08h", dbg_x10);
        $display("[TB] dbg_x11   = 0x%08h", dbg_x11);
        $display("============================================================");
        $fatal(1, "[TB] Simulation timeout");
      end
    end
  end

  // ------------------------------------------------------------
  // Memory-mapped tohost exit monitor (standard RISC-V test convention)
  // ------------------------------------------------------------
  logic [DW-1:0] tohost_val;
  logic          tohost_seen;



  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tohost_val <= '0;
      tohost_seen <= 1'b0;
    end else begin
      if (commit.valid && commit.mem_valid && commit.mem_we &&
          (commit.mem_addr == TOHOST_ADDR)) begin
        tohost_val  <= commit.mem_wdata;
        tohost_seen <= 1'b1;
      end
    end
  end

  // ------------------------------------------------------------
  // Finish on tohost write
  // ------------------------------------------------------------
  initial begin
    wait (rst_n == 1'b1);
    wait (tohost_seen == 1'b1);
    repeat (2) @(posedge clk);
    assert (!data_outstanding)
      else $fatal(1, "Test ended with an outstanding data transaction");
    assert (accepted_request_count == response_count)
      else $fatal(1, "Accepted/response count mismatch: %0d/%0d",
                  accepted_request_count, response_count);
    assert (response_count == memory_commit_count)
      else $fatal(1, "Response/memory-commit count mismatch: %0d/%0d",
                  response_count, memory_commit_count);
    $display("============================================================");
    $display("[TB] tohost write detected");
    $display("[TB] cycle          = %0d", cycle_count);
    $display("[TB] instr_addr     = 0x%08h", instr_addr);
    $display("[TB] dbg_x3         = 0x%08h", dbg_x3);
    $display("[TB] dbg_x10        = 0x%08h", dbg_x10);
    $display("[TB] dbg_x11        = 0x%08h", dbg_x11);
    $display("[TB] illegal_instr  = %0b", illegal_instr);
    $display("[TB] exception      = %0b", exception);
    $display("[TB] tohost         = 0x%08h", tohost_val);

    if (tohost_val == 32'd1) begin
      $display("[TB] RESULT: PASS");
      $display("============================================================");
      $finish;
    end
    else begin
      $display("[TB] RESULT: FAIL");
      $display("[TB] Failure code in tohost = %0d / 0x%08h", tohost_val, tohost_val);
      $display("============================================================");
      $fatal(1, "[TB] RV32IM test failed");
    end
  end

  // ------------------------------------------------------------
  // Optional monitor
  // ------------------------------------------------------------
`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (illegal_instr) begin
        $display("[TB] illegal instruction pulse detected");
      end
      if (exception) begin
        $display("[TB] exception pulse detected");
      end
    end
  end
`endif

  // ------------------------------------------------------------
  // WB Monitor (Updated for struct hierarchy)
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n && TRACE_ENABLE) begin
      $display("[WBPATH] cycle=%0d | ex2wb_in: valid=%0b we=%0b rd=%0d sel=%0d alu=0x%08h | ex2wb_out: valid=%0b we=%0b rd=%0d sel=%0d alu=0x%08h | final_wb: wen=%0b rd=%0d wdata=0x%08h",
               cycle_count,
               u_riscv.ex2wb_pkt_in.valid,
               u_riscv.ex2wb_pkt_in.rf.we,
               u_riscv.ex2wb_pkt_in.rf.addr,
               u_riscv.ex2wb_pkt_in.wb_sel,
               u_riscv.ex2wb_pkt_in.alu_data,
               u_riscv.ex2wb_pkt_out.valid,
               u_riscv.ex2wb_pkt_out.rf.we,
               u_riscv.ex2wb_pkt_out.rf.addr,
               u_riscv.ex2wb_pkt_out.wb_sel,
               u_riscv.ex2wb_pkt_out.alu_data,
               u_riscv.wb_rf_wen,
               u_riscv.wb_rf_waddr,
               u_riscv.wb_rf_wdata);
    end
  end

  // ------------------------------------------------------------
  // ID/EX Monitor (Updated for struct hierarchy)
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n && TRACE_ENABLE) begin
      // 监控 ID 级输出 (即 id2ex 寄存器的输入)
      if (u_riscv.id2ex_pkt.valid) begin
        $display("[ID] cycle=%0d pc=0x%08h instr=0x%08h rd=%0d rf_we=%0b illegal=%0b ebreak=%0b",
                 cycle_count,
                 u_riscv.id2ex_pkt.pc,
                 u_riscv.id2ex_pkt.instr,
                 u_riscv.id2ex_pkt.rf.addr,
                 u_riscv.id2ex_pkt.rf.we,
                 u_riscv.id2ex_pkt.exc.illegal_instr,
                 u_riscv.id2ex_pkt.exc.ebreak);
      end
      // 监控 EX 级输入 (即 id2ex 寄存器的输出)
      if (u_riscv.id2ex_pkt_out.valid) begin
        $display("[EX] cycle=%0d pc=0x%08h instr=0x%08h rd=%0d rf_we=%0b illegal=%0b ebreak=%0b",
                 cycle_count,
                 u_riscv.id2ex_pkt_out.pc,
                 u_riscv.id2ex_pkt_out.instr,
                 u_riscv.id2ex_pkt_out.rf.addr,
                 u_riscv.id2ex_pkt_out.rf.we,
                 u_riscv.id2ex_pkt_out.exc.illegal_instr,
                 u_riscv.id2ex_pkt_out.exc.ebreak);
      end
    end
  end

  // ------------------------------------------------------------
  // Instruction-memory request/response timing
  // ------------------------------------------------------------
  logic          fetch_req_valid_q;
  logic [AW-1:0] fetch_req_addr_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fetch_req_valid_q <= 1'b0;
      fetch_req_addr_q  <= '0;
    end else begin
      fetch_req_valid_q <= instr_ren;
      if (instr_ren)
        fetch_req_addr_q <= instr_addr;
    end
  end

  // A request accepted at a rising edge must drive the corresponding clocked
  // BRAM response after that edge. This assertion is intentionally independent
  // of the CPU's response tag so it detects an asynchronous/live-address RAM.
  always @(negedge clk) begin
    if (rst_n && fetch_req_valid_q) begin
      assert (instr_rdata === u_prog_ram.mem[fetch_req_addr_q[31:2]])
        else $error("Fetch response mismatch: request_pc=%08h response=%08h expected=%08h",
                    fetch_req_addr_q,
                    instr_rdata,
                    u_prog_ram.mem[fetch_req_addr_q[31:2]]);
    end
  end

  // ------------------------------------------------------------
  // Final IF/ID PC/instruction pairing
  // ------------------------------------------------------------
  always @(posedge clk) begin
    #1ps;
    if (rst_n && u_riscv.if2id_pkt_out.valid) begin
      assert (u_riscv.if2id_pkt_out.instr[31:0] === u_prog_ram.mem[u_riscv.if2id_pkt_out.pc[31:2]])
        else $error("ID PC/INSTR mismatch: pc=%08h instr=%08h expected=%08h",
                     u_riscv.if2id_pkt_out.pc,
                     u_riscv.if2id_pkt_out.instr[31:0],
                     u_prog_ram.mem[u_riscv.if2id_pkt_out.pc[31:2]]);
    end
  end

  // ------------------------------------------------------------
  // IF Monitor
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n && instr_ren && TRACE_ENABLE) begin
      $display("[IF] cycle=%0d pc=0x%08h instr=0x%08h",
               cycle_count, instr_addr, instr_rdata);
    end
  end

  // ------------------------------------------------------------
  // >>> 新增：Core Ctrl Monitor (用于观测抽离出的控制信号) <<<
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // 只有当控制信号有效（非全0）时才打印，避免刷屏
      if (TRACE_ENABLE && (u_riscv.u_core_ctrl.pc_stall || u_riscv.u_core_ctrl.ifid_flush ||
          u_riscv.u_core_ctrl.idex_flush || u_riscv.u_core_ctrl.pipe_kill)) begin
        $display("[CTRL ] cycle=%0d | stall: pc=%0b ifid=%0b idex=%0b | flush: ifid=%0b idex=%0b | kill=%0b",
                 cycle_count,
                 u_riscv.u_core_ctrl.pc_stall,
                 u_riscv.u_core_ctrl.ifid_stall,
                 u_riscv.u_core_ctrl.idex_stall,
                 u_riscv.u_core_ctrl.ifid_flush,
                 u_riscv.u_core_ctrl.idex_flush,
                 u_riscv.u_core_ctrl.pipe_kill);
      end
    end
  end

endmodule
`default_nettype wire
