`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
module if2id #(
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
  output logic          valid_o,
  output logic [AW-1:0] pc_o,
  output logic [DW-1:0] instr_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_o <= 1'b0;
      pc_o    <= '0;
      instr_o <= INST_NOP;
    end
    else if (flush_i) begin
      valid_o <= 1'b0;
      pc_o    <= '0;
      instr_o <= INST_NOP;
    end
    else if (!stall_i) begin
      valid_o <= valid_i;
      pc_o    <= pc_i;
      instr_o <= instr_i;
    end
  end
endmodule
`default_nettype wire