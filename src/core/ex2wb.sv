`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
module ex2wb #(
  parameter int DW = riscv_pkg::DW
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          valid_i,
  input  logic          rf_wen_i,
  input  logic [4:0]    rf_waddr_i,
  input  logic [DW-1:0] alu_data_i,
  input  logic          is_load_i,
  input  logic [2:0]    load_funct3_i,
  input  logic [1:0]    load_offset_i,
  output logic          valid_o,
  output logic          rf_wen_o,
  output logic [4:0]    rf_waddr_o,
  output logic [DW-1:0] alu_data_o,
  output logic          is_load_o,
  output logic [2:0]    load_funct3_o,
  output logic [1:0]    load_offset_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_o       <= 1'b0;
      rf_wen_o      <= 1'b0;
      rf_waddr_o    <= 5'd0;
      alu_data_o    <= '0;
      is_load_o     <= 1'b0;
      load_funct3_o <= 3'd0;
      load_offset_o <= 2'd0;
    end
    else begin
      valid_o       <= valid_i;
      rf_wen_o      <= rf_wen_i;
      rf_waddr_o    <= rf_waddr_i;
      alu_data_o    <= alu_data_i;
      is_load_o     <= is_load_i;
      load_funct3_o <= load_funct3_i;
      load_offset_o <= load_offset_i;
    end
  end
endmodule
`default_nettype wire