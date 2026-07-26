`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: ex2wb
// Description:
//   Pipeline register between EX and WB stages.
//
// Responsibilities:
//   - Register writeback control and data.
//   - Register load extension control.
//   - Register exception/halt related flags.
//   - Support pipeline stall (backpressure).
//
// Note:
//   - No flush_i here! Branch/Jump instructions themselves must 
//     flow to WB to complete their writeback (e.g. PC+4).
// ============================================================
module ex2wb (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        stall_i,  // 新增：支持流水线暂停
  
  // 结构体输入：替代原本的散线
  input  ex_wb_pkt_t  pkt2wb_i,
  
  // 结构体输出
  output ex_wb_pkt_t  pkt2wb_o
);

  ex_wb_pkt_t pkt2wb_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      // One assignment keeps every packet field, including future additions,
      // in a known safe bubble state after reset.
      pkt2wb_q <= EX_WB_PKT_BUBBLE;
    end
    // 新增 stall 逻辑：只有在不停顿时才更新寄存器
    else if (!stall_i) begin
      if (pkt2wb_i.valid)
        pkt2wb_q <= pkt2wb_i;
      else
        pkt2wb_q <= EX_WB_PKT_BUBBLE;
    end
    // 如果 stall_i 为高，pkt2wb_q 自动保持原值，无需写 else 分支
  end

  assign pkt2wb_o = pkt2wb_q;

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni && !pkt2wb_q.valid) begin
      assert (pkt2wb_q === EX_WB_PKT_BUBBLE)
        else $error("EX/WB invalid packet is not the canonical bubble");
    end
  end
`endif

endmodule
`default_nettype wire
