`timescale 1ns/1ps
`default_nettype wire

// Byte-oriented, polling-friendly UART transmitter. Byte ownership transfers
// only when tx_valid_i && tx_ready_o. The physical format is fixed to 8N1:
// one low start bit, eight LSB-first data bits, and one high stop bit.
module uart_tx #(
  parameter int unsigned CLK_FREQ_HZ = 25_000_000,
  parameter int unsigned BAUD_RATE   = 115_200
)(
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       tx_valid_i,
  output logic       tx_ready_o,
  input  logic [7:0] tx_data_i,
  output logic       tx_o,
  output logic       tx_busy_o,
  output logic       tx_done_o
);
  localparam int unsigned CLKS_PER_BIT =
      (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
  localparam int unsigned BAUD_COUNT_W =
      (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

  logic [9:0] frame_q;
  logic [3:0] bit_index_q;
  logic [BAUD_COUNT_W-1:0] baud_count_q;
  logic busy_q;
  logic done_q;

  assign tx_ready_o = !busy_q;
  assign tx_busy_o  = busy_q;
  assign tx_done_o  = done_q;
  assign tx_o       = busy_q ? frame_q[bit_index_q] : 1'b1;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      frame_q      <= 10'h3ff;
      bit_index_q  <= '0;
      baud_count_q <= '0;
      busy_q       <= 1'b0;
      done_q       <= 1'b0;
    end else begin
      done_q <= 1'b0;

      if (!busy_q) begin
        baud_count_q <= '0;
        bit_index_q  <= '0;
        if (tx_valid_i) begin
          frame_q <= {1'b1, tx_data_i, 1'b0};
          busy_q  <= 1'b1;
        end
      end else if (baud_count_q == CLKS_PER_BIT - 1) begin
        baud_count_q <= '0;
        if (bit_index_q == 4'd9) begin
          bit_index_q <= '0;
          busy_q      <= 1'b0;
          done_q      <= 1'b1;
        end else begin
          bit_index_q <= bit_index_q + 1'b1;
        end
      end else begin
        baud_count_q <= baud_count_q + 1'b1;
      end
    end
  end

  initial begin
    if (CLK_FREQ_HZ == 0)
      $fatal(1, "uart_tx CLK_FREQ_HZ must be nonzero");
    if (BAUD_RATE == 0)
      $fatal(1, "uart_tx BAUD_RATE must be nonzero");
    if (CLKS_PER_BIT < 2)
      $fatal(1, "uart_tx requires at least two clocks per serial bit");
  end

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (tx_ready_o == !tx_busy_o)
        else $error("UART TX ready/busy outputs disagree");
      if (!tx_busy_o)
        assert (tx_o)
          else $error("UART TX line is not high while idle");
      if (tx_done_o)
        assert (!tx_busy_o && tx_o)
          else $error("UART TX completion did not return to idle");
    end
  end
`endif
endmodule

`default_nettype wire
