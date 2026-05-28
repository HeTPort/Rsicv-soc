`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
// ============================================================
// Module: tb_riscv
// Description:
//   Simple top-level testbench for the reconstructed RV32IM CPU.
//
// Structure:
//   tb_riscv
//     |- riscv
//     |- prog_ram
//
// Program:
//   prog_ram loads "prog.hex" by $readmemh.
//
// Pass/fail convention:
//   PASS:
//     dbg_x10_o == 1
//     dbg_x11_o == 0
//
//   FAIL:
//     dbg_x10_o == 0
//     dbg_x11_o contains failure code.
//
// Notes:
//   - Program ends with EBREAK.
//   - The CPU treats EBREAK as halt/exception.
// ============================================================
module tb_riscv_core;
  localparam int AW = 32;
  localparam int DW = 32;
  localparam int PROG_RAM_DEPTH = 4096;
  localparam int DATA_RAM_DEPTH = 4096;
  localparam int CLK_PERIOD_NS = 10;
  localparam int TIMEOUT_CYCLES = 20000;
  // ------------------------------------------------------------
  // Clock / reset
  // ------------------------------------------------------------
  logic clk;
  logic rst_n;
  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS / 2) clk = ~clk;
  end
  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end
  // ------------------------------------------------------------
  // Instruction interface between CPU and prog_ram
  // ------------------------------------------------------------
  logic          instr_ren;
  logic [AW-1:0] instr_addr;
  logic [DW-1:0] instr_rdata;
  // ------------------------------------------------------------
  // Debug outputs
  // ------------------------------------------------------------
  logic [DW-1:0] dbg_x3;
  logic [DW-1:0] dbg_x10;
  logic [DW-1:0] dbg_x11;
  logic halt;
  logic illegal_instr;
  logic exception;
  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv #(
    .AW(AW),
    .DW(DW),
    .DATA_RAM_DEPTH(DATA_RAM_DEPTH)
  ) u_riscv (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .instr_ren_o     (instr_ren),
    .instr_addr_o    (instr_addr),
    .instr_rdata_i   (instr_rdata),
    .dbg_x3_o        (dbg_x3),
    .dbg_x10_o       (dbg_x10),
    .dbg_x11_o       (dbg_x11),
    .halt_o          (halt),
    .illegal_instr_o (illegal_instr),
    .exception_o     (exception)
  );
  // ------------------------------------------------------------
  // Program RAM
  // ------------------------------------------------------------
  prog_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(PROG_RAM_DEPTH),
    .FILE("prog.hex"),
    .INVALID_RDATA(32'h0010_0073) // ebreak on invalid fetch
  ) u_prog_ram (
    .clk_i        (clk),
    .ren_i        (instr_ren),
    .instr_addr_i (instr_addr),
    .instr_data_o (instr_rdata),
    .wen_i        (1'b0),
    .waddr_i      ('0),
    .wdata_i      ('0)
  );
  // ------------------------------------------------------------
  // Wave dump
  // ------------------------------------------------------------
  initial begin
    $dumpfile("tb_riscv.vcd");
    $dumpvars(0, tb_riscv);
  end
  // ------------------------------------------------------------
  // Timeout watchdog
  // ------------------------------------------------------------
  integer cycle_count;
  initial begin
    cycle_count = 0;
    wait (rst_n == 1'b1);
    forever begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("============================================================");
        $display("[TB] TIMEOUT");
        $display("[TB] cycle     = %0d", cycle_count);
        $display("[TB] instr_addr= 0x%08h", instr_addr);
        $display("[TB] dbg_x3    = 0x%08h", dbg_x3);
        $display("[TB] dbg_x10   = 0x%08h", dbg_x10);
        $display("[TB] dbg_x11   = 0x%08h", dbg_x11);
        $display("============================================================");
        $fatal(1, "[TB] Simulation timeout");
      end
    end
  end
  // ------------------------------------------------------------
  // Finish on halt
  // ------------------------------------------------------------
  initial begin
    wait (rst_n == 1'b1);
    wait (halt == 1'b1);
    repeat (2) @(posedge clk);
    $display("============================================================");
    $display("[TB] CPU halted");
    $display("[TB] cycle          = %0d", cycle_count);
    $display("[TB] instr_addr     = 0x%08h", instr_addr);
    $display("[TB] dbg_x3         = 0x%08h", dbg_x3);
    $display("[TB] dbg_x10        = 0x%08h", dbg_x10);
    $display("[TB] dbg_x11        = 0x%08h", dbg_x11);
    $display("[TB] illegal_instr  = %0b",_instr);
    $display("[TB] exception      = %0b", exception);
    if (dbg_x10 == 32'd1 && dbg_x11 == 32'd0) begin
      $display("[TB] RESULT: PASS");
      $display("============================================================");
      $finish;
    end
    else begin
      $display("[TB] RESULT: FAIL");
      $display("[TB] Failure code in x11 = %0d / 0x%08h", dbg_x11, dbg_x11);
      $display("============================================================");
      $fatal(1, "[TB] RV32IM test failed");
    end
  end
  // ------------------------------------------------------------
  // Optional monitor
  // ------------------------------------------------------------
`ifndef SYNTHESIS
  always_ff @(posedge clk) begin
    if (rst_n) begin
      if (illegal_instr) begin
        $display("[TB] illegal instruction pulse detected");
      end
      if (exception) begin
        $display("[TB] exception pulse detected");
      end
    end
  end
`endif

//some checks
always @(posedge clk_i) begin
  #1ps;
  if (rst_ni && u_core.id_valid) begin
    assert (u_core.id_instr[31:0] === u_prog_ram.mem[u_core.id_pc[31:2]])
      else $error("ID PC/INSTR mismatch: pc=%08h instr=%08h expected=%08h",
                  u_core.id_pc,
                  u_core.id_instr[31:0],
                  u_prog_ram.mem[u_core.id_pc[31:2]]);
  end
end

endmodule
`default_nettype wire