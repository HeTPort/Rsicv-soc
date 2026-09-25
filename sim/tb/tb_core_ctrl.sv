`timescale 1ns/1ps
`default_nettype none
import riscv_pkg::*;

module tb_core_ctrl;
  logic clk;
  logic rst_n;
  logic id_valid;
  logic [4:0] id_rs1_addr;
  logic [4:0] id_rs2_addr;
  logic id_use_rs1;
  logic id_use_rs2;
  logic ex_valid;
  logic [4:0] ex_rd_addr;
  logic ex_rf_we;
  exc_pkt_t ex_exc;
  redirect_t ex_redirect;
  logic ex_wait;
  redirect_t retire_redirect;
  logic wfi_enter;
  logic wfi_wait;
  redirect_t selected_redirect;
  pipe_ctrl_t pipe_ctrl;
  integer cases;

  always #5ns clk = ~clk;

  core_ctrl dut (
    .clk_i                (clk),
    .rst_ni               (rst_n),
    .id_valid_i           (id_valid),
    .id_rs1_addr_i        (id_rs1_addr),
    .id_rs2_addr_i        (id_rs2_addr),
    .id_use_rs1_i         (id_use_rs1),
    .id_use_rs2_i         (id_use_rs2),
    .ex_valid_i           (ex_valid),
    .ex_rd_addr_i         (ex_rd_addr),
    .ex_rf_we_i           (ex_rf_we),
    .ex_exc_i             (ex_exc),
    .ex_redirect_i        (ex_redirect),
    .ex_wait_i            (ex_wait),
    .retire_redirect_i    (retire_redirect),
    .wfi_enter_i          (wfi_enter),
    .wfi_wait_i           (wfi_wait),
    .redirect_o           (selected_redirect),
    .pipe_ctrl_o          (pipe_ctrl)
  );

  task automatic defaults;
    begin
      id_valid = 1'b0;
      id_rs1_addr = '0;
      id_rs2_addr = '0;
      id_use_rs1 = 1'b0;
      id_use_rs2 = 1'b0;
      ex_valid = 1'b0;
      ex_rd_addr = '0;
      ex_rf_we = 1'b0;
      ex_exc = '0;
      ex_redirect = '0;
      ex_wait = 1'b0;
      retire_redirect = '0;
      wfi_enter = 1'b0;
      wfi_wait = 1'b0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin
      cases = cases + 1;
      assert (condition) else $fatal(1, "%s", message);
    end
  endtask

  initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    cases = 0;
    defaults();
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;
    #1;

    check(pipe_ctrl.instr_req && !pipe_ctrl.pc_stall &&
          !selected_redirect.valid, "normal movement is wrong");

    id_valid = 1'b1;
    id_rs1_addr = 5'd7;
    id_use_rs1 = 1'b1;
    ex_valid = 1'b1;
    ex_rd_addr = 5'd7;
    ex_rf_we = 1'b1;
    #1;
    check(pipe_ctrl.pc_stall && pipe_ctrl.ifid_stall &&
          !pipe_ctrl.idex_stall && pipe_ctrl.idex_flush,
          "RAW hazard did not hold front end and inject one bubble");

    ex_wait = 1'b1;
    #1;
    check(pipe_ctrl.pc_stall && pipe_ctrl.ifid_stall &&
          pipe_ctrl.idex_stall && !pipe_ctrl.idex_flush,
          "EX wait did not retain the owning packet");

    defaults();
    ex_redirect.valid = 1'b1;
    ex_redirect.pc = 32'h100;
    ex_redirect.reason = REDIRECT_BRANCH;
    #1;
    check(selected_redirect == ex_redirect && pipe_ctrl.ifid_flush &&
          pipe_ctrl.idex_flush && pipe_ctrl.instr_req && !pipe_ctrl.pipe_kill,
          "EX redirect movement is wrong");
    @(posedge clk);
    @(negedge clk);
    ex_redirect = '0;
    #1;
    check(pipe_ctrl.ifid_flush, "stale synchronous fetch was not killed");
    @(posedge clk);
    @(negedge clk);
    #1;
    check(!pipe_ctrl.ifid_flush, "delayed fetch kill lasted too long");

    ex_redirect.valid = 1'b1;
    ex_redirect.pc = 32'h104;
    ex_redirect.reason = REDIRECT_JUMP;
    retire_redirect.valid = 1'b1;
    retire_redirect.pc = 32'h200;
    retire_redirect.reason = REDIRECT_SYNC_TRAP;
    #1;
    check(selected_redirect == retire_redirect && pipe_ctrl.pipe_kill &&
          pipe_ctrl.ex_kill && !pipe_ctrl.instr_req,
          "retirement redirect did not dominate younger EX redirect");

    defaults();
    ex_valid = 1'b1;
    ex_exc.illegal_instr = 1'b1;
    #1;
    check(pipe_ctrl.ex_kill && !pipe_ctrl.pipe_kill,
          "EX exception did not cancel local work independently");

    defaults();
    wfi_enter = 1'b1;
    #1;
    check(pipe_ctrl.pipe_kill && pipe_ctrl.ex_kill &&
          pipe_ctrl.pc_stall && !pipe_ctrl.instr_req,
          "WFI entry did not kill younger work");

    defaults();
    wfi_wait = 1'b1;
    #1;
    check(pipe_ctrl.pc_stall && pipe_ctrl.ifid_stall &&
          pipe_ctrl.idex_stall && !pipe_ctrl.pipe_kill,
          "WFI wait did not hold the pipeline cleanly");

    $display("[CORE-CTRL-TB] RESULT: PASS cases=%0d", cases);
    $finish;
  end
endmodule

`default_nettype wire
