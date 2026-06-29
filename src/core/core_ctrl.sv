`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module core_ctrl(
    input logic         clk_i,
    input logic         rst_ni,
    
    //----------------------
    // 1. 状态观测
    //----------------------
    input  logic        id_valid,
    input  logic [4:0]  id_rs1_addr,
    input  logic [4:0]  id_rs2_addr,
    input  logic        id_use_rs1,
    input  logic        id_use_rs2,

    input  logic        ex_valid,
    input  logic [4:0]  ex_rd_addr,
    input  logic        ex_rf_we,
    input  logic        ex_mem_req,    // 保留接口，但当前不参与 hazard_stall 判断
    input  logic        ex_mem_we,

    input  logic        wb_valid,
    input  logic [4:0]  wb_rd_addr,
    input  logic        wb_rf_we,

    input  logic        ex_redirect_en,
    input  logic        ex_flush_req,  // 必须保留，严格遵循原逻辑
    input  logic        wb_trap_event,

    //----------------------
    // 2. 控制输出
    //----------------------
    output logic        pc_stall,
    output logic        ifid_stall,
    output logic        idex_stall,
    output logic        exwb_stall,

    output logic        ifid_flush,
    output logic        idex_flush,
    output logic        pipe_kill,
    output logic        halt_o
);

  // ============================================================
  // Trap 状态机
  // ============================================================
  logic halt_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)           halt_q <= 1'b0;
    else if (wb_trap_event) halt_q <= 1'b1;
  end

  assign halt_o     = halt_q;
  assign pipe_kill = wb_trap_event | halt_q;

  // ============================================================
  // 冒险检测 (严格还原原始逻辑：对所有写寄存器指令的RAW都停顿)
  // ============================================================
  logic hazard_stall;
  assign hazard_stall = 
      id_valid && ex_valid && ex_rf_we && (ex_rd_addr != 5'd0) &&
      ((id_use_rs1 && id_rs1_addr == ex_rd_addr) ||
       (id_use_rs2 && id_rs2_addr == ex_rd_addr));

  logic ex_stall;
  assign ex_stall = 1'b0; 

  // ============================================================
  // 跳转冲刷状态机 (严格还原原始逻辑)
  // ============================================================
  logic fetch_kill_q;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) fetch_kill_q <= 1'b0;
    else         fetch_kill_q <= ex_flush_req;
  end

  // ============================================================
  // 生成流水线控制信号 (严格还原原始逻辑)
  // ============================================================
  assign pc_stall   = hazard_stall | ex_stall | pipe_kill;
  assign ifid_stall = hazard_stall | ex_stall;
  assign idex_stall = ex_stall;
  assign exwb_stall = 1'b0; 

  // 严格还原：idex_flush 依赖 ex_flush_req 而不是 ex_redirect_en
  assign ifid_flush = ex_flush_req | fetch_kill_q | pipe_kill;
  assign idex_flush = ex_flush_req | hazard_stall | pipe_kill;

endmodule
`default_nettype wire