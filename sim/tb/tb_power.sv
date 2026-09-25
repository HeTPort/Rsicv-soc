`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

// Stable SoC activity-capture boundary. Firmware owns useful work and its
// checksum oracle; this testbench owns marker ordering, fixed-window metrics,
// and final tohost acceptance. ModelSim Tcl controls power on/off around the
// public capture_active/capture_complete signals.
module tb_power #(
  parameter string PROGRAM_FILE = "../testdata/firmware_p0_mix.imem.hex",
  parameter string DATA_FILE = "../testdata/firmware_p0_mix.dmem.hex",
  parameter int TIMEOUT_CYCLES = 1000000,
  parameter logic [31:0] TOHOST_ADDR = 32'h8000_FFFC,
  parameter logic [31:0] MARKER_ADDR = 32'h8000_0410,
  parameter logic [31:0] START_MARKER = 32'h504F_5752,
  parameter logic [31:0] END_MARKER = 32'h454E_4421,
  parameter bit ALLOW_ECALL_TRAPS = 1'b0,
  parameter logic [31:0] RESULT0_ADDR = 32'h0,
  parameter logic [31:0] RESULT1_ADDR = 32'h0,
  parameter logic [31:0] RESULT2_ADDR = 32'h0,
  parameter int PROG_RAM_DEPTH = 16384,
  parameter int DATA_RAM_DEPTH = 16384
);
  localparam int AW = 32;
  localparam int DW = 32;
  localparam realtime CLK_HALF_PERIOD_NS = 500.0 / 95.0;

  logic clk;
  logic rst_n;
  logic load_done;
  logic prog_wr_en;
  logic [AW-1:0] prog_wr_addr;
  logic [DW-1:0] prog_wr_data;
  logic uart_rx;
  logic uart_tx;
  logic [7:0] gpio_out;
  commit_pkt_t commit;
  trap_entry_t trap_entry;

  logic capture_active;
  logic capture_complete;
  longint unsigned cycle_count;
  longint unsigned capture_start_cycle;
  longint unsigned capture_end_cycle;
  longint unsigned retired_in_window;
  integer start_count;
  integer end_count;
  logic result0_seen;
  logic result1_seen;
  logic result2_seen;
  logic [31:0] result0_value;
  logic [31:0] result1_value;
  logic [31:0] result2_value;

  initial begin
    clk = 1'b0;
    forever #CLK_HALF_PERIOD_NS clk = ~clk;
  end

  initial begin
    rst_n        = 1'b0;
    load_done    = 1'b0;
    prog_wr_en   = 1'b0;
    prog_wr_addr = '0;
    prog_wr_data = '0;
    uart_rx      = 1'b1;

    #1ns;
    $display("[POWER-TB] Loading program image: %s", PROGRAM_FILE);
    $readmemh(PROGRAM_FILE, u_soc.u_prog_ram.mem);
    if (DATA_FILE != "") begin
      $display("[POWER-TB] Loading data image: %s", DATA_FILE);
      $readmemh(DATA_FILE, u_soc.u_data_target.u_data_ram.mem);
    end
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    load_done = 1'b1;
  end

  riscv_soc #(
    .PROG_RAM_DEPTH(PROG_RAM_DEPTH),
    .DATA_RAM_DEPTH(DATA_RAM_DEPTH),
    .DATA_REQ_WAIT_CYCLES(0),
    .DATA_RSP_WAIT_CYCLES(0),
    .UART_CLK_FREQ_HZ(95_000_000),
    .UART_BAUD_RATE(115200),
    .UART_RX_FIFO_DEPTH(16)
  ) u_soc (
    .clk         (clk),
    .rst_n       (rst_n),
    .prog_wr_en  (prog_wr_en),
    .prog_wr_addr(prog_wr_addr),
    .prog_wr_data(prog_wr_data),
    .load_done   (load_done),
    .uart_rx_i   (uart_rx),
    .commit_o    (commit),
    .trap_entry_o(trap_entry),
    .uart_tx_o   (uart_tx),
    .gpio_out_o  (gpio_out)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    logic marker_store;
    marker_store = commit.valid && commit.mem_valid && commit.mem_we &&
                   (commit.mem_addr == MARKER_ADDR);

    if (!rst_n) begin
      capture_active      <= 1'b0;
      capture_complete    <= 1'b0;
      cycle_count         <= '0;
      capture_start_cycle <= '0;
      capture_end_cycle   <= '0;
      retired_in_window   <= '0;
      start_count         <= 0;
      end_count           <= 0;
      result0_seen        <= 1'b0;
      result1_seen        <= 1'b0;
      result2_seen        <= 1'b0;
      result0_value       <= '0;
      result1_value       <= '0;
      result2_value       <= '0;
    end else begin
      cycle_count <= cycle_count + 64'd1;

      // FreeRTOS uses machine-mode ECALL (cause 11) as its deliberate yield
      // path. Other workloads and all other synchronous traps remain fatal.
      if (commit.valid && commit.trap &&
          !(ALLOW_ECALL_TRAPS && commit.trap_cause == 32'd11)) begin
        $fatal(1, "[POWER-TB] Unexpected trap at PC 0x%08h cause 0x%08h",
               commit.pc, commit.trap_cause);
      end

      if (capture_active && commit.valid && !marker_store)
        retired_in_window <= retired_in_window + 64'd1;

      if (marker_store && commit.mem_wdata == START_MARKER) begin
        if (capture_active || capture_complete || start_count != 0)
          $fatal(1, "[POWER-TB] Duplicate or out-of-order START marker");
        capture_active      <= 1'b1;
        capture_start_cycle <= cycle_count;
        start_count         <= start_count + 1;
        $display("[POWER-TB] START marker at cycle %0d", cycle_count);
      end else if (marker_store && commit.mem_wdata == END_MARKER) begin
        if (!capture_active || capture_complete || start_count != 1)
          $fatal(1, "[POWER-TB] Missing or out-of-order END marker");
        capture_active    <= 1'b0;
        capture_complete  <= 1'b1;
        capture_end_cycle <= cycle_count;
        end_count         <= end_count + 1;
        $display("[POWER-TB] END marker at cycle %0d", cycle_count);
        $display("[POWER-TB] Window cycles = %0d", cycle_count - capture_start_cycle);
        $display("[POWER-TB] Retired instructions = %0d", retired_in_window);
        $display("[POWER-TB] CAPTURE: PASS");
      end else if (marker_store && capture_active) begin
        $fatal(1, "[POWER-TB] Unexpected marker value 0x%08h inside window",
               commit.mem_wdata);
      end

      // Optional workload result words are committed only after END, so they
      // provide exact KPI evidence without changing the measured SAIF window.
      if (capture_complete && commit.valid && commit.mem_valid && commit.mem_we) begin
        if (RESULT0_ADDR != 32'h0 && commit.mem_addr == RESULT0_ADDR) begin
          result0_seen  <= 1'b1;
          result0_value <= commit.mem_wdata;
          $display("[POWER-TB] RESULT0 = %0d", commit.mem_wdata);
        end
        if (RESULT1_ADDR != 32'h0 && commit.mem_addr == RESULT1_ADDR) begin
          result1_seen  <= 1'b1;
          result1_value <= commit.mem_wdata;
          $display("[POWER-TB] RESULT1 = %0d", commit.mem_wdata);
        end
        if (RESULT2_ADDR != 32'h0 && commit.mem_addr == RESULT2_ADDR) begin
          result2_seen  <= 1'b1;
          result2_value <= commit.mem_wdata;
          $display("[POWER-TB] RESULT2 = %0d", commit.mem_wdata);
        end
      end

      if (commit.valid && commit.mem_valid && commit.mem_we &&
          commit.mem_addr == TOHOST_ADDR) begin
        if (!capture_complete || start_count != 1 || end_count != 1)
          $fatal(1, "[POWER-TB] tohost observed without one complete window");
        if (commit.mem_wdata != 32'd1)
          $fatal(1, "[POWER-TB] Firmware failure code 0x%08h", commit.mem_wdata);
        if ((RESULT0_ADDR != 32'h0 && !result0_seen) ||
            (RESULT1_ADDR != 32'h0 && !result1_seen) ||
            (RESULT2_ADDR != 32'h0 && !result2_seen))
          $fatal(1, "[POWER-TB] Expected post-window result store missing");
        $display("[POWER-TB] tohost = 0x%08h", commit.mem_wdata);
        $display("[TB] RESULT: PASS");
        $finish;
      end
    end
  end

  initial begin
    repeat (TIMEOUT_CYCLES) @(posedge clk);
    $fatal(1, "[POWER-TB] Timeout after %0d cycles", TIMEOUT_CYCLES);
  end
endmodule

`default_nettype wire
