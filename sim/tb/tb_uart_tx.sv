`timescale 1ns/1ps
`default_nettype wire

module tb_uart_tx;
  localparam int CLK_FREQ_HZ = 16;
  localparam int BAUD_RATE = 4;
  localparam int CLKS_PER_BIT = 4;

  logic clk;
  logic rst_n;
  logic tx_valid;
  logic tx_ready;
  logic [7:0] tx_data;
  logic tx;
  logic tx_busy;
  logic tx_done;

  uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE)
  ) u_dut (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .tx_valid_i (tx_valid),
    .tx_ready_o (tx_ready),
    .tx_data_i  (tx_data),
    .tx_o       (tx),
    .tx_busy_o  (tx_busy),
    .tx_done_o  (tx_done)
  );

  always #5 clk = ~clk;

  task automatic send_and_check(input logic [7:0] value);
    logic [9:0] expected_frame;
    integer bit_index;
    integer cycle_index;
    begin
      expected_frame = {1'b1, value, 1'b0};
      @(negedge clk);
      assert (tx_ready && !tx_busy)
        else $fatal(1, "transmitter not ready before byte launch");
      tx_data  = value;
      tx_valid = 1'b1;
      @(posedge clk);
      #1;
      tx_valid = 1'b0;
      tx_data  = ~value;

      assert (!tx_ready && tx_busy)
        else $fatal(1, "accepted byte did not enter busy state");

      for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
        for (cycle_index = 0; cycle_index < CLKS_PER_BIT;
             cycle_index = cycle_index + 1) begin
          @(negedge clk);
          assert (tx === expected_frame[bit_index])
            else $fatal(1,
              "frame mismatch bit=%0d cycle=%0d expected=%0b actual=%0b",
              bit_index, cycle_index, expected_frame[bit_index], tx);
        end
      end

      @(posedge clk);
      #1;
      assert (tx_done && tx_ready && !tx_busy && tx)
        else $fatal(1, "byte completion/idle contract is wrong");
      @(posedge clk);
      #1;
      assert (!tx_done)
        else $fatal(1, "tx_done must be a one-cycle pulse");
    end
  endtask

  initial begin
    clk      = 1'b0;
    rst_n    = 1'b0;
    tx_valid = 1'b0;
    tx_data  = '0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;
    assert (tx && tx_ready && !tx_busy && !tx_done)
      else $fatal(1, "UART reset/idle state is wrong");

    send_and_check(8'h00);
    send_and_check(8'ha5);
    send_and_check(8'hff);

    $display("[UART-TX-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
