`timescale 1ns / 1ps
`default_nettype none

// Vivado 2019.2's `-include_xilinx_libs` functional export omits this simple
// primitive even though the XDC enables weak pull-ups on board inputs.
module PULLUP(output wire O);
  pullup (O);
endmodule

// Marker-driven harness for the functional netlist exported from the exact
// routed board checkpoint. The RTL run remains the architectural oracle; this
// harness proves the same image reaches the same markers while recording names
// that correspond to the implemented design.
module tb_power_postroute #(
  parameter integer TIMEOUT_CORE_CYCLES = 1_000_000,
  parameter [31:0] TOHOST_ADDR = 32'h8000_FFFC,
  parameter [31:0] MARKER_ADDR = 32'h8000_0410,
  parameter [31:0] START_MARKER = 32'h504F_5752,
  parameter [31:0] END_MARKER = 32'h454E_4421
);
  reg clk_50m_i;
  reg reset_n_i;
  reg uart_rx_i;
  wire uart_tx_o;
  wire [3:0] led_o;

  reg capture_active;
  reg capture_complete;
  reg [63:0] cycle_count;
  reg [63:0] capture_start_cycle;
  integer start_count;
  integer end_count;

  wire core_clk = u_dut.clk_core;
  wire core_reset_n = u_dut.reset_sync_q[3];
  wire [30:2] data_addr_word;
  wire [31:0] data_wdata;
  wire data_write;
  wire data_accept;
  wire [31:0] data_addr = {1'b1, data_addr_word, 2'b00};
  wire accepted_store = data_write && data_accept;

  // Escaped identifiers are emitted by Vivado from packed request fields.
  assign data_addr_word = u_dut.u_soc.\cpu_data_req[addr] ;
  assign data_wdata = u_dut.u_soc.\cpu_data_req[wdata] ;
  assign data_write = u_dut.u_soc.\cpu_data_req[write] ;
  assign data_accept = u_dut.u_soc.accept;

  top u_dut (
    .clk_50m_i (clk_50m_i),
    .reset_n_i (reset_n_i),
    .uart_rx_i (uart_rx_i),
    .uart_tx_o (uart_tx_o),
    .led_o      (led_o)
  );

  initial begin
    clk_50m_i = 1'b0;
    forever #10 clk_50m_i = ~clk_50m_i;
  end

  initial begin
    reset_n_i = 1'b0;
    uart_rx_i = 1'b1;
    capture_active = 1'b0;
    capture_complete = 1'b0;
    cycle_count = 64'd0;
    capture_start_cycle = 64'd0;
    start_count = 0;
    end_count = 0;
    repeat (20) @(posedge clk_50m_i);
    reset_n_i = 1'b1;
  end

  always @(posedge core_clk) begin
    if (!core_reset_n) begin
      capture_active <= 1'b0;
      capture_complete <= 1'b0;
      cycle_count <= 64'd0;
      capture_start_cycle <= 64'd0;
      start_count <= 0;
      end_count <= 0;
    end else begin
      cycle_count <= cycle_count + 64'd1;

      if (accepted_store && data_addr == MARKER_ADDR &&
          data_wdata == START_MARKER) begin
        if (capture_active || capture_complete || start_count != 0)
          $fatal(1, "[POSTROUTE-POWER-TB] Duplicate/out-of-order START");
        capture_active <= 1'b1;
        capture_start_cycle <= cycle_count;
        start_count <= start_count + 1;
        $display("[POSTROUTE-POWER-TB] START marker at cycle %0d", cycle_count);
      end else if (accepted_store && data_addr == MARKER_ADDR &&
                   data_wdata == END_MARKER) begin
        if (!capture_active || capture_complete || start_count != 1)
          $fatal(1, "[POSTROUTE-POWER-TB] Missing/out-of-order END");
        capture_active <= 1'b0;
        capture_complete <= 1'b1;
        end_count <= end_count + 1;
        $display("[POSTROUTE-POWER-TB] END marker at cycle %0d", cycle_count);
        $display("[POSTROUTE-POWER-TB] Window cycles = %0d",
                 cycle_count - capture_start_cycle);
        $display("[POSTROUTE-POWER-TB] CAPTURE: PASS");
      end

      if (accepted_store && data_addr == TOHOST_ADDR) begin
        if (!capture_complete || start_count != 1 || end_count != 1)
          $fatal(1, "[POSTROUTE-POWER-TB] tohost before complete window");
        if (data_wdata != 32'd1)
          $fatal(1, "[POSTROUTE-POWER-TB] Firmware failure 0x%08h", data_wdata);
        $display("[POSTROUTE-POWER-TB] tohost = 0x%08h", data_wdata);
        $display("[POSTROUTE-POWER-TB] RESULT: PASS");
        $finish;
      end
    end
  end

  initial begin
    repeat (TIMEOUT_CORE_CYCLES) @(posedge core_clk);
    $fatal(1, "[POSTROUTE-POWER-TB] Timeout after %0d core cycles",
           TIMEOUT_CORE_CYCLES);
  end
endmodule

`default_nettype wire
