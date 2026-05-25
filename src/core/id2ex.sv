`timescale 1ns / 1ps
`include "define.sv"
module id2ex #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic          clk,
  input  logic          rst_n,
  // flush=1 时，向 EX 注入 NOP
  // 用于：
  // 1) branch/jump 冲刷
  // 2）hazard 时插入 bubble
  input  logic          flush,
  // stall=1 时，保持 ID/EX 不变
  // 当前最小方案里暂时不一定用到，但先留好接口
  input  logic          stall,
  input  logic [AW-1:0] instr_addr_in,
  input  logic [DW-1:0] instr_in,
  input  logic [DW-1:0] op1_in,
  input  logic [DW-1:0] op2_in,
  input  logic [DW-1:0] store_data_in,
  output logic [AW-1:0] instr_addr_out,
  output logic [DW-1:0] instr_out,
  output logic [DW-1:0] op1_out,
  output logic [DW-1:0] op2_out,
  output logic [DW-1:0] store_data_out
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
      op1_out        <= '0;
      op2_out        <= '0;
      store_data_out <= '0;
    end
    // flush 时向 EX 注入 bubble
    else if (flush) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
      op1_out        <= '0;
      op2_out        <= '0;
      store_data_out <= '0;
    end
    // stall 时保持当前内容
    else if (stall) begin
      instr_addr_out <= instr_addr_out;
      instr_out      <= instr_out;
      op1_out        <= op1_out;
      op2_out        <= op2_out;
      store_data_out <= store_data_out;
    end
    // 正常推进
    else begin
      instr_addr_out <= instr_addr_in;
      instr_out      <= instr_in;
      op1_out        <= op1_in;
      op2_out        <= op2_in;
      store_data_out <= store_data_in;
    end
  end
endmodule