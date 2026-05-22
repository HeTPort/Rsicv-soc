`timescale 1ns / 1ps
`include "define.sv"
module decode #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic [AW-1:0] instr_addr_in,
  input  logic [DW-1:0] instr_in,
  // to regfile
  output logic [4:0]    rd_rs1_addr,
  output logic [4:0]    rd_rs2_addr,
  // from regfile
  input  logic [DW-1:0] rd_rs1_data,
  input  logic [DW-1:0] rd_rs2_data,
  // to execute
  output logic [DW-1:0] op1_out,
  output logic [DW-1:0] op2_out,
  output logic [DW-1:0] store_data_out
);
  logic [6:0] opcode;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [DW-1:0] imm_i;
  logic [DW-1:0] imm_s;
  logic [DW-1:0] imm_j;
  logic [DW-1:0] imm_u;
  assign opcode = instr_in[6:0];
  assign rs1    = instr_in[19:15];
  assign rs2    = instr_in[24:20];
  assign imm_i  = {{20{instr_in[31]}}, instr_in[31:20]};
  assign imm_s  = {{20{instr_in[31]}}, instr_in[31:25], instr_in[11:7]};
  assign imm_j  = {{11{instr_in[31]}}, instr_in[31], instr_in[19:12], instr_in[20], instr_in[30:21], 1'b0};
  assign imm_u  = {instr_in[31:12], 12'h000};
  always_comb begin
    rd_rs1_addr    = 5'd0;
    rd_rs2_addr    = 5'd0;
    op1_out        = '0;
    op2_out        = '0;
    store_data_out = '0;
    unique case (opcode)
      `INST_TYPE_I: begin
        rd_rs1_addr    = rs1;
        op1_out        = rd_rs1_data;
        op2_out        = imm_i;
      end
      `INST_TYPE_R_M: begin
        rd_rs1_addr    = rs1;
        rd_rs2_addr    = rs2;
        op1_out        = rd_rs1_data;
        op2_out        = rd_rs2_data;
      end
      `INST_TYPE_L: begin
        rd_rs1_addr    = rs1;
        op1_out        = rd_rs1_data;
        op2_out        = imm_i;
      end
      `INST_TYPE_S: begin
        rd_rs1_addr    = rs1;
        rd_rs2_addr    = rs2;
        op1_out        = rd_rs1_data;
        op2_out        = imm_s;
        store_data_out = rd_rs2_data;
      end
      `INST_TYPE_B: begin
        rd_rs1_addr    = rs1;
        rd_rs2_addr    = rs2;
        op1_out        = rd_rs1_data;
        op2_out        = rd_rs2_data;
      end
      `INST_TYPE_JAL: begin
        op1_out        = instr_addr_in;
        op2_out        = imm_j;
      end
      `INST_TYPE_JALR: begin
        rd_rs1_addr    = rs1;
        op1_out        = rd_rs1_data;
        op2_out        = imm_i;
      end
      `INST_LUI: begin
        op2_out        = imm_u;
      end
      `INST_AUIPC: begin
        op1_out        = instr_addr_in;
        op2_out        = imm_u;
      end
      default: begin
        rd_rs1_addr    = 5'd0;
        rd_rs2_addr    = 5'd0;
        op1_out        = '0;
        op2_out        = '0;
        store_data_out = '0;
      end
    endcase
  end
endmodule