`timescale 1ns/1ps
`default_nettype none

// Bo Chen Jing Xin ZYNQ MINI 20240221/REVB programmable-logic wrapper.
//
// The board supplies a 50 MHz clock directly to the PL on K17.  The MMCM
// produces the conservative 25 MHz board clock, the exact 95 MHz P0 power
// profile, or the 100 MHz timing evaluation clock selected by CORE_CLOCK_HZ.
// PL K2 is active low.  Reset asserts asynchronously and is released only
// after the MMCM is locked and four core-clock edges have passed.
module top #(
  // Untyped filename parameters are intentional for Vivado 2019.2.
  parameter PROGRAM_INIT_FILE = "",
  parameter DATA_INIT_FILE = "",
  parameter integer TIMER_TICK_CYCLES = 1,
  parameter integer CORE_CLOCK_HZ = 25_000_000
)(
  input  wire        clk_50m_i,
  input  wire        reset_n_i,
  input  wire        uart_rx_i,
  output wire        uart_tx_o,
  output wire [3:0]  led_o
);
  wire clkfb_mmcm;
  wire clkfb_bufg;
  wire clk_core_mmcm;
  wire clk_core;
  wire mmcm_locked;
  wire reset_async_n;
  wire soc_reset_n;

  (* ASYNC_REG = "TRUE" *) reg [3:0] reset_sync_q = 4'b0000;
  wire [7:0] gpio_out;

  // Zynq configuration requires the PS7 hard block to be present even though
  // this design uses none of its clocks, AXI ports, or ARM processors.  All
  // application execution remains in u_soc in programmable logic.
  (* DONT_TOUCH = "TRUE" *) PS7 u_ps7 ();

  // The 50 MHz input drives a 1000 MHz VCO for 25/100 MHz, or a 950 MHz VCO
  // for exact 95 MHz. Both VCO choices are within the 7-series MMCM range.
  MMCME2_BASE #(
    .BANDWIDTH          ("OPTIMIZED"),
    .CLKFBOUT_MULT_F    (CORE_CLOCK_HZ == 95_000_000 ? 19.0 : 20.0),
    .CLKFBOUT_PHASE     (0.0),
    .CLKIN1_PERIOD      (20.0),
    .CLKOUT0_DIVIDE_F   (CORE_CLOCK_HZ == 25_000_000 ? 40.0 : 10.0),
    .CLKOUT0_DUTY_CYCLE (0.5),
    .CLKOUT0_PHASE      (0.0),
    .DIVCLK_DIVIDE      (1),
    .REF_JITTER1        (0.010),
    .STARTUP_WAIT       ("FALSE")
  ) u_core_mmcm (
    .CLKFBOUT  (clkfb_mmcm),
    .CLKOUT0   (clk_core_mmcm),
    .LOCKED    (mmcm_locked),
    .CLKFBIN   (clkfb_bufg),
    .CLKIN1    (clk_50m_i),
    .PWRDWN    (1'b0),
    .RST       (~reset_n_i)
  );

  BUFG u_clkfb_bufg (
    .I (clkfb_mmcm),
    .O (clkfb_bufg)
  );

  BUFG u_core_clk_bufg (
    .I (clk_core_mmcm),
    .O (clk_core)
  );

  assign reset_async_n = reset_n_i & mmcm_locked;

  always @(posedge clk_core or negedge reset_async_n) begin
    if (!reset_async_n) begin
      reset_sync_q <= 4'b0000;
    end else begin
      reset_sync_q <= {reset_sync_q[2:0], 1'b1};
    end
  end

  assign soc_reset_n = reset_sync_q[3];
  assign led_o       = gpio_out[3:0];

  riscv_soc #(
    .TIMER_TICK_CYCLES (TIMER_TICK_CYCLES),
    .UART_CLK_FREQ_HZ  (CORE_CLOCK_HZ),
    .UART_BAUD_RATE    (115_200),
    .GPIO_WIDTH        (8),
    .PROGRAM_INIT_FILE (PROGRAM_INIT_FILE),
    .DATA_INIT_FILE    (DATA_INIT_FILE)
  ) u_soc (
    .clk          (clk_core),
    .rst_n        (soc_reset_n),
    .prog_wr_en   (1'b0),
    .prog_wr_addr (32'b0),
    .prog_wr_data (32'b0),
    .load_done    (1'b1),
    .uart_rx_i    (uart_rx_i),
    .commit_o     (),
    .trap_entry_o (),
    .uart_tx_o    (uart_tx_o),
    .gpio_out_o   (gpio_out)
  );
endmodule

`default_nettype wire
