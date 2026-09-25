`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

module tb_rv32m_unit;
  localparam int DW = 32;

  logic clk;
  logic rst_n;
  logic req_valid;
  logic req_ready;
  rv32m_req_t req;
  logic rsp_valid;
  logic rsp_ready;
  rv32m_rsp_t rsp;
  logic kill;
  logic wait_required;
  logic busy;
  int unsigned case_count;

  rv32m_unit dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .req_valid_i (req_valid),
    .req_ready_o (req_ready),
    .req_i       (req),
    .rsp_valid_o (rsp_valid),
    .rsp_ready_i (rsp_ready),
    .rsp_o       (rsp),
    .kill_i      (kill),
    .wait_o      (wait_required),
    .busy_o      (busy)
  );

  always #5 clk = ~clk;

  function automatic logic is_multiply(input muldiv_op_e op);
    is_multiply = op inside {
      MULDIV_MUL, MULDIV_MULH, MULDIV_MULHSU, MULDIV_MULHU
    };
  endfunction

  function automatic logic [31:0] reference_result(
    input muldiv_op_e op,
    input logic [31:0] lhs,
    input logic [31:0] rhs
  );
    logic lhs_signed;
    logic rhs_signed;
    logic signed [32:0] lhs_ext;
    logic signed [32:0] rhs_ext;
    logic signed [65:0] product_ext;
    begin
      lhs_signed = (op == MULDIV_MULH) || (op == MULDIV_MULHSU);
      rhs_signed = (op == MULDIV_MULH);
      lhs_ext = $signed({lhs_signed && lhs[31], lhs});
      rhs_ext = $signed({rhs_signed && rhs[31], rhs});
      product_ext = lhs_ext * rhs_ext;

      unique case (op)
        MULDIV_MUL:    reference_result = product_ext[31:0];
        MULDIV_MULH,
        MULDIV_MULHSU,
        MULDIV_MULHU:  reference_result = product_ext[63:32];
        MULDIV_DIV: begin
          if (rhs == 0)
            reference_result = 32'hffff_ffff;
          else if ((lhs == 32'h8000_0000) && (rhs == 32'hffff_ffff))
            reference_result = 32'h8000_0000;
          else
            reference_result = $signed(lhs) / $signed(rhs);
        end
        MULDIV_DIVU:
          reference_result = (rhs == 0) ? 32'hffff_ffff : lhs / rhs;
        MULDIV_REM: begin
          if (rhs == 0)
            reference_result = lhs;
          else if ((lhs == 32'h8000_0000) && (rhs == 32'hffff_ffff))
            reference_result = 0;
          else
            reference_result = $signed(lhs) % $signed(rhs);
        end
        MULDIV_REMU:
          reference_result = (rhs == 0) ? lhs : lhs % rhs;
        default: reference_result = 0;
      endcase
    end
  endfunction

  task automatic run_case(
    input muldiv_op_e op,
    input logic [31:0] lhs,
    input logic [31:0] rhs
  );
    logic [31:0] expected;
    begin
      expected = reference_result(op, lhs, rhs);
      @(negedge clk);
      req.op    = op;
      req.lhs   = lhs;
      req.rhs   = rhs;
      req_valid = 1'b1;

      while (!req_ready)
        @(negedge clk);

      if (is_multiply(op)) begin
        @(posedge clk);
        #1;
        assert (!rsp_valid && busy && wait_required && !req_ready)
          else $fatal(1, "multiply was not captured into its registered PARTIAL state");
        @(negedge clk);
        req_valid = 1'b0;
        repeat (2) begin
          @(posedge clk);
          #1;
          assert (!rsp_valid && busy && wait_required && !req_ready)
            else $fatal(1, "multiply left its registered arithmetic pipeline early");
        end
        @(posedge clk);
        #1;
        assert (rsp_valid && rsp.result == expected && !wait_required)
          else $fatal(1, "registered multiply mismatch op=%0d lhs=%h rhs=%h got=%h expected=%h",
                      op, lhs, rhs, rsp.result, expected);
        @(posedge clk);
        #1;
        assert (!rsp_valid && !busy)
          else $fatal(1, "accepted multiply response did not return to idle");
      end else begin
        @(posedge clk);
        @(negedge clk);
        req_valid = 1'b0;
        while (!rsp_valid)
          @(negedge clk);
        assert (rsp.result == expected)
          else $fatal(1, "divide mismatch op=%0d lhs=%h rhs=%h got=%h expected=%h",
                      op, lhs, rhs, rsp.result, expected);
      end
      case_count = case_count + 1;
    end
  endtask

  task automatic check_backpressure;
    logic [31:0] held_result;
    int i;
    begin
      @(negedge clk);
      rsp_ready = 1'b0;
      req.op    = MULDIV_REMU;
      req.lhs   = 32'h1234_5678;
      req.rhs   = 32'd97;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      while (!rsp_valid)
        @(negedge clk);
      held_result = rsp.result;
      assert (held_result == reference_result(MULDIV_REMU, 32'h1234_5678, 32'd97))
        else $fatal(1, "backpressured response has wrong result");
      for (i = 0; i < 3; i = i + 1) begin
        @(negedge clk);
        assert (rsp_valid && rsp.result == held_result)
          else $fatal(1, "backpressured response was not held stable");
      end
      rsp_ready = 1'b1;
      @(posedge clk);
      @(negedge clk);
      assert (!rsp_valid)
        else $fatal(1, "accepted response did not clear");
      case_count = case_count + 1;
    end
  endtask

  task automatic check_mul_backpressure;
    logic [31:0] expected;
    int i;
    begin
      expected = reference_result(MULDIV_MULHSU, 32'h8000_0001,
                                  32'hffff_fffd);
      @(negedge clk);
      rsp_ready = 1'b0;
      req.op    = MULDIV_MULHSU;
      req.lhs   = 32'h8000_0001;
      req.rhs   = 32'hffff_fffd;
      req_valid = 1'b1;
      assert (req_ready)
        else $fatal(1, "idle multiplier did not accept with response backpressure");
      @(posedge clk);
      #1;
      assert (!rsp_valid && busy && wait_required && !req_ready)
        else $fatal(1, "multiply did not enter EXEC under response backpressure");
      @(negedge clk);
      req_valid = 1'b0;
      repeat (2) begin
        @(posedge clk);
        #1;
        assert (!rsp_valid && busy && wait_required && !req_ready)
          else $fatal(1, "multiply left its registered arithmetic pipeline early under backpressure");
      end
      @(posedge clk);
      #1;
      assert (rsp_valid && rsp.result == expected && wait_required && !req_ready)
        else $fatal(1, "multiply response was not registered and held");
      for (i = 0; i < 3; i = i + 1) begin
        @(negedge clk);
        assert (!req_ready && rsp_valid && rsp.result == expected && wait_required)
          else $fatal(1, "multiply request/response changed while backpressured");
      end
      rsp_ready = 1'b1;
      #1;
      assert (!req_ready && rsp_valid && rsp.result == expected && !wait_required)
        else $fatal(1, "multiply transfer was not released by response ready");
      @(posedge clk);
      #1;
      assert (!rsp_valid && !busy)
        else $fatal(1, "multiply response did not clear after acceptance");
      case_count = case_count + 1;
    end
  endtask

  task automatic check_mul_kill_exec;
    int i;
    begin
      @(negedge clk);
      req.op    = MULDIV_MULHU;
      req.lhs   = 32'hffff_0001;
      req.rhs   = 32'h8000_0003;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      #1;
      assert (busy && wait_required && !rsp_valid)
        else $fatal(1, "multiply did not enter EXEC before kill");
      @(negedge clk);
      req_valid = 1'b0;
      kill = 1'b1;
      #1;
      assert (!rsp_valid && !req_ready)
        else $fatal(1, "kill did not suppress multiplier protocol outputs");
      @(posedge clk);
      @(negedge clk);
      kill = 1'b0;
      for (i = 0; i < 4; i = i + 1) begin
        @(negedge clk);
        assert (!rsp_valid && !busy)
          else $fatal(1, "EXEC-killed multiply produced a late response");
      end
      run_case(MULDIV_MULHU, 32'hffff_0001, 32'h8000_0003);
      case_count = case_count + 1;
    end
  endtask

  task automatic check_mul_kill_response;
    int i;
    begin
      @(negedge clk);
      rsp_ready = 1'b0;
      req.op    = MULDIV_MUL;
      req.lhs   = 32'd12345;
      req.rhs   = 32'd6789;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      repeat (2) @(posedge clk);
      @(posedge clk);
      #1;
      assert (rsp_valid && wait_required)
        else $fatal(1, "multiply did not reach held RESP before kill");
      @(negedge clk);
      kill = 1'b1;
      #1;
      assert (!rsp_valid)
        else $fatal(1, "kill did not suppress held multiply response");
      @(posedge clk);
      @(negedge clk);
      kill = 1'b0;
      rsp_ready = 1'b1;
      for (i = 0; i < 4; i = i + 1) begin
        @(negedge clk);
        assert (!rsp_valid && !busy)
          else $fatal(1, "RESP-killed multiply produced a late response");
      end
      case_count = case_count + 1;
    end
  endtask

  task automatic check_kill_restart;
    int i;
    begin
      @(negedge clk);
      req.op    = MULDIV_DIVU;
      req.lhs   = 32'hffff_ffff;
      req.rhs   = 32'd3;
      req_valid = 1'b1;
      while (!req_ready)
        @(negedge clk);
      @(posedge clk);
      @(negedge clk);
      req_valid = 1'b0;
      repeat (5) @(negedge clk);
      kill = 1'b1;
      @(negedge clk);
      kill = 1'b0;
      for (i = 0; i < 40; i = i + 1) begin
        @(negedge clk);
        assert (!rsp_valid)
          else $fatal(1, "killed operation produced a response");
      end
      assert (!busy)
        else $fatal(1, "RV32M unit remained busy after kill");
      run_case(MULDIV_DIVU, 32'hffff_ffff, 32'd3);
      case_count = case_count + 1;
    end
  endtask

  initial begin
    int i;
    clk        = 1'b0;
    rst_n      = 1'b0;
    req_valid  = 1'b0;
    req        = '0;
    rsp_ready  = 1'b1;
    kill       = 1'b0;
    case_count = 0;
    repeat (3) @(posedge clk);
    rst_n = 1'b1;

    run_case(MULDIV_MUL,    32'hffff_ffff, 32'd2);
    run_case(MULDIV_MULH,   32'h8000_0000, 32'd2);
    run_case(MULDIV_MULHSU, 32'h8000_0000, 32'hffff_ffff);
    run_case(MULDIV_MULHU,  32'hffff_ffff, 32'hffff_ffff);
    run_case(MULDIV_DIV,    32'h8000_0000, 32'hffff_ffff);
    run_case(MULDIV_DIVU,   32'h1234_5678, 0);
    run_case(MULDIV_REM,    32'h8000_0001, 32'd7);
    run_case(MULDIV_REMU,   32'h1234_5678, 0);

    for (i = 0; i < 32; i = i + 1) begin
      run_case(MULDIV_MUL,    $urandom, $urandom);
      run_case(MULDIV_MULH,   $urandom, $urandom);
      run_case(MULDIV_MULHSU, $urandom, $urandom);
      run_case(MULDIV_MULHU,  $urandom, $urandom);
    end

    for (i = 0; i < 8; i = i + 1) begin
      run_case(MULDIV_DIV,  $urandom, $urandom);
      run_case(MULDIV_DIVU, $urandom, $urandom);
      run_case(MULDIV_REM,  $urandom, $urandom);
      run_case(MULDIV_REMU, $urandom, $urandom);
    end

    check_mul_backpressure();
    check_mul_kill_exec();
    check_mul_kill_response();
    check_backpressure();
    check_kill_restart();

    $display("[RV32M-TB] RESULT: PASS cases=%0d", case_count);
    $finish;
  end
endmodule

`default_nettype wire
