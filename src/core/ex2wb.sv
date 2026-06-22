`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: ex2wb
// Description:
//   Pipeline register between EX and WB stages.
//
// Responsibilities:
//   - Register writeback control and data.
//   - Register load extension control.
//   - Register exception/halt related flags.
// ============================================================
module ex2wb #(
  parameter int DW = riscv_pkg::DW
)(
  input  wire logic          clk_i,
  input  wire logic          rst_ni,
  input  wire logic          valid_i,
  input  wire logic          rf_wen_i,
  input  wire logic [4:0]    rf_waddr_i,
  input  wire wb_sel_e       wb_sel_i,
  input  wire logic [DW-1:0] alu_data_i,
  input  wire logic [DW-1:0] pc4_data_i,
  input  wire mem_size_e     mem_size_i,
  input  wire logic          mem_unsigned_i,
  input  wire logic [1:0]    load_offset_i,
  input  wire logic          illegal_instr_i,
  input  wire logic          ecall_i,
  input  wire logic          ebreak_i,
  input  wire logic          mem_misaligned_i,
  output logic          valid_o,
  output logic          rf_wen_o,
  output logic [4:0]    rf_waddr_o,
  output wb_sel_e       wb_sel_o,
  output logic [DW-1:0] alu_data_o,
  output logic [DW-1:0] pc4_data_o,
  output mem_size_e     mem_size_o,
  output logic          mem_unsigned_o,
  output logic [1:0]    load_offset_o,
  output logic          illegal_instr_o,
  output logic          ecall_o,
  output logic          ebreak_o,
  output logic          mem_misaligned_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      valid_o          <= 1'b0;
      rf_wen_o         <= 1'b0;
      rf_waddr_o       <= 5'd0;
      wb_sel_o         <= WB_NONE;
      alu_data_o       <= '0;
      pc4_data_o       <= '0;
      mem_size_o       <= MEM_SIZE_WORD;
      mem_unsigned_o   <= 1'b0;
      load_offset_o    <= 2'd0;
      illegal_instr_o  <= 1'b0;
      ecall_o          <= 1'b0;
      ebreak_o         <= 1'b0;
      mem_misaligned_o <= 1'b0;
    end
    else begin
      valid_o          <= valid_i;
      rf_wen_o         <= rf_wen_i;
      rf_waddr_o       <= rf_waddr_i;
      wb_sel_o         <= wb_sel_i;
      alu_data_o       <= alu_data_i;
      pc4_data_o       <= pc4_data_i;
      mem_size_o       <= mem_size_i;
      mem_unsigned_o   <= mem_unsigned_i;
      load_offset_o    <= load_offset_i;
      illegal_instr_o  <= illegal_instr_i;
      ecall_o          <= ecall_i;
      ebreak_o         <= ebreak_i;
      mem_misaligned_o <= mem_misaligned_i;
    end
  end
endmodule
`default_nettype wire