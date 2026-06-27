`timescale 1ns / 1ps
`default_nettype wire
// ============================================================
// Package: riscv_pkg
// Description:
//   Global definitions for the simple RISC-V core.
//
// Notes:
//   - Current target ISA is RV32IM (Default).
//   - XLEN/DW are localparamized for future RV64 extension (+define+RISCV_XLEN_64).
//   - Opcode/funct3/funct7 constants are kept compatible with the original code.
//   - New enum control types are used to move instruction decode
//     out of execute and into decode.
// ============================================================
package riscv_pkg;

  // ------------------------------------------------------------
  // Section 1: Architecture Configuration (Compile-Time Switch)
  // ------------------------------------------------------------
  // Usage: 
  //   RV32: make/compile normally (defaults to 32)
  //   RV64: add "+define+RISCV_XLEN_64" to your compiler/simulator flags
  `ifndef RISCV_XLEN_64
    `define RISCV_XLEN 32
  `else
    `define RISCV_XLEN 64
  `endif

  // ------------------------------------------------------------
  // Global localparams
  // ------------------------------------------------------------
  localparam int XLEN       = `RISCV_XLEN;
  // 解耦物理地址宽度：实际芯片中地址宽度往往不等于 XLEN，RV64 默认设为 40
  localparam int unsigned AW         = (XLEN == 64) ? 40 : 32; 
  localparam int unsigned DW         = XLEN;
  localparam int unsigned REG_NUM    = 32;
  localparam int unsigned REG_ADDR_W = 5; // $clog2(32)
  localparam int unsigned BYTE_NUM   = DW / 8;

  // Shift amount width: 5 bits for RV32, 6 bits for RV64
  localparam int SHAMT_W    = (XLEN == 64) ? 6 : 5; // Shift amount width

  // ------------------------------------------------------------
  // Section 2: Common instruction constants
  // ------------------------------------------------------------
  localparam logic [XLEN-1:0] INST_NOP    = {{(XLEN-12){1'b0}}, 12'h013}; // addi x0,x0,0
  localparam logic [XLEN-1:0] INST_ECALL  = {{(XLEN-12){1'b0}}, 12'h073};
  localparam logic [XLEN-1:0] INST_EBREAK = {{(XLEN-12){1'b0}}, 12'h173};
  localparam logic [XLEN-1:0] INST_MRET   = {{(XLEN-12){1'b0}}, 12'h302}; // 特权架构返回

  // ------------------------------------------------------------
  // Section 3: Opcodes
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
  
  // RV64 Specific Opcodes
  `ifdef RISCV_XLEN_64
  localparam logic [6:0] OPCODE_OP_IMM_32 = 7'b0011011; // ADDIW, SLLIW, etc.
  localparam logic [6:0] OPCODE_OP_32     = 7'b0111011; // ADDW, SUBW, SLLW, etc.
  `endif

  // ------------------------------------------------------------
  // Section 4: OP-IMM funct3
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
  // Section 5: OP funct3
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
  // Section 6: Load funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_LB  = 3'b000;
  localparam logic [2:0] FUNCT3_LH  = 3'b001;
  localparam logic [2:0] FUNCT3_LW  = 3'b010;
  localparam logic [2:0] FUNCT3_LBU = 3'b100;
  localparam logic [2:0] FUNCT3_LHU = 3'b101;
  `ifdef RISCV_XLEN_64
  localparam logic [2:0] FUNCT3_LWU = 3'b110;
  localparam logic [2:0] FUNCT3_LD  = 3'b011;
  `endif

  // ------------------------------------------------------------
  // Section 7: Store funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_SB = 3'b000;
  localparam logic [2:0] FUNCT3_SH = 3'b001;
  localparam logic [2:0] FUNCT3_SW = 3'b010;
  `ifdef RISCV_XLEN_64
  localparam logic [2:0] FUNCT3_SD = 3'b011;
  `endif

  // ------------------------------------------------------------
  // Section 8: Branch funct3
  // ------------------------------------------------------------
  localparam logic [2:0] FUNCT3_BEQ  = 3'b000;
  localparam logic [2:0] FUNCT3_BNE  = 3'b001;
  localparam logic [2:0] FUNCT3_BLT  = 3'b100;
  localparam logic [2:0] FUNCT3_BGE  = 3'b101;
  localparam logic [2:0] FUNCT3_BLTU = 3'b110;
  localparam logic [2:0] FUNCT3_BGEU = 3'b111;

  // ------------------------------------------------------------
  // Section 9: funct7
  // ------------------------------------------------------------
  localparam logic [6:0] FUNCT7_BASE   = 7'b0000000;
  localparam logic [6:0] FUNCT7_ALT    = 7'b0100000;
  localparam logic [6:0] FUNCT7_MULDIV = 7'b0000001;

  // ------------------------------------------------------------
  // Section 10: Control Enumerations
  // ------------------------------------------------------------
  
  // ALU operation type
  typedef enum logic [4:0] {
    ALU_NONE   = 5'd0,
    ALU_ADD    = 5'd1,
    ALU_SUB    = 5'd2,
    ALU_SLL    = 5'd3,
    ALU_SLT    = 5'd4,
    ALU_SLTU   = 5'd5,
    ALU_XOR    = 5'd6,
    ALU_SRL    = 5'd7,
    ALU_SRA    = 5'd8,
    ALU_OR     = 5'd9,
    ALU_AND    = 5'd10,
    ALU_COPY_B = 5'd11
    `ifdef RISCV_XLEN_64
    , // 逗号放在宏内部，避免 RV32 末尾出现悬空逗号
    ALU_ADDW   = 5'd12,
    ALU_SUBW   = 5'd13,
    ALU_SLLW   = 5'd14,
    ALU_SRLW   = 5'd15,
    ALU_SRAW   = 5'd16
    `endif
  } alu_op_e;

  // Branch operation type
  typedef enum logic [2:0] {
    BR_NONE = 3'd0,
    BR_BEQ  = 3'd1,
    BR_BNE  = 3'd2,
    BR_BLT  = 3'd3,
    BR_BGE  = 3'd4,
    BR_BLTU = 3'd5,
    BR_BGEU = 3'd6
  } branch_op_e;

  // Jump operation type
  typedef enum logic [1:0] {
    JMP_NONE = 2'd0,
    JMP_JAL  = 2'd1,
    JMP_JALR = 2'd2
  } jump_op_e;

  // Memory access size
  typedef enum logic [1:0] {
    MEM_SIZE_BYTE = 2'd0,
    MEM_SIZE_HALF = 2'd1,
    MEM_SIZE_WORD = 2'd2
    `ifdef RISCV_XLEN_64
    ,
    MEM_SIZE_DWORD = 2'd3 // Double word for RV64 LD/SD
    `endif
  } mem_size_e;

  // Writeback select type
  typedef enum logic [2:0] {
    WB_NONE   = 3'd0,
    WB_ALU    = 3'd1,
    WB_MEM    = 3'd2,
    WB_PC4    = 3'd3,
    WB_MULDIV = 3'd4
    // WB_CSR    = 3'd5 // [扩展] 后续支持 CSR 时启用
  } wb_sel_e;

  // Multiply/divide operation type
  typedef enum logic [3:0] {
    MULDIV_NONE   = 4'd0,
    MULDIV_MUL    = 4'd1,
    MULDIV_MULH   = 4'd2,
    MULDIV_MULHSU = 4'd3,
    MULDIV_MULHU  = 4'd4,
    MULDIV_DIV    = 4'd5,
    MULDIV_DIVU   = 4'd6,
    MULDIV_REM    = 4'd7,
    MULDIV_REMU   = 4'd8
  } muldiv_op_e;

  // [扩展] 特权模式 (后续支持特权架构时取消注释)
  // typedef enum logic [1:0] {
  //   PRIV_MODE_U = 2'd0,
  //   PRIV_MODE_S = 2'd1,
  //   PRIV_MODE_M = 2'd3
  // } priv_mode_e;

   // ============================================================
  // Section 11: Pipeline Payload Structures
  // ============================================================

  // 11.1 Fetch Packet (对应 if2id 模块的接口)
  typedef struct packed {
    logic          valid;
    logic [AW-1:0] pc;
    logic [DW-1:0] instr;
  } fetch_pkt_t;

  // 11.2 Register File Write Control (对应 rd, rf_we)
  // 注意：wdata 不在此包内，因为 wdata 是在 WB 阶段才最终生成的
  typedef struct packed {
    logic          we;    // 对应 rf_we
    logic [4:0]    addr;  // 对应 rd / rf_waddr
  } rf_pkt_t;

  // 11.3 Execute Data Payload (对应 op1, op2, imm, store_data)
  typedef struct packed {
    logic [DW-1:0] op1;
    logic [DW-1:0] op2;
    logic [DW-1:0] imm;
    logic [DW-1:0] store_data;
  } ex_data_pkt_t;

  // 11.4 Execute Control Payload (对应译码后的所有控制信号)
  typedef struct packed {
    alu_op_e       alu_op;
    branch_op_e    branch_op;
    jump_op_e      jump_op;
    logic          mem_req;
    logic          mem_we;
    mem_size_e     mem_size;
    logic          mem_unsigned;
    wb_sel_e       wb_sel;
    logic          muldiv_valid;
    muldiv_op_e    muldiv_op;
  } ex_ctrl_pkt_t;

  // 11.5 Exception Packet (对应 ID/EX 阶段的异常信号)
  // 注意: mem_misaligned 是在 EX 阶段计算出的，所以不在此包中
  typedef struct packed {
    logic          illegal_instr;
    logic          ecall;
    logic          ebreak;
  } exc_pkt_t;

  // 11.6 Memory Info Packet (对应 ex2wb 和 wb_stage 的 mem 接口)
  typedef struct packed {
    mem_size_e     mem_size;
    logic          mem_unsigned;
    // 按照你原有代码，保持 [1:0] (若未来支持 RV64 可改为 $clog2(BYTE_NUM)-1:0)
    logic [1:0]    load_offset; 
  } mem_pkt_t;

  // 11.7 [扩展] CSR Packet (后续支持特权架构时取消注释)
  // typedef struct packed {
  //   logic          csr_we;
  //   logic [11:0]   csr_addr;
  //   logic [DW-1:0] csr_wdata;
  //   logic [2:0]    csr_op;
  // } csr_pkt_t;

  // ============================================================
  // Section 12: Aggregate Pipeline Packets
  // ============================================================

  // 12.1 ID/EX Pipeline Register Payload (精确对应 id2ex 模块的数据接口)
  typedef struct packed {
    logic          valid;
    logic [AW-1:0] pc;
    logic [DW-1:0] instr;
    rf_pkt_t       rf;          // 包含 rf_we, rd
    ex_data_pkt_t  ex_data;     // 包含 op1, op2, imm, store_data
    ex_ctrl_pkt_t  ex_ctrl;     // 包含 alu_op, branch_op, mem_req 等
    exc_pkt_t      exc;         // 包含 illegal_instr, ecall, ebreak
    logic          use_rs1;
    logic          use_rs2;
  } id_ex_pkt_t;

  // 12.2 EX/WB Pipeline Register Payload (精确对应 ex2wb 模块的数据接口)
  typedef struct packed {
    logic          valid;
    rf_pkt_t       rf;          // 包含 rf_wen, rf_waddr
    wb_sel_e       wb_sel;
    logic [DW-1:0] alu_data;
    logic [DW-1:0] pc4_data;
    mem_pkt_t      mem_info;    // 包含 mem_size, mem_unsigned, load_offset
    logic          mem_misaligned; // EX 阶段新增的异常
    exc_pkt_t      exc;         // 包含 illegal_instr, ecall, ebreak
  } ex_wb_pkt_t;
endpackage
`default_nettype wire