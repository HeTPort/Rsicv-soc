`timescale 1ns / 1ps
module prog_ram #(
  parameter AW    = 32,
  parameter DW    = 32,
  parameter DEPTH = 4096,
  parameter FILE  = "prog.dat"
)(
  input  logic              clk,
  // CPU fetch port
  input  logic [AW-1:0]     instr_addr,
  output logic [DW-1:0]     instr_data,
  // write port
  input  logic              wr_en,
  input  logic [AW-1:0]     wr_addr,
  input  logic [DW-1:0]     wr_data
);
  localparam ADDR_W = $clog2(DEPTH);
  logic [DW-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] fetch_word_addr;
  logic [ADDR_W-1:0] wr_word_addr;
  assign fetch_word_addr = cpu_addr[ADDR_W+1:2];
  assign wr_word_addr  = wr_addr[ADDR_W+1:2];
  // 初始化
  initial begin
    $readmemh(FILE, mem);
  end
  // 同步读写
  always_ff @(posedge clk) begin
    // 同址读写行为：写优先，读出写入后的新值
    if (wr_en && (wr_word_addr < DEPTH))
      mem[wr_word_addr] <= wr_data;
    if (fetch_word_addr < DEPTH) begin
      if (wr_en && (wr_word_addr == fetch_word_addr) && (wr_word_addr < DEPTH))
        instr_data <= wr_data;
      else
        instr_data <= mem[fetch_word_addr];
    end
    else begin
      instr_data <= '0;
    end
  end
endmodule