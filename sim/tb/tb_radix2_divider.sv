`timescale 1ns/1ps
`default_nettype wire
module tb_radix2_divider;
  localparam int DW = 32;

  logic clk;
  logic rst_n;
  logic start;
  logic kill;
  logic signed_mode;
  logic [DW-1:0] dividend;
  logic [DW-1:0] divisor;
  logic busy;
  logic complete;
  logic [DW-1:0] quotient;
  logic [DW-1:0] remainder;

  logic [DW-1:0] random_a;
  logic [DW-1:0] random_b;
  integer random_index;
  integer completion_count;

  radix2_divider #(
    .DW(DW)
  ) dut (
    .clk_i       (clk),
    .rst_ni      (rst_n),
    .start_i     (start),
    .kill_i      (kill),
    .signed_i    (signed_mode),
    .dividend_i  (dividend),
    .divisor_i   (divisor),
    .busy_o      (busy),
    .complete_o  (complete),
    .quotient_o  (quotient),
    .remainder_o (remainder)
  );

  initial begin
    clk = 1'b0;
    forever #5ns clk = ~clk;
  end

  always @(posedge clk) begin
    if (!rst_n)
      completion_count <= 0;
    else if (complete)
      completion_count <= completion_count + 1;
  end

  function automatic logic [DW-1:0] reference_quotient(
    input logic signed_operation,
    input logic [DW-1:0] lhs,
    input logic [DW-1:0] rhs
  );
    logic signed [DW-1:0] signed_lhs;
    logic signed [DW-1:0] signed_rhs;
    begin
      signed_lhs = signed'(lhs);
      signed_rhs = signed'(rhs);
      if (rhs == '0)
        reference_quotient = {DW{1'b1}};
      else if (signed_operation &&
               lhs == 32'h8000_0000 && rhs == 32'hffff_ffff)
        reference_quotient = 32'h8000_0000;
      else if (signed_operation)
        reference_quotient = signed_lhs / signed_rhs;
      else
        reference_quotient = lhs / rhs;
    end
  endfunction

  function automatic logic [DW-1:0] reference_remainder(
    input logic signed_operation,
    input logic [DW-1:0] lhs,
    input logic [DW-1:0] rhs
  );
    logic signed [DW-1:0] signed_lhs;
    logic signed [DW-1:0] signed_rhs;
    begin
      signed_lhs = signed'(lhs);
      signed_rhs = signed'(rhs);
      if (rhs == '0)
        reference_remainder = lhs;
      else if (signed_operation &&
               lhs == 32'h8000_0000 && rhs == 32'hffff_ffff)
        reference_remainder = '0;
      else if (signed_operation)
        reference_remainder = signed_lhs % signed_rhs;
      else
        reference_remainder = lhs % rhs;
    end
  endfunction

  task automatic run_case(
    input string case_name,
    input logic signed_operation,
    input logic [DW-1:0] lhs,
    input logic [DW-1:0] rhs
  );
    logic [DW-1:0] expected_quotient;
    logic [DW-1:0] expected_remainder;
    integer run_cycles;
    begin
      expected_quotient  = reference_quotient(signed_operation, lhs, rhs);
      expected_remainder = reference_remainder(signed_operation, lhs, rhs);

      wait (!busy && !complete);
      @(negedge clk);
      signed_mode = signed_operation;
      dividend    = lhs;
      divisor     = rhs;
      start       = 1'b1;

      @(posedge clk);
      #1ns;
      start = 1'b0;
      assert (busy && !complete)
        else $fatal(1, "%s did not enter busy state", case_name);

      run_cycles = 0;
      while (!complete) begin
        @(posedge clk);
        #1ns;
        run_cycles = run_cycles + 1;
        if (run_cycles > DW)
          $fatal(1, "%s exceeded the expected iteration count", case_name);
        if (!complete) begin
          assert (busy)
            else $fatal(1, "%s dropped busy before completion", case_name);
        end
      end

      assert (run_cycles == DW)
        else $fatal(1, "%s latency mismatch: %0d cycles", case_name, run_cycles);
      assert (!busy)
        else $fatal(1, "%s asserted busy and complete together", case_name);
      assert (quotient === expected_quotient)
        else $fatal(1,
                    "%s quotient mismatch: expected=%08h actual=%08h",
                    case_name, expected_quotient, quotient);
      assert (remainder === expected_remainder)
        else $fatal(1,
                    "%s remainder mismatch: expected=%08h actual=%08h",
                    case_name, expected_remainder, remainder);

      @(posedge clk);
      #1ns;
      assert (!complete && !busy)
        else $fatal(1, "%s completion did not return to idle", case_name);
    end
  endtask

  task automatic run_kill_case;
    integer count_before;
    begin
      wait (!busy && !complete);
      @(negedge clk);
      signed_mode = 1'b0;
      dividend    = 32'hffff_ffff;
      divisor     = 32'd3;
      start       = 1'b1;
      count_before = completion_count;

      @(posedge clk);
      #1ns;
      start = 1'b0;
      assert (busy)
        else $fatal(1, "kill test did not start");

      repeat (7) begin
        @(posedge clk);
        #1ns;
        assert (busy && !complete)
          else $fatal(1, "kill test completed too early");
      end

      @(negedge clk);
      kill = 1'b1;
      @(posedge clk);
      #1ns;
      kill = 1'b0;
      assert (!busy && !complete)
        else $fatal(1, "kill did not cancel the divider");
      assert (quotient == '0 && remainder == '0)
        else $fatal(1, "kill did not clear stale results");

      repeat (2) @(posedge clk);
      assert (completion_count == count_before)
        else $fatal(1, "killed operation emitted a completion");
    end
  endtask

  initial begin
    rst_n        = 1'b0;
    start        = 1'b0;
    kill         = 1'b0;
    signed_mode  = 1'b0;
    dividend     = '0;
    divisor      = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;

    run_case("unsigned basic", 1'b0, 32'd100, 32'd7);
    run_case("signed negative dividend", 1'b1, -32'sd100, 32'd7);
    run_case("signed negative divisor", 1'b1, 32'd100, -32'sd7);
    run_case("signed both negative", 1'b1, -32'sd100, -32'sd7);
    run_case("unsigned zero dividend", 1'b0, 32'd0, 32'd5);
    run_case("unsigned divide by zero", 1'b0, 32'h1234_5678, 32'd0);
    run_case("signed divide by zero", 1'b1, 32'h8000_0001, 32'd0);
    run_case("signed overflow", 1'b1, 32'h8000_0000, 32'hffff_ffff);
    run_case("maximum unsigned", 1'b0, 32'hffff_ffff, 32'hffff_fffe);

    for (random_index = 0; random_index < 32; random_index = random_index + 1) begin
      random_a = $urandom;
      random_b = $urandom;
      run_case("random", random_index[0], random_a, random_b);
    end

    run_kill_case();
    run_case("post-kill recovery", 1'b0, 32'd1000, 32'd9);

    $display("[DIVIDER-TB] RESULT: PASS cases=%0d", completion_count);
    $finish;
  end

endmodule
`default_nettype wire
