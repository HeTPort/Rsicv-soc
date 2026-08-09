`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_core_bus_uart;
  localparam int CLK_FREQ_HZ = 16;
  localparam int BAUD_RATE = 4;
  localparam int CLKS_PER_BIT = 4;

  logic clk;
  logic rst_n;
  logic req_valid;
  logic req_ready;
  core_bus_req_t req;
  logic rsp_valid;
  core_bus_rsp_t rsp;
  logic uart_tx;
  logic uart_rx;
  logic uart_ready;
  logic uart_busy;

  logic [7:0] received [0:2];
  integer received_count;

  core_bus_uart #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE),
    .TXDATA_OFFSET(32'h0000_0000),
    .STATUS_OFFSET(32'h0000_0004)
  ) u_dut (
    .clk_i        (clk),
    .rst_ni       (rst_n),
    .req_valid_i  (req_valid),
    .req_ready_o  (req_ready),
    .req_i        (req),
    .rsp_valid_o  (rsp_valid),
    .rsp_o        (rsp),
    .uart_rx_i    (uart_rx),
    .uart_tx_o    (uart_tx),
    .tx_ready_o   (uart_ready),
    .tx_busy_o    (uart_busy)
  );

  always #5 clk = ~clk;

  task automatic set_request(
    input logic [31:0] addr,
    input logic write,
    input mem_size_e size,
    input logic [31:0] wdata,
    input logic [3:0] wstrb
  );
    begin
      req       = '0;
      req.addr  = addr;
      req.write = write;
      req.size  = size;
      req.wdata = wdata;
      req.wstrb = wstrb;
    end
  endtask

  task automatic transact(
    input logic [31:0] addr,
    input logic write,
    input mem_size_e size,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    input logic expect_error,
    output logic [31:0] read_data
  );
    begin
      @(negedge clk);
      set_request(addr, write, size, wdata, wstrb);
      req_valid = 1'b1;
      #1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      assert (rsp_valid && rsp.error == expect_error)
        else $fatal(1, "UART bus response contract mismatch");
      read_data = rsp.rdata;
      @(posedge clk);
    end
  endtask

  task automatic decode_byte(output logic [7:0] value);
    integer bit_index;
    begin
      value = '0;
      @(negedge uart_tx);
      repeat (CLKS_PER_BIT/2) @(posedge clk);
      assert (!uart_tx)
        else $fatal(1, "UART decoder observed a false start bit");
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        repeat (CLKS_PER_BIT) @(posedge clk);
        value[bit_index] = uart_tx;
      end
      repeat (CLKS_PER_BIT) @(posedge clk);
      assert (uart_tx)
        else $fatal(1, "UART decoder observed an invalid stop bit");
    end
  endtask

  logic [31:0] read_data;
  integer stalled_cycles;

  initial begin
    clk            = 1'b0;
    rst_n          = 1'b0;
    req_valid      = 1'b0;
    req            = '0;
    uart_rx        = 1'b1;
    received_count = 0;

    fork
      begin
        while (received_count < 3) begin
          decode_byte(received[received_count]);
          received_count = received_count + 1;
        end
      end
    join_none

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[1:0] == 2'b01)
      else $fatal(1, "reset STATUS is not ready/idle");

    transact(32'h0, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b1, read_data);
    transact(32'h4, 1'b1, MEM_SIZE_WORD, '0, 4'b1111, 1'b1, read_data);
    transact(32'h10, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b1, read_data);
    transact(32'h0, 1'b1, MEM_SIZE_BYTE, 32'h41, 4'b0001, 1'b1, read_data);

    transact(32'h0, 1'b1, MEM_SIZE_WORD, 32'h0000_0041,
             4'b1111, 1'b0, read_data);
    transact(32'h0, 1'b1, MEM_SIZE_WORD, 32'h0000_0042,
             4'b1111, 1'b0, read_data);

    // The shifter owns 'A' and the holding slot owns 'B'. A third valid write
    // must remain stable and backpressured until 'B' transfers to the shifter.
    @(negedge clk);
    set_request(32'h0, 1'b1, MEM_SIZE_WORD, 32'h0000_0043, 4'b1111);
    req_valid = 1'b1;
    #1;
    stalled_cycles = 0;
    while (!req_ready) begin
      @(negedge clk);
      stalled_cycles = stalled_cycles + 1;
      assert (req_valid && req.addr == 32'h0 && req.wdata == 32'h43)
        else $fatal(1, "backpressured UART request changed");
    end
    assert (stalled_cycles >= CLKS_PER_BIT)
      else $fatal(1, "full holding slot did not backpressure third byte");
    @(posedge clk);
    @(negedge clk);
    req_valid = 1'b0;
    assert (rsp_valid && !rsp.error)
      else $fatal(1, "released third byte did not receive success response");

    wait (received_count == 3);
    wait (!uart_busy);
    assert (received[0] == 8'h41 && received[1] == 8'h42 &&
            received[2] == 8'h43)
      else $fatal(1, "UART byte ordering/data mismatch");

    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[1:0] == 2'b01)
      else $fatal(1, "final STATUS is not ready/idle");

    $display("[CORE-BUS-UART-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
