`timescale 1ns/1ps
`default_nettype wire

module tb_uart_rx;
  localparam int CLK_FREQ_HZ = 32;
  localparam int BAUD_RATE = 4;
  localparam int CLKS_PER_BIT = 8;

  logic clk;
  logic rst_n;
  logic uart_rx;
  logic rx_valid;
  logic [7:0] rx_data;
  logic frame_error;
  logic rx_busy;

  logic [7:0] received [0:2];
  integer received_count;
  integer frame_error_count;

  uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) u_dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .uart_rx_i         (uart_rx),
    .rx_byte_valid_o   (rx_valid),
    .rx_byte_data_o    (rx_data),
    .rx_frame_error_o  (frame_error),
    .rx_busy_o         (rx_busy)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      received_count    <= 0;
      frame_error_count <= 0;
    end else begin
      if (rx_valid) begin
        assert (received_count < 3)
          else $fatal(1, "UART RX emitted too many bytes");
        received[received_count] <= rx_data;
        received_count <= received_count + 1;
      end
      if (frame_error)
        frame_error_count <= frame_error_count + 1;
      assert (!(rx_valid && frame_error))
        else $fatal(1, "Bad frame was also reported as a valid byte");
    end
  end

  task automatic drive_serial_bit(input logic value);
    begin
      @(negedge clk);
      uart_rx = value;
      repeat (CLKS_PER_BIT) @(posedge clk);
    end
  endtask

  task automatic send_frame(
    input logic [7:0] value,
    input logic good_stop
  );
    integer bit_index;
    begin
      drive_serial_bit(1'b0);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
        drive_serial_bit(value[bit_index]);
      drive_serial_bit(good_stop);
      @(negedge clk);
      uart_rx = 1'b1;
      repeat (2) @(posedge clk);
    end
  endtask

  initial begin
    clk      = 1'b0;
    rst_n    = 1'b0;
    uart_rx  = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    repeat (3) @(posedge clk);
    assert (!rx_busy && !rx_valid && !frame_error)
      else $fatal(1, "UART RX reset state is wrong");

    // A low pulse shorter than the half-bit confirmation point is noise, not
    // a character start.
    @(negedge clk);
    uart_rx = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    uart_rx = 1'b1;
    repeat (CLKS_PER_BIT + 4) @(posedge clk);
    assert (received_count == 0 && frame_error_count == 0)
      else $fatal(1, "false start produced a receive event");

    send_frame(8'h00, 1'b1);
    send_frame(8'ha5, 1'b1);
    send_frame(8'hff, 1'b1);
    wait (received_count == 3);
    assert (received[0] == 8'h00 && received[1] == 8'ha5 &&
            received[2] == 8'hff)
      else $fatal(1, "UART RX byte data/order mismatch");

    send_frame(8'h3c, 1'b0);
    wait (frame_error_count == 1);
    repeat (CLKS_PER_BIT) @(posedge clk);
    assert (received_count == 3)
      else $fatal(1, "framing-error byte was incorrectly delivered");

    $display("[UART-RX-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
