`timescale 1ns / 1ps
`default_nettype none
module prog_ram #(
  parameter int AW    = 32,
  parameter int DW    = 32,
  parameter int DEPTH = 4096,
  parameter     FILE  = "prog.dat"
)(
  input  logic          clk_i,
  input  logic          ren_i,
  input  logic [AW-1:0] instr_addr_i,
  output logic [DW-1:0] instr_data_o,
  input  logic          wen_i,
  input  logic [AW-1:0] waddr_i,
  input  logic [DW-1:0] wdata_i
);
  localparam int BYTE_NUM = DW / 8;
  localparam int ADDR_LSB = $clog2(BYTE_NUM);
  localparam int ADDR_W   = $clog2(DEPTH);
  logic [DW-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] fetch_word_addr;
  logic [ADDR_W-1:0] write_word_addr;
  assign fetch_word_addr = instr_addr_i[ADDR_LSB +: ADDR_W];
  assign write_word_addr = waddr_i[ADDR_LSB +: ADDR_W];
  initial begin
    $readmemh(FILE, mem);
  end
  always_ff @(posedge clk_i) begin
    if (wen_i) begin
      mem[write_word_addr] <= wdata_i;
    end
    if (ren_i) begin
      if (wen_i && write_word_addr == fetch_word_addr)
        instr_data_o <= wdata_i;
      else
        instr_data_o <= mem[fetch_word_addr];
    end
  end
endmodule
`default_nettype wire