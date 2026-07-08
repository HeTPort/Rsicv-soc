`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

module riscv #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter int DATA_RAM_DEPTH = 4096,
  parameter string INIT_DATA_FILE = ""
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  output logic          instr_ren_o,
  output logic [AW-1:0] instr_addr_o,
  input  logic [DW-1:0] instr_rdata_i,
  output logic [DW-1:0] dbg_x3_o,
  output logic [DW-1:0] dbg_x10_o,
  output logic [DW-1:0] dbg_x11_o,
  output logic          halt_o,
  output logic          illegal_instr_o,
  output logic          exception_o
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
  logic [4:0]    wb_rf_waddr;
  logic [DW-1:0] wb_rf_wdata;

  // EX outputs
  logic          ex_redirect_en;
  logic [AW-1:0] ex_redirect_pc;
  logic          ex_flush_req;

  // CSR interface
  logic [DW-1:0] csr_rdata;
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

  // LSU <-> Data RAM interface
  logic            ram_req_valid;
  logic            ram_we;
  logic [DW/8-1:0] ram_wstrb;
  logic [AW-1:0]   ram_addr;
  logic [DW-1:0]   ram_wdata;
  logic [DW-1:0]   ram_rdata;

  // LSU <-> Pipeline interface
  mem_pkt_t       lsu_mem_info;
  logic           lsu_mem_misaligned;
  logic [DW-1:0]  lsu_load_data;
  logic           ex_kill;

  // ============================================================
  // 3. Control Unit Interface Signals
  // ============================================================
  logic pc_stall, ifid_stall, idex_stall, exwb_stall;
  logic ifid_flush, idex_flush, pipe_kill;

  assign wb_trap_event = ex2wb_pkt_out.valid &&
      (ex2wb_pkt_out.exc.illegal_instr || ex2wb_pkt_out.exc.ecall ||
       ex2wb_pkt_out.exc.ebreak || ex2wb_pkt_out.mem_misaligned);
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

  assign wb_csr_we    = wb_trap_event ? 1'b0 : ex2wb_pkt_out.csr.valid;
  assign wb_csr_addr  = ex2wb_pkt_out.csr.addr;
  assign wb_csr_wdata = ex2wb_pkt_out.csr.wdata;

  csr_regfile #(
    .AW(AW),
    .DW(DW)
  ) u_csr_regfile (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    // Read port (used in EX stage)
    .csr_addr_i   (id2ex_pkt_out.csr.addr),
    .csr_rdata_o  (csr_rdata),
    // Write port (from WB stage)
    .csr_we_i     (wb_csr_we),
    .csr_waddr_i  (wb_csr_addr),
    .csr_wdata_i  (wb_csr_wdata),
    // Trap entry
    .trap_entry_i (wb_trap_event),
    .trap_pc_i    (ex2wb_pkt_out.trap_pc),
    .trap_cause_i (ex2wb_pkt_out.trap_cause),
    .trap_val_i   (ex2wb_pkt_out.trap_val),
    // MRET
    .mret_i       (wb_mret_event),
    // Retire
    .instret_i    (ex2wb_pkt_out.valid),
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
      $error("RV32IM core illegal instruction detected at WB stage");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ecall)
      $info("RV32IM core ECALL detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ebreak)
      $info("RV32IM core EBREAK detected; entering trap handler");
    if (ex2wb_pkt_out.valid && ex2wb_pkt_out.mem_misaligned)
      $error("RV32IM core memory misaligned access detected");
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
  logic [DW-1:0] if_resp_instr_q;
  assign instr_ren_o  = !pipe_kill && (!pc_stall || pc_redirect_en);
  assign instr_addr_o = if_pc;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      if_resp_pc_q    <= '0;
      if_resp_valid_q <= 1'b0;
      if_resp_instr_q <= '0;
    end else begin
      if (!pc_stall || pc_redirect_en) begin
        if_resp_pc_q    <= if_pc;
        if_resp_valid_q <= 1'b1;
        if_resp_instr_q <= instr_rdata_i;
      end
    end
  end

  assign if2id_pkt.valid = if_resp_valid_q;
  assign if2id_pkt.pc    = if_resp_pc_q;
  assign if2id_pkt.instr = if_resp_instr_q;

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

  // EX kill for LSU: pipe_kill or any EX-stage exception
  assign ex_kill = pipe_kill |
                   id2ex_pkt_out.exc.illegal_instr |
                   id2ex_pkt_out.exc.ecall |
                   id2ex_pkt_out.exc.ebreak;

  // ============================================================
  // 7. Execute (no longer drives data_ram directly)
  // ============================================================
  execute u_execute (
    .pkt_exe_i        (id2ex_pkt_out),
    .mem_misaligned_i (lsu_mem_misaligned), // Feedback from LSU
    .csr_rdata_i      (csr_rdata),
    .mepc_i           (csr_mepc),
    .redirect_en_o    (ex_redirect_en),
    .redirect_pc_o    (ex_redirect_pc),
    .flush_req_o      (ex_flush_req),
    .pkt_exe_o        (ex2wb_pkt_in)
  );

  // ============================================================
  // 8. LSU (Load/Store Unit) — sole interface to data_ram
  // ============================================================
  lsu #(
    .AW(AW),
    .DW(DW)
  ) u_lsu (
    // EX stage inputs
    .pkt_ex_i         (id2ex_pkt_out),
    .ex_kill_i        (ex_kill),
    // WB stage inputs
    .wb_mem_info_i    (ex2wb_pkt_out.mem_info),
    .ram_rdata_i      (ram_rdata),
    // Data RAM interface
    .ram_req_valid_o  (ram_req_valid),
    .ram_req_ready_i  (),       // Direct RAM always ready
    .ram_we_o         (ram_we),
    .ram_wstrb_o      (ram_wstrb),
    .ram_addr_o       (ram_addr),
    .ram_wdata_o      (ram_wdata),
    .ram_resp_valid_i (),       // Direct RAM 1-cycle response
    // Pipeline outputs
    .mem_info_o       (lsu_mem_info),
    .mem_misaligned_o (lsu_mem_misaligned),
    .load_data_o      (lsu_load_data),
    .load_fault_o     (),           // Unconnected for now
    .store_fault_o    ()            // Unconnected for now
  );

  // ============================================================
  // 9. ex2wb_pkt_in_safe assembly
  //    Override mem_info with LSU's output; apply pipe_kill.
  // ============================================================
  always_comb begin
    ex2wb_pkt_in_safe = ex2wb_pkt_in;
    ex2wb_pkt_in_safe.mem_info = lsu_mem_info; // Overwrite by LSU
    if (pipe_kill) begin
      ex2wb_pkt_in_safe.valid             = 1'b0;
      ex2wb_pkt_in_safe.rf.we             = 1'b0;
      ex2wb_pkt_in_safe.exc.illegal_instr = 1'b0;
      ex2wb_pkt_in_safe.exc.ecall         = 1'b0;
      ex2wb_pkt_in_safe.exc.ebreak        = 1'b0;
      ex2wb_pkt_in_safe.mem_misaligned    = 1'b0;
    end
  end

  // ============================================================
  // 10. Data RAM (only LSU talks to it)
  // ============================================================
  logic ram_ren;
  assign ram_ren = ram_req_valid & !ram_we; // Read enable is valid & not write

  data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DATA_RAM_DEPTH),
    .INIT_FILE(INIT_DATA_FILE)
  ) u_data_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .ren_i   (ram_ren),
    .wen_i   (ram_we),
    .wstrb_i (ram_wstrb),
    .addr_i  (ram_addr),
    .wdata_i (ram_wdata),
    .rdata_o (ram_rdata)
  );

  // ============================================================
  // 11. EX/WB Pipeline Register
  // ============================================================
  ex2wb u_ex2wb (
    .clk_i    (clk_i),
    .rst_ni   (rst_ni),
    .stall_i  (exwb_stall),
    .pkt2wb_i (ex2wb_pkt_in_safe),
    .pkt2wb_o (ex2wb_pkt_out)
  );

  // ============================================================
  // 12. Regfile
  // ============================================================
  logic wb_rf_wen_safe;
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
  // 13. WB Stage (load_data from LSU)
  // ============================================================
  wb_stage u_wb_stage (
    .pkt_wb_i    (ex2wb_pkt_out),
    .load_data_i (lsu_load_data),
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

endmodule
`default_nettype wire