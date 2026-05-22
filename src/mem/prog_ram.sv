`timescale 1ns / 1ps
module prog_ram #(
  parameter AW    = 32,
  parameter DW    = 32,
  parameter DEPTH = 4096
)(
  input  logic              clk,
  // CPU fetch port
  input  logic [AW-1:0]     cpu_addr,
  output logic [DW-1:0]     cpu_rdata,
  // write port
  input  logic              wr_en,
  input  logic [AW-1:0]     wr_addr,
  input  logic [DW-1:0]     wr_data
);
  logic [DW-1:0] mem [0:DEPTH-1];
  logic [AW-1:2] cpu_word_addr;
  logic [AW-1:2] wr_word_addr;
  assign cpu_word_addr = cpu_addr[AW-1:2];
  assign wr_word_addr  = wr_addr[AW-1:2];
  always_ff @(posedge clk) begin
    if (wr_en)
      mem[wr_word_addr] <= wr_data;
  end
  always_comb begin
    cpu_rdata = mem[cpu_word_addr];
  end
endmodule