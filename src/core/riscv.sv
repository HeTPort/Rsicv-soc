`timescale 1ns / 1ps
`default_nettype none
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
  parameter int DATA_RAM_DEPTH = 4096
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
  // IF
  // ============================================================
  logic [AW-1:0] if_pc;
  logic [AW-1:0] if_resp_pc_q;
  logic          if_resp_valid_q;
  logic          fetch_kill_q;
  // ============================================================
  // IF/ID
  // ============================================================
  logic          id_valid;
  logic [AW-1:0] id_pc;
  logic [DW-1:0] id_instr;
  // ============================================================
  // Decode / Regfile
  // ============================================================
  logic [4:0]    id_rs1_raddr;
  logic [4:0]    id_rs2_raddr;
  logic [DW-1:0] id_rs1_rdata;
  logic [DW-1:0] id_rs2_rdata;
  logic [DW-1:0] id_op1;
  logic [DW-1:0] id_op2;
  logic [DW-1:0] id_store_data;
  logic          id_use_rs1;
  logic          id_use_rs2;
  logic [4:0]    id_rd;
  logic          id_rf_we;
  logic [DW-1:0] id_imm;
  alu_op_e       id_alu_op;
  branch_op_e    id_branch_op;
  jump_op_e      id_jump_op;
  logic          id_mem_req;
  logic          id_mem_we;
  mem_size_e     id_mem_size;
  logic          id_mem_unsigned;
  wb_sel_e       id_wb_sel;
  logic          id_muldiv_valid;
  muldiv_op_e    id_muldiv_op;
  logic          id_illegal_instr;
  logic          id_ecall;
  logic          id_ebreak;
  // ============================================================
  // ID/EX
  // ============================================================
  logic          ex_valid;
  logic [AW-1:0] ex_pc;
  logic [DW-1:0] ex_instr;
  logic [DW-1:0] ex_op1;
  logic [DW-1:0] ex_op2;
  logic [DW-1:0] ex_store_data;
  logic [4:0]    ex_rd;
  logic          ex_rf_we;
  logic [DW-1:0] ex_imm;
  alu_op_e       ex_alu_op;
  branch_op_e    ex_branch_op;
  jump_op_e      ex_jump_op;
  logic          ex_mem_req;
  logic          ex_mem_we;
  mem_size_e     ex_mem_size;
  logic          ex_mem_unsigned;
  wb_sel_e       ex_wb_sel;
  logic          ex_muldiv_valid;
  muldiv_op_e    ex_muldiv_op;
  logic          ex_illegal_instr;
  logic          ex_ecall;
  logic          ex_ebreak;
  // ============================================================
  // EX outputs
  // ============================================================
  logic          ex_wb_valid;
  logic          ex_wb_rf_wen;
  logic [4:0]    ex_wb_rf_waddr;
  wb_sel_e       ex_wb_sel_out;
  logic [DW-1:0] ex_wb_alu_data;
  logic [DW-1:0] ex_wb_pc4_data;
  mem_size_e     ex_wb_mem_size;
  logic          ex_wb_mem_unsigned;
  logic [1:0]    ex_wb_load_offset;
  logic          ex_wb_illegal_instr;
  logic          ex_wb_ecall;
  logic          ex_wb_ebreak;
  logic          ex_wb_mem_misaligned;
  logic          ex_redirect_en;
  logic [AW-1:0] ex_redirect_pc;
  logic          ex_flush_req;
  // ============================================================
  // Data memory
  // ============================================================
  logic            dmem_ren;
  logic            dmem_wen;
  logic [DW/8-1:0] dmem_wstrb;
  logic [AW-1:0]   dmem_addr;
  logic [DW-1:0]   dmem_wdata;
  logic [DW-1:0]   dmem_rdata;
  // ============================================================
  // EX/WB
  // ============================================================
  logic          wb_valid;
  logic          wb_rf_wen_pre;
  logic [4:0]    wb_rf_waddr_pre;
  wb_sel_e       wb_sel;
  logic [DW-1:0] wb_alu_data;
  logic [DW-1:0] wb_pc4_data;
  mem_size_e     wb_mem_size;
  logic          wb_mem_unsigned;
  logic [1:0]    wb_load_offset;
  logic          wb_illegal_instr;
  logic          wb_ecall;
  logic          wb_ebreak;
  logic          wb_mem_misaligned;
  // ============================================================
  // Final WB to regfile
  // ============================================================
  logic          wb_rf_wen;
  logic [4:0]    wb_rf_waddr;
  logic [DW-1:0] wb_rf_wdata;
  // ============================================================
  // Add trap/halt kill signals
  // ============================================================
  logic trap_event;
  logic pipe_kill;
  assign trap_event = 
      wb_valid && (wb_illegal_instr || wb_ecall || wb_ebreak || wb_mem_misaligned);
  assign pipe_kill = trap_event | halt_q;
  // ============================================================
  // Minimal halt/exception handling
  // ============================================================
  logic halt_q;
  logic exception_event;
  assign exception_event = trap_event;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      halt_q <= 1'b0;
    end
    else if (exception_event) begin
      halt_q <= 1'b1;
    end
  end
  assign halt_o          = halt_q;
  assign illegal_instr_o = wb_valid && wb_illegal_instr && !halt_q;
  assign exception_o     = exception_event && !halt_q;
