`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
// ============================================================
// Module: decode
// Description:
//   RV32IM instruction decode stage.
//   This module parses instruction fields and generates control
//   signals for execute, memory, and writeback stages.
//
// Responsibilities:
//   - Parse opcode/funct3/funct7/rs1/rs2/rd.
//   - Generate register read addresses.
//   - Generate use_rs1/use_rs2 for hazard detection.
//   - Generate immediate values.
//   - Generate ALU, branch, jump, memory, writeback controls.
//   - Generate RV32M multiply/divide controls.
//   - Detect illegal/unsupported instructions.
//   - Detect ecall/ebreak as explicit control signals.
//
// Notes:
//   - Current target is RV32IM.
//   - fence is treated as NOP in this simple single-core design.
//   - ecall/ebreak are not treated as NOP; explicit flags are
//     generated for top-level halt/exception handling.
//   - CSR instructions are currently unsupported and reported as
//     illegal.
//   - instr_i is DW wide for compatibility with the existing
//     code, but only instr_i[31:0] is decoded.
//   - For future RV64 extension, DW parameterization is preserved
//     where practical. Current implementation can still be limited
//     to DW == 32 at integration level.
// ============================================================
module decode #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic [AW-1:0] pc_i,
  input  logic [DW-1:0] instr_i,
  // Register file read interface
  // --------------------------------------------------------------------------
  // Register file read interface
  //
  // Direction is from the point of view of this decode module.
  //
  // Decode extracts rs1/rs2 fields from the instruction and drives the
  // register-file read addresses outward.
  //
  // The external register file reads x[rs1] and x[rs2], then returns the
  // corresponding register values back into this decode module.
  //
  // Typical connection:
  //
  //   decode.rf_rs1_raddr_o  --->  regfile.raddr1_i
  //   decode.rf_rs2_raddr_o  --->  regfile.raddr2_i
  //   decode.rf_rs1_rdata_i  <---  regfile.rdata1_o
  //   decode.rf_rs2_rdata_i  <---  regfile.rdata2_o
  //
  // This interface assumes that the register file has combinational or
  // asynchronous read ports, meaning rdata is valid in the same cycle after
  // raddr is driven.
  //
  // If the register file uses synchronous reads, then rf_rs*_rdata_i would be
  // valid one clock later, and the pipeline must add an extra register stage
  // or otherwise align the timing.
  // --------------------------------------------------------------------------
  output logic [4:0]    rf_rs1_raddr_o,
  output logic [4:0]    rf_rs2_raddr_o,
  input  logic [DW-1:0] rf_rs1_rdata_i,
  input  logic [DW-1:0] rf_rs2_rdata_i,
  // Operand outputs to ID/EX
    // --------------------------------------------------------------------------
  // Decoded operands forwarded to the execute stage.
  //
  // These are already selected by decode and are not necessarily raw register
  // values.
  //
  // Examples:
  //   R-type ALU: op1 = x[rs1], op2 = x[rs2]
  //   I-type ALU: op1 = x[rs1], op2 = immediate
  //   Load/store address: op1 = x[rs1], op2 = immediate
  //   AUIPC: op1 = pc, op2 = upper immediate
  //   LUI: op1 = 0, op2 = upper immediate
  //
  // store_data_o is specifically the data to be written to memory for store
  // instructions, normally x[rs2].
  // --------------------------------------------------------------------------
  output logic [DW-1:0] op1_o,
  output logic [DW-1:0] op2_o,
  output logic [DW-1:0] store_data_o,
  // Register usage information for hazard detection
    // --------------------------------------------------------------------------
  // Source register usage flags.
  //
  // use_rs1_o/use_rs2_o indicate whether the current instruction actually
  // reads rs1/rs2 architecturally.
  //
  // They are used by hazard detection and forwarding logic.
  //
  // Examples:
  //   ADD  uses rs1 and rs2
  //   ADDI uses rs1 only
  //   LUI  uses neither rs1 nor rs2
  //   SW   uses rs1 for address and rs2 for store data
  //   BEQ  uses rs1 and rs2
  // --------------------------------------------------------------------------
  output logic          use_rs1_o,
  output logic          use_rs2_o,
  // Destination register and RF write control
  output logic [4:0]    rd_o,
  output logic          rf_we_o,
  // Decoded immediate
  output logic [DW-1:0] imm_o,
  // Execute controls
  output alu_op_e       alu_op_o,
  output branch_op_e    branch_op_o,
  output jump_op_e      jump_op_o,
  // Memory controls
  output logic          mem_req_o,
  output logic          mem_we_o,
  output mem_size_e     mem_size_o,
  output logic          mem_unsigned_o,
  // Writeback control
  output wb_sel_e       wb_sel_o,
  // RV32M controls
  output logic          muldiv_valid_o,
  output muldiv_op_e    muldiv_op_o,
  // Exception/special instruction flags
  output logic          illegal_instr_o,
  output logic          ecall_o,
  output logic          ebreak_o
);

  initial begin
    if (DW < 32) begin
      $error("decode requires DW >= 32, got DW=%0d", DW);
    end
  end
  initial begin
    if (AW > DW) begin
      $error("decode assumes AW <= DW, got AW=%0d DW=%0d", AW, DW);
    end
  end
  // ------------------------------------------------------------
  // Instruction fields
  // ------------------------------------------------------------
  logic [31:0] instr32;
  logic [6:0] opcode;
  logic [4:0] rd;
  logic [2:0] funct3;
  logic [4:0] rs1;
  logic [4:0] rs2;
  logic [6:0] funct7;
  assign instr32 = instr_i[31:0];
  assign opcode = instr32[6:0];
  assign rd     = instr32[11:7];
  assign funct3 = instr32[14:12];
  assign rs1    = instr32[19:15];
  assign rs2    = instr32[24:20];
  assign funct7 = instr32[31:25];
  // ------------------------------------------------------------
  // Immediate generation
  // ------------------------------------------------------------
  //
  // RV32 immediates are first generated as signed 32-bit values,
  // then cast to DW. This keeps the code simple for RV32 and still
  // gives a reasonable path for future RV64 sign extension.
  //
  logic signed [31:0] imm_i_32;
  logic signed [31:0] imm_s_32;
  logic signed [31:0] imm_b_32;
  logic signed [31:0] imm_u_32;
  logic signed [31:0] imm_j_32;
  logic [DW-1:0] imm_i;
  logic [DW-1:0] imm_s;
  logic [DW-1:0] imm_b;
  logic [DW-1:0] imm_u;
  logic [DW-1:0] imm_j;
  assign imm_i_32 = {{20{instr32[31]}}, instr32[31:20]};
  assign imm_s_32 = {{20{instr32[31]}},
                     instr32[31:25],
                     instr32[11:7]};
  assign imm_b_32 = {{19{instr32[31]}},
                     instr32[31],
                     instr32[7],
                     instr32[30:25],
                     instr32[11:8],
                     1'b0};
  assign imm_u_32 = {instr32[31:12], 12'b0};
  assign imm_j_32 = {{11{instr32[31]}},
                     instr32[31],
                     instr32[19:12],
                     instr32[20],
                     instr32[30:21],
                     1'b0};
  assign imm_i = DW'(imm_i_32);
  assign imm_s = DW'(imm_s_32);
  assign imm_b = DW'(imm_b_32);
  assign imm_u = DW'(imm_u_32);
  assign imm_j = DW'(imm_j_32);
  // ------------------------------------------------------------
  // Decode logic
  // ------------------------------------------------------------
  //
  // All outputs get safe defaults first. Illegal/unsupported
  // instructions keep these safe controls, so they cannot write
  // registers, write memory, or redirect PC accidentally.
  //
  always_comb begin
    // Register file defaults
    rf_rs1_raddr_o  = 5'd0;
    rf_rs2_raddr_o  = 5'd0;
    use_rs1_o       = 1'b0;
    use_rs2_o       = 1'b0;
    // Operand defaults
    op1_o           = '0;
    op2_o           = '0;
    store_data_o    = '0;
    // Destination/write defaults
    rd_o            = 5'd0;
    rf_we_o         = 1'b0;
    // Immediate default
    imm_o           = '0;
    // Execute control defaults
    alu_op_o        = ALU_NONE;
    branch_op_o     = BR_NONE;
    jump_op_o       = JMP_NONE;
    // Memory defaults
    mem_req_o       = 1'b0;
    mem_we_o        = 1'b0;
    mem_size_o      = MEM_SIZE_WORD;
    mem_unsigned_o  = 1'b0;
    // Writeback default
    wb_sel_o        = WB_NONE;
    // M extension defaults
    muldiv_valid_o  = 1'b0;
    muldiv_op_o     = MULDIV_NONE;
    // Exception/special defaults
    illegal_instr_o = 1'b0;
    ecall_o         = 1'b0;
    ebreak_o        = 1'b0;
    unique case (opcode)
      // --------------------------------------------------------
      // LUI
      // rd = imm_u
      // --------------------------------------------------------
      OPCODE_LUI: begin
        rd_o     = rd;
        rf_we_o  = 1'b1;
        imm_o    = imm_u;
        op1_o    = '0;
        op2_o    = imm_u;
        alu_op_o = ALU_COPY_B;
        wb_sel_o = WB_ALU;
      end
      // --------------------------------------------------------
      // AUIPC
      // rd = pc + imm_u
      // --------------------------------------------------------
      OPCODE_AUIPC: begin
        rd_o     = rd;
        rf_we_o  = 1'b1;
        imm_o    = imm_u;
        op1_o    = DW'(pc_i);
        op2_o    = imm_u;
        alu_op_o = ALU_ADD;
        wb_sel_o = WB_ALU;
      end
      // --------------------------------------------------------
      // JAL
      // rd = pc + 4, redirect to pc + imm_j
      // --------------------------------------------------------
      OPCODE_JAL: begin
        rd_o       = rd;
        rf_we_o    = 1'b1;
        imm_o      = imm_j;
        op1_o      = DW'(pc_i);
        op2_o      = imm_j;
        jump_op_o  = JMP_JAL;
        wb_sel_o   = WB_PC4;
      end
      // --------------------------------------------------------
      // JALR
      // rd = pc + 4, redirect to (rs1 + imm_i) & ~1
      // funct3 must be 000.
      // --------------------------------------------------------
      OPCODE_JALR: begin
        if (funct3 == 3'b000) begin
          rf_rs1_raddr_o = rs1;
          use_rs1_o      = 1'b1;
          rd_o           = rd;
          rf_we_o        = 1'b1;
          imm_o          = imm_i;
          op1_o          = rf_rs1_rdata_i;
          op2_o          = imm_i;
          jump_op_o      = JMP_JALR;
          wb_sel_o       = WB_PC4;
        end
        else begin
          illegal_instr_o = 1'b1;
        end
      end
      // --------------------------------------------------------
      // Branch
      // BEQ/BNE/BLT/BGE/BLTU/BGEU
      // --------------------------------------------------------
      OPCODE_BRANCH: begin
        rf_rs1_raddr_o = rs1;
        rf_rs2_raddr_o = rs2;
        use_rs1_o      = 1'b1;
        use_rs2_o      = 1'b1;
        imm_o          = imm_b;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = rf_rs2_rdata_i;
        unique case (funct3)
          FUNCT3_BEQ:  branch_op_o = BR_BEQ;
          FUNCT3_BNE:  branch_op_o = BR_BNE;
          FUNCT3_BLT:  branch_op_o = BR_BLT;
          FUNCT3_BGE:  branch_op_o = BR_BGE;
          FUNCT3_BLTU: branch_op_o = BR_BLTU;
          FUNCT3_BGEU: branch_op_o = BR_BGEU;
          default: begin
            branch_op_o     = BR_NONE;
            illegal_instr_o = 1'b1;
          end
        endcase
      end
      // --------------------------------------------------------
      // Load
      // LB/LH/LW/LBU/LHU
      // address = rs1 + imm_i
      // --------------------------------------------------------
      OPCODE_LOAD: begin
        rf_rs1_raddr_o = rs1;
        use_rs1_o      = 1'b1;
        rd_o           = rd;
        rf_we_o        = 1'b1;
        imm_o          = imm_i;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_i;
        alu_op_o       = ALU_ADD;
        mem_req_o      = 1'b1;
        mem_we_o       = 1'b0;
        wb_sel_o       = WB_MEM;
        unique case (funct3)
          FUNCT3_LB: begin
            mem_size_o     = MEM_SIZE_BYTE;
            mem_unsigned_o = 1'b0;
          end
          FUNCT3_LH: begin
            mem_size_o     = MEM_SIZE_HALF;
            mem_unsigned_o = 1'b0;
          end
          FUNCT3_LW: begin
            mem_size_o     = MEM_SIZE_WORD;
            mem_unsigned_o = 1'b0;
          end
          FUNCT3_LBU: begin
            mem_size_o     = MEM_SIZE_BYTE;
            mem_unsigned_o = 1'b1;
          end
          FUNCT3_LHU: begin
            mem_size_o     = MEM_SIZE_HALF;
            mem_unsigned_o = 1'b1;
          end
          default: begin
            rf_we_o         = 1'b0;
            mem_req_o       = 1'b0;
            wb_sel_o        = WB_NONE;
            //prevent illegal instr engaging in hazard detection
            use_rs1_o       = 1'b0;
            use_rs2_o       = 1'b0;
            illegal_instr_o = 1'b1;
          end
        endcase
      end
      // --------------------------------------------------------
      // Store
      // SB/SH/SW
      // address = rs1 + imm_s
      // store_data = rs2
      // --------------------------------------------------------
      OPCODE_STORE: begin
        rf_rs1_raddr_o = rs1;
        rf_rs2_raddr_o = rs2;
        use_rs1_o      = 1'b1;
        use_rs2_o      = 1'b1;
        imm_o          = imm_s;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_s;
        store_data_o   = rf_rs2_rdata_i;
        alu_op_o       = ALU_ADD;
        mem_req_o      = 1'b1;
        mem_we_o       = 1'b1;
        wb_sel_o       = WB_NONE;
        unique case (funct3)
          FUNCT3_SB: begin
            mem_size_o = MEM_SIZE_BYTE;
          end
          FUNCT3_SH: begin
            mem_size_o = MEM_SIZE_HALF;
          end
          FUNCT3_SW: begin
            mem_size_o = MEM_SIZE_WORD;
          end
          default: begin
            mem_req_o       = 1'b0;
            mem_we_o        = 1'b0;
            illegal_instr_o = 1'b1;
          end
        endcase
      end
      // --------------------------------------------------------
      // OP-IMM
      // ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
      // --------------------------------------------------------
      OPCODE_OP_IMM: begin
        rf_rs1_raddr_o = rs1;
        use_rs1_o      = 1'b1;
        rd_o           = rd;
        imm_o          = imm_i;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = imm_i;
        wb_sel_o       = WB_ALU;
        unique case (funct3)
          FUNCT3_ADDI: begin
            rf_we_o  = 1'b1;
            alu_op_o = ALU_ADD;
          end
          FUNCT3_SLTI: begin
            rf_we_o  = 1'b1;
            alu_op_o = ALU_SLT;
          end
          FUNCT3_SLTIU: begin
            rf_we_o  = 1'b1;
            alu_op_o = ALU_SLTU;
          end
          FUNCT3_XORI: begin
            rf_we_o  = 1'b1;
            alu_op_o = ALU_XOR;
          end
          FUNCT3_ORI: begin
            rf_we_o  = 1'b1;
            alu_op_o = ALU_OR;
          end
          FUNCT3_ANDI: begin
            rf_we_o  = 1'b1;
            alu_op_o = ALU_AND;
          end
          FUNCT3_SLLI: begin
            if (funct7 == FUNCT7_BASE) begin
              rf_we_o  = 1'b1;
              alu_op_o = ALU_SLL;
            end
            else begin
              wb_sel_o        = WB_NONE;
              illegal_instr_o = 1'b1;
            end          end
          FUNCT3_SRI: begin
            if (funct7 == FUNCT7_BASE) begin
              rf_we_o  = 1'b1;
              alu_op_o = ALU_SRL;
            end
            else if (funct7 == FUNCT7_ALT) begin
              rf_we_o  = 1'b1;
              alu_op_o = ALU_SRA;
            end
            else begin
              wb_sel_o        = WB_NONE;
              illegal_instr_o = 1'b1;
            end
          end
          default: begin
            wb_sel_o        = WB_NONE;
            illegal_instr_o = 1'b1;
          end
        endcase
      end
      // --------------------------------------------------------
      // OP
      // RV32I R-type ALU and RV32M MULDIV
      // --------------------------------------------------------
      OPCODE_OP: begin
        rf_rs1_raddr_o = rs1;
        rf_rs2_raddr_o = rs2;
        use_rs1_o      = 1'b1;
        use_rs2_o      = 1'b1;
        rd_o           = rd;
        op1_o          = rf_rs1_rdata_i;
        op2_o          = rf_rs2_rdata_i;
        unique case (funct7)
          // ----------------------------------------------------
          // RV32I base R-type operations
          // ----------------------------------------------------
          FUNCT7_BASE: begin
            rf_we_o  = 1'b1;
            wb_sel_o = WB_ALU;
            unique case (funct3)
              FUNCT3_ADD_SUB: alu_op_o = ALU_ADD;
              FUNCT3_SLL:     alu_op_o = ALU_SLL;
              FUNCT3_SLT:     alu_op_o = ALU_SLT;
              FUNCT3_SLTU:    alu_op_o = ALU_SLTU;
              FUNCT3_XOR:     alu_op_o = ALU_XOR;
              FUNCT3_SR:      alu_op_o = ALU_SRL;
              FUNCT3_OR:      alu_op_o = ALU_OR;
              FUNCT3_AND:     alu_op_o = ALU_AND;
              default: begin
                rf_we_o         = 1'b0;
                wb_sel_o        = WB_NONE;
                illegal_instr_o = 1'b1;
              end
            endcase
          end
          // ----------------------------------------------------
          // SUB/SRA
          // ----------------------------------------------------
          FUNCT7_ALT: begin
            rf_we_o  = 1'b1;
            wb_sel_o = WB_ALU;
            unique case (funct3)
              FUNCT3_ADD_SUB: alu_op_o = ALU_SUB;
              FUNCT3_SR:      alu_op_o = ALU_SRA;
              default: begin
                rf_we_o         = 1'b0;
                wb_sel_o        = WB_NONE;
                illegal_instr_o = 1'b1;
              end
            endcase
          end
          // ----------------------------------------------------
          // RV32M multiply/divide extension
          // ----------------------------------------------------
          FUNCT7_MULDIV: begin
            rf_we_o        = 1'b1;
            wb_sel_o       = WB_MULDIV;
            muldiv_valid_o = 1'b1;
            unique case (funct3)
              3'b000: muldiv_op_o = MULDIV_MUL;
              3'b001: muldiv_op_o = MULDIV_MULH;
              3'b010: muldiv_op_o = MULDIV_MULHSU;
              3'b011: muldiv_op_o = MULDIV_MULHU;
              3'b100: muldiv_op_o = MULDIV_DIV;
              3'b101: muldiv_op_o = MULDIV_DIVU;
              3'b110: muldiv_op_o = MULDIV_REM;
              3'b111: muldiv_op_o = MULDIV_REMU;
              default: begin
                rf_we_o         = 1'b0;
                wb_sel_o        = WB_NONE;
                muldiv_valid_o  = 1'b0;
                muldiv_op_o     = MULDIV_NONE;
                illegal_instr_o = 1'b1;
              end
            endcase
          end
          default: begin
            illegal_instr_o = 1'b1;
          end
        endcase
      end
      // --------------------------------------------------------
      // MISC-MEM
      // fence is treated as NOP for this simple single-core
      // no-cache, in-order implementation.
      //
      // Zifencei / fence.i is not implemented and is reported as
      // illegal/unsupported.
      // --------------------------------------------------------
      OPCODE_MISC_MEM: begin
        if (funct3 == 3'b000) begin
          // fence: legal NOP in this implementation.
        end
        else begin
          illegal_instr_o = 1'b1;
        end
      end
      // --------------------------------------------------------
      // SYSTEM
      //
      // ecall/ebreak are explicitly reported.
      // CSR instructions and mret are currently unsupported.
      // They must not be silently executed as NOP.
      // --------------------------------------------------------
      OPCODE_SYSTEM: begin
        if (instr32 == INST_ECALL) begin
          ecall_o = 1'b1;
        end
        else if (instr32 == INST_EBREAK) begin
          ebreak_o = 1'b1;
        end
        else begin
          illegal_instr_o = 1'b1;
        end
      end
      // --------------------------------------------------------
      // Unknown opcode
      // --------------------------------------------------------
      default: begin
        illegal_instr_o = 1'b1;
      end
    endcase
    // ----------------------------------------------------------
    // x0 write suppression is usually handled in regfile.
    // Here rf_we_o is kept as decoded architectural intent.
    // The regfile still prevents actual writes to x0.
    // ----------------------------------------------------------
  end
  // ------------------------------------------------------------
  // RV64 extension note
  // ------------------------------------------------------------
  // The current decode logic targets RV32IM. If DW is changed to
  // 64 in the future, additional RV64 opcodes such as OP-IMM-32
  // and OP-32 must be added, and shift-immediate legality checks
  // need to use a 6-bit shamt.
  // ------------------------------------------------------------
endmodule
`default_nettype wire