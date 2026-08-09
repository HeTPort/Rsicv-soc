`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_mtime_timer;
  logic clk;
  logic rst_n;
  logic req_valid;
  logic req_ready;
  core_bus_req_t req;
  logic rsp_valid;
  core_bus_rsp_t rsp;
  logic irq_mti;

  mtime_timer #(.TICK_CYCLES(4)) u_dut (
    .clk_i(clk), .rst_ni(rst_n),
    .req_valid_i(req_valid), .req_ready_o(req_ready), .req_i(req),
    .rsp_valid_o(rsp_valid), .rsp_o(rsp), .irq_mti_o(irq_mti)
  );

  always #5 clk = ~clk;

  task automatic transact(
    input logic [31:0] addr,
    input logic write,
    input mem_size_e size,
    input logic [31:0] wdata,
    input logic [3:0] wstrb,
    output logic [31:0] rdata,
    output logic error
  );
    begin
      @(negedge clk);
      req = '0;
      req.addr = addr;
      req.write = write;
      req.size = size;
      req.wdata = wdata;
      req.wstrb = wstrb;
      req_valid = 1'b1;
      do @(posedge clk); while (!req_ready);
      #1;
      req_valid = 1'b0;
      assert (rsp_valid)
        else $fatal(1, "timer did not return a registered response");
      rdata = rsp.rdata;
      error = rsp.error;
      @(posedge clk);
      #1;
      assert (!rsp_valid)
        else $fatal(1, "timer response lasted more than one cycle");
    end
  endtask

  logic [31:0] rdata;
  logic error;
  logic [31:0] mtime_before;

  initial begin
    clk       = 1'b0;
    rst_n     = 1'b0;
    req_valid = 1'b0;
    req       = '0;
    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    assert (!irq_mti)
      else $fatal(1, "timer interrupted immediately after reset");

    transact(32'h0000_bff8, 1'b0, MEM_SIZE_WORD, '0, '0,
             mtime_before, error);
    assert (!error)
      else $fatal(1, "legal mtime read returned an error");
    repeat (8) @(posedge clk);
    transact(32'h0000_bff8, 1'b0, MEM_SIZE_WORD, '0, '0,
             rdata, error);
    assert (!error && rdata > mtime_before)
      else $fatal(1, "mtime did not increment at the configured rate");

    transact(32'h0000_4000, 1'b1, MEM_SIZE_WORD,
             rdata + 32'd3, 4'b1111, mtime_before, error);
    transact(32'h0000_4004, 1'b1, MEM_SIZE_WORD,
             32'h0000_0000, 4'b1111, mtime_before, error);
    repeat (20) begin
      @(posedge clk);
      if (irq_mti) break;
    end
    assert (irq_mti)
      else $fatal(1, "MTIP did not assert when mtime reached mtimecmp");

    // First step of the standard RV32 update sequence.
    transact(32'h0000_4000, 1'b1, MEM_SIZE_WORD,
             32'hffff_ffff, 4'b1111, mtime_before, error);
    assert (!irq_mti)
      else $fatal(1, "safe mtimecmp low-word update did not deassert MTIP");

    transact(32'h0000_4001, 1'b1, MEM_SIZE_BYTE,
             32'h0000_00aa, 4'b0010, rdata, error);
    assert (error && rdata == '0)
      else $fatal(1, "invalid timer access did not return a clean error");

    $display("[MTIME-TIMER-TB] RESULT: PASS");
    $finish;
  end
endmodule
`default_nettype wire
