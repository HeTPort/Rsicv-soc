`timescale 1ns / 1ps
`default_nettype none
module regfile #(
  parameter int DW = 32
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic [4:0]    rs1_raddr_i,
  output logic [DW-1:0] rs1_rdata_o,
  input  logic [4:0]    rs2_raddr_i,
  output logic [DW-1:0] rs2_rdata_o,
  input  logic          rd_wen_i,
  input  logic [4:0]    rd_waddr_i,
  input  logic [DW-1:0] rd_wdata_i,
  output logic [DW-1:0] dbg_x3_o,
  output logic [DW-1:0] dbg_x10_o,
  output logic [DW-1:0] dbg_x11_o
);
  logic [DW-1:0] regs [0:31];
  integer i;
  always_comb begin
    if (!rst_ni)
      rs1_rdata_o = '0;
    else if (rs1_raddr_i == 5'd0)
      rs1_rdata_o = '0;
    else if (rd_wen_i && rd_waddr_i != 5'd0 && rs1_raddr_i == rd_waddr_i)
      rs1_rdata_o = rd_wdata_i;
    else
      rs1_rdata_o = regs[rs1_raddr_i];
  end
  always_comb begin
    if (!rst_ni)
      rs2_rdata_o = '0;
    else if (rs2_raddr_i == 5'd0)
      rs2_rdata_o = '0;
    else if (rd_wen_i && rd_waddr_i != 5'd0 && rs2_raddr_i == rd_waddr_i)
      rs2_rdata_o = rd_wdata_i;
    else
      rs2_rdata_o = regs[rs2_raddr_i];
  end
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      for (i = 0; i < 32; i = i + 1)
        regs[i] <= '0;
    end
    else if (rd_wen_i && rd_waddr_i != 5'd0) begin
      regs[rd_waddr_i] <= rd_wdata_i;
    end
  end
  assign dbg_x3_o  = regs[3];
  assign dbg_x10_o = regs[10];
  assign dbg_x11_o = regs[11];
endmodule
`default_nettype wire