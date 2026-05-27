`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
module decode #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic [AW-1:0] pc_i,
  input  logic [DW-1:0] instr_i,
  output logic [4:0]    rf_rs1_raddr_o,
  output logic [4:0]    rf_rs2_raddr_o,
  input  logic [DW-1:0] rf_rs1_rdata_i,
  input  logic [DW-1:0] rf_rs2_rdata_i,
  output logic [DW-1:0] op1_o,
  output logic [DW-1:0] op2_o,
  output logic [DW-1:0] store_data_o
);
  logic [6:0] opcode;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [DW-1:0] imm_i;
  logic [DW-1:0] imm_s;
  logic [DW-1:0] imm_j;
  logic [DW-1:0] imm_u;
  assign opcode = instr_i[6:0];
  assign rs1    = instr_i[19:15];
  assign rs2    = instr_i[24:20];
  assign imm_i = {{20{instr_i[31]}}, instr_i[31:20]};
  assign imm_s = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
  assign imm_j = {{11{instr_i[31]}},
                  instr_i[31],
                  instr_i[19:12],
                  instr_i[20],
                  instr_i[30:21],
                  1'b0};
  assign imm_u = {instr_i[31:12], 12'h000};
  always_comb begin
    rf_rs1_raddr_o = 5'd0;
    rf_rs2_raddr_o = 5'd0;
    op1_o        = '0;
    op2_o        = '0;
    store_data_o = '0;
    unique case (opcode)
      OPCODE_OP_IMM: begin
        rf_rs1_raddr_o = rs1;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_i;
      end
      OPCODE_OP: begin
        rf_rs1_raddr_o = rs1;
        rf_rs2_raddr_o = rs2;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = rf_rs2_rdata_i;
      end
      OPCODE_LOAD: begin
        rf_rs1_raddr_o = rs1;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_i;
      end
      OPCODE_STORE: begin
        rf_rs1_raddr_o = rs1;
        rf_rs2_raddr_o = rs2;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_s;
        store_data_o   = rf_rs2_rdata_i;
      end
      OPCODE_BRANCH: begin
        rf_rs1_raddr_o = rs1;
        rf_rs2_raddr_o = rs2;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = rf_rs2_rdata_i;
      end
      OPCODE_JAL: begin
        op1_o = pc_i;
        op2_o = imm_j;
      end
      OPCODE_JALR: begin
        rf_rs1_raddr_o = rs1;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_i;
      end
      OPCODE_LUI: begin
        op1_o = '0;
        op2_o = imm_u;
      end
      OPCODE_AUIPC: begin
        op1_o = pc_i;
        op2_o = imm_u;
      end
      default: begin
        rf_rs1_raddr_o = 5'd0;
        rf_rs2_raddr_o = 5'd0;
        op1_o          = '0;
        op2_o          = '0;
        store_data_o   = '0;
      end
    endcase
  end
endmodule
`default_nettype wire