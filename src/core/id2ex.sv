`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
module id2ex #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          flush_i,
  input  logic          stall_i,
  input  logic          valid_i,
  input  logic [AW-1:0] pc_i,
  input  logic [DW-1:0] instr_i,
  input  logic [DW-1:0] op1_i,
  input  logic [DW-1:0] op2_i,
  input  logic [DW-1:0] store_data_i,
  output logic          valid_o,
  output logic [AW-1:0] pc_o,
  output logic [DW-1:0] instr_o,
  output logic [DW-1:0] op1_o,
  output logic [DW-1:0] op2_o,
  output logic [DW-1:0] store_data_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_o      <= 1'b0;
      pc_o         <= '0;
      instr_o      <= INST_NOP;
      op1_o        <= '0;
      op2_o        <= '0;
      store_data_o <= '0;
    end
    else if (flush_i) begin
      valid_o      <= 1'b0;
      pc_o         <= '0;
      instr_o      <= INST_NOP;
      op1_o        <= '0;
      op2_o        <= '0;
      store_data_o <= '0;
    end
    else if (!stall_i) begin
      valid_o      <= valid_i;
      pc_o         <= pc_i;
      instr_o      <= instr_i;
      op1_o        <= op1_i;
      op2_o        <= op2_i;
      store_data_o <= store_data_i;
    end
  end
endmodule
`default_nettype wire