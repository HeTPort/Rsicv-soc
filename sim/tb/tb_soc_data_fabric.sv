`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_soc_data_fabric;
  localparam logic [31:0] DATA_BASE = 32'h8000_0000;
  localparam logic [31:0] DATA_END  = 32'h8000_ffff;

  logic clk;
  logic rst_n;

  logic cpu_req_valid;
  logic cpu_req_ready;
  core_bus_req_t cpu_req;
  logic cpu_rsp_valid;
  core_bus_rsp_t cpu_rsp;

  logic data_req_valid;
  logic data_req_ready;
  core_bus_req_t data_req;
  logic data_rsp_valid;
  core_bus_rsp_t data_rsp;

  int cpu_accept_count;
  int data_accept_count;
  int cpu_response_count;

  soc_data_fabric #(
    .AW(32),
    .DW(32),
    .DATA_RAM_BASE(DATA_BASE),
    .DATA_RAM_END(DATA_END),
    .DEFAULT_RDATA(32'h0000_0000),
    .DEFAULT_ERROR(1'b1)
  ) u_dut (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .cpu_req_valid_i  (cpu_req_valid),
    .cpu_req_ready_o  (cpu_req_ready),
    .cpu_req_i        (cpu_req),
    .cpu_rsp_valid_o  (cpu_rsp_valid),
    .cpu_rsp_o        (cpu_rsp),
    .data_req_valid_o (data_req_valid),
    .data_req_ready_i (data_req_ready),
    .data_req_o       (data_req),
    .data_rsp_valid_i (data_rsp_valid),
    .data_rsp_i       (data_rsp)
  );

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      cpu_accept_count   <= 0;
      data_accept_count  <= 0;
      cpu_response_count <= 0;
    end else begin
      if (cpu_req_valid && cpu_req_ready)
        cpu_accept_count <= cpu_accept_count + 1;
      if (data_req_valid && data_req_ready)
        data_accept_count <= data_accept_count + 1;
      if (cpu_rsp_valid)
        cpu_response_count <= cpu_response_count + 1;
    end
  end

  task automatic set_request(
    input logic [31:0] addr,
    input logic write,
    input mem_size_e size,
    input logic [31:0] wdata,
    input logic [3:0] wstrb
  );
    begin
      cpu_req       = '0;
      cpu_req.addr  = addr;
      cpu_req.write = write;
      cpu_req.size  = size;
      cpu_req.wdata = wdata;
      cpu_req.wstrb = wstrb;
    end
  endtask

  initial begin
    clk            = 1'b0;
    rst_n          = 1'b0;
    cpu_req_valid  = 1'b0;
    cpu_req        = '0;
    data_req_ready = 1'b1;
    data_rsp_valid = 1'b0;
    data_rsp       = '0;

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // An unmapped store must select only the registered default target.
    set_request(32'h4000_0000, 1'b1, MEM_SIZE_WORD,
                32'hdead_beef, 4'b1111);
    cpu_req_valid = 1'b1;
    #1;
    assert (cpu_req_ready && !data_req_valid && !cpu_rsp_valid)
      else $fatal(1, "unmapped store decode/ready is wrong");

    @(posedge clk);
    #1;
    assert (cpu_rsp_valid && cpu_rsp.error && cpu_rsp.rdata == 32'h0)
      else $fatal(1, "default response is not registered zero-data error");
    assert (data_accept_count == 0)
      else $fatal(1, "unmapped store reached data RAM");

    @(negedge clk);
    cpu_req_valid = 1'b0;
    @(posedge clk);
    #1;
    assert (!cpu_rsp_valid && cpu_req_ready)
      else $fatal(1, "default response did not retire after one cycle");

    // RAM request back-pressure must propagate and the RAM address must be
    // base-subtracted without changing the other payload fields.
    @(negedge clk);
    data_req_ready = 1'b0;
    set_request(DATA_BASE + 32'h4, 1'b0, MEM_SIZE_WORD, '0, '0);
    cpu_req_valid = 1'b1;
    #1;
    assert (data_req_valid && !cpu_req_ready)
      else $fatal(1, "RAM back-pressure was not propagated");
    assert (data_req.addr == 32'h0000_0004 &&
            data_req.size == MEM_SIZE_WORD && !data_req.write)
      else $fatal(1, "RAM request translation/payload is wrong");

    @(posedge clk);
    @(negedge clk);
    data_req_ready = 1'b1;
    @(posedge clk);
    #1;
    assert (!cpu_rsp_valid && data_accept_count == 1)
      else $fatal(1, "mapped RAM request acceptance is wrong");

    // Change the live request to an unmapped address while RAM is outstanding.
    // The registered owner must still route only the RAM response.
    @(negedge clk);
    set_request(DATA_END + 32'h1, 1'b0, MEM_SIZE_BYTE, '0, '0);
    cpu_req_valid  = 1'b1;
    data_rsp.rdata = 32'h1234_5678;
    data_rsp.error = 1'b0;
    data_rsp_valid = 1'b1;
    #1;
    assert (!cpu_req_ready && !data_req_valid)
      else $fatal(1, "fabric accepted/redecoded a request while outstanding");
    assert (cpu_rsp_valid && cpu_rsp.rdata == 32'h1234_5678 && !cpu_rsp.error)
      else $fatal(1, "registered RAM owner did not route its response");

    // Keep the next request asserted. It becomes eligible immediately after
    // the RAM response retires and must then select the default target.
    @(posedge clk);
    #1;
    data_rsp_valid = 1'b0;
    assert (cpu_req_ready && !data_req_valid)
      else $fatal(1, "cross-target request was not released after response");
    @(posedge clk);
    #1;
    assert (cpu_rsp_valid && cpu_rsp.error && cpu_rsp.rdata == '0)
      else $fatal(1, "above-RAM boundary did not select the default target");
    assert (data_accept_count == 1)
      else $fatal(1, "above-RAM boundary reached RAM");

    @(negedge clk);
    cpu_req_valid = 1'b0;
    @(posedge clk);

    // The final byte of the configured region is mapped and translated to the
    // final local byte address.
    @(negedge clk);
    set_request(DATA_END, 1'b0, MEM_SIZE_BYTE, '0, '0);
    cpu_req_valid = 1'b1;
    #1;
    assert (data_req_valid && cpu_req_ready &&
            data_req.addr == 32'h0000_ffff)
      else $fatal(1, "inclusive RAM end boundary is wrong");
    @(posedge clk);
    @(negedge clk);
    cpu_req_valid  = 1'b0;
    data_rsp.rdata = 32'h0000_00a5;
    data_rsp.error = 1'b0;
    data_rsp_valid = 1'b1;
    #1;
    assert (cpu_rsp_valid && cpu_rsp.rdata == 32'h0000_00a5)
      else $fatal(1, "RAM end-boundary response was not routed");
    @(posedge clk);
    #1;
    data_rsp_valid = 1'b0;

    assert (cpu_accept_count == 4)
      else $fatal(1, "CPU acceptance count mismatch: %0d", cpu_accept_count);
    assert (data_accept_count == 2)
      else $fatal(1, "RAM acceptance count mismatch: %0d", data_accept_count);
    assert (cpu_response_count == 4)
      else $fatal(1, "response count mismatch: %0d", cpu_response_count);

    $display("[SOC-DATA-FABRIC-TB] RESULT: PASS");
    $finish;
  end

endmodule
`default_nettype wire
