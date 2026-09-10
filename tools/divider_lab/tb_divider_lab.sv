`timescale 1ns/1ps
// Teaching harness only: the production divider is not modified.
module tb_divider_lab;
  logic clk = 0;
  logic rst_n = 0, start = 0, kill = 0, signed_mode = 0;
  logic [31:0] dividend = 0, divisor = 0;
  wire busy, complete;
  wire [31:0] quotient, remainder;
  integer trace_file, case_id = 0, step = 0;

  radix2_divider dut (
    .clk_i(clk), .rst_ni(rst_n), .start_i(start), .kill_i(kill),
    .signed_i(signed_mode), .dividend_i(dividend), .divisor_i(divisor),
    .busy_o(busy), .complete_o(complete),
    .quotient_o(quotient), .remainder_o(remainder)
  );
  always #20ns clk = ~clk; // 25 MHz; same period as the timing exercise.

  task automatic snapshot(input string phase_name);
    $fdisplay(trace_file,
      "{\"time_ns\":%0.3f,\"case\":%0d,\"step\":%0d,\"phase\":\"%s\",\"start\":%0d,\"kill\":%0d,\"busy\":%0d,\"complete\":%0d,\"state\":%0d,\"iteration\":%0d,\"work_q\":%0d,\"work_r\":%0d,\"divisor_q\":%0d,\"quotient\":%0d,\"remainder\":%0d}",
      $realtime, case_id, step, phase_name, start, kill, busy, complete,
      dut.state_q, dut.iteration_q, dut.quotient_work_q,
      dut.remainder_work_q, dut.divisor_q, quotient, remainder);
  endtask

  task automatic launch(input bit is_signed,
                        input logic [31:0] lhs, rhs);
    wait (!busy && !complete);
    @(negedge clk); // Drive away from the DUT's sampling edge.
    signed_mode = is_signed;
    dividend = lhs;
    divisor = rhs;
    start = 1;
    @(posedge clk);
    #1ns; // Observe AFTER nonblocking assignments have updated the registers.
    step = 0;
    snapshot("accepted");
    assert (busy && !complete) else $fatal(1, "LAB_START_NOT_ACCEPTED");
    @(negedge clk);
    start = 0;
  endtask

  task automatic calculate(input integer id, input bit is_signed,
                           input logic [31:0] lhs, rhs, expected_q, expected_r);
    case_id = id;
    launch(is_signed, lhs, rhs);
    for (integer n = 1; n <= 32; n++) begin
      @(posedge clk);
      #1ns;
      step = n;
      snapshot(n == 32 ? "complete" : "run");
      assert ((n == 32) ? (complete && !busy) : (busy && !complete))
        else $fatal(1, "LAB_LATENCY case=%0d step=%0d", id, n);
    end
    assert (quotient === expected_q && remainder === expected_r)
      else $fatal(1,
        "LAB_RESULT_MISMATCH case=%0d expected_q=%08h actual_q=%08h expected_r=%08h actual_r=%08h",
        id, expected_q, quotient, expected_r, remainder);
    $display("[DIVIDER-LAB] case=%0d latency=32 q=%08h r=%08h PASS",
             id, quotient, remainder);
    @(posedge clk);
    #1ns;
    step = 33;
    snapshot("idle");
    assert (!busy && !complete) else $fatal(1, "LAB_COMPLETE_NOT_ONE_CYCLE");
  endtask

  task automatic cancel_operation;
    case_id = 5;
    launch(0, 32'hffff_ffff, 32'd3);
    for (integer n = 1; n <= 7; n++) begin
      @(posedge clk);
      #1ns;
      step = n;
      snapshot("run");
      assert (busy && !complete) else $fatal(1, "LAB_PREMATURE_COMPLETE");
    end
    @(negedge clk);
    kill = 1;
    start = 1; // Kill must win even if a new start is also high.
    @(posedge clk);
    #1ns;
    step = 8;
    snapshot("killed");
    assert (!busy && !complete && quotient == 0 && remainder == 0)
      else $fatal(1, "LAB_KILL_PRIORITY");
    @(negedge clk);
    kill = 0;
    start = 0;
    repeat (34) begin
      @(posedge clk);
      #1ns;
      step++;
      snapshot("cancel_guard");
      assert (!busy && !complete) else $fatal(1, "LAB_ORPHAN_COMPLETION");
    end
    $display("[DIVIDER-LAB] kill/start priority and 34-cycle no-completion guard PASS");
  endtask

  initial begin
    trace_file = $fopen("trace.jsonl", "w");
    if (!trace_file) $fatal(1, "LAB_TRACE_OPEN_FAILED");
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    // Negative infrastructure test deliberately expects 13 instead of 14.
    calculate(1, 0, 100, 7, $test$plusargs("BAD_EXPECT_Q") ? 13 : 14, 2);
    calculate(2, 1, -32'sd100, 7, -32'sd14, -32'sd2);
    calculate(3, 0, 32'h1234_5678, 0, 32'hffff_ffff, 32'h1234_5678);
    calculate(4, 1, 32'h8000_0000, 32'hffff_ffff, 32'h8000_0000, 0);
    cancel_operation();
    calculate(6, 0, 1000, 9, 111, 1);
    $fclose(trace_file);
    $display("[DIVIDER-LAB] RESULT: PASS completed=5 cancelled=1");
    $finish;
  end
  initial begin
    #20us;
    $fatal(1, "LAB_WATCHDOG_TIMEOUT");
  end
endmodule