`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
  //避免halt后重復打印，後續可能考慮從源頭保證wb_valid 在 halt 后为 0，而不是只屏蔽打印。
    if (!halt_q) begin 
      if (wb_valid && wb_illegal_instr) begin
        $error("RV32IM core illegal instruction detected at WB stage");
      end
      if (wb_valid && wb_ecall) begin
        $error("RV32IM core ECALL detected; halting core");
      end
      if (wb_valid && wb_ebreak) begin
        $info("RV32IM core EBREAK detected; halting core");
      end
      if (wb_valid && wb_mem_misaligned) begin
        $error("RV32IM core memory misaligned access detected");
      end
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
      id_valid &&
      ex_valid &&
      ex_rf_we &&
      ex_rd != 5'd0 &&
      (
        (id_use_rs1 && id_rs1_raddr == ex_rd) ||
        (id_use_rs2 && id_rs2_raddr == ex_rd)
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
  // ============================================================
  // IF/ID
  // ============================================================
  if2id #(
    .AW(AW),
    .DW(DW)
  ) u_if2id (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .flush_i (ifid_flush),
    .stall_i (ifid_stall),
    .valid_i (if_resp_valid_q),
    .pc_i    (if_resp_pc_q),
    .instr_i (instr_rdata_i),
    .valid_o (id_valid),
    .pc_o    (id_pc),
    .instr_o (id_instr)
  );
  // ============================================================
  // Decode
  // ============================================================
  decode #(
    .AW(AW),
    .DW(DW)
  ) u_decode (
    .pc_i             (id_pc),
    .instr_i          (id_instr),
    .rf_rs1_raddr_o   (id_rs1_raddr),
    .rf_rs2_raddr_o   (id_rs2_raddr),
    .rf_rs1_rdata_i   (id_rs1_rdata),
    .rf_rs2_rdata_i   (id_rs2_rdata),
    .op1_o            (id_op1),
    .op2_o            (id_op2),
    .store_data_o     (id_store_data),
    .use_rs1_o        (id_use_rs1),
    .use_rs2_o        (id_use_rs2),
    .rd_o             (id_rd),
    .rf_we_o          (id_rf_we),
    .imm_o            (id_imm),
    .alu_op_o         (id_alu_op),
    .branch_op_o      (id_branch_op),
    .jump_op_o        (id_jump_op),
    .mem_req_o        (id_mem_req),
    .mem_we_o         (id_mem_we),
    .mem_size_o       (id_mem_size),
    .mem_unsigned_o   (id_mem_unsigned),
    .wb_sel_o         (id_wb_sel),
    .muldiv_valid_o   (id_muldiv_valid),
    .muldiv_op_o      (id_muldiv_op),
    .illegal_instr_o  (id_illegal_instr),
    .ecall_o          (id_ecall),
    .ebreak_o         (id_ebreak)
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
  id2ex #(
    .AW(AW),
    .DW(DW)
  ) u_id2ex (
    .clk_i           (clk_i),
    .rst_ni          (rst_ni),
    .flush_i         (idex_flush),
    .stall_i         (idex_stall),
    .valid_i         (id_valid),
    .pc_i            (id_pc),
    .instr_i         (id_instr),
    .op1_i           (id_op1),
    .op2_i           (id_op2),
    .store_data_i    (id_store_data),
    .rd_i            (id_rd),
    .rf_we_i         (id_rf_we),
    .imm_i           (id_imm),
    .alu_op_i        (id_alu_op),
    .branch_op_i     (id_branch_op),
    .jump_op_i       (id_jump_op),
    .mem_req_i       (id_mem_req),
    .mem_we_i        (id_mem_we),
    .mem_size_i      (id_mem_size),
    .mem_unsigned_i  (id_mem_unsigned),
    .wb_sel_i        (id_wb_sel),
    .muldiv_valid_i  (id_muldiv_valid),
    .muldiv_op_i     (id_muldiv_op),
    .illegal_instr_i (id_illegal_instr),
    .ecall_i         (id_ecall),
    .ebreak_i        (id_ebreak),
    .valid_o         (ex_valid),
    .pc_o            (ex_pc),
    .instr_o         (ex_instr),
    .op1_o           (ex_op1),
    .op2_o           (ex_op2),
    .store_data_o    (ex_store_data),
    .rd_o            (ex_rd),
    .rf_we_o         (ex_rf_we),
    .imm_o           (ex_imm),
    .alu_op_o        (ex_alu_op),
    .branch_op_o     (ex_branch_op),
    .jump_op_o       (ex_jump_op),
    .mem_req_o       (ex_mem_req),
    .mem_we_o        (ex_mem_we),
    .mem_size_o      (ex_mem_size),
    .mem_unsigned_o  (ex_mem_unsigned),
    .wb_sel_o        (ex_wb_sel),
    .muldiv_valid_o  (ex_muldiv_valid),
    .muldiv_op_o     (ex_muldiv_op),
    .illegal_instr_o (ex_illegal_instr),
    .ecall_o         (ex_ecall),
    .ebreak_o        (ex_ebreak)
  );
  // ============================================================
  // Execute
  // ============================================================
  execute #(
    .AW(AW),
    .DW(DW)
  ) u_execute (
    .valid_i              (ex_valid),
    .pc_i                 (ex_pc),
    .instr_i              (ex_instr),
    .op1_i                (ex_op1),
    .op2_i                (ex_op2),
    .store_data_i         (ex_store_data),
    .rd_i                 (ex_rd),
    .rf_we_i              (ex_rf_we),
    .imm_i                (ex_imm),
    .alu_op_i             (ex_alu_op),
    .branch_op_i          (ex_branch_op),
    .jump_op_i            (ex_jump_op),
    .mem_req_i            (ex_mem_req),
    .mem_we_i             (ex_mem_we),
    .mem_size_i           (ex_mem_size),
    .mem_unsigned_i       (ex_mem_unsigned),
    .wb_sel_i             (ex_wb_sel),
    .muldiv_valid_i       (ex_muldiv_valid),
    .muldiv_op_i          (ex_muldiv_op),
    .illegal_instr_i      (ex_illegal_instr),
    .ecall_i              (ex_ecall),
    .ebreak_i             (ex_ebreak),
    .wb_valid_o           (ex_wb_valid),
    .wb_rf_wen_o          (ex_wb_rf_wen),
    .wb_rf_waddr_o        (ex_wb_rf_waddr),
    .wb_sel_o             (ex_wb_sel_out),
    .wb_alu_data_o        (ex_wb_alu_data),
    .wb_pc4_data_o        (ex_wb_pc4_data),
    .wb_mem_size_o        (ex_wb_mem_size),
    .wb_mem_unsigned_o    (ex_wb_mem_unsigned),
    .wb_load_offset_o     (ex_wb_load_offset),
    .wb_illegal_instr_o   (ex_wb_illegal_instr),
    .wb_ecall_o           (ex_wb_ecall),
    .wb_ebreak_o          (ex_wb_ebreak),
    .wb_mem_misaligned_o  (ex_wb_mem_misaligned),
    .redirect_en_o        (ex_redirect_en),
    .redirect_pc_o        (ex_redirect_pc),
    .flush_req_o          (ex_flush_req),
    .dmem_ren_o           (dmem_ren),
    .dmem_wen_o           (dmem_wen),
    .dmem_wstrb_o         (dmem_wstrb),
    .dmem_addr_o          (dmem_addr),
    .dmem_wdata_o         (dmem_wdata)
  );
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
    .DEPTH(DATA_RAM_DEPTH)
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
  // EX/WB
  // ============================================================
  logic ex2wb_valid_i;
  logic ex2wb_rf_wen_i;
  assign ex2wb_valid_i = ex_wb_valid && !pipe_kill;
  assign ex2wb_rf_wen_i = ex_wb_rf_wen && !pipe_kill;
  ex2wb #(
    .DW(DW)
  ) u_ex2wb (
    .clk_i             (clk_i),
    .rst_ni            (rst_ni),
    .valid_i           (ex2wb_valid_i),
    .rf_wen_i          (ex2wb_rf_wen_i),
    .rf_waddr_i        (ex_wb_rf_waddr),
    .wb_sel_i          (ex_wb_sel_out),
    .alu_data_i        (ex_wb_alu_data),
    .pc4_data_i        (ex_wb_pc4_data),
    .mem_size_i        (ex_wb_mem_size),
    .mem_unsigned_i    (ex_wb_mem_unsigned),
    .load_offset_i     (ex_wb_load_offset),
    .illegal_instr_i   (ex_wb_illegal_instr && !pipe_kill),
    .ecall_i           (ex_wb_ecall && !pipe_kill),
    .ebreak_i          (ex_wb_ebreak && !pipe_kill),
    .mem_misaligned_i  (ex_wb_mem_misaligned && !pipe_kill),
    .valid_o           (wb_valid),
    .rf_wen_o          (wb_rf_wen_pre),
    .rf_waddr_o        (wb_rf_waddr_pre),
    .wb_sel_o          (wb_sel),
    .alu_data_o        (wb_alu_data),
    .pc4_data_o        (wb_pc4_data),
    .mem_size_o        (wb_mem_size),
    .mem_unsigned_o    (wb_mem_unsigned),
    .load_offset_o     (wb_load_offset),
    .illegal_instr_o   (wb_illegal_instr),
    .ecall_o           (wb_ecall),
    .ebreak_o          (wb_ebreak),
    .mem_misaligned_o  (wb_mem_misaligned)
  );
  // ============================================================
  // WB
  // ============================================================
  wb_stage #(
    .DW(DW)
  ) u_wb_stage (
    .valid_i          (wb_valid),
    .rf_wen_i         (wb_rf_wen_pre),
    .rf_waddr_i       (wb_rf_waddr_pre),
    .wb_sel_i         (wb_sel),
    .alu_data_i       (wb_alu_data),
    .pc4_data_i       (wb_pc4_data),
    .mem_size_i       (wb_mem_size),
    .mem_unsigned_i   (wb_mem_unsigned),
    .load_offset_i    (wb_load_offset),
    .dmem_rdata_i     (dmem_rdata),
    .illegal_instr_i  (wb_illegal_instr),
    .ecall_i          (wb_ecall),
    .ebreak_i         (wb_ebreak),
    .mem_misaligned_i (wb_mem_misaligned),
    .rf_wen_o         (wb_rf_wen),
    .rf_waddr_o       (wb_rf_waddr),
    .rf_wdata_o       (wb_rf_wdata)
  );
endmodule
`default_nettype wire