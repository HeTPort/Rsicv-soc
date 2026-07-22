`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: tb_riscv
// Description:
//   Simple top-level testbench for the reconstructed RV32IM CPU.
// ============================================================
module tb_riscv_core #(
  parameter string PROGRAM_FILE = "../testdata/prog.hex",
  parameter string DATA_FILE = "",
  parameter bit TRACE_ENABLE = 1'b0,
  parameter bit DUMP_WAVES = 1'b0,
  parameter int TIMEOUT_CYCLES = 20000,
  parameter logic [31:0] TOHOST_ADDR = 32'h0000_1000
);
  localparam int AW = 32;
  localparam int DW = 32;
  localparam int PROG_RAM_DEPTH = 4096;
  localparam int DATA_RAM_DEPTH = 4096;
  localparam int CLK_PERIOD_NS = 10;

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
  commit_pkt_t commit;

  // ------------------------------------------------------------
  // DUT
  // ------------------------------------------------------------
  riscv #(
    .AW(AW),
    .DW(DW),
    .DATA_RAM_DEPTH(DATA_RAM_DEPTH),
    .INIT_DATA_FILE(DATA_FILE)
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
    .exception_o     (exception),
    .commit_o        (commit)
  );

  // ------------------------------------------------------------
  // Program RAM
  // ------------------------------------------------------------
  prog_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(PROG_RAM_DEPTH),
    .FILE(PROGRAM_FILE),
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
    if (DUMP_WAVES) begin
      $dumpfile("tb_riscv.vcd");
      $dumpvars(0, tb_riscv_core);
    end
  end

  // ------------------------------------------------------------
  // Timeout watchdog
  // ------------------------------------------------------------
  integer cycle_count;
  logic [63:0] expected_commit_order;
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

  // ------------------------------------------------------------
  // Architectural commit interface checks
  // ------------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      expected_commit_order <= '0;
    end else if (commit.valid) begin
      assert (commit.order == expected_commit_order)
        else $fatal(1, "Commit order mismatch: got=%0d expected=%0d",
                    commit.order, expected_commit_order);
      assert (commit.pc[1:0] == 2'b00)
        else $fatal(1, "Committed PC is misaligned: pc=0x%08h", commit.pc);
      assert (!commit.rd_we || (commit.rd_addr != 5'd0))
        else $fatal(1, "Commit interface attempted to write x0");
      assert (!commit.trap || !commit.rd_we)
        else $fatal(1, "Trapping instruction reported a register write");
      assert (!commit.mem_we || (commit.mem_wmask != '0))
        else $fatal(1, "Committed store has an empty write mask");
      assert (!commit.mem_valid || commit.mem_we || (commit.mem_rmask != '0))
        else $fatal(1, "Committed load has an empty read mask");
      assert (!(commit.mem_rmask != '0 && commit.mem_wmask != '0))
        else $fatal(1, "Commit record reports a simultaneous load and store");

      expected_commit_order <= expected_commit_order + 64'd1;

      if (TRACE_ENABLE) begin
        $display("[COMMIT] order=%0d pc=0x%08h instr=0x%08h rd_we=%0b rd=%0d data=0x%08h mem=%0b/%0b addr=0x%08h trap=%0b cause=0x%08h",
                 commit.order, commit.pc, commit.instr,
                 commit.rd_we, commit.rd_addr, commit.rd_data,
                 commit.mem_valid, commit.mem_we, commit.mem_addr,
                 commit.trap, commit.trap_cause);
      end
    end
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
  // Memory-mapped tohost exit monitor (standard RISC-V test convention)
  // ------------------------------------------------------------
  logic [DW-1:0] tohost_val;
  logic          tohost_seen;



  always_ff @(posedge clk) begin
    if (!rst_n) begin
      tohost_val <= '0;
      tohost_seen <= 1'b0;
    end else begin
      if (commit.valid && commit.mem_valid && commit.mem_we &&
          (commit.mem_addr == TOHOST_ADDR)) begin
        tohost_val  <= commit.mem_wdata;
        tohost_seen <= 1'b1;
      end
    end
  end

  // ------------------------------------------------------------
  // Finish on tohost write
  // ------------------------------------------------------------
  initial begin
    wait (rst_n == 1'b1);
    wait (tohost_seen == 1'b1);
    repeat (2) @(posedge clk);
    $display("============================================================");
    $display("[TB] tohost write detected");
    $display("[TB] cycle          = %0d", cycle_count);
    $display("[TB] instr_addr     = 0x%08h", instr_addr);
    $display("[TB] dbg_x3         = 0x%08h", dbg_x3);
    $display("[TB] dbg_x10        = 0x%08h", dbg_x10);
    $display("[TB] dbg_x11        = 0x%08h", dbg_x11);
    $display("[TB] illegal_instr  = %0b", illegal_instr);
    $display("[TB] exception      = %0b", exception);
    $display("[TB] tohost         = 0x%08h", tohost_val);

    if (tohost_val == 32'd1) begin
      $display("[TB] RESULT: PASS");
      $display("============================================================");
      $finish;
    end
    else begin
      $display("[TB] RESULT: FAIL");
      $display("[TB] Failure code in tohost = %0d / 0x%08h", tohost_val, tohost_val);
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
    if (rst_n && TRACE_ENABLE) begin
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
    if (rst_n && TRACE_ENABLE) begin
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
    if (rst_n && instr_ren && TRACE_ENABLE) begin
      $display("[IF] cycle=%0d pc=0x%08h instr=0x%08h",
               cycle_count, instr_addr, instr_rdata);
    end
  end

  // ------------------------------------------------------------
  // >>> 新增：Core Ctrl Monitor (用于观测抽离出的控制信号) <<<
  // ------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (rst_n) begin
      // 只有当控制信号有效（非全0）时才打印，避免刷屏
      if (TRACE_ENABLE && (u_riscv.u_core_ctrl.pc_stall || u_riscv.u_core_ctrl.ifid_flush ||
          u_riscv.u_core_ctrl.idex_flush || u_riscv.u_core_ctrl.pipe_kill)) begin
        $display("[CTRL ] cycle=%0d | stall: pc=%0b ifid=%0b idex=%0b | flush: ifid=%0b idex=%0b | kill=%0b",
                 cycle_count,
                 u_riscv.u_core_ctrl.pc_stall,
                 u_riscv.u_core_ctrl.ifid_stall,
                 u_riscv.u_core_ctrl.idex_stall,
                 u_riscv.u_core_ctrl.ifid_flush,
                 u_riscv.u_core_ctrl.idex_flush,
                 u_riscv.u_core_ctrl.pipe_kill);
      end
    end
  end

endmodule
`default_nettype wire
