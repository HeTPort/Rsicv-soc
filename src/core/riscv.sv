<<<<<<< Updated upstream
`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

module riscv #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  output logic          instr_ren_o,
  output logic [AW-1:0] instr_addr_o,
  input  logic [DW-1:0] instr_rdata_i,
  input  logic          instr_fetch_error_i,
  output logic          data_req_valid_o,
  input  logic          data_req_ready_i,
  output core_bus_req_t data_req_o,
  input  logic          data_rsp_valid_i,
  input  core_bus_rsp_t data_rsp_i,
  output logic [DW-1:0] dbg_x3_o,
  output logic [DW-1:0] dbg_x10_o,
  output logic [DW-1:0] dbg_x11_o,
  output logic          halt_o,
  output logic          illegal_instr_o,
  output logic          exception_o,
  output commit_pkt_t   commit_o
);
  initial begin
    if (DW != 32) begin
      $fatal(1, "Current core supports only RV32. RV64 is reserved for future extension.");
    end
  end

  // ============================================================
  // 1. Pipeline Payload Structures (Vertical Data Flow)
  // ============================================================
  fetch_pkt_t if2id_pkt, if2id_pkt_out;
  id_ex_pkt_t id2ex_pkt, id2ex_pkt_out;
  ex_wb_pkt_t ex2wb_pkt_in, ex2wb_pkt_in_safe, ex2wb_pkt_out;

  // ============================================================
  // 2. Horizontal Control & Bus Signals
  // ============================================================
  logic [AW-1:0] if_pc;
  logic [AW-1:0] if_resp_pc_q;
  logic          if_resp_valid_q;

  // Regfile interface
  logic [4:0]    id_rs1_raddr;
  logic [4:0]    id_rs2_raddr;
  logic [DW-1:0] id_rs1_rdata;
  logic [DW-1:0] id_rs2_rdata;
  logic          wb_rf_wen;
  logic          wb_rf_wen_safe;
  logic [4:0]    wb_rf_waddr;
  logic [DW-1:0] wb_rf_wdata;

  // EX outputs
  logic          ex_redirect_en;
  logic [AW-1:0] ex_redirect_pc;
  logic          ex_flush_req;

  // CSR interface
  logic [DW-1:0] csr_rdata;
  logic [DW-1:0] csr_rdata_for_ex;
  logic          csr_implemented;
  logic          csr_read_only;
  logic          csr_privilege_ok;
  logic [AW-1:0] csr_mtvec;
  logic [AW-1:0] csr_mepc;
  logic [DW-1:0] csr_mstatus;
  logic [DW-1:0] csr_mie;
  logic [DW-1:0] csr_mip;

  // Trap / mret controls
  logic          wb_trap_event;
  logic          wb_mret_event;
  logic          trap_redirect_en;
  logic [AW-1:0] trap_redirect_pc;
  logic          pc_redirect_en;
  logic [AW-1:0] pc_redirect_pc;

  // LSU <-> pipeline interface
  mem_pkt_t       lsu_mem_info;
  logic           lsu_mem_misaligned;
  logic [DW-1:0]  lsu_raw_rdata;
  logic [DW-1:0]  lsu_load_data;
  logic           lsu_load_fault;
  logic           lsu_store_fault;
  logic           lsu_busy;
  logic           lsu_complete;
  logic           ex_kill;
  logic           ex_mem_transaction;

  // Iterative divider <-> pipeline interface
  logic           ex_div_instruction;
  logic           div_start;
  logic           div_signed;
  logic           div_busy;
  logic           div_complete;
  logic           div_wait;
  logic           ex_wait;
  logic [DW-1:0]  div_quotient;
  logic [DW-1:0]  div_remainder;
  logic [DW-1:0]  div_result;

  // ============================================================
  // 3. Control Unit Interface Signals
  // ============================================================
  logic pc_stall, ifid_stall, idex_stall, exwb_stall;
  logic ifid_flush, idex_flush, pipe_kill;

  assign wb_trap_event = ex2wb_pkt_out.valid &&
      (ex2wb_pkt_out.exc.illegal_instr || ex2wb_pkt_out.exc.instr_access_fault ||
       ex2wb_pkt_out.exc.ecall ||
       ex2wb_pkt_out.exc.ebreak || ex2wb_pkt_out.instr_misaligned ||
       ex2wb_pkt_out.mem_misaligned || ex2wb_pkt_out.mem_error);
  assign wb_mret_event = ex2wb_pkt_out.valid && ex2wb_pkt_out.is_mret;

  assign trap_redirect_en = wb_trap_event;
  assign trap_redirect_pc = csr_mtvec;
  assign pc_redirect_en   = ex_redirect_en || trap_redirect_en;
  assign pc_redirect_pc   = trap_redirect_en ? trap_redirect_pc : ex_redirect_pc;

  // ============================================================
  // 4. Core Control Unit Instantiation
  // ============================================================
  core_ctrl u_core_ctrl (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .id_valid       (if2id_pkt_out.valid),
    .id_rs1_addr    (id_rs1_raddr),
    .id_rs2_addr    (id_rs2_raddr),
    .id_use_rs1     (id2ex_pkt.use_rs1),
    .id_use_rs2     (id2ex_pkt.use_rs2),
    .ex_valid       (id2ex_pkt_out.valid),
    .ex_rd_addr     (id2ex_pkt_out.rf.addr),
    .ex_rf_we       (id2ex_pkt_out.rf.we),
    .ex_mem_req     (id2ex_pkt_out.ex_ctrl.mem_req),
    .ex_mem_we      (id2ex_pkt_out.ex_ctrl.mem_we),
    .wb_valid       (ex2wb_pkt_out.valid),
    .wb_rd_addr     (ex2wb_pkt_out.rf.addr),
    .wb_rf_we       (ex2wb_pkt_out.rf.we),
    .ex_redirect_en (ex_redirect_en),
    .ex_flush_req   (ex_flush_req),
    .ex_wait_i      (ex_wait),
    .trap_redirect_en(trap_redirect_en),
    .wb_trap_event  (wb_trap_event),
    .pc_stall       (pc_stall),
    .ifid_stall     (ifid_stall),
    .idex_stall     (idex_stall),
    .exwb_stall     (exwb_stall),
    .ifid_flush     (ifid_flush),
    .idex_flush     (idex_flush),
    .pipe_kill      (pipe_kill)
  );

  assign halt_o          = 1'b0; // No longer halt; tests use tohost exit
  assign illegal_instr_o = ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.illegal_instr;
  assign exception_o     = wb_trap_event;

  // ============================================================
  // 4.5 CSR Register File
  // ============================================================
  logic wb_csr_we;
  logic [11:0] wb_csr_addr;
  logic [DW-1:0] wb_csr_wdata;
  logic [DW-1:0] wb_csr_wdata_effective;
  logic [AW-1:0] csr_mepc_for_ex;

  assign wb_csr_we    = ex2wb_pkt_out.valid &&
                        ex2wb_pkt_out.csr.valid &&
                        ex2wb_pkt_out.csr.write &&
                        !wb_trap_event;
  assign wb_csr_addr  = ex2wb_pkt_out.csr.addr;
  assign wb_csr_wdata = ex2wb_pkt_out.csr.wdata;
  // An adjacent CSR instruction in EX must observe the effective (WARL-filtered)
  // value written by the older CSR instruction in WB.
  assign csr_rdata_for_ex =
      (wb_csr_we && (wb_csr_addr == id2ex_pkt_out.csr.addr)) ?
      wb_csr_wdata_effective : csr_rdata;

  // MRET may immediately follow a write to mepc. Reuse the same effective
  // WB value so redirect generation cannot use stale or unaligned state.
  assign csr_mepc_for_ex =
      (wb_csr_we && (wb_csr_addr == CSR_MEPC)) ?
      AW'(wb_csr_wdata_effective) : csr_mepc;

  csr_regfile #(
    .AW(AW),
    .DW(DW)
  ) u_csr_regfile (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .current_priv_i(PRIV_MODE_M),
    // Read port (used in EX stage)
    .csr_addr_i   (id2ex_pkt_out.csr.addr),
    .csr_rdata_o  (csr_rdata),
    .csr_implemented_o(csr_implemented),
    .csr_read_only_o(csr_read_only),
    .csr_privilege_ok_o(csr_privilege_ok),
    // Write port (from WB stage)
    .csr_we_i     (wb_csr_we),
    .csr_waddr_i  (wb_csr_addr),
    .csr_wdata_i  (wb_csr_wdata),
    .csr_wdata_effective_o(wb_csr_wdata_effective),
    // Trap entry
    .trap_entry_i (wb_trap_event),
    .trap_pc_i    (ex2wb_pkt_out.trap_pc),
    .trap_cause_i (ex2wb_pkt_out.trap_cause),
    .trap_val_i   (ex2wb_pkt_out.trap_val),
    // MRET
    .mret_i       (wb_mret_event),
    // Retire
    .instret_i    (ex2wb_pkt_out.valid && !wb_trap_event),
    // Outputs
    .mtvec_o      (csr_mtvec),
    .mepc_o       (csr_mepc),
    .mstatus_o    (csr_mstatus),
    .mie_o        (csr_mie),
    .mip_o        (csr_mip)
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.illegal_instr)
      $info("RV32IM core illegal instruction detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ecall)
      $info("RV32IM core ECALL detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ebreak)
      $info("RV32IM core EBREAK detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.instr_misaligned)
      $info("RV32IM core instruction-address misalignment detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.mem_misaligned)
      $info("RV32IM core memory misaligned access detected; entering trap handler");
  end
`endif

  // ============================================================
  // 5. PC & IF Stage
  // ============================================================
  pc_counter #(
    .AW(AW),
    .RESET_PC('0)
  ) u_pc_counter (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .stall_i      (pc_stall),
    .redirect_en_i(pc_redirect_en),
    .redirect_pc_i(pc_redirect_pc),
    .pc_o         (if_pc)
  );
  assign instr_ren_o  = !pipe_kill && (!pc_stall || pc_redirect_en);
  assign instr_addr_o = if_pc;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      if_resp_pc_q    <= '0;
      if_resp_valid_q <= 1'b0;
    end else begin
      if (instr_ren_o) begin
        if_resp_pc_q    <= instr_addr_o;
        if_resp_valid_q <= 1'b1;
      end
    end
  end

  assign if2id_pkt.valid = if_resp_valid_q;
  assign if2id_pkt.error = if_resp_valid_q && instr_fetch_error_i;
  assign if2id_pkt.pc    = if_resp_pc_q;
  assign if2id_pkt.instr = instr_rdata_i;

  // ============================================================
  // 6. Pipeline Registers & Datapath
  // ============================================================
  if2id u_if2id (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (ifid_flush),
    .stall_i (ifid_stall),
    .pkt2id_i (if2id_pkt),
    .pkt2id_o (if2id_pkt_out)
  );

  decode u_decode (
    .pktd_i          (if2id_pkt_out),
    .rf_rs1_raddr_o (id_rs1_raddr),
    .rf_rs2_raddr_o (id_rs2_raddr),
    .rf_rs1_rdata_i (id_rs1_rdata),
    .rf_rs2_rdata_i (id_rs2_rdata),
    .pktd_o          (id2ex_pkt)
  );

  id2ex u_id2ex (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (idex_flush),
    .stall_i (idex_stall),
    .pkt2ex_i (id2ex_pkt),
    .pkt2ex_o (id2ex_pkt_out)
  );

  // EX kill for outstanding LSU or divider work: pipe_kill or any EX exception.
  assign ex_kill = pipe_kill |
                   id2ex_pkt_out.exc.illegal_instr |
                   id2ex_pkt_out.exc.instr_access_fault |
                   id2ex_pkt_out.exc.ecall |
                   id2ex_pkt_out.exc.ebreak;

  // DIV/DIVU/REM/REMU hold ID/EX until the one-cycle divider completion.
  // `div_wait` includes the initial start cycle, avoiding an early advance
  // before the divider's registered busy state becomes visible.
  always_comb begin
    ex_div_instruction = 1'b0;
    div_signed         = 1'b0;
    div_result         = div_quotient;

    if (id2ex_pkt_out.valid && id2ex_pkt_out.ex_ctrl.muldiv_valid) begin
      unique case (id2ex_pkt_out.ex_ctrl.muldiv_op)
        MULDIV_DIV: begin
          ex_div_instruction = 1'b1;
          div_signed         = 1'b1;
          div_result         = div_quotient;
        end
        MULDIV_DIVU: begin
          ex_div_instruction = 1'b1;
          div_result         = div_quotient;
        end
        MULDIV_REM: begin
          ex_div_instruction = 1'b1;
          div_signed         = 1'b1;
          div_result         = div_remainder;
        end
        MULDIV_REMU: begin
          ex_div_instruction = 1'b1;
          div_result         = div_remainder;
        end
        default: begin
          ex_div_instruction = 1'b0;
        end
      endcase
    end
  end

  assign div_start = ex_div_instruction &&
                     !div_busy &&
                     !div_complete &&
                     !ex_kill;
  assign div_wait  = ex_div_instruction && !div_complete && !ex_kill;
  assign ex_wait   = lsu_busy || div_wait;

  radix2_divider #(
    .DW(DW)
  ) u_radix2_divider (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .start_i     (div_start),
    .kill_i      (ex_kill),
    .signed_i    (div_signed),
    .dividend_i  (id2ex_pkt_out.ex_data.op1),
    .divisor_i   (id2ex_pkt_out.ex_data.op2),
    .busy_o      (div_busy),
    .complete_o  (div_complete),
    .quotient_o  (div_quotient),
    .remainder_o (div_remainder)
  );

  // ============================================================
  // 7. Execute (no longer drives data_ram directly)
  // ============================================================
  execute u_execute (
    .pkt_exe_i        (id2ex_pkt_out),
    .mem_misaligned_i (lsu_mem_misaligned), // Feedback from LSU
    .csr_rdata_i      (csr_rdata_for_ex),
    .csr_implemented_i(csr_implemented),
    .csr_read_only_i  (csr_read_only),
    .csr_privilege_ok_i(csr_privilege_ok),
    .mepc_i           (csr_mepc_for_ex),
    .div_result_i     (div_result),
    .redirect_en_o    (ex_redirect_en),
    .redirect_pc_o    (ex_redirect_pc),
    .flush_req_o      (ex_flush_req),
    .pkt_exe_o        (ex2wb_pkt_in)
  );

  // ============================================================
  // 8. LSU (Load/Store Unit) — transaction owner for the external data bus
  // ============================================================
  lsu #(
    .AW(AW),
    .DW(DW)
  ) u_lsu (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .pkt_ex_i          (id2ex_pkt_out),
    .ex_kill_i         (ex_kill),
    .bus_req_valid_o   (data_req_valid_o),
    .bus_req_ready_i   (data_req_ready_i),
    .bus_req_o         (data_req_o),
    .bus_rsp_valid_i   (data_rsp_valid_i),
    .bus_rsp_i         (data_rsp_i),
    .mem_info_o        (lsu_mem_info),
    .mem_misaligned_o  (lsu_mem_misaligned),
    .raw_rdata_o       (lsu_raw_rdata),
    .load_data_o       (lsu_load_data),
    .load_fault_o      (lsu_load_fault),
    .store_fault_o     (lsu_store_fault),
    .busy_o            (lsu_busy),
    .complete_o        (lsu_complete)
  );

  // ============================================================
  // 9. ex2wb_pkt_in_safe assembly
  //    A memory or divide instruction enters EX/WB only on completion.
  // ============================================================
  assign ex_mem_transaction = id2ex_pkt_out.valid &&
                              id2ex_pkt_out.ex_ctrl.mem_req &&
                              !lsu_mem_misaligned &&
                              !ex_kill;

  always_comb begin
    ex2wb_pkt_in_safe = ex2wb_pkt_in;
    if (ex_mem_transaction) begin
      if (lsu_complete) begin
        ex2wb_pkt_in_safe.mem_info  = lsu_mem_info;
        ex2wb_pkt_in_safe.mem_valid = 1'b1;
        ex2wb_pkt_in_safe.mem_we    = data_req_o.write;
        ex2wb_pkt_in_safe.mem_addr  = data_req_o.addr;
        ex2wb_pkt_in_safe.mem_wdata = data_req_o.wdata;
        ex2wb_pkt_in_safe.mem_wstrb = data_req_o.wstrb;
        ex2wb_pkt_in_safe.mem_rdata = lsu_raw_rdata;
        ex2wb_pkt_in_safe.mem_load_data = lsu_load_data;
        ex2wb_pkt_in_safe.mem_error = lsu_load_fault || lsu_store_fault;
        if (lsu_load_fault || lsu_store_fault) begin
          ex2wb_pkt_in_safe.rf.we = 1'b0;
          ex2wb_pkt_in_safe.wb_sel = WB_NONE;
          ex2wb_pkt_in_safe.trap_cause =
              lsu_store_fault ? MCAUSE_STORE_ACCESS : MCAUSE_LOAD_ACCESS;
          ex2wb_pkt_in_safe.trap_val = data_req_o.addr;
        end
      end else begin
        ex2wb_pkt_in_safe = EX_WB_PKT_BUBBLE;
      end
    end

    if (ex_div_instruction && !div_complete)
      ex2wb_pkt_in_safe = EX_WB_PKT_BUBBLE;

    if (pipe_kill)
      ex2wb_pkt_in_safe = EX_WB_PKT_BUBBLE;
  end

