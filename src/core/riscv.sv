`timescale 1ns / 1ps
`include "define.sv"
module riscv #(
  parameter AW = 32,
  parameter DW = 32,
  parameter DATA_RAM_DEPTH = 4096
)(
  input  logic          clk,
  input  logic          rst_n,
  output logic [AW-1:0] instr_addr,
  input  logic [DW-1:0] instr_rdata,
  output logic [DW-1:0] test_case,
  output logic [DW-1:0] reg_s10,
  output logic [DW-1:0] reg_s11
);
  // =========================================================
  // EX stage redirect / writeback / memory
  // =========================================================
  logic                 jump_en;
  logic [AW-1:0]        jump_addr;
  // 这个信号现在真正作为“flush 请求”使用
  logic                 jump_hold;
  logic                 wr_reg_en;
  logic [4:0]           wr_reg_addr;
  logic [DW-1:0]        wr_reg_data;
  logic                 mem_wr_en;
  logic [DW/8-1:0]      mem_wr_strb;
  logic [AW-1:0]        mem_addr;
  logic [DW-1:0]        mem_wdata;
  logic [DW-1:0]        mem_rdata;
  // =========================================================
  // IF stage
  // =========================================================
  logic [AW-1:0]        pc_pointer;
  logic [DW-1:0]        instruction;
  // pipeline control
  logic                 pc_stall;
  logic                 ifid_stall;
  logic                 ifid_flush;
  logic                 idex_stall;
  logic                 idex_flush;
  // =========================================================
  // IF/ID
  // =========================================================
  logic [AW-1:0]        instr_addr_reg;
  logic [DW-1:0]        instr_reg;
  // =========================================================
  // ID stage
  // =========================================================
  logic [4:0]           rd_rs1_addr;
  logic [4:0]           rd_rs2_addr;
  logic [DW-1:0]        rd_rs1_data;
  logic [DW-1:0]        rd_rs2_data;
  logic [DW-1:0]        decode_op1;
  logic [DW-1:0]        decode_op2;
  logic [DW-1:0]        decode_store_data;
  // =========================================================
  // ID/EX
  // =========================================================
  logic [AW-1:0]        execute_instr_addr;
  logic [DW-1:0]        execute_instr;
  logic [DW-1:0]        execute_op1;
  logic [DW-1:0]        execute_op2;
  logic [DW-1:0]        execute_store_data;
  // =========================================================
  // Minimal hazard detection
  // =========================================================
  logic [6:0]           id_opcode;
  logic                 id_use_rs1;
  logic                 id_use_rs2;
  logic                 hazard_stall;
  assign id_opcode = instr_reg[6:0];
  // ---------------------------------------------------------
  // 判断 ID 级当前指令是否真正使用 rs1 / rs2
  // 这样做比“无脑比较 rs1/rs2”更稳，能减少误判
  // ---------------------------------------------------------
  always_comb begin
    id_use_rs1 = 1'b0;
    id_use_rs2 = 1'b0;
    unique case (id_opcode)
      `INST_TYPE_I: begin
        id_use_rs1 = 1'b1;
        id_use_rs2 = 1'b0;
      end
      `INST_TYPE_R_M: begin
        id_use_rs1 = 1'b1;
        id_use_rs2 = 1'b1;
      end
      `INST_TYPE_L: begin
        id_use_rs1 = 1'b1;
        id_use_rs2 = 1'b0;
      end
      `INST_TYPE_S: begin
        id_use_rs1 = 1'b1;
        id_use_rs2 = 1'b1;
      end
      `INST_TYPE_B: begin
        id_use_rs1 = 1'b1;
        id_use_rs2 = 1'b1;
      end
      `INST_TYPE_JALR: begin
        id_use_rs1 = 1'b1;
        id_use_rs2 = 1'b0;
      end
      // JAL / LUI / AUIPC 不读 rs1/rs2
      `INST_TYPE_JAL,
      `INST_LUI,
      `INST_AUIPC: begin
        id_use_rs1 = 1'b0;
        id_use_rs2 = 1'b0;
      end
      default: begin
        id_use_rs1 = 1'b0;
        id_use_rs2 = 1'b0;
      end
    endcase
  end
  // ---------------------------------------------------------
  // 最小 hazard 检测：
  // 如果 ID 级当前指令要读的寄存器，与 EX 级当前将要写回的寄存器相同，
  // 那么停住前两级，并向 EX 插入一个 bubble。
  //
  // 说明：
  // 1) wr_reg_en / wr_reg_addr 来自 execute 当前组合输出
  // 2) 这是最简策略，先追求正确，不追求性能
  // ---------------------------------------------------------
  assign hazard_stall =
      wr_reg_en &&
      (wr_reg_addr != 5'd0) &&
      (
        (id_use_rs1 && (rd_rs1_addr == wr_reg_addr)) ||
        (id_use_rs2 && (rd_rs2_addr == wr_reg_addr))
      );
  // ---------------------------------------------------------
  // pipeline control policy
  //
  // jump_hold:
  //   表示 EX 判定需要冲刷前面流水（branch taken / jal / jalr）
  //
  // hazard_stall:
  //   表示 ID 读到了 EX 正在生产的目的寄存器，需插泡等待
  // ---------------------------------------------------------
  assign pc_stall   = hazard_stall;
  assign ifid_stall = hazard_stall;
  assign ifid_flush = jump_hold;
  // hazard 时向 EX 插 bubble；jump 时也需要 flush 掉错误路径
  assign idex_stall = 1'b0;
  assign idex_flush = jump_hold | hazard_stall;
  // =========================================================
  // IF
  // =========================================================
  assign instr_addr  = pc_pointer;
  assign instruction = instr_rdata;
  pc_counter #(
    .AW(AW),
    .RESET_PC(32'h0000_0000)
  ) u_pc_counter (
    .clk       (clk),
    .rst_n     (rst_n),
    .stall     (pc_stall),
    .jump_en   (jump_en),
    .jump_addr (jump_addr),
    .pc_pointer(pc_pointer)
  );
  // =========================================================
  // IF/ID
  // =========================================================
  if2id #(
    .AW(AW),
    .DW(DW)
  ) u_if2id (
    .clk          (clk),
    .rst_n        (rst_n),
    .flush        (ifid_flush),
    .stall        (ifid_stall),
    .instr_addr_in(pc_pointer),
    .instr_in     (instruction),
    .instr_addr_out(instr_addr_reg),
    .instr_out    (instr_reg)
  );
  // =========================================================
  // ID
  // =========================================================
  decode #(
    .AW(AW),
    .DW(DW)
  ) u_decode (
    .instr_addr_in  (instr_addr_reg),
    .instr_in       (instr_reg),
    .rd_rs1_addr    (rd_rs1_addr),
    .rd_rs2_addr    (rd_rs2_addr),
    .rd_rs1_data    (rd_rs1_data),
    .rd_rs2_data    (rd_rs2_data),
    .op1_out        (decode_op1),
    .op2_out        (decode_op2),
    .store_data_out (decode_store_data)
  );
  register #(
    .DW(DW)
  ) u_register (
    .clk        (clk),
    .rst_n      (rst_n),
    .rd_rs1_addr(rd_rs1_addr),
    .rd_rs2_addr(rd_rs2_addr),
    .rd_rs1_data(rd_rs1_data),
    .rd_rs2_data(rd_rs2_data),
    .wr_reg_en  (wr_reg_en),
    .wr_reg_addr(wr_reg_addr),
    .wr_reg_data(wr_reg_data)
  );
  // =========================================================
  // ID/EX
  // =========================================================
  id2ex #(
    .AW(AW),
    .DW(DW)
  ) u_id2ex (
    .clk           (clk),
    .rst_n         (rst_n),
    .flush         (idex_flush),
    .stall         (idex_stall),
    .instr_addr_in (instr_addr_reg),
    .instr_in      (instr_reg),
    .op1_in        (decode_op1),
    .op2_in        (decode_op2),
    .store_data_in (decode_store_data),
    .instr_addr_out(execute_instr_addr),
    .instr_out     (execute_instr),
    .op1_out       (execute_op1),
    .op2_out       (execute_op2),
    .store_data_out(execute_store_data)
  );
  // =========================================================
  // EX (contains EX + MEM + WB in current minimal core)
  // =========================================================
  execute #(
    .AW(AW),
    .DW(DW)
  ) u_execute (
    .instr_addr (execute_instr_addr),
    .instr      (execute_instr),
    .op1        (execute_op1),
    .op2        (execute_op2),
    .store_data (execute_store_data),
    .wr_reg_en  (wr_reg_en),
    .wr_reg_addr(wr_reg_addr),
    .wr_reg_data(wr_reg_data),
    .jump_en    (jump_en),
    .jump_addr  (jump_addr),
    .jump_hold  (jump_hold),
    .mem_wr_en  (mem_wr_en),
    .mem_wr_strb(mem_wr_strb),
    .mem_addr   (mem_addr),
    .mem_wdata  (mem_wdata),
    .mem_rdata  (mem_rdata)
  );
  // =========================================================
  // data memory
  // =========================================================
  data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DATA_RAM_DEPTH)
  ) u_data_ram (
    .clk    (clk),
    .rst_n  (rst_n),
    .wr_en  (mem_wr_en),
    .wr_strb(mem_wr_strb),
    .addr   (mem_addr),
    .wr_data(mem_wdata),
    .rd_data(mem_rdata)
  );
  // =========================================================
  // debug output
  // 暂时先接一些常用寄存器，便于 testbench 检查
  // 你后面也可以直接在 tb 中层次引用 u_register.regs[x]
  // =========================================================
  assign test_case = u_register.regs[3];   // x3
  assign reg_s10   = u_register.regs[10];  // x10 (a0)
  assign reg_s11   = u_register.regs[11];  // x11 (a1)
endmodule