`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
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
  output logic [DW-1:0] dbg_x11_o
);
  // =========================================================
  // IF request PC and synchronous instruction response tracking
  // =========================================================
  logic [AW-1:0] if_pc;
  logic [AW-1:0] if_resp_pc_q;
  logic          if_resp_valid_q;
  // branch/jump 后，由于同步 RAM 下一拍还会返回旧路径指令，
  // 所以需要 fetch_kill_q 杀掉这条返回指令。
  logic          fetch_kill_q;
  // =========================================================
  // IF/ID
  // =========================================================
  logic          id_valid;
  logic [AW-1:0] id_pc;
  logic [DW-1:0] id_instr;
  // =========================================================
  // Decode / Regfile
  // =========================================================
  logic [4:0]    id_rs1_raddr;
  logic [4:0]    id_rs2_raddr;
  logic [DW-1:0] id_rs1_rdata;
  logic [DW-1:0] id_rs2_rdata;
  logic [DW-1:0] id_op1;
  logic [DW-1:0] id_op2;
  logic [DW-1:0] id_store_data;
  // =========================================================
  // ID/EX
  // =========================================================
  logic          ex_valid;
  logic [AW-1:0] ex_pc;
  logic [DW-1:0] ex_instr;
  logic [DW-1:0] ex_op1;
  logic [DW-1:0] ex_op2;
  logic [DW-1:0] ex_store_data;
  // =========================================================
  // EX outputs
  // =========================================================
  logic          ex_wb_valid;
  logic          ex_wb_rf_wen;
  logic [4:0]    ex_wb_rf_waddr;
  logic [DW-1:0] ex_wb_alu_data;
  logic          ex_wb_is_load;
  logic [2:0]    ex_wb_load_funct3;
  logic [1:0]    ex_wb_load_offset;
  logic          ex_redirect_en;
  logic [AW-1:0] ex_redirect_pc;
  logic          ex_flush_req;
  // =========================================================
  // Data memory
  // =========================================================
  logic          dmem_ren;
  logic          dmem_wen;
  logic [DW/8-1:0] dmem_wstrb;
  logic [AW-1:0] dmem_addr;
  logic [DW-1:0] dmem_wdata;
  logic [DW-1:0] dmem_rdata;
  // =========================================================
  // EX/WB
  // =========================================================
  logic          wb_valid;
  logic          wb_rf_wen_pre;
  logic [4:0]    wb_rf_waddr_pre;
  logic [DW-1:0] wb_alu_data;
  logic          wb_is_load;
  logic [2:0]    wb_load_funct3;
  logic [1:0]    wb_load_offset;
  // =========================================================
  // Final WB to regfile
  // =========================================================
  logic          wb_rf_wen;
  logic [4:0]    wb_rf_waddr;
  logic [DW-1:0] wb_rf_wdata;
  // =========================================================
  // Hazard detection
  // =========================================================
  logic [6:0] id_opcode;
  logic       id_use_rs1;
  logic       id_use_rs2;
  logic       hazard_stall;
  assign id_opcode = id_instr[6:0];
  always_comb begin
    id_use_rs1 = 1'b0;
    id_use_rs2 = 1'b0;
    unique case (id_opcode)
      OPCODE_OP_IMM: begin id_use_rs1 = 1'b1; id_use_rs2 = 1'b0; end
      OPCODE_OP:     begin id_use_rs1 = 1'b1; id_use_rs2 = 1'b1; end
      OPCODE_LOAD:   begin id_use_rs1 = 1'b1; id_use_rs2 = 1'b0; end
      OPCODE_STORE:  begin id_use_rs1 = 1'b1; id_use_rs2 = 1'b1; end
      OPCODE_BRANCH: begin id_use_rs1 = 1'b1; id_use_rs2 = 1'b1; end
      OPCODE_JALR:   begin id_use_rs1 = 1'b1; id_use_rs2 = 1'b0; end
      default:       begin id_use_rs1 = 1'b0; id_use_rs2 = 1'b0; end
    endcase
  end
  assign hazard_stall =
      id_valid &&
      ex_valid &&
      ex_wb_rf_wen &&
      ex_wb_rf_waddr != 5'd0 &&
      (
        (id_use_rs1 && id_rs1_raddr == ex_wb_rf_waddr) ||
        (id_use_rs2 && id_rs2_raddr == ex_wb_rf_waddr)
      );
  // =========================================================
  // Pipeline control
  // =========================================================
  logic pc_stall;
  logic ifid_stall;
  logic ifid_flush;
  logic idex_flush;
  assign pc_stall   = hazard_stall;
  assign ifid_stall = hazard_stall;
  // 同步取指下，redirect 当拍 flush 当前 IF/ID；
  // 下一拍 fetch_kill_q flush RAM 返回的旧路径指令。
  assign ifid_flush = ex_flush_req | fetch_kill_q;
  // hazard 插 bubble；redirect 杀掉 ID->EX 的年轻指令。
  assign idex_flush = ex_flush_req | hazard_stall;
  // =========================================================
  // PC and instruction fetch
  // =========================================================
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
  assign instr_ren_o  = 1'b1;
  assign instr_addr_o = if_pc;
  // 保存同步 RAM 请求对应的 PC。
  // if_resp_pc_q 在下一拍与 instr_rdata_i 对齐。
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
        if_resp_valid_q <= 1'b1;
      end
    end
  end
  // =========================================================
  // IF/ID
  // =========================================================
  if2id #(
    .AW(AW),
    .DWW)
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
  // =========================================================
  // Decode
  // =========================================================
  decode #(
    .AW(AW),
    .DW(DW)
  ) u_decode (
    .pc_i           (id_pc),
    .instr_i        (id_instr),
    .rf_rs1_raddr_o (id_rs1_raddr),
    .rf_rs2_raddr_o (id_rs2_raddr),
    .rf_rs1_rdata_i (id_rs1_rdata),
    .rf_rs2_rdata_i (id_rs2_rdata),
    .op1_o          (id_op1),
    .op2_o          (id_op2),
    .store_data_o   (id_store_data)
  );
  // =========================================================
  // Regfile
  // =========================================================
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
  // =========================================================
  // ID/EX
  // =========================================================
  id2ex #(
    .AW(AW),
    .DW(DW)
  ) u_id2ex (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .flush_i      (idex_flush),
    .stall_i      (1'b0),
    .valid_i      (id_valid),
    .pc_i         (id_pc),
    .instr_i      (id_instr),
    .op1_i        (id_op1),
    .op2_i        (id_op2),
    .store_data_i (id_store_data),
    .valid_o      (ex_valid),
    .pc_o         (ex_pc),
    .instr_o      (ex_instr),
    .op1_o        (ex_op1),
    .op2_o        (ex_op2),
    .store_data_o (ex_store_data)
  );
  // =========================================================
  // EX
  // =========================================================
  execute #(
    .AW(AW),
    .DW(DW)
  ) u_execute (
    .valid_i         (ex_valid),
    .pc_i            (ex_pc),
    .instr_i         (ex_instr),
    .op1_i           (ex_op1),
    .op2_i           (ex_op2),
    .store_data_i    (ex_store_data),
    .wb_valid_o      (ex_wb_valid),
    .wb_rf_wen_o     (ex_wb_rf_wen),
    .wb_rf_waddr_o   (ex_wb_rf_waddr),
    .wb_alu_data_o   (ex_wb_alu_data),
    .wb_is_load_o    (ex_wb_is_load),
    .wb_load_funct3_o(ex_wb_load_funct3),
    .wb_load_offset_o(ex_wb_load_offset),
    .redirect_en_o   (ex_redirect_en),
    .redirect_pc_o   (ex_redirect_pc),
    .flush_req_o     (ex_flush_req),
    .dmem_ren_o      (dmem_ren),
    .dmem_wen_o      (dmem_wen),
    .dmem_wstrb_o    (dmem_wstrb),
    .dmem_addr_o     (dmem_addr),
    .dmem_wdata_o    (dmem_wdata)
  );
  // =========================================================
  // Data RAM
  // =========================================================
  data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DATA_RAM_DEPTH)
  ) u_data_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .ren_i   (dmem_ren),
    .wen_i   (dmem_wen),
    .wstrb_i (dmem_wstrb),
    .addr_i  (dmem_addr),
    .wdata_i (dmem_wdata),
    .rdata_o (dmem_rdata)
  );
  // =========================================================
  // EX/WB
  // =========================================================
  ex2wb #(
    .DW(DW)
  ) u_ex2wb (
    .clk_i        (clk_i),
    .rst_ni       (rst_ni),
    .valid_i      (ex_wb_valid),
    .rf_wen_i     (ex_wb_rf_wen),
    .rf_waddr_i   (ex_wb_rf_waddr),
    .alu_data_i   (ex_wb_alu_data),
    .is_load_i    (ex_wb_is_load),
    .load_funct3_i(ex_wb_load_funct3),
    .load_offset_i(ex_wb_load_offset),
    .valid_o      (wb_valid),
    .rf_wen_o     (wb_rf_wen_pre),
    .rf_waddr_o   (wb_rf_waddr_pre),
    .alu_data_o   (wb_alu_data),
    .is_load_o    (wb_is_load),
    .load_funct3_o(wb_load_funct3),
    .load_offset_o(wb_load_offset)
  );
  // =========================================================
  // WB
  // =========================================================
  wb_stage #(
    .DW(DW)
  ) u_wb_stage (
    .valid_i      (wb_valid),
    .rf_wen_i     (wb_rf_wen_pre),
    .rf_waddr_i   (wb_rf_waddr_pre),
    .alu_data_i   (wb_alu_data),
    .is_load_i    (wb_is_load),
    .load_funct3_i(wb_load_funct3),
    .load_offset_i(wb_load_offset),
    .dmem_rdata_i (dmem_rdata),
    .rf_wen_o     (wb_rf_wen),
    .rf_waddr_o   (wb_rf_waddr),
    .rf_wdata_o   (wb_rf_wdata)
  );
endmodule
`default_nettype wire