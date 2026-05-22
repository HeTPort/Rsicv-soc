`timescale 1ns / 1ps
`ifndef DEFINE_SV
`define DEFINE_SV
// ============================================================
// Global architecture parameters
// ============================================================
`define AW             32
`define DW             32
`define REG_NUM        32
`define REG_ADDR_W     5
`define BYTE_W         8
`define BYTE_NUM       (`DW/8)
// default memory depth
`define PROG_RAM_DEPTH 4096
`define DATA_RAM_DEPTH 4096
// ============================================================
// Special instructions
// ============================================================
`define INST_NOP       32'h00000013   // addi x0, x0, 0
`define INST_ECALL     32'h00000073
`define INST_EBREAK    32'h00100073
`define INST_MRET      32'h30200073
// ============================================================
// Opcode definitions
// ============================================================
`define INST_TYPE_I      7'b0010011
`define INST_TYPE_R_M    7'b0110011
`define INST_TYPE_L      7'b0000011
`define INST_TYPE_S      7'b0100011
`define INST_TYPE_B      7'b1100011
`define INST_TYPE_JALR   7'b1100111
`define INST_TYPE_JAL    7'b1101111
`define INST_LUI         7'b0110111
`define INST_AUIPC       7'b0010111
// ============================================================
// I-type func3
// ============================================================
`define INST_ADDI        3'b000
`define INST_SLLI        3'b001
`define INST_SLTI        3'b010
`define INST_SLTIU       3'b011
`define INST_XORI        3'b100
`define INST_SRI         3'b101   // SRLI/SRAI
`define INST_ORI         3'b110
`define INST_ANDI        3'b111
// ============================================================
// R-type func3
// ============================================================
`define INST_ADD_SUB     3'b000
`define INST_SLL         3'b001
`define INST_SLT         3'b010
`define INST_SLTU        3'b011
`define INST_XOR         3'b100
`define INST_SR          3'b101   // SRL/SRA
`define INST_OR          3'b110
`define INST_AND         3'b111
// ============================================================
// Load func3
// ============================================================
`define INST_LB          3'b000
`define INST_LH          3'b001
`define INST_LW          3'b010
`define INST_LBU         3'b100
`define INST_LHU         3'b101
// ============================================================
// Store func3
// ============================================================
`define INST_SB          3'b000
`define INST_SH          3'b001
`define INST_SW          3'b010
// ============================================================
// Branch func3
// ============================================================
`define INST_BEQ         3'b000
`define INST_BNE         3'b001
`define INST_BLT         3'b100
`define INST_BGE         3'b101
`define INST_BLTU        3'b110
`define INST_BGEU        3'b111
`endif