`timescale 1ns / 1ps
import riscv_pkg::*;
import soc_mem_map_pkg::*;
module riscv_soc #(
  parameter AW             = 32,
  parameter DW             = 32,
  parameter PROG_RAM_DEPTH = SOC_PROG_RAM_DEPTH_WORDS,
  parameter DATA_RAM_DEPTH = SOC_DATA_RAM_DEPTH_WORDS,
  parameter int DATA_REQ_WAIT_CYCLES = 0,
  parameter int DATA_RSP_WAIT_CYCLES = 0,
  parameter int unsigned TIMER_TICK_CYCLES = 1,
  parameter int unsigned UART_CLK_FREQ_HZ = 25_000_000,
  parameter int unsigned UART_BAUD_RATE = 115_200
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
  output commit_pkt_t       commit_o,
  output trap_entry_t       trap_entry_o,
  output logic              uart_tx_o
);
  logic          cpu_rst_n;
  logic          instr_ren;
  logic [AW-1:0] instr_addr;
  logic [DW-1:0] instr_rdata;
  logic          instr_fetch_error;
  localparam logic [AW-1:0] DATA_RAM_END =
      SOC_DATA_RAM_BASE + (DATA_RAM_DEPTH * (DW / 8)) - 1;
  localparam logic [AW-1:0] MTIMECMP_LOCAL_OFFSET =
      SOC_MTIMECMP_ADDR - SOC_TIMER_BASE;
  localparam logic [AW-1:0] MTIME_LOCAL_OFFSET =
      SOC_MTIME_ADDR - SOC_TIMER_BASE;
  localparam logic [AW-1:0] UART_TXDATA_LOCAL_OFFSET =
      SOC_UART_TXDATA_ADDR - SOC_UART_BASE;
  localparam logic [AW-1:0] UART_STATUS_LOCAL_OFFSET =
      SOC_UART_STATUS_ADDR - SOC_UART_BASE;

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
  logic          timer_req_valid;
  logic          timer_req_ready;
  core_bus_req_t timer_req;
  logic          timer_rsp_valid;
  core_bus_rsp_t timer_rsp;
  logic          timer_irq_mti;
  logic          uart_req_valid;
  logic          uart_req_ready;
  core_bus_req_t uart_req;
  logic          uart_rsp_valid;
  core_bus_rsp_t uart_rsp;
  logic          uart_tx_ready;
  logic          uart_tx_busy;
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
    .irq_mti_i       (timer_irq_mti),
    .wfi_wait_o      (),
    .trap_entry_o    (trap_entry_o),
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
    .TIMER_BASE(SOC_TIMER_BASE),
    .TIMER_END(SOC_TIMER_END),
    .UART_BASE(SOC_UART_BASE),
    .UART_END(SOC_UART_END),
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
    .timer_req_valid_o(timer_req_valid),
    .timer_req_ready_i(timer_req_ready),
    .timer_req_o      (timer_req),
    .timer_rsp_valid_i(timer_rsp_valid),
    .timer_rsp_i      (timer_rsp),
    .uart_req_valid_o (uart_req_valid),
    .uart_req_ready_i (uart_req_ready),
    .uart_req_o       (uart_req),
    .uart_rsp_valid_i (uart_rsp_valid),
    .uart_rsp_i       (uart_rsp),
    .data_req_valid_o (ram_data_req_valid),
    .data_req_ready_i (ram_data_req_ready),
    .data_req_o       (ram_data_req),
    .data_rsp_valid_i (ram_data_rsp_valid),
    .data_rsp_i       (ram_data_rsp)
  );

  core_bus_uart #(
    .AW(AW),
    .DW(DW),
    .CLK_FREQ_HZ(UART_CLK_FREQ_HZ),
    .BAUD_RATE(UART_BAUD_RATE),
    .TXDATA_OFFSET(UART_TXDATA_LOCAL_OFFSET),
    .STATUS_OFFSET(UART_STATUS_LOCAL_OFFSET)
  ) u_uart_target (
    .clk_i       (clk),
    .rst_ni      (cpu_rst_n),
    .req_valid_i (uart_req_valid),
    .req_ready_o (uart_req_ready),
    .req_i       (uart_req),
    .rsp_valid_o (uart_rsp_valid),
    .rsp_o       (uart_rsp),
    .uart_tx_o   (uart_tx_o),
    .tx_ready_o  (uart_tx_ready),
    .tx_busy_o   (uart_tx_busy)
  );

  mtime_timer #(
    .AW(AW),
    .DW(DW),
    .TICK_CYCLES(TIMER_TICK_CYCLES),
    .MTIMECMP_OFFSET(MTIMECMP_LOCAL_OFFSET),
    .MTIME_OFFSET(MTIME_LOCAL_OFFSET)
  ) u_timer_target (
    .clk_i       (clk),
    .rst_ni      (cpu_rst_n),
    .req_valid_i (timer_req_valid),
    .req_ready_o (timer_req_ready),
    .req_i       (timer_req),
    .rsp_valid_o (timer_rsp_valid),
    .rsp_o       (timer_rsp),
    .irq_mti_o   (timer_irq_mti)
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
