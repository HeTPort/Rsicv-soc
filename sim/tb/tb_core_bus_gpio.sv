`timescale 1ns/1ps
`default_nettype wire

import riscv_pkg::*;

module tb_core_bus_gpio;
  localparam int GPIO_WIDTH = 16;
  localparam logic [GPIO_WIDTH-1:0] RESET_VALUE = 16'h1234;

  logic clk;
  logic rst_n;

  logic          req_valid;
  logic          req_ready;
  core_bus_req_t req;

  logic          rsp_valid;
  core_bus_rsp_t rsp;

  logic [GPIO_WIDTH-1:0] gpio_out;

  core_bus_gpio #(
    .GPIO_WIDTH    (GPIO_WIDTH),
    .RESET_VALUE   (RESET_VALUE),
    .GPIO_OUT_OFFSET(32'h0000_0000)
  ) u_dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .req_valid_i (req_valid),
    .req_ready_o (req_ready),
    .req_i       (req),
    .rsp_valid_o (rsp_valid),
    .rsp_o       (rsp),
    .gpio_out_o  (gpio_out)
  );

  always #5 clk = ~clk;

  task automatic set_request(
    input logic [31:0] addr,
    input logic        write,
    input mem_size_e   size,
    input logic [31:0] wdata,
    input logic [3:0]  wstrb
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
    input  logic [31:0] addr,
    input  logic        write,
    input  mem_size_e   size,
    input  logic [31:0] wdata,
    input  logic [3:0]  wstrb,
    input  logic        expect_error,
    output logic [31:0] read_data
  );
    begin
      // Present the request before the accepting edge.
      @(negedge clk);
      set_request(addr, write, size, wdata, wstrb);
      req_valid = 1'b1;

      // Allow combinational ready logic to settle.
      #1;
      while (!req_ready)
        @(negedge clk);

      // This edge accepts the request.
      @(posedge clk);

      // A registered response must be visible during this cycle.
      @(negedge clk);
      req_valid = 1'b0;

      assert (rsp_valid)
        else $fatal(1, "GPIO did not return a registered response");

      assert (rsp.error == expect_error)
        else $fatal(
          1,
          "GPIO response error mismatch: got %0b expected %0b",
          rsp.error,
          expect_error
        );

      read_data = rsp.rdata;

      // The response must be a one-cycle event.
      @(posedge clk);
      @(negedge clk);

      assert (!rsp_valid)
        else $fatal(1, "GPIO response lasted more than one cycle");
    end
  endtask

  logic [31:0] read_data;

  initial begin
    clk       = 1'b0;
    rst_n     = 1'b0;
    req_valid = 1'b0;
    req       = '0;

    repeat (3) @(posedge clk);
    #1;

    assert (gpio_out == RESET_VALUE)
      else $fatal(
        1,
        "GPIO reset mismatch: got 0x%04h expected 0x%04h",
        gpio_out,
        RESET_VALUE
      );

    @(negedge clk);
    rst_n = 1'b1;

    // Reset readback.
    transact(
      32'h0000_0000,
      1'b0,
      MEM_SIZE_WORD,
      '0,
      4'b0000,
      1'b0,
      read_data
    );

    assert (read_data == 32'h0000_1234)
      else $fatal(1, "GPIO reset readback mismatch");

    // Full word write. Only GPIO_WIDTH low bits may be retained.
    transact(
      32'h0000_0000,
      1'b1,
      MEM_SIZE_WORD,
      32'hdead_beef,
      4'b1111,
      1'b0,
      read_data
    );

    assert (gpio_out == 16'hbeef)
      else $fatal(1, "GPIO full-word write or width mask failed");

    // Byte write to address +1 replaces bits 15:8 only.
    transact(
      32'h0000_0001,
      1'b1,
      MEM_SIZE_BYTE,
      32'h0000_5a00,
      4'b0010,
      1'b0,
      read_data
    );

    assert (gpio_out == 16'h5aef)
      else $fatal(1, "GPIO byte-strobe merge failed");

    // Verify readback after the partial write.
    transact(
      32'h0000_0000,
      1'b0,
      MEM_SIZE_WORD,
      '0,
      4'b0000,
      1'b0,
      read_data
    );

    assert (read_data == 32'h0000_5aef)
      else $fatal(1, "GPIO readback after partial write failed");

    // Invalid offset must return an error without modifying the output.
    transact(
      32'h0000_0004,
      1'b1,
      MEM_SIZE_WORD,
      32'hffff_ffff,
      4'b1111,
      1'b1,
      read_data
    );

    assert (read_data == '0)
      else $fatal(1, "Invalid GPIO access returned nonzero data");

    assert (gpio_out == 16'h5aef)
      else $fatal(1, "Invalid GPIO offset changed output state");

    // A word access with halfword strobes is malformed.
    transact(
      32'h0000_0000,
      1'b1,
      MEM_SIZE_WORD,
      32'h0000_cafe,
      4'b0011,
      1'b1,
      read_data
    );

    assert (gpio_out == 16'h5aef)
      else $fatal(1, "Malformed GPIO write changed output state");

    $display("[CORE-BUS-GPIO-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire