`timescale 1ns / 1ps
import riscv_pkg::*;
module riscv_soc #(
  parameter AW             = 32,
  parameter DW             = 32,
  parameter PROG_RAM_DEPTH = 4096,
  parameter DATA_RAM_DEPTH = 4096
)(
  input  logic              clk,
  input  logic              rst_n,
  // program ram write port
  input  logic              prog_wr_en,
  input  logic [AW-1:0]     prog_wr_addr,
  input  logic [DW-1:0]     prog_wr_data,
  input  logic              load_done,
  output logic [DW-1:0]     test_case,
  output logic [DW-1:0]     reg_s10,
  output logic [DW-1:0]     reg_s11,
  output commit_pkt_t       commit_o
);
  logic          cpu_rst_n;
  logic          instr_ren;
  logic [AW-1:0] instr_addr;
  logic [DW-1:0] instr_rdata;
  assign cpu_rst_n = rst_n & load_done;
  prog_ram #(
    .AW(AW), .DW(DW), .DEPTH(PROG_RAM_DEPTH)
  ) u_prog_ram (
    .clk_i        (clk),
    .ren_i        (instr_ren),
    .instr_addr_i (instr_addr),
    .instr_data_o (instr_rdata),
    .wen_i        (prog_wr_en),
    .waddr_i      (prog_wr_addr),
    .wdata_i      (prog_wr_data)
  );
  riscv #(
    .AW(AW), .DW(DW), .DATA_RAM_DEPTH(DATA_RAM_DEPTH)
  ) u_riscv (
    .clk_i           (clk),
    .rst_ni          (cpu_rst_n),
    .instr_ren_o     (instr_ren),
    .instr_addr_o    (instr_addr),
    .instr_rdata_i   (instr_rdata),
    .dbg_x3_o        (test_case),
    .dbg_x10_o       (reg_s10),
    .dbg_x11_o       (reg_s11),
    .halt_o          (),
    .illegal_instr_o (),
    .exception_o     (),
    .commit_o        (commit_o)
  );
endmodule
