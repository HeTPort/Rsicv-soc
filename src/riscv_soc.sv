`timescale 1ns / 1ps
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
  output logic [DW-1:0]     reg_s11
);
  logic          cpu_rst_n;
  logic [AW-1:0] instr_addr;
  logic [DW-1:0] instr_rdata;
  assign cpu_rst_n = rst_n & load_done;
  prog_ram #(
    .AW(AW), .DW(DW), .DEPTH(PROG_RAM_DEPTH)
  ) u_prog_ram (
    .clk(clk),
    .cpu_addr(instr_addr), .cpu_rdata(instr_rdata),
    .wr_en(prog_wr_en), .wr_addr(prog_wr_addr), .wr_data(prog_wr_data)
  );
  riscv #(
    .AW(AW), .DW(DW), .DATA_RAM_DEPTH(DATA_RAM_DEPTH)
  ) u_riscv (
    .clk(clk), .rst_n(cpu_rst_n),
    .instr_addr(instr_addr), .instr_rdata(instr_rdata),
    .test_case(test_case), .reg_s10(reg_s10), .reg_s11(reg_s11)
  );
endmodule