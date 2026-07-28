`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_lsu_protocol;
  localparam int AW = 32;
  localparam int DW = 32;

  logic clk;
  logic rst_n;
  id_ex_pkt_t pkt_ex;
  logic ex_kill;

  logic req_valid;
  logic req_ready;
  core_bus_req_t req;
  logic rsp_valid;
  core_bus_rsp_t rsp;

  mem_pkt_t mem_info;
  logic mem_misaligned;
  logic [DW-1:0] load_data;
  logic load_fault;
  logic store_fault;
  logic busy;
  logic complete;

  integer accepted_count;
  integer response_count;
  integer complete_count;
  core_bus_req_t held_req;

  lsu #(
    .AW(AW),
    .DW(DW)
  ) dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .pkt_ex_i          (pkt_ex),
    .ex_kill_i         (ex_kill),
    .bus_req_valid_o   (req_valid),
    .bus_req_ready_i   (req_ready),
    .bus_req_o         (req),
    .bus_rsp_valid_i   (rsp_valid),
    .bus_rsp_i         (rsp),
    .mem_info_o        (mem_info),
    .mem_misaligned_o  (mem_misaligned),
    .load_data_o       (load_data),
    .load_fault_o      (load_fault),
    .store_fault_o     (store_fault),
    .busy_o            (busy),
    .complete_o        (complete)
  );

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  always @(posedge clk) begin
    if (!rst_n) begin
      accepted_count <= 0;
      response_count <= 0;
      complete_count <= 0;
    end else begin
      if (req_valid && req_ready)
        accepted_count <= accepted_count + 1;
      if (rsp_valid)
        response_count <= response_count + 1;
      if (complete)
        complete_count <= complete_count + 1;
    end
  end

  task automatic drive_load(
    input logic [AW-1:0] base,
    input logic [DW-1:0] offset,
    input mem_size_e size,
    input logic unsigned_load
  );
    begin
      pkt_ex = ID_EX_PKT_BUBBLE;
      pkt_ex.valid = 1'b1;
      pkt_ex.rf.we = 1'b1;
      pkt_ex.rf.addr = 5'd7;
      pkt_ex.ex_data.op1 = base;
      pkt_ex.ex_data.imm = offset;
      pkt_ex.ex_ctrl.mem_req = 1'b1;
      pkt_ex.ex_ctrl.mem_we = 1'b0;
      pkt_ex.ex_ctrl.mem_size = size;
      pkt_ex.ex_ctrl.mem_unsigned = unsigned_load;
      pkt_ex.ex_ctrl.wb_sel = WB_MEM;
    end
  endtask

  task automatic drive_store(
    input logic [AW-1:0] base,
    input logic [DW-1:0] offset,
    input mem_size_e size,
    input logic [DW-1:0] data
  );
    begin
      pkt_ex = ID_EX_PKT_BUBBLE;
      pkt_ex.valid = 1'b1;
      pkt_ex.ex_data.op1 = base;
      pkt_ex.ex_data.imm = offset;
      pkt_ex.ex_data.store_data = data;
      pkt_ex.ex_ctrl.mem_req = 1'b1;
      pkt_ex.ex_ctrl.mem_we = 1'b1;
      pkt_ex.ex_ctrl.mem_size = size;
      pkt_ex.ex_ctrl.wb_sel = WB_NONE;
    end
  endtask

  task automatic hold_request_for(input int cycles);
    begin
      wait (req_valid === 1'b1);
      held_req = req;
      repeat (cycles) begin
        @(negedge clk);
        assert (req_valid)
          else $fatal(1, "request valid dropped before acceptance");
        assert (req === held_req)
          else $fatal(1, "request payload changed under back-pressure");
        assert (!complete)
          else $fatal(1, "transaction completed before request acceptance");
      end
      req_ready = 1'b1;
      @(negedge clk);
      req_ready = 1'b0;
      assert (!req_valid)
        else $fatal(1, "accepted request was reissued");
    end
  endtask

  task automatic return_response(
    input int delay_cycles,
    input logic [DW-1:0] data,
    input logic error
  );
    begin
      repeat (delay_cycles) begin
        @(negedge clk);
        assert (busy)
          else $fatal(1, "LSU stopped waiting before the response");
        assert (!req_valid)
          else $fatal(1, "LSU reissued an accepted request");
        assert (!complete)
          else $fatal(1, "LSU completed before rsp_valid");
      end
      rsp.rdata = data;
      rsp.error = error;
      rsp_valid = 1'b1;
      @(negedge clk);
      rsp_valid = 1'b0;
      assert (complete)
        else $fatal(1, "rsp_valid did not produce a completion");
      @(negedge clk);
      assert (!complete)
        else $fatal(1, "completion lasted more than one cycle");
    end
  endtask

  initial begin
    rst_n = 1'b0;
    pkt_ex = ID_EX_PKT_BUBBLE;
    ex_kill = 1'b0;
    req_ready = 1'b0;
    rsp_valid = 1'b0;
    rsp = '0;
    held_req = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    // Delayed word load.
    drive_load(32'h0000_0100, 32'h0000_0004, MEM_SIZE_WORD, 1'b0);
    hold_request_for(3);
    assert (held_req.addr == 32'h0000_0104 && !held_req.write)
      else $fatal(1, "load request payload is wrong");
    assert (held_req.size == MEM_SIZE_WORD && held_req.wstrb == '0)
      else $fatal(1, "load size/strobes are wrong");
    return_response(4, 32'h1122_3344, 1'b0);
    assert (load_data == 32'h1122_3344 && !load_fault)
      else $fatal(1, "load completion data/fault is wrong");
    pkt_ex = ID_EX_PKT_BUBBLE;
    @(negedge clk);

    // Delayed byte store with an error response.
    drive_store(32'h0000_0200, 32'h0000_0001, MEM_SIZE_BYTE, 32'h0000_00a5);
    hold_request_for(2);
    assert (held_req.addr == 32'h0000_0201 && held_req.write)
      else $fatal(1, "store request payload is wrong");
    assert (held_req.size == MEM_SIZE_BYTE &&
            held_req.wstrb == 4'b0010 &&
            held_req.wdata == 32'h0000_a500)
      else $fatal(1, "store lane alignment is wrong");
    return_response(2, 32'h0000_0000, 1'b1);
    assert (store_fault)
      else $fatal(1, "store response error was not reported");
    pkt_ex = ID_EX_PKT_BUBBLE;
    @(negedge clk);

    // A killed, unaccepted request is cancelled without completion.
    drive_load(32'h0000_0300, '0, MEM_SIZE_WORD, 1'b0);
    wait (req_valid === 1'b1);
    @(negedge clk);
    ex_kill = 1'b1;
    @(negedge clk);
    ex_kill = 1'b0;
    pkt_ex = ID_EX_PKT_BUBBLE;
    assert (!req_valid && !complete)
      else $fatal(1, "killed unaccepted request was not cancelled");

    repeat (2) @(negedge clk);
    assert (accepted_count == 2)
      else $fatal(1, "accepted request count mismatch: %0d", accepted_count);
    assert (response_count == 2)
      else $fatal(1, "response count mismatch: %0d", response_count);
    assert (complete_count == 2)
      else $fatal(1, "completion count mismatch: %0d", complete_count);

    $display("[LSU-TB] RESULT: PASS");
    $finish;
  end

endmodule
`default_nettype wire
