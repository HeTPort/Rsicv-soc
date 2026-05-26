`timescale 1ns / 1ps
`include "define.sv"
module if2id #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic          clk,
  input  logic          rst_n,
  // flush=1 时，向 IF/ID 注入 NOP，用于 branch/jump 冲刷
  input  logic          flush,
  // stall=1 时，保持 IF/ID 当前内容不变，用于数据相关暂停
  input  logic          stall,
  input  logic [AW-1:0] instr_addr_in,
  input  logic [DW-1:0] instr_in,
  output logic [AW-1:0] instr_addr_out,
  output logic [DW-1:0] instr_out
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
    end
    // flush 优先级高于 stall：
    // 跳转后错误路径指令必须被杀掉，不能继续保留
    else if (flush) begin
      instr_addr_out <= '0;
      instr_out      <= `INST_NOP;
    end
    // stall 时保持原值，不推进流水,取消stall有效的自赋值，因为寄存器在没有新赋值时，天然会保持原值，这正是寄存器的正常行为，不是锁存器，锁存器一般出现在组合逻辑中
    else if (!stall) begin
      instr_addr_out <= instr_addr_in;
      instr_out      <= instr_in;
    end
  end
endmodule