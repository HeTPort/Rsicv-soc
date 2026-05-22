`timescale 1ns / 1ps
module data_ram #(
  parameter AW    = 32,
  parameter DW    = 32,
  parameter DEPTH = 4096
)(
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  wr_en,
  input  logic [DW/8-1:0]       wr_strb,
  input  logic [AW-1:0]         addr,
  input  logic [DW-1:0]         wr_data,
  output logic [DW-1:0]         rd_data
);
  localparam BYTE_NUM = DW / 8;
  localparam ADDR_LSB = $clog2(BYTE_NUM);
  logic [DW-1:0] mem [0:DEPTH-1];
  logic [AW-ADDR_LSB-1:0] word_addr;
  integer i;
  assign word_addr = addr[AW-1:ADDR_LSB];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < DEPTH; i = i + 1)
        mem[i] <= '0;
    end
    else if (wr_en) begin
      for (i = 0; i < BYTE_NUM; i = i + 1) begin
        if (wr_strb[i]) begin
          mem[word_addr][8*i +: 8] <= wr_data[8*i +: 8];
        end
      end
    end
  end
  always_comb begin
    rd_data = mem[word_addr];
  end
endmodule