`timescale 1ns/1ps
`default_nettype wire

// Asynchronous-input, byte-oriented 8N1 UART receiver. The two-flop
// synchronizer limits metastability propagation; the state machine separately
// establishes sampling phase by confirming the start bit at its midpoint.
module uart_rx #(
  parameter int unsigned CLK_FREQ_HZ = 25_000_000,
  parameter int unsigned BAUD_RATE   = 115_200
)(
  input  logic       clk_i,
  input  logic       rst_ni,
  input  logic       uart_rx_i,
  output logic       rx_byte_valid_o,
  output logic [7:0] rx_byte_data_o,
  output logic       rx_frame_error_o,
  output logic       rx_busy_o
);
  localparam int unsigned CLKS_PER_BIT =
      (CLK_FREQ_HZ + (BAUD_RATE / 2)) / BAUD_RATE;
  localparam int unsigned HALF_CLKS = CLKS_PER_BIT / 2;
  localparam int unsigned BAUD_COUNT_W =
      (CLKS_PER_BIT <= 1) ? 1 : $clog2(CLKS_PER_BIT);

  typedef enum logic [1:0] {
    RX_IDLE,
    RX_START,
    RX_DATA,
    RX_STOP
  } rx_state_e;

  (* ASYNC_REG = "TRUE" *) logic rx_meta_q;
  (* ASYNC_REG = "TRUE" *) logic rx_sync_q;
  rx_state_e state_q;
  logic [BAUD_COUNT_W-1:0] baud_count_q;
  logic [2:0] bit_index_q;
  logic [7:0] data_q;
  logic [7:0] byte_data_q;
  logic byte_valid_q;
  logic frame_error_q;

  assign rx_byte_valid_o  = byte_valid_q;
  assign rx_byte_data_o   = byte_data_q;
  assign rx_frame_error_o = frame_error_q;
  assign rx_busy_o        = state_q != RX_IDLE;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_meta_q <= 1'b1;
      rx_sync_q <= 1'b1;
    end else begin
      rx_meta_q <= uart_rx_i;
      rx_sync_q <= rx_meta_q;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q       <= RX_IDLE;
      baud_count_q  <= '0;
      bit_index_q   <= '0;
      data_q        <= '0;
      byte_data_q   <= '0;
      byte_valid_q  <= 1'b0;
      frame_error_q <= 1'b0;
    end else begin
      byte_valid_q  <= 1'b0;
      frame_error_q <= 1'b0;

      unique case (state_q)
        RX_IDLE: begin
          baud_count_q <= '0;
          bit_index_q  <= '0;
          if (!rx_sync_q) begin
            state_q      <= RX_START;
            baud_count_q <= HALF_CLKS - 1;
          end
        end

        RX_START: begin
          if (baud_count_q == 0) begin
            if (!rx_sync_q) begin
              state_q      <= RX_DATA;
              baud_count_q <= CLKS_PER_BIT - 1;
              bit_index_q  <= '0;
            end else begin
              state_q <= RX_IDLE;
            end
          end else begin
            baud_count_q <= baud_count_q - 1'b1;
          end
        end

        RX_DATA: begin
          if (baud_count_q == 0) begin
            data_q[bit_index_q] <= rx_sync_q;
            baud_count_q <= CLKS_PER_BIT - 1;
            if (bit_index_q == 3'd7) begin
              state_q <= RX_STOP;
            end else begin
              bit_index_q <= bit_index_q + 1'b1;
            end
          end else begin
            baud_count_q <= baud_count_q - 1'b1;
          end
        end

        RX_STOP: begin
          if (baud_count_q == 0) begin
            state_q <= RX_IDLE;
            if (rx_sync_q) begin
              byte_data_q  <= data_q;
              byte_valid_q <= 1'b1;
            end else begin
              frame_error_q <= 1'b1;
            end
          end else begin
            baud_count_q <= baud_count_q - 1'b1;
          end
        end

        default: state_q <= RX_IDLE;
      endcase
    end
  end

  initial begin
    if (CLK_FREQ_HZ == 0)
      $fatal(1, "uart_rx CLK_FREQ_HZ must be nonzero");
    if (BAUD_RATE == 0)
      $fatal(1, "uart_rx BAUD_RATE must be nonzero");
    if (CLKS_PER_BIT < 4)
      $fatal(1, "uart_rx requires at least four clocks per serial bit");
  end

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(rx_byte_valid_o && rx_frame_error_o))
        else $error("UART RX valid byte and frame error events overlapped");
      if (rx_byte_valid_o)
        assert (!rx_busy_o)
          else $error("UART RX byte event did not return receiver to idle");
    end
  end
`endif
endmodule

`default_nettype wire
