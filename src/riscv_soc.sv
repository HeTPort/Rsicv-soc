`timescale 1ns / 1ps
import riscv_pkg::*;
import soc_mem_map_pkg::*;
module riscv_soc #(
  parameter AW             = 32,
  parameter DW             = 32,
  parameter PROG_RAM_DEPTH = SOC_PROG_RAM_DEPTH_WORDS,
  parameter DATA_RAM_DEPTH = SOC_DATA_RAM_DEPTH_WORDS,
  parameter int DATA_REQ_WAIT_CYCLES = 0,
  parameter int DATA_RSP_WAIT_CYCLES = 0
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
  logic          instr_fetch_error;
  localparam logic [AW-1:0] DATA_RAM_END =
      SOC_DATA_RAM_BASE + (DATA_RAM_DEPTH * (DW / 8)) - 1;

  logic          cpu_data_req_valid;
  logic          cpu_data_req_ready;
  core_bus_req_t cpu_data_req;
  logic          cpu_data_rsp_valid;
  core_bus_rsp_t cpu_data_rsp;
  logic          ram_data_req_valid;
  logic          ram_data_req_ready;
  core_bus_req_t ram_data_req;
  logic          ram_data_rsp_valid;
  core_bus_rsp_t ram_data_rsp;
  assign cpu_rst_n = rst_n & load_done;
  prog_ram #(
    .AW(AW), .DW(DW), .DEPTH(PROG_RAM_DEPTH)
  ) u_prog_ram (
    .clk_i        (clk),
    .ren_i        (instr_ren),
    .instr_addr_i (instr_addr),
    .instr_data_o (instr_rdata),
    .fetch_error_o(instr_fetch_error),
    .wen_i        (prog_wr_en),
    .waddr_i      (prog_wr_addr),
    .wdata_i      (prog_wr_data)
  );
  riscv #(
    .AW(AW), .DW(DW)
  ) u_riscv (
    .clk_i           (clk),
    .rst_ni          (cpu_rst_n),
    .instr_ren_o     (instr_ren),
    .instr_addr_o    (instr_addr),
    .instr_rdata_i   (instr_rdata),
    .instr_fetch_error_i(instr_fetch_error),
    .data_req_valid_o(cpu_data_req_valid),
    .data_req_ready_i(cpu_data_req_ready),
    .data_req_o      (cpu_data_req),
    .data_rsp_valid_i(cpu_data_rsp_valid),
    .data_rsp_i      (cpu_data_rsp),
    .dbg_x3_o        (test_case),
    .dbg_x10_o       (reg_s10),
    .dbg_x11_o       (reg_s11),
    .halt_o          (),
    .illegal_instr_o (),
    .exception_o     (),
    .commit_o        (commit_o)
  );

  soc_data_fabric #(
    .AW(AW),
    .DW(DW),
    .DATA_RAM_BASE(SOC_DATA_RAM_BASE),
    .DATA_RAM_END(DATA_RAM_END),
    .DEFAULT_RDATA(SOC_DEFAULT_RDATA),
    .DEFAULT_ERROR(SOC_DEFAULT_RESPONSE_ERROR)
  ) u_data_fabric (
    .clk_i            (clk),
    .rst_ni           (cpu_rst_n),
    .cpu_req_valid_i  (cpu_data_req_valid),
    .cpu_req_ready_o  (cpu_data_req_ready),
    .cpu_req_i        (cpu_data_req),
    .cpu_rsp_valid_o  (cpu_data_rsp_valid),
    .cpu_rsp_o        (cpu_data_rsp),
    .data_req_valid_o (ram_data_req_valid),
    .data_req_ready_i (ram_data_req_ready),
    .data_req_o       (ram_data_req),
    .data_rsp_valid_i (ram_data_rsp_valid),
    .data_rsp_i       (ram_data_rsp)
  );

  core_bus_data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DATA_RAM_DEPTH),
    .REQ_WAIT_CYCLES(DATA_REQ_WAIT_CYCLES),
    .RSP_WAIT_CYCLES(DATA_RSP_WAIT_CYCLES)
  ) u_data_target (
    .clk_i       (clk),
    .rst_ni      (cpu_rst_n),
    .req_valid_i (ram_data_req_valid),
    .req_ready_o (ram_data_req_ready),
    .req_i       (ram_data_req),
    .rsp_valid_o (ram_data_rsp_valid),
    .rsp_o       (ram_data_rsp)
  );
endmodule
