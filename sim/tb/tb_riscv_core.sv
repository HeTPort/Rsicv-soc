`timescale 1ns / 1ps
module tb_riscv_core;
  localparam AW = 32;
  localparam DW = 32;
  localparam PROG_RAM_DEPTH = 4096;
  logic          clk;
  logic          rst_n;
  // CPU <-> program memory
  logic [AW-1:0] instr_addr;
  logic [DW-1:0] instr_rdata;
  // debug outputs
  logic [DW-1:0] test_case;
  logic [DW-1:0] reg_s10;
  logic [DW-1:0] reg_s11;
  // program memory write port (testbench preload)
  logic          prog_wr_en;
  logic [AW-1:0] prog_wr_addr;
  logic [DW-1:0] prog_wr_data;
  // --------------------------------------------
  // clock
  // --------------------------------------------
  initial clk = 1'b0;
  always #5 clk = ~clk;
  // --------------------------------------------
  // DUT: CPU core
  // --------------------------------------------
  riscv #(
    .AW(32),
    .DW(32),
    .DATA_RAM_DEPTH(4096)
  ) u_riscv (
    .clk       (clk),
    .rst_n     (rst_n),
    .instr_addr(instr_addr),
    .instr_rdata(instr_rdata),
    .test_case (test_case),
    .reg_s10   (reg_s10),
    .reg_s11   (reg_s11)
  );
  // --------------------------------------------
  // Program RAM
  // --------------------------------------------
  prog_ram #(
    .AW   (32),
    .DW   (32),
    .DEPTH(PROG_RAM_DEPTH)
  ) u_prog_ram (
    .clk     (clk),
    .cpu_addr(instr_addr),
    .cpu_rdata(instr_rdata),
    .wr_en   (prog_wr_en),
    .wr_addr (prog_wr_addr),
    .wr_data (prog_wr_data)
  );
  // --------------------------------------------
  // task: preload one word into program RAM
  // --------------------------------------------
  task automatic write_prog_word(input [31:0] addr, input [31:0] data);
    begin
      @(posedge clk);
      prog_wr_en   <= 1'b1;
      prog_wr_addr <= addr;
      prog_wr_data <= data;
      @(posedge clk);
      prog_wr_en   <= 1'b0;
      prog_wr_addr <= '0;
      prog_wr_data <= '0;
    end
  endtask
  // --------------------------------------------
  // preload program
  // --------------------------------------------
  initial begin
    rst_n        = 1'b0;
    prog_wr_en   = 1'b0;
    prog_wr_addr = '0;
    prog_wr_data = '0;
    repeat (5) @(posedge clk);
    // ------------------------------------------------
    // program:
    // 0x0000: addi x1, x0, 5      -> 0x00500093
    // 0x0004: addi x2, x0, 7      -> 0x00700113
    // 0x0008: add  x3, x1, x2     -> 0x002081b3
    // 0x000c: sub  x4, x3, x1     -> 0x40118233
    // 0x0010: addi x5, x0, 16     -> 0x01000293
    // 0x0014: sw   x3, 0(x5)      -> 0x0032a023
    // 0x0018: lw   x6, 0(x5)      -> 0x0002a303
    // 0x001c: sb   x4, 4(x5)      -> 0x00428223
    // 0x0020: lb   x7, 4(x5)      -> 0x00428383
    // 0x0024: lbu  x8, 4(x5)      -> 0x0042c403
    // 0x0028: beq  x6, x3, +8     -> 0x00330463
    // 0x002c: addi x9, x0, 99     -> 0x06300493
    // 0x0030: jal  x0, 0          -> 0x0000006f
    // ------------------------------------------------
    write_prog_word(32'h0000_0000, 32'h0050_0093);
    write_prog_word(32'h0000_0004, 32'h0070_0113);
    write_prog_word(32'h0000_0008, 32'h0020_81b3);
    write_prog_word(32'h0000_000c, 32'h4011_8233);
    write_prog_word(32'h0000_0010, 32'h0100_0293);
    write_prog_word(32'h0000_0014, 32'h0032_a023);
    write_prog_word(32'h0000_0018, 32'h0002_a303);
    write_prog_word(32'h0000_001c, 32'h0042_8223);
    write_prog_word(32'h0000_0020, 32'h0042_8383);
    write_prog_word(32'h0000_0024, 32'h0042_c403);
    write_prog_word(32'h0000_0028, 32'h0033_0463);
    write_prog_word(32'h0000_002c, 32'h0630_0493);
    write_prog_word(32'h0000_0030, 32'h0000_006f);
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    // run enough cycles
    repeat (80) @(posedge clk);
    $display("======================================");
    $display("Simulation finished");
    $display("Inspect waveform for:");
    $display("x1=5, x2=7, x3=12, x4=7, x6=12, x7=7, x8=7");
    $display("x9 should remain 0 if branch works");
    $display("======================================");
    $finish;
  end
endmodule