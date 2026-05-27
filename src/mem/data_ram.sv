`timescale 1ns / 1ps
`default_nettype none
module data_ram #(
  parameter int AW    = 32,
  parameter int DW    = 32,
  parameter int DEPTH = 4096
)(
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            ren_i,
  input  logic            wen_i,
  input  logic [DW/8-1:0] wstrb_i,
  input  logic [AW-1:0]   addr_i,
  input  logic [DW-1:0]   wdata_i,
  output logic [DW-1:0]   rdata_o
);
  localparam int BYTE_NUM = DW / 8;
  localparam int ADDR_LSB = $clog2(BYTE_NUM);
  localparam int ADDR_W   = $clog2(DEPTH);
  logic [DW-1:0] mem [0:DEPTH-1];
  logic [ADDR_W-1:0] word_addr;
  integer i;
  assign word_addr = addr_i[ADDR_LSB +: ADDR_W];
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o <= '0;
      // 注意：
      // FPGA BRAM 一般不建议 reset 整个 RAM。
      // 初期验证可以保留，后续上板时建议删除 RAM 清零逻辑，
      // 改用 initial/$readmemh 或外部 loader 初始化。
      for (i = 0; i < DEPTH; i = i + 1)
        mem[i] <= '0;
    end
    else begin
      if (wen_i) begin
        for (i = 0; i < BYTE_NUM; i = i + 1) begin
          if (wstrb_i[i])
            mem[word_addr][8*i +: 8] <= wdata_i[8*i +: 8];
        end
      end
      if (ren_i) begin
        rdata_o <= mem[word_addr];
      end
    end
  end
endmodule
`default_nettype wire