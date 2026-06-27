`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: tb_riscv
// Description:
//   Simple top-level testbench for the reconstructed RV32IM CPU.
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
  //logic  seen_illegal;

  // ------------------------------------------------------------
  // Sticky illegal instruction monitor
  // ------------------------------------------------------------
  //always_ff @(posedge clk or negedge rst_n) begin
  //  if (!rst_n) begin
  //    seen_illegal <= 1'b0;
  //  end else if (illegal_instr) begin
  //    seen_illegal <= 1'b1;
  //  end
  //end

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
    $display("[TB] instr_addr     = 0x%08h", instr_addr);
    $display("[TB] dbg_x3         = 0x%08h", dbg_x3);
    $display("[TB] dbg_x10        = 0x%08h", dbg_x10);
    $display("[TB] dbg_x11        = 0x%08h", dbg_x11);
    $display("[TB] illegal_instr  = %0b",illegal_instr);
    $display("[TB] exception      = %0b", exception);

    if (dbg_x10 == 32'd1 && dbg_x11 == 32'd0 && !illegal_instr) begin
      $display("[TB] RESULT: PASS");
      $display("============================================================");
      $finish;
    end
    else begin
      $display("[TB] RESULT: FAIL");
      $display("[TB] Failure code in x11 = %0d / 0x%08h", dbg_x11, dbg_x11);
      $display("[TB] seen_illegal = %0b", illegal_instr);
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

  // ------------------------------------------------------------
  // WB Monitor (Updated for struct hierarchy)
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n) begin
      $display("[WBPATH] cycle=%0d | ex2wb_in: valid=%0b we=%0b rd=%0d sel=%0d alu=0x%08h | ex2wb_out: valid=%0b we=%0b rd=%0d sel=%0d alu=0x%08h | final_wb: wen=%0b rd=%0d wdata=0x%08h",
               cycle_count,
               u_riscv.ex2wb_pkt_in.valid,
               u_riscv.ex2wb_pkt_in.rf.we,
               u_riscv.ex2wb_pkt_in.rf.addr,
               u_riscv.ex2wb_pkt_in.wb_sel,
               u_riscv.ex2wb_pkt_in.alu_data,
               u_riscv.ex2wb_pkt_out.valid,
               u_riscv.ex2wb_pkt_out.rf.we,
               u_riscv.ex2wb_pkt_out.rf.addr,
               u_riscv.ex2wb_pkt_out.wb_sel,
               u_riscv.ex2wb_pkt_out.alu_data,
               u_riscv.wb_rf_wen,
               u_riscv.wb_rf_waddr,
               u_riscv.wb_rf_wdata);
    end
  end

  // ------------------------------------------------------------
  // ID/EX Monitor (Updated for struct hierarchy)
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // 监控 ID 级输出 (即 id2ex 寄存器的输入)
      if (u_riscv.id2ex_pkt.valid) begin
        $display("[ID] cycle=%0d pc=0x%08h instr=0x%08h rd=%0d rf_we=%0b illegal=%0b ebreak=%0b",
                 cycle_count,
                 u_riscv.id2ex_pkt.pc,
                 u_riscv.id2ex_pkt.instr,
                 u_riscv.id2ex_pkt.rf.addr,
                 u_riscv.id2ex_pkt.rf.we,
                 u_riscv.id2ex_pkt.exc.illegal_instr,
                 u_riscv.id2ex_pkt.exc.ebreak);
      end
      // 监控 EX 级输入 (即 id2ex 寄存器的输出)
      if (u_riscv.id2ex_pkt_out.valid) begin
        $display("[EX] cycle=%0d pc=0x%08h instr=0x%08h rd=%0d rf_we=%0b illegal=%0b ebreak=%0b",
                 cycle_count,
                 u_riscv.id2ex_pkt_out.pc,
                 u_riscv.id2ex_pkt_out.instr,
                 u_riscv.id2ex_pkt_out.rf.addr,
                 u_riscv.id2ex_pkt_out.rf.we,
                 u_riscv.id2ex_pkt_out.exc.illegal_instr,
                 u_riscv.id2ex_pkt_out.exc.ebreak);
      end
    end
  end

  // ------------------------------------------------------------
  // Some check (Updated for struct hierarchy)
  // ------------------------------------------------------------
  always @(posedge clk) begin
    #1ps;
    if (rst_n && u_riscv.if2id_pkt_out.valid) begin
      assert (u_riscv.if2id_pkt_out.instr[31:0] === u_prog_ram.mem[u_riscv.if2id_pkt_out.pc[31:2]])
        else $error("ID PC/INSTR mismatch: pc=%08h instr=%08h expected=%08h",
                     u_riscv.if2id_pkt_out.pc,
                     u_riscv.if2id_pkt_out.instr[31:0],
                     u_prog_ram.mem[u_riscv.if2id_pkt_out.pc[31:2]]);
    end
  end

  // ------------------------------------------------------------
  // IF Monitor
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n && instr_ren) begin
      $display("[IF] cycle=%0d pc=0x%08h instr=0x%08h",
               cycle_count, instr_addr, instr_rdata);
    end
  end

endmodule
`default_nettype wire