`timescale 1ns / 1ps
module pc_counter #(
  parameter AW = 32,
  parameter RESET_PC = 32'h0000_0000
)(
  input  logic          clk,
  input  logic          rst_n,
  // stall=1 时，PC 保持不变，不继续取下一条指令
  input  logic          stall,
  // jump_en=1 时，PC 重定向到 jump_addr
  input  logic          jump_en,
  input  logic [AW-1:0] jump_addr,
  output logic [AW-1:0] pc_pointer
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc_pointer <= RESET_PC;
    end
    // jump 优先级高于 stall：
    // 一旦 EX 判断跳转成立，PC 必须立刻重定向
    else if (jump_en) begin
      pc_pointer <= jump_addr;
    end
    // stall 时保持当前 PC，不取新指令
    else if (stall) begin
      pc_pointer <= pc_pointer;
    end
    // 正常顺序执行
    else begin
      pc_pointer <= pc_pointer + AW'(32'd4);
    end
  end
endmodule