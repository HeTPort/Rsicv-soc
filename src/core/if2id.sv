`timescale 1ns / 1ps
`include "define.sv"
module if2id #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          instr_hold,
  input  logic [AW-1:0] instr_addr_in,
  input  logic [DW-1:0] instr_in,
  output logic [AW-1:0] instr_addr_out,
  output logic [DW-1:0] instr_out
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
    end
    else if (instr_hold) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
    end
    else begin
      instr_addr_out <= instr_addr_in;
      instr_out      <= instr_in;
    end
  end
endmodule