`ifndef SYNTHESIS
  always @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(wb_csr_we && !ex2wb_pkt_out.valid))
        else $error("Invalid EX/WB packet enabled a CSR write");

      if (pipe_kill) begin
        assert (!(ex2wb_pkt_in_safe.valid ||
                  ex2wb_pkt_in_safe.rf.we ||
                  ex2wb_pkt_in_safe.csr.valid ||
                  ex2wb_pkt_in_safe.mem_valid))
          else $error("Pipeline kill did not clear EX/WB side effects");
        assert (!data_req_valid_o)
          else $error("Pipeline kill did not suppress the LSU request");
        assert (!div_start)
          else $error("Pipeline kill did not suppress divider start");
      end

      if (ex_div_instruction && !div_complete) begin
        assert (!ex2wb_pkt_in_safe.valid)
          else $error("Incomplete divide instruction entered EX/WB");
      end

      assert (!(div_start && div_busy))
        else $error("Divider restarted while busy");
    end
  end
`endif

  // ============================================================
  // 10. EX/WB Pipeline Register
  // ============================================================
  ex2wb u_ex2wb (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .stall_i  (exwb_stall),
    .pkt2wb_i (ex2wb_pkt_in_safe),
    .pkt2wb_o (ex2wb_pkt_out)
  );

  // ============================================================
  // 11. Regfile
  // ============================================================
  assign wb_rf_wen_safe = wb_rf_wen && !wb_trap_event;

  regfile #(
    .DW(DW)
  ) u_regfile (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .rs1_raddr_i (id_rs1_raddr),
    .rs1_rdata_o (id_rs1_rdata),
    .rs2_raddr_i (id_rs2_raddr),
    .rs2_rdata_o (id_rs2_rdata),
    .rd_wen_i    (wb_rf_wen_safe),
    .rd_waddr_i  (wb_rf_waddr),
    .rd_wdata_i  (wb_rf_wdata),
    .dbg_x3_o    (dbg_x3_o),
    .dbg_x10_o   (dbg_x10_o),
    .dbg_x11_o   (dbg_x11_o)
  );

  // ============================================================
  // 12. WB Stage (memory result is owned by the EX/WB packet)
  // ============================================================
  wb_stage u_wb_stage (
    .pkt_wb_i    (ex2wb_pkt_out),
    .rf_wen_o    (wb_rf_wen),
    .rf_waddr_o  (wb_rf_waddr),
    .rf_wdata_o  (wb_rf_wdata),
    .csr_we_o    (/* tied off in top; csr write handled above */),
    .csr_addr_o  (),
    .csr_wdata_o (),
    .mret_o      (),
    .trap_cause_o(),
    .trap_val_o  ()
  );

`ifndef SYNTHESIS
  // Check stable post-clock values. Raw control fields may exist inside valid
  // instructions, so assert the externally effective side effects here.
  always @(negedge clk_i) begin
    if (rst_ni) begin
      if (!id2ex_pkt_out.valid) begin
        assert (!(data_req_valid_o || ex_redirect_en || ex_flush_req))
          else $error("Invalid ID/EX packet caused an EX-stage side effect");
      end

      if (ex2wb_pkt_in.instr_misaligned) begin
        assert (!(ex_redirect_en || ex_flush_req || ex2wb_pkt_in.rf.we))
          else $error("Misaligned control transfer was not suppressed");
        assert (ex2wb_pkt_in.trap_cause == MCAUSE_INST_MISALIGNED)
          else $error("Misaligned control transfer has the wrong trap cause");
        assert (ex2wb_pkt_in.trap_val[IALIGN_LSB-1:0] != '0)
          else $error("Misaligned control transfer has an aligned trap value");
      end

      if (!ex2wb_pkt_out.valid) begin
        assert (!(wb_rf_wen_safe ||
                  wb_csr_we ||
                  ex2wb_pkt_out.mem_valid ||
                  ex2wb_pkt_out.mem_we ||
                  wb_trap_event ||
                  wb_mret_event))
          else $error("Invalid EX/WB packet caused a retirement side effect");
      end
    end
  end
`endif

  // ============================================================
  // 13. Architectural Commit Interface
  // ============================================================
  logic [63:0] commit_order_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      commit_order_q <= '0;
    end else if (ex2wb_pkt_out.valid) begin
      commit_order_q <= commit_order_q + 64'd1;
    end
  end

  always_comb begin
    commit_o = '0;
    commit_o.valid      = ex2wb_pkt_out.valid;
    commit_o.order      = commit_order_q;
    commit_o.pc         = ex2wb_pkt_out.pc;
    commit_o.instr      = ex2wb_pkt_out.instr;
    commit_o.rd_we      = wb_rf_wen_safe;
    commit_o.rd_addr    = wb_rf_wen_safe ? wb_rf_waddr : '0;
    commit_o.rd_data    = wb_rf_wen_safe ? wb_rf_wdata : '0;
    commit_o.mem_valid  = ex2wb_pkt_out.mem_valid;
    commit_o.mem_we     = ex2wb_pkt_out.mem_we;
    commit_o.mem_addr   = ex2wb_pkt_out.mem_valid ? ex2wb_pkt_out.mem_addr : '0;
    commit_o.mem_wmask  = ex2wb_pkt_out.mem_we ? ex2wb_pkt_out.mem_wstrb : '0;
    commit_o.mem_rdata  = (ex2wb_pkt_out.mem_valid &&
                           !ex2wb_pkt_out.mem_we &&
                           !ex2wb_pkt_out.mem_error) ?
                          ex2wb_pkt_out.mem_rdata : '0;
    commit_o.mem_wdata  = (ex2wb_pkt_out.mem_valid && ex2wb_pkt_out.mem_we) ?
                          ex2wb_pkt_out.mem_wdata : '0;
    commit_o.trap       = wb_trap_event;
    commit_o.trap_cause = ex2wb_pkt_out.trap_cause;
    commit_o.trap_val   = ex2wb_pkt_out.trap_val;

    if (ex2wb_pkt_out.mem_valid && !ex2wb_pkt_out.mem_we) begin
      unique case (ex2wb_pkt_out.mem_info.mem_size)
        MEM_SIZE_BYTE:
          commit_o.mem_rmask = 4'b0001 << ex2wb_pkt_out.mem_info.load_offset;
        MEM_SIZE_HALF:
          commit_o.mem_rmask = 4'b0011 << ex2wb_pkt_out.mem_info.load_offset;
        MEM_SIZE_WORD:
          commit_o.mem_rmask = 4'b1111;
        default:
          commit_o.mem_rmask = '0;
      endcase
    end
  end

endmodule
`default_nettype wire
=======
`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

module riscv #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  output logic          instr_ren_o,
  output logic [AW-1:0] instr_addr_o,
  input  logic [DW-1:0] instr_rdata_i,
  input  logic          instr_fetch_error_i,
  output logic          data_req_valid_o,
  input  logic          data_req_ready_i,
  output core_bus_req_t data_req_o,
  input  logic          data_rsp_valid_i,
  input  core_bus_rsp_t data_rsp_i,
  output logic [DW-1:0] dbg_x3_o,
  output logic [DW-1:0] dbg_x10_o,
  output logic [DW-1:0] dbg_x11_o,
  output logic          halt_o,
  output logic          illegal_instr_o,
  output logic          exception_o,
  output commit_pkt_t   commit_o
);
  initial begin
    if (DW != 32) begin
      $fatal(1, "Current core supports only RV32. RV64 is reserved for future extension.");
    end
  end

  // ============================================================
  // 1. Pipeline Payload Structures (Vertical Data Flow)
  // ============================================================
  fetch_pkt_t if2id_pkt, if2id_pkt_out;
  id_ex_pkt_t id2ex_pkt, id2ex_pkt_out;
  ex_wb_pkt_t ex2wb_pkt_in, ex2wb_pkt_in_safe, ex2wb_pkt_out;

  // ============================================================
  // 2. Horizontal Control & Bus Signals
  // ============================================================
  logic [AW-1:0] if_pc;
  logic [AW-1:0] if_resp_pc_q;
  logic          if_resp_valid_q;

  // Regfile interface
  logic [4:0]    id_rs1_raddr;
  logic [4:0]    id_rs2_raddr;
  logic [DW-1:0] id_rs1_rdata;
  logic [DW-1:0] id_rs2_rdata;
  logic          wb_rf_wen;
  logic          wb_rf_wen_safe;
  logic [4:0]    wb_rf_waddr;
  logic [DW-1:0] wb_rf_wdata;

  // EX outputs
  logic          ex_redirect_en;
  logic [AW-1:0] ex_redirect_pc;
  logic          ex_flush_req;

  // CSR interface
  logic [DW-1:0] csr_rdata;
  logic [DW-1:0] csr_rdata_for_ex;
  logic          csr_implemented;
  logic          csr_read_only;
  logic          csr_privilege_ok;
  logic [AW-1:0] csr_mtvec;
  logic [AW-1:0] csr_mepc;
  logic [DW-1:0] csr_mstatus;
  logic [DW-1:0] csr_mie;
  logic [DW-1:0] csr_mip;

  // Trap / mret controls
  logic          wb_trap_event;
  logic          wb_mret_event;
  logic          trap_redirect_en;
  logic [AW-1:0] trap_redirect_pc;
  logic          pc_redirect_en;
  logic [AW-1:0] pc_redirect_pc;

  // LSU <-> pipeline interface
  mem_pkt_t       lsu_mem_info;
  logic           lsu_mem_misaligned;
  logic [DW-1:0]  lsu_raw_rdata;
  logic [DW-1:0]  lsu_load_data;
  logic           lsu_load_fault;
  logic           lsu_store_fault;
  logic           lsu_busy;
  logic           lsu_complete;
  logic           ex_kill;
  logic           ex_mem_transaction;

  // Iterative divider <-> pipeline interface
  logic           ex_div_instruction;
  logic           div_start;
  logic           div_signed;
  logic           div_busy;
  logic           div_complete;
  logic           div_wait;
  logic           ex_wait;
  logic [DW-1:0]  div_quotient;
  logic [DW-1:0]  div_remainder;
  logic [DW-1:0]  div_result;

  // ============================================================
  // 3. Control Unit Interface Signals
  // ============================================================
  logic pc_stall, ifid_stall, idex_stall, exwb_stall;
  logic ifid_flush, idex_flush, pipe_kill;

  assign wb_trap_event = ex2wb_pkt_out.valid &&
      (ex2wb_pkt_out.exc.illegal_instr || ex2wb_pkt_out.exc.instr_access_fault ||
       ex2wb_pkt_out.exc.ecall ||
       ex2wb_pkt_out.exc.ebreak || ex2wb_pkt_out.instr_misaligned ||
       ex2wb_pkt_out.mem_misaligned || ex2wb_pkt_out.mem_error);
  assign wb_mret_event = ex2wb_pkt_out.valid && ex2wb_pkt_out.is_mret;

  assign trap_redirect_en = wb_trap_event;
  assign trap_redirect_pc = csr_mtvec;
  assign pc_redirect_en   = ex_redirect_en || trap_redirect_en;
  assign pc_redirect_pc   = trap_redirect_en ? trap_redirect_pc : ex_redirect_pc;

  // ============================================================
  // 4. Core Control Unit Instantiation
  // ============================================================
  core_ctrl u_core_ctrl (
    .clk_i          (clk_i),
    .rst_ni         (rst_ni),
    .id_valid       (if2id_pkt_out.valid),
    .id_rs1_addr    (id_rs1_raddr),
    .id_rs2_addr    (id_rs2_raddr),
    .id_use_rs1     (id2ex_pkt.use_rs1),
    .id_use_rs2     (id2ex_pkt.use_rs2),
    .ex_valid       (id2ex_pkt_out.valid),
    .ex_rd_addr     (id2ex_pkt_out.rf.addr),
    .ex_rf_we       (id2ex_pkt_out.rf.we),
    .ex_mem_req     (id2ex_pkt_out.ex_ctrl.mem_req),
    .ex_mem_we      (id2ex_pkt_out.ex_ctrl.mem_we),
    .wb_valid       (ex2wb_pkt_out.valid),
    .wb_rd_addr     (ex2wb_pkt_out.rf.addr),
    .wb_rf_we       (ex2wb_pkt_out.rf.we),
    .ex_redirect_en (ex_redirect_en),
    .ex_flush_req   (ex_flush_req),
    .ex_wait_i      (ex_wait),
    .trap_redirect_en(trap_redirect_en),
    .wb_trap_event  (wb_trap_event),
    .pc_stall       (pc_stall),
    .ifid_stall     (ifid_stall),
    .idex_stall     (idex_stall),
    .exwb_stall     (exwb_stall),
    .ifid_flush     (ifid_flush),
    .idex_flush     (idex_flush),
    .pipe_kill      (pipe_kill)
  );

  assign halt_o          = 1'b0; // No longer halt; tests use tohost exit
  assign illegal_instr_o = ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.illegal_instr;
  assign exception_o     = wb_trap_event;

  // ============================================================
  // 4.5 CSR Register File
  // ============================================================
  logic wb_csr_we;
  logic [11:0] wb_csr_addr;
  logic [DW-1:0] wb_csr_wdata;
  logic [DW-1:0] wb_csr_wdata_effective;
  logic [AW-1:0] csr_mepc_for_ex;

  assign wb_csr_we    = ex2wb_pkt_out.valid &&
                        ex2wb_pkt_out.csr.valid &&
                        ex2wb_pkt_out.csr.write &&
                        !wb_trap_event;
  assign wb_csr_addr  = ex2wb_pkt_out.csr.addr;
  assign wb_csr_wdata = ex2wb_pkt_out.csr.wdata;
  // An adjacent CSR instruction in EX must observe the effective (WARL-filtered)
  // value written by the older CSR instruction in WB.
  assign csr_rdata_for_ex =
      (wb_csr_we && (wb_csr_addr == id2ex_pkt_out.csr.addr)) ?
      wb_csr_wdata_effective : csr_rdata;

  // MRET may immediately follow a write to mepc. Reuse the same effective
  // WB value so redirect generation cannot use stale or unaligned state.
  assign csr_mepc_for_ex =
      (wb_csr_we && (wb_csr_addr == CSR_MEPC)) ?
      AW'(wb_csr_wdata_effective) : csr_mepc;

  csr_regfile #(
    .AW(AW),
    .DW(DW)
  ) u_csr_regfile (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .current_priv_i(PRIV_MODE_M),
    // Read port (used in EX stage)
    .csr_addr_i   (id2ex_pkt_out.csr.addr),
    .csr_rdata_o  (csr_rdata),
    .csr_implemented_o(csr_implemented),
    .csr_read_only_o(csr_read_only),
    .csr_privilege_ok_o(csr_privilege_ok),
    // Write port (from WB stage)
    .csr_we_i     (wb_csr_we),
    .csr_waddr_i  (wb_csr_addr),
    .csr_wdata_i  (wb_csr_wdata),
    .csr_wdata_effective_o(wb_csr_wdata_effective),
    // Trap entry
    .trap_entry_i (wb_trap_event),
    .trap_pc_i    (ex2wb_pkt_out.trap_pc),
    .trap_cause_i (ex2wb_pkt_out.trap_cause),
    .trap_val_i   (ex2wb_pkt_out.trap_val),
    // MRET
    .mret_i       (wb_mret_event),
    // Retire
    .instret_i    (ex2wb_pkt_out.valid && !wb_trap_event),
    // Outputs
    .mtvec_o      (csr_mtvec),
    .mepc_o       (csr_mepc),
    .mstatus_o    (csr_mstatus),
    .mie_o        (csr_mie),
    .mip_o        (csr_mip)
  );

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.illegal_instr)
      $info("RV32IM core illegal instruction detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ecall)
      $info("RV32IM core ECALL detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ebreak)
      $info("RV32IM core EBREAK detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.instr_misaligned)
      $info("RV32IM core instruction-address misalignment detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.mem_misaligned)
      $info("RV32IM core memory misaligned access detected; entering trap handler");
  end
`endif

  // ============================================================
  // 5. PC & IF Stage
  // ============================================================
  pc_counter #(
    .AW(AW),
    .RESET_PC('0)
  ) u_pc_counter (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .stall_i      (pc_stall),
    .redirect_en_i(pc_redirect_en),
    .redirect_pc_i(pc_redirect_pc),
    .pc_o         (if_pc)
  );
  assign instr_ren_o  = !pipe_kill && (!pc_stall || pc_redirect_en);
  assign instr_addr_o = if_pc;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      if_resp_pc_q    <= '0;
      if_resp_valid_q <= 1'b0;
    end else begin
      if (instr_ren_o) begin
        if_resp_pc_q    <= instr_addr_o;
        if_resp_valid_q <= 1'b1;
      end
    end
  end

  assign if2id_pkt.valid = if_resp_valid_q;
  assign if2id_pkt.error = if_resp_valid_q && instr_fetch_error_i;
  assign if2id_pkt.pc    = if_resp_pc_q;
  assign if2id_pkt.instr = instr_rdata_i;

  // ============================================================
  // 6. Pipeline Registers & Datapath
  // ============================================================
  if2id u_if2id (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (ifid_flush),
    .stall_i (ifid_stall),
    .pkt2id_i (if2id_pkt),
    .pkt2id_o (if2id_pkt_out)
  );

  decode u_decode (
    .pktd_i          (if2id_pkt_out),
    .rf_rs1_raddr_o (id_rs1_raddr),
    .rf_rs2_raddr_o (id_rs2_raddr),
    .rf_rs1_rdata_i (id_rs1_rdata),
    .rf_rs2_rdata_i (id_rs2_rdata),
    .pktd_o          (id2ex_pkt)
  );

  id2ex u_id2ex (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (idex_flush),
    .stall_i (idex_stall),
    .pkt2ex_i (id2ex_pkt),
    .pkt2ex_o (id2ex_pkt_out)
  );

  // EX kill for outstanding LSU or divider work: pipe_kill or any EX exception.
  assign ex_kill = pipe_kill |
                   id2ex_pkt_out.exc.illegal_instr |
                   id2ex_pkt_out.exc.instr_access_fault |
                   id2ex_pkt_out.exc.ecall |
                   id2ex_pkt_out.exc.ebreak;

  // DIV/DIVU/REM/REMU hold ID/EX until the one-cycle divider completion.
  // `div_wait` includes the initial start cycle, avoiding an early advance
  // before the divider's registered busy state becomes visible.
  always_comb begin
    ex_div_instruction = 1'b0;
    div_signed         = 1'b0;
    div_result         = div_quotient;

    if (id2ex_pkt_out.valid && id2ex_pkt_out.ex_ctrl.muldiv_valid) begin
      unique case (id2ex_pkt_out.ex_ctrl.muldiv_op)
        MULDIV_DIV: begin
          ex_div_instruction = 1'b1;
          div_signed         = 1'b1;
          div_result         = div_quotient;
        end
        MULDIV_DIVU: begin
          ex_div_instruction = 1'b1;
          div_result         = div_quotient;
        end
        MULDIV_REM: begin
          ex_div_instruction = 1'b1;
          div_signed         = 1'b1;
          div_result         = div_remainder;
        end
        MULDIV_REMU: begin
          ex_div_instruction = 1'b1;
          div_result         = div_remainder;
        end
        default: begin
          ex_div_instruction = 1'b0;
        end
      endcase
    end
  end

  assign div_start = ex_div_instruction &&
                     !div_busy &&
                     !div_complete &&
                     !ex_kill;
  assign div_wait  = ex_div_instruction && !div_complete && !ex_kill;
  assign ex_wait   = lsu_busy || div_wait;

  radix2_divider #(
    .DW(DW)
  ) u_radix2_divider (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .start_i     (div_start),
    .kill_i      (ex_kill),
    .signed_i    (div_signed),
    .dividend_i  (id2ex_pkt_out.ex_data.op1),
    .divisor_i   (id2ex_pkt_out.ex_data.op2),
    .busy_o      (div_busy),
    .complete_o  (div_complete),
    .quotient_o  (div_quotient),
    .remainder_o (div_remainder)
  );

  // ============================================================
  // 7. Execute (no longer drives data_ram directly)
  // ============================================================
  execute u_execute (
    .pkt_exe_i        (id2ex_pkt_out),
    .mem_misaligned_i (lsu_mem_misaligned), // Feedback from LSU
    .csr_rdata_i      (csr_rdata_for_ex),
    .csr_implemented_i(csr_implemented),
    .csr_read_only_i  (csr_read_only),
    .csr_privilege_ok_i(csr_privilege_ok),
    .mepc_i           (csr_mepc_for_ex),
    .div_result_i     (div_result),
    .redirect_en_o    (ex_redirect_en),
    .redirect_pc_o    (ex_redirect_pc),
    .flush_req_o      (ex_flush_req),
    .pkt_exe_o        (ex2wb_pkt_in)
  );

  // ============================================================
  // 8. LSU (Load/Store Unit) — transaction owner for the external data bus
  // ============================================================
  lsu #(
    .AW(AW),
    .DW(DW)
  ) u_lsu (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .pkt_ex_i          (id2ex_pkt_out),
    .ex_kill_i         (ex_kill),
    .bus_req_valid_o   (data_req_valid_o),
    .bus_req_ready_i   (data_req_ready_i),
    .bus_req_o         (data_req_o),
    .bus_rsp_valid_i   (data_rsp_valid_i),
    .bus_rsp_i         (data_rsp_i),
    .mem_info_o        (lsu_mem_info),
    .mem_misaligned_o  (lsu_mem_misaligned),
    .raw_rdata_o       (lsu_raw_rdata),
    .load_data_o       (lsu_load_data),
    .load_fault_o      (lsu_load_fault),
    .store_fault_o     (lsu_store_fault),
    .busy_o            (lsu_busy),
    .complete_o        (lsu_complete)
  );

  // ============================================================
  // 9. ex2wb_pkt_in_safe assembly
  //    A memory or divide instruction enters EX/WB only on completion.
  // ============================================================
  assign ex_mem_transaction = id2ex_pkt_out.valid &&
                              id2ex_pkt_out.ex_ctrl.mem_req &&
                              !lsu_mem_misaligned &&
                              !ex_kill;

  always_comb begin
    ex2wb_pkt_in_safe = ex2wb_pkt_in;
    if (ex_mem_transaction) begin
      if (lsu_complete) begin
        ex2wb_pkt_in_safe.mem_info  = lsu_mem_info;
        ex2wb_pkt_in_safe.mem_valid = 1'b1;
        ex2wb_pkt_in_safe.mem_we    = data_req_o.write;
        ex2wb_pkt_in_safe.mem_addr  = data_req_o.addr;
        ex2wb_pkt_in_safe.mem_wdata = data_req_o.wdata;
        ex2wb_pkt_in_safe.mem_wstrb = data_req_o.wstrb;
        ex2wb_pkt_in_safe.mem_rdata = lsu_raw_rdata;
        ex2wb_pkt_in_safe.mem_load_data = lsu_load_data;
        ex2wb_pkt_in_safe.mem_error = lsu_load_fault || lsu_store_fault;
        if (lsu_load_fault || lsu_store_fault) begin
          ex2wb_pkt_in_safe.rf.we = 1'b0;
          ex2wb_pkt_in_safe.wb_sel = WB_NONE;
          ex2wb_pkt_in_safe.trap_cause =
              lsu_store_fault ? MCAUSE_STORE_ACCESS : MCAUSE_LOAD_ACCESS;
          ex2wb_pkt_in_safe.trap_val = data_req_o.addr;
        end
      end else begin
        ex2wb_pkt_in_safe = EX_WB_PKT_BUBBLE;
      end
    end

    if (ex_div_instruction && !div_complete)
      ex2wb_pkt_in_safe = EX_WB_PKT_BUBBLE;

    if (pipe_kill)
      ex2wb_pkt_in_safe = EX_WB_PKT_BUBBLE;
  end

`ifndef SYNTHESIS
  always @(posedge clk_i) begin
    if (rst_ni) begin
      assert (!(wb_csr_we && !ex2wb_pkt_out.valid))
        else $error("Invalid EX/WB packet enabled a CSR write");

      if (pipe_kill) begin
        assert (!(ex2wb_pkt_in_safe.valid ||
                  ex2wb_pkt_in_safe.rf.we ||
                  ex2wb_pkt_in_safe.csr.valid ||
                  ex2wb_pkt_in_safe.mem_valid))
          else $error("Pipeline kill did not clear EX/WB side effects");
        assert (!data_req_valid_o)
          else $error("Pipeline kill did not suppress the LSU request");
        assert (!div_start)
          else $error("Pipeline kill did not suppress divider start");
      end

      if (ex_div_instruction && !div_complete) begin
        assert (!ex2wb_pkt_in_safe.valid)
          else $error("Incomplete divide instruction entered EX/WB");
      end

      assert (!(div_start && div_busy))
        else $error("Divider restarted while busy");
    end
  end
`endif

  // ============================================================
  // 10. EX/WB Pipeline Register
  // ============================================================
  ex2wb u_ex2wb (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .stall_i  (exwb_stall),
    .pkt2wb_i (ex2wb_pkt_in_safe),
    .pkt2wb_o (ex2wb_pkt_out)
  );

  // ============================================================
  // 11. Regfile
  // ============================================================
  assign wb_rf_wen_safe = wb_rf_wen && !wb_trap_event;

  regfile #(
    .DW(DW)
  ) u_regfile (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .rs1_raddr_i (id_rs1_raddr),
    .rs1_rdata_o (id_rs1_rdata),
    .rs2_raddr_i (id_rs2_raddr),
    .rs2_rdata_o (id_rs2_rdata),
    .rd_wen_i    (wb_rf_wen_safe),
    .rd_waddr_i  (wb_rf_waddr),
    .rd_wdata_i  (wb_rf_wdata),
    .dbg_x3_o    (dbg_x3_o),
    .dbg_x10_o   (dbg_x10_o),
    .dbg_x11_o   (dbg_x11_o)
  );

  // ============================================================
  // 12. WB Stage (memory result is owned by the EX/WB packet)
  // ============================================================
  wb_stage u_wb_stage (
    .pkt_wb_i    (ex2wb_pkt_out),
    .rf_wen_o    (wb_rf_wen),
    .rf_waddr_o  (wb_rf_waddr),
    .rf_wdata_o  (wb_rf_wdata),
    .csr_we_o    (/* tied off in top; csr write handled above */),
    .csr_addr_o  (),
    .csr_wdata_o (),
    .mret_o      (),
    .trap_cause_o(),
    .trap_val_o  ()
  );

`ifndef SYNTHESIS
  // Check stable post-clock values. Raw control fields may exist inside valid
  // instructions, so assert the externally effective side effects here.
  always @(negedge clk_i) begin
    if (rst_ni) begin
      if (!id2ex_pkt_out.valid) begin
        assert (!(data_req_valid_o || ex_redirect_en || ex_flush_req))
          else $error("Invalid ID/EX packet caused an EX-stage side effect");
      end

      if (ex2wb_pkt_in.instr_misaligned) begin
        assert (!(ex_redirect_en || ex_flush_req || ex2wb_pkt_in.rf.we))
          else $error("Misaligned control transfer was not suppressed");
        assert (ex2wb_pkt_in.trap_cause == MCAUSE_INST_MISALIGNED)
          else $error("Misaligned control transfer has the wrong trap cause");
        assert (ex2wb_pkt_in.trap_val[IALIGN_LSB-1:0] != '0)
          else $error("Misaligned control transfer has an aligned trap value");
      end

      if (!ex2wb_pkt_out.valid) begin
        assert (!(wb_rf_wen_safe ||
                  wb_csr_we ||
                  ex2wb_pkt_out.mem_valid ||
                  ex2wb_pkt_out.mem_we ||
                  wb_trap_event ||
                  wb_mret_event))
          else $error("Invalid EX/WB packet caused a retirement side effect");
      end
    end
  end
`endif

  // ============================================================
  // 13. Architectural Commit Interface
  // ============================================================
  logic [63:0] commit_order_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      commit_order_q <= '0;
    end else if (ex2wb_pkt_out.valid) begin
      commit_order_q <= commit_order_q + 64'd1;
    end
  end

  always_comb begin
    commit_o = '0;
    commit_o.valid      = ex2wb_pkt_out.valid;
    commit_o.order      = commit_order_q;
    commit_o.pc         = ex2wb_pkt_out.pc;
    commit_o.instr      = ex2wb_pkt_out.instr;
    commit_o.rd_we      = wb_rf_wen_safe;
    commit_o.rd_addr    = wb_rf_wen_safe ? wb_rf_waddr : '0;
    commit_o.rd_data    = wb_rf_wen_safe ? wb_rf_wdata : '0;
    commit_o.mem_valid  = ex2wb_pkt_out.mem_valid;
    commit_o.mem_we     = ex2wb_pkt_out.mem_we;
    commit_o.mem_addr   = ex2wb_pkt_out.mem_valid ? ex2wb_pkt_out.mem_addr : '0;
    commit_o.mem_wmask  = ex2wb_pkt_out.mem_we ? ex2wb_pkt_out.mem_wstrb : '0;
    commit_o.mem_rdata  = (ex2wb_pkt_out.mem_valid &&
                           !ex2wb_pkt_out.mem_we &&
                           !ex2wb_pkt_out.mem_error) ?
                          ex2wb_pkt_out.mem_rdata : '0;
    commit_o.mem_wdata  = (ex2wb_pkt_out.mem_valid && ex2wb_pkt_out.mem_we) ?
                          ex2wb_pkt_out.mem_wdata : '0;
    commit_o.trap       = wb_trap_event;
    commit_o.trap_cause = ex2wb_pkt_out.trap_cause;
    commit_o.trap_val   = ex2wb_pkt_out.trap_val;

    if (ex2wb_pkt_out.mem_valid && !ex2wb_pkt_out.mem_we) begin
      unique case (ex2wb_pkt_out.mem_info.mem_size)
        MEM_SIZE_BYTE:
          commit_o.mem_rmask = 4'b0001 << ex2wb_pkt_out.mem_info.load_offset;
        MEM_SIZE_HALF:
          commit_o.mem_rmask = 4'b0011 << ex2wb_pkt_out.mem_info.load_offset;
        MEM_SIZE_WORD:
          commit_o.mem_rmask = 4'b1111;
        default:
          commit_o.mem_rmask = '0;
      endcase
    end
  end

endmodule
`default_nettype wire
>>>>>>> Stashed changes
