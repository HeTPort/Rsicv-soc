`timescale 1ns / 1ps
`default_nettype none
// ============================================================
// Package: riscv_pkg
// Description:
//   Global definitions for the simple RISC-V core.
//
// Notes:
//   - Current target ISA is RV32IM.
//   - XLEN/DW are parameterized for future RV64 extension.
//   - Opcode/funct3/funct7 constants are kept compatible with
//     the original code.
//   - New enum control types are used to move instruction decode
//     out of execute and into decode.
// ============================================================
package riscv_pkg;
  // ------------------------------------------------------------
  // Global parameters
  // ------------------------------------------------------------
  parameter int XLEN = 32;
  parameter int AW   = 32;
  parameter int DW   = 32;
  parameter int REG_NUM    = 32;
  parameter int REG_ADDR_W = 5;
  parameter int BYTE_NUM   = DW / 8;
  // ------------------------------------------------------------
  // Common instruction constants
  // ------------------------------------------------------------
  localparam logic [31:0] INST_NOP    = 32'h0000_0013; // addi x0,x0,0
  localparam logic [31:0] INST_ECALL  = 32'h0000_0073;
  localparam logic [31:0] INST_EBREAK = 32'h0010_0073;
  localparam logic [31:0] INST_MRET   = 32'h3020_0073;
  // ------------------------------------------------------------
  // Opcodes
  // ------------------------------------------------------------
  localparam logic [6:0] OPCODE_LOAD     = 7'b0000011;
  localparam logic [6:0] OPCODE_MISC_MEM = 7'b0001111;
  localparam logic [6:0] OPCODE_OP_IMM   = 7'b0010011;
  localparam logic [6:0] OPCODE_AUIPC    = 7'b0010111;
  localparam logic [6:0] OPCODE_STORE    = 7'b0100011;
  localparam logic [6:0] OPCODE_OP       = 7'b0110011;
  localparam logic [6:0] OPCODE_LUI      = 7'b0110111;
  localparam logic [6:0] OPCODE_BRANCH   = 7'b1100011;
  localparam logic [6:0] OPCODE_JALR     = 7'b1100111;
  localparam logic [6:0] OPCODE_JAL      = 7'b1101111;
  localparam logic [6:0] OPCODE_SYSTEM   = 7'b1110011;
  // ------------------------------------------------------------
  // OP-IMM funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_ADDI  = 3'b000;
  localparam logic [2:0] FUNCT3_SLLI  = 3'b001;
  localparam logic [2:0] FUNCT3_SLTI  = 3'b010;
  localparam logic [2:0] FUNCT3_SLTIU = 3'b011;
  localparam logic [2:0] FUNCT3_XORI  = 3'b100;
  localparam logic [2:0] FUNCT3_SRI   = 3'b101;
  localparam logic [2:0] FUNCT3_ORI   = 3'b110;
  localparam logic [2:0] FUNCT3_ANDI  = 3'b111;
  // ------------------------------------------------------------
  // OP funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_ADD_SUB = 3'b000;
  localparam logic [2:0] FUNCT3_SLL     = 3'b001;
  localparam logic [2:0] FUNCT3_SLT     = 3'b010;
  localparam logic [2:0] FUNCT3_SLTU    = 3'b011;
  localparam logic [2:0] FUNCT3_XOR     = 3'b100;
  localparam logic [2:0] FUNCT3_SR      = 3'b101;
  localparam logic [2:0] FUNCT3_OR      = 3'b110;
  localparam logic [2:0] FUNCT3_AND     = 3'b111;
  // ------------------------------------------------------------
  // Load funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_LB  = 3'b000;
  localparam logic [2:0] FUNCT3_LH  = 3'b001;
  localparam logic [2:0] FUNCT3_LW  = 3'b010;
  localparam logic [2:0] FUNCT3_LBU = 3'b100;
  localparam logic [2:0] FUNCT3_LHU = 3'b101;
  // ------------------------------------------------------------
  // Store funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_SB = 3'b000;
  localparam logic [2:0] FUNCT3_SH = 3'b001;
  localparam logic [2:0] FUNCT3_SW = 3'b010;
  // ------------------------------------------------------------
  // Branch funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_BEQ  = 3'b000;
  localparam logic [2:0] FUNCT3_BNE  = 3'b001;
  localparam logic [2:0] FUNCT3_BLT  = 3'b100;
  localparam logic [2:0] FUNCT3_BGE  = 3'b101;
  localparam logic [2:0] FUNCT3_BLTU = 3'b110;
  localparam logic [2:0] FUNCT3_BGEU = 3'b111;
  // ------------------------------------------------------------
  // funct7
  // ------------------------------------------------------------
  localparam logic [6:0] FUNCT7_BASE   = 7'b0000000;
  localparam logic [6:0] FUNCT7_ALT    = 7'b0100000;
  localparam logic [6:0] FUNCT7_MULDIV = 7'b0000001;
  // ------------------------------------------------------------
  // ALU operation type
  // ------------------------------------------------------------
  typedef enum logic [4:0] {
    ALU_NONE,
    ALU_ADD,
    ALU_SUB,
    ALU_SLL,
    ALU_SLT,
    ALU_SLTU,
    ALU_XOR,
    ALU_SRL,
    ALU_SRA,
    ALU_OR,
    ALU_AND,
    ALU_COPY_B
  } alu_op_e;
  // ------------------------------------------------------------
  // Branch operation type
  // ------------------------------------------------------------
  typedef enum logic [2:0] {
    BR_NONE,
    BR_BEQ,
    BR_BNE,
    BR_BLT,
    BR_BGE,
    BR_BLTU,
    BR_BGEU
  } branch_op_e;
  // ------------------------------------------------------------
  // Jump operation type
  // ------------------------------------------------------------
  typedef enum logic [1:0] {
    JMP_NONE,
    JMP_JAL,
    JMP_JALR
  } jump_op_e;
  // ------------------------------------------------------------
  // Memory access size
  // ------------------------------------------------------------
  typedef enum logic [1:0] {
    MEM_SIZE_BYTE,
    MEM_SIZE_HALF,
    MEM_SIZE_WORD
  } mem_size_e;
  // ------------------------------------------------------------
  // Writeback select type
  // ------------------------------------------------------------
  typedef enum logic [2:0] {
    WB_NONE,
    WB_ALU,
    WB_MEM,
    WB_PC4,
    WB_MULDIV
  } wb_sel_e;
  // ------------------------------------------------------------
  // Multiply/divide operation type
  // ------------------------------------------------------------
  typedef enum logic [3:0] {
    MULDIV_NONE,
    MULDIV_MUL,
    MULDIV_MULH,
    MULDIV_MULHSU,
    MULDIV_MULHU,
    MULDIV_DIV,
    MULDIV_DIVU,
    MULDIV_REM,
    MULDIV_REMU
  } muldiv_op_e;
endpackage
`default_nettype wire