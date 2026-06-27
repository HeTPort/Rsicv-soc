`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: riscv
// Description:
//   Top-level RV32IM simple pipelined CPU.
//
// Pipeline:
//   IF -> IF/ID -> ID/decode -> ID/EX -> EX/MEM -> EX/WB -> WB
//
// Responsibilities:
//   - Connect pc_counter, instruction interface, decode, regfile,
//     ID/EX, execute, data RAM, EX/WB, and WB.
//   - Perform simple RAW hazard detection using decode-generated
//     use_rs1/use_rs2 signals.
//   - Handle branch/jump redirect flush.
//   - Provide minimal halt/exception reporting.
//
// Notes:
//   - Top no longer decodes opcode for hazard detection.
//   - Hazard detection relies on decode outputs.
//   - Current RV32M is combinational; ex_stall is reserved.
// ============================================================
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
  // Pipeline Payload Structures (Vertical Data Flow)
  // ============================================================
  fetch_pkt_t if2id_pkt;
  fetch_pkt_t if2id_pkt_out;
  
  id_ex_pkt_t id2ex_pkt;
  id_ex_pkt_t id2ex_pkt_out;
  
  ex_wb_pkt_t ex2wb_pkt_in;
  ex_wb_pkt_t ex2wb_pkt_in_safe;
  ex_wb_pkt_t ex2wb_pkt_out;

  // ============================================================
  // Horizontal Control & Bus Signals
  // ============================================================
  logic [AW-1:0] if_pc;
  logic [AW-1:0] if_resp_pc_q;
  logic          if_resp_valid_q;
  logic          fetch_kill_q;

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

  // Data memory interface
  logic            dmem_ren;
  logic            dmem_wen;
  logic [DW/8-1:0] dmem_wstrb;
  logic [AW-1:0]   dmem_addr;
  logic [DW-1:0]   dmem_wdata;
  logic [DW-1:0]   dmem_rdata;


  // Trap/Halt logic
  logic trap_event;
  logic pipe_kill;
  logic halt_q;
  logic exception_event;

  assign trap_event = 
    ex2wb_pkt_out.valid && 
    (ex2wb_pkt_out.exc.illegal_instr || ex2wb_pkt_out.exc.ecall || ex2wb_pkt_out.exc.ebreak || ex2wb_pkt_out.mem_misaligned);
  assign pipe_kill = trap_event | halt_q;
  assign exception_event = trap_event;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) halt_q <= 1'b0;
    else if (exception_event) halt_q <= 1'b1;
  end

  assign halt_o          = halt_q;
  assign illegal_instr_o = ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.illegal_instr && !halt_q;
  assign exception_o     = exception_event && !halt_q;

`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if (!halt_q) begin 
      if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.illegal_instr)
        $error("RV32IM core illegal instruction detected at WB stage");
      if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ecall)
        $error("RV32IM core ECALL detected; halting core");
      if (ex2wb_pkt_out.valid && ex2wb_pkt_out.exc.ebreak)
        $info("RV32IM core EBREAK detected; halting core");
      if (ex2wb_pkt_out.valid && ex2wb_pkt_out.mem_misaligned)
        $error("RV32IM core memory misaligned access detected");
    end
  end
`endif
  // ============================================================
  // Hazard detection
  // ============================================================
  logic hazard_stall;
  logic ex_stall;
  assign ex_stall = 1'b0; // Reserved for future multi-cycle mul/div.

  assign hazard_stall =
      id2ex_pkt.valid &&               // ID stage has valid instruction
      id2ex_pkt_out.valid &&           // EX stage has valid instruction
      id2ex_pkt_out.rf.we &&           // EX stage will write back
      id2ex_pkt_out.rf.addr != 5'd0 && // Not x0
      (
        (id2ex_pkt.use_rs1 && id_rs1_raddr == id2ex_pkt_out.rf.addr) ||
        (id2ex_pkt.use_rs2 && id_rs2_raddr == id2ex_pkt_out.rf.addr)
      );

  // ============================================================
  // Pipeline control
  // ============================================================
  logic pc_stall;
  logic ifid_stall;
  logic ifid_flush;
  logic idex_flush;
  logic idex_stall;
  assign pc_stall   = hazard_stall | ex_stall | pipe_kill;
  assign ifid_stall = hazard_stall | ex_stall ;
  assign idex_stall = ex_stall ;
  assign ifid_flush = ex_flush_req | fetch_kill_q | pipe_kill;
  assign idex_flush = ex_flush_req | hazard_stall | pipe_kill;
  // ============================================================
  // PC
  // ============================================================
  pc_counter #(
    .AW(AW),
    .RESET_PC('0)
  ) u_pc_counter (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .stall_i      (pc_stall),
    .redirect_en_i(ex_redirect_en),
    .redirect_pc_i(ex_redirect_pc),
    .pc_o         (if_pc)
  );
  assign instr_ren_o  = !pipe_kill && (!pc_stall || ex_redirect_en);
  assign instr_addr_o = if_pc;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      if_resp_pc_q    <= '0;
      if_resp_valid_q <= 1'b0;
      fetch_kill_q    <= 1'b0;
    end
    else begin
      fetch_kill_q <= ex_flush_req;
      if (!pc_stall || ex_redirect_en) begin
        if_resp_pc_q    <= if_pc;
        if_resp_valid_q <= !halt_q;
      end
    end
  end


  // Pack IF packet
  assign if2id_pkt.valid = if_resp_valid_q;
  assign if2id_pkt.pc    = if_resp_pc_q;
  assign if2id_pkt.instr = instr_rdata_i;
  // ============================================================
  // IF/ID Pipeline Register
  // ============================================================
  if2id u_if2id (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (ifid_flush),
    .stall_i (ifid_stall),
    .pkt2id_i   (if2id_pkt),
    .pkt2id_o   (if2id_pkt_out)
  );
  // ============================================================
  // Decode
  // ============================================================
  decode u_decode (
    .pktd_i          (if2id_pkt_out),
    .rf_rs1_raddr_o (id_rs1_raddr),
    .rf_rs2_raddr_o (id_rs2_raddr),
    .rf_rs1_rdata_i (id_rs1_rdata),
    .rf_rs2_rdata_i (id_rs2_rdata),
    .pktd_o          (id2ex_pkt)
  );
  // ============================================================
  // Regfile
  // ============================================================

  logic wb_rf_wen_safe;
  assign wb_rf_wen_safe = wb_rf_wen && !halt_q && !trap_event;
  regfile #(
    .DW(DW)
  ) u_regfile (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .rs1_raddr_i (id_rs1_raddr),
    .rs1_rdata_o (id_rs1_rdata),
    .rs2_raddr_i (id_rs2_raddr),
    .rs2_rdata_o (id_rs2_rdata),
    .rd_wen_i    (wb_rf_wen),
    .rd_waddr_i  (wb_rf_waddr),
    .rd_wdata_i  (wb_rf_wdata),
    .dbg_x3_o    (dbg_x3_o),
    .dbg_x10_o   (dbg_x10_o),
    .dbg_x11_o   (dbg_x11_o)
  );
  // ============================================================
  // ID/EX
  // ============================================================
  id2ex u_id2ex (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (idex_flush),
    .stall_i (idex_stall),
    .pkt2ex_i   (id2ex_pkt),
    .pkt2ex_o   (id2ex_pkt_out)
  );
  // ============================================================
  // Execute
  // ============================================================
  execute u_execute (
    .pkt_exe_i        (id2ex_pkt_out),
    .redirect_en_o(ex_redirect_en),
    .redirect_pc_o(ex_redirect_pc),
    .flush_req_o  (ex_flush_req),
    .dmem_ren_o   (dmem_ren),
    .dmem_wen_o   (dmem_wen),
    .dmem_wstrb_o (dmem_wstrb),
    .dmem_addr_o  (dmem_addr),
    .dmem_wdata_o (dmem_wdata),
    .pkt_exe_o        (ex2wb_pkt_in)
  );

  // Trap masking before EX/WB register
  always_comb begin
    ex2wb_pkt_in_safe = ex2wb_pkt_in;
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
  // Data RAM
  // ============================================================
  logic dmem_ren_safe;
  logic dmem_wen_safe;
  assign dmem_ren_safe = dmem_ren && !pipe_kill;
  assign dmem_wen_safe = dmem_wen && !pipe_kill;
  data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DATA_RAM_DEPTH),
    .INIT_FILE(INIT_DATA_FILE)
  ) u_data_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .ren_i   (dmem_ren_safe),
    .wen_i   (dmem_wen_safe),
    .wstrb_i (dmem_wstrb),
    .addr_i  (dmem_addr),
    .wdata_i (dmem_wdata),
    .rdata_o (dmem_rdata)
  );

  // ============================================================
  // EX/WB Pipeline Register
  // ============================================================
  ex2wb u_ex2wb (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .stall_i (1'b0), // Currently no stall source for EX/WB
    .pkt2wb_i   (ex2wb_pkt_in_safe),
    .pkt2wb_o   (ex2wb_pkt_out)
  );
  // ============================================================
  // WB
  // ============================================================
  wb_stage u_wb_stage (
    .pkt_wb_i         (ex2wb_pkt_out),
    .dmem_rdata_i  (dmem_rdata),
    .rf_wen_o      (wb_rf_wen),
    .rf_waddr_o    (wb_rf_waddr),
    .rf_wdata_o    (wb_rf_wdata)
  );
endmodule
`default_nettype wire