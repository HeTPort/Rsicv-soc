`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_core_bus_uart_rx;
  localparam int CLK_FREQ_HZ = 32;
  localparam int BAUD_RATE = 4;
  localparam int CLKS_PER_BIT = 8;
  localparam int RX_FIFO_DEPTH = 16;

  logic clk;
  logic rst_n;
  logic req_valid;
  logic req_ready;
  core_bus_req_t req;
  logic rsp_valid;
  core_bus_rsp_t rsp;
  logic uart_rx;
  logic uart_tx;
  logic tx_ready;
  logic tx_busy;

  core_bus_uart #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE(BAUD_RATE),
    .RX_FIFO_DEPTH(RX_FIFO_DEPTH),
    .TXDATA_OFFSET(32'h0000_0000),
    .STATUS_OFFSET(32'h0000_0004),
    .RXDATA_OFFSET(32'h0000_0008),
    .RXERROR_OFFSET(32'h0000_000c)
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
    .tx_ready_o   (tx_ready),
    .tx_busy_o    (tx_busy)
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
        else $fatal(1, "UART RX bus response mismatch");
      read_data = rsp.rdata;
      @(posedge clk);
    end
  endtask

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

  logic [31:0] read_data;
  integer byte_index;

  initial begin
    clk       = 1'b0;
    rst_n     = 1'b0;
    req_valid = 1'b0;
    req       = '0;
    uart_rx   = 1'b1;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[12:8] == 5'd0 && !read_data[5] &&
            !read_data[4] && !read_data[3] && !read_data[2])
      else $fatal(1, "UART RX reset STATUS is wrong");

    // Empty RXDATA is a legal nonblocking read and does not invent a byte.
    transact(32'h8, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data == '0)
      else $fatal(1, "empty RXDATA did not return zero");
    transact(32'h8, 1'b1, MEM_SIZE_WORD, 32'h55, 4'b1111,
             1'b1, read_data);

    for (byte_index = 0; byte_index < RX_FIFO_DEPTH;
         byte_index = byte_index + 1)
      send_frame(8'h20 + byte_index[7:0], 1'b1);

    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[12:8] == 5'd16 && read_data[3] && read_data[2] &&
            !read_data[5] && !read_data[4])
      else $fatal(1, "16-byte RX FIFO full STATUS is wrong: %08h", read_data);

    // The asynchronous producer cannot be stalled. Full policy drops this
    // newest byte, preserves the 16 older bytes, and records sticky overrun.
    send_frame(8'hee, 1'b1);
    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[12:8] == 5'd16 && read_data[4])
      else $fatal(1, "RX overrun/count STATUS is wrong");

    for (byte_index = 0; byte_index < RX_FIFO_DEPTH;
         byte_index = byte_index + 1) begin
      transact(32'h8, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
      assert (read_data[7:0] == 8'h20 + byte_index[7:0])
        else $fatal(1, "RX FIFO order mismatch at %0d", byte_index);
    end

    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[12:8] == 5'd0 && !read_data[3] && !read_data[2] &&
            read_data[4])
      else $fatal(1, "RX FIFO empty/sticky overrun STATUS is wrong");
    transact(32'hc, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[1:0] == 2'b01)
      else $fatal(1, "RXERROR overrun readback is wrong");
    transact(32'hc, 1'b1, MEM_SIZE_WORD, 32'h1, 4'b1111,
             1'b0, read_data);

    send_frame(8'h3c, 1'b0);
    transact(32'h4, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[5] && !read_data[4] && read_data[12:8] == 5'd0)
      else $fatal(1, "framing error was not sticky/side-effect-free");
    transact(32'hc, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[1:0] == 2'b10)
      else $fatal(1, "RXERROR framing readback is wrong");
    transact(32'hc, 1'b1, MEM_SIZE_WORD, 32'h2, 4'b1111,
             1'b0, read_data);
    transact(32'hc, 1'b0, MEM_SIZE_WORD, '0, '0, 1'b0, read_data);
    assert (read_data[1:0] == 2'b00)
      else $fatal(1, "RXERROR W1C did not clear sticky errors");

    transact(32'h8, 1'b0, MEM_SIZE_BYTE, '0, '0, 1'b1, read_data);

    $display("[CORE-BUS-UART-RX-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
