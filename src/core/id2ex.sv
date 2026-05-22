`timescale 1ns / 1ps
`include "define.sv"
module id2ex #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          instr_hold,
  input  logic [AW-1:0] instr_addr_in,
  input  logic [DW-1:0] instr_in,
  input  logic [DW-1:0] op1_in,
  input  logic [DW-1:0] op2_in,
  input  logic [DW-1:0] store_data_in,
  output logic [AW-1:0] instr_addr_out,
  output logic [DW-1:0] instr_out,
  output logic [DW-1:0] op1_out,
  output logic [DW-1:0] op2_out,
  output logic [DW-1:0] store_data_out
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
      op1_out        <= '0;
      op2_out        <= '0;
      store_data_out <= '0;
    end
    else if (instr_hold) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
      op1_out        <= '0;
      op2_out        <= '0;
      store_data_out <= '0;
    end
    else begin
      instr_addr_out <= instr_addr_in;
      instr_out      <= instr_in;
      op1_out        <= op1_in;
      op2_out        <= op2_in;
      store_data_out <= store_data_in;
    end
  end
endmodule