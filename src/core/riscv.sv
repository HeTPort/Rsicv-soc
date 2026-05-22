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
  logic                 jump_en;
  logic [AW-1:0]        jump_addr;
  logic                 jump_hold;
  logic [AW-1:0]        pc_pointer;
  logic [DW-1:0]        instruction;
  logic [AW-1:0]        instr_addr_reg;
  logic [DW-1:0]        instr_reg;
  logic [4:0]           rd_rs1_addr;
  logic [4:0]           rd_rs2_addr;
  logic [DW-1:0]        rd_rs1_data;
  logic [DW-1:0]        rd_rs2_data;
  logic [DW-1:0]        decode_op1;
  logic [DW-1:0]        decode_op2;
  logic [DW-1:0]        decode_store_data;
  logic [AW-1:0]        execute_instr_addr;
  logic [DW-1:0]        execute_instr;
  logic [DW-1:0]        execute_op1;
  logic [DW-1:0]        execute_op2;
  logic [DW-1:0]        execute_store_data;
  logic                 wr_reg_en;
  logic [4:0]           wr_reg_addr;
  logic [DW-1:0]        wr_reg_data;
  logic                 mem_wr_en;
  logic [DW/8-1:0]      mem_wr_strb;
  logic [AW-1:0]        mem_addr;
  logic [DW-1:0]        mem_wdata;
  logic [DW-1:0]        mem_rdata;
  assign instr_addr  = pc_pointer;
  assign instruction = instr_rdata;
  pc_counter #(.AW(AW)) u_pc_counter (
    .clk(clk), .rst_n(rst_n), .jump_en(jump_en), .jump_addr(jump_addr), .pc_pointer(pc_pointer)
  );
  if2id #(.AW(AW), .DW(DW)) u_if2id (
    .clk(clk), .rst_n(rst_n), .instr_hold(jump_en),
    .instr_addr_in(pc_pointer), .instr_in(instruction),
    .instr_addr_out(instr_addr_reg), .instr_out(instr_reg)
  );
  decode #(.AW(AW), .DW(DW)) u_decode (
    .instr_addr_in(instr_addr_reg), .instr_in(instr_reg),
    .rd_rs1_addr(rd_rs1_addr), .rd_rs2_addr(rd_rs2_addr),
    .rd_rs1_data(rd_rs1_data), .rd_rs2_data(rd_rs2_data),
    .op1_out(decode_op1), .op2_out(decode_op2), .store_data_out(decode_store_data)
  );
  register #(.DW(DW)) u_register (
    .clk(clk), .rst_n(rst_n),
    .rd_rs1_addr(rd_rs1_addr), .rd_rs2_addr(rd_rs2_addr),
    .rd_rs1_data(rd_rs1_data), .rd_rs2_data(rd_rs2_data),
    .wr_reg_en(wr_reg_en), .wr_reg_addr(wr_reg_addr), .wr_reg_data(wr_reg_data)
  );
  id2ex #(.AW(AW), .DW(DW)) u_id2ex (
    .clk(clk), .rst_n(rst_n), .instr_hold(jump_en),
    .instr_addr_in(instr_addr_reg), .instr_in(instr_reg),
    .op1_in(decode_op1), .op2_in(decode_op2), .store_data_in(decode_store_data),
    .instr_addr_out(execute_instr_addr), .instr_out(execute_instr),
    .op1_out(execute_op1), .op2_out(execute_op2), .store_data_out(execute_store_data)
  );
  execute #(.AW(AW), .DW(DW)) u_execute (
    .instr_addr(execute_instr_addr), .instr(execute_instr),
    .op1(execute_op1), .op2(execute_op2), .store_data(execute_store_data),
    .wr_reg_en(wr_reg_en), .wr_reg_addr(wr_reg_addr), .wr_reg_data(wr_reg_data),
    .jump_en(jump_en), .jump_addr(jump_addr), .jump_hold(jump_hold),
    .mem_wr_en(mem_wr_en), .mem_wr_strb(mem_wr_strb), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
  );
  data_ram #(.AW(AW), .DW(DW), .DEPTH(DATA_RAM_DEPTH)) u_data_ram (
    .clk(clk), .rst_n(rst_n),
    .wr_en(mem_wr_en), .wr_strb(mem_wr_strb),
    .addr(mem_addr), .wr_data(mem_wdata), .rd_data(mem_rdata)
  );
  assign test_case = 32'h0;
  assign reg_s10   = 32'h0;
  assign reg_s11   = 32'h0;
endmodule