`timescale 1ns / 1ps
`default_nettype wire
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
  logic  seen_illegal;
  // ------------------------------------------------------------
  // Sticky illegal instruction monitor
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      seen_illegal <= 1'b0;
    end else if (illegal_instr) begin
      seen_illegal <= 1'b1;
    end
  end
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
    .DATA_RAM_DEPTH(DATA_RAM_DEPTH),
    .INIT_DATA_FILE("")
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
    .FILE("D:/Rsicv-soc/testdata/prog.hex"),
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
    $dumpvars(0, tb_riscv_core);
  end
  // ------------------------------------------------------------
  // Timeout watchdog
  // ------------------------------------------------------------
  integer cycle_count;
  initial begin
    #1ns;
    $display("[TB] Check program RAM content");
    $display("[TB] u_prog_ram.mem[0] = 0x%08h", u_prog_ram.mem[0]);
    $display("[TB] u_prog_ram.mem[1] = 0x%08h", u_prog_ram.mem[1]);
    $display("[TB] u_prog_ram.mem[2] = 0x%08h", u_prog_ram.mem[2]);
    $display("[TB] u_prog_ram.mem[3] = 0x%08h", u_prog_ram.mem[3]);
    $display("[TB] u_prog_ram.mem[4] = 0x%08h", u_prog_ram.mem[4]);
    $display("[TB] u_prog_ram.mem[5] = 0x%08h", u_prog_ram.mem[5]);
    $display("[TB] u_prog_ram.mem[6] = 0x%08h", u_prog_ram.mem[6]);
    $display("[TB] u_prog_ram.mem[7] = 0x%08h", u_prog_ram.mem[7]);
    $display("[TB] u_prog_ram.mem[253] = 0x%08h", u_prog_ram.mem[253]);
  end
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
    //instr_addr是取指地址，並非“最后提交执行的指令地址”
    //想知道最后真正触发 halt 的 PC，最好 CPU 内部暴露一个调试信号,在wb階段輸出
    $display("[TB] instr_addr     = 0x%08h", instr_addr);
    $display("[TB] dbg_x3         = 0x%08h", dbg_x3);
    $display("[TB] dbg_x10        = 0x%08h", dbg_x10);
    $display("[TB] dbg_x11        = 0x%08h", dbg_x11);
    $display("[TB] illegal_instr  = %0b",illegal_instr);
    $display("[TB] exception      = %0b", exception);

    if (dbg_x10 == 32'd1 && dbg_x11 == 32'd0 && !seen_illegal) begin
      $display("[TB] RESULT: PASS");
      $display("============================================================");
      $finish;
    end
    else begin
      $display("[TB] RESULT: FAIL");
      $display("[TB] Failure code in x11 = %0d / 0x%08h", dbg_x11, dbg_x11);
      $display("[TB] seen_illegal = %0b", seen_illegal);
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
//WB monitor
always_ff @(posedge clk) begin
  if (rst_n) begin
    $display("[WBPATH] cycle=%0d | ex_wb_valid=%0b ex_wb_rf_wen=%0b ex_wb_rd=%0d ex_wb_sel=%0d ex_wb_alu=0x%08h | wb_valid=%0b wb_pre_wen=%0b wb_pre_rd=%0d wb_sel=%0d wb_alu=0x%08h | wb_wen=%0b wb_rd=%0d wb_wdata=0x%08h",
             cycle_count,
             u_riscv.ex_wb_valid,
             u_riscv.ex_wb_rf_wen,
             u_riscv.ex_wb_rf_waddr,
             u_riscv.ex_wb_sel_out,
             u_riscv.ex_wb_alu_data,
             u_riscv.wb_valid,
             u_riscv.wb_rf_wen_pre,
             u_riscv.wb_rf_waddr_pre,
             u_riscv.wb_sel,
             u_riscv.wb_alu_data,
             u_riscv.wb_rf_wen,
             u_riscv.wb_rf_waddr,
             u_riscv.wb_rf_wdata);
  end
end
//ID/EX monitor
always_ff @(posedge clk) begin
  if (rst_n) begin
    if (u_riscv.id_valid) begin
      $display("[ID] cycle=%0d pc=0x%08h instr=0x%08h rd=%0d rf_we=%0b illegal=%0b ebreak=%0b",
               cycle_count,
               u_riscv.id_pc,
               u_riscv.id_instr,
               u_riscv.id_rd,
               u_riscv.id_rf_we,
               u_riscv.id_illegal_instr,
               u_riscv.id_ebreak);
    end
    if (u_riscv.ex_valid) begin
      $display("[EX] cycle=%0d pc=0x%08h instr=0x%08h rd=%0d rf_we=%0b illegal=%0b ebreak=%0b",
               cycle_count,
               u_riscv.ex_pc,
               u_riscv.ex_instr,
               u_riscv.ex_rd,
               u_riscv.ex_rf_we,
               u_riscv.ex_illegal_instr,
               u_riscv.ex_ebreak);
    end
  end
end

//some check
always @(posedge clk) begin
  #1ps;
  if (rst_n &&  u_riscv.id_valid) begin
    assert ( u_riscv.id_instr[31:0] === u_prog_ram.mem[ u_riscv.id_pc[31:2]])
      else $error("ID PC/INSTR mismatch: pc=%08h instr=%08h expected=%08h",
                   u_riscv.id_pc,
                   u_riscv.id_instr[31:0],
                   u_prog_ram.mem[ u_riscv.id_pc[31:2]]);
  end
end

always_ff @(posedge clk) begin
  if (rst_n && instr_ren) begin
    $display("[IF] cycle=%0d pc=0x%08h instr=0x%08h",
             cycle_count, instr_addr, instr_rdata);
  end
end
endmodule
`default_nettype wire