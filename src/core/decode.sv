`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

module decode #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic [AW-1:0] pc_i,
  input  logic [DW-1:0] instr_i,
  // Register file read interface
  output logic [4:0]    rf_rs1_raddr_o,
  output logic [4:0]    rf_rs2_raddr_o,
  input  logic [DW-1:0] rf_rs1_rdata_i,
  input  logic [DW-1:0] rf_rs2_rdata_i,
  // Operand outputs to ID/EX
  output logic [DW-1:0] op1_o,
  output logic [DW-1:0] op2_o,
  output logic [DW-1:0] store_data_o,
  // Register usage information for hazard detection
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
  assign opcode  = instr32[6:0];
  assign rd      = instr32[11:7];
  assign funct3  = instr32[14:12];
  assign rs1     = instr32[19:15];
  assign rs2     = instr32[24:20];
  assign funct7  = instr32[31:25];

  // ------------------------------------------------------------
  // Immediate generation (Unchanged)
  // ------------------------------------------------------------
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
  assign imm_s_32 = {{20{instr32[31]}}, instr32[31:25], instr32[11:7]};
  assign imm_b_32 = {{19{instr32[31]}}, instr32[31], instr32[7], instr32[30:25], instr32[11:8], 1'b0};
  assign imm_u_32 = {instr32[31:12], 12'b0};
  assign imm_j_32 = {{11{instr32[31]}}, instr32[31], instr32[19:12], instr32[20], instr32[30:21], 1'b0};

  assign imm_i = DW'(imm_i_32);
  assign imm_s = DW'(imm_s_32);
  assign imm_b = DW'(imm_b_32);
  assign imm_u = DW'(imm_u_32);
  assign imm_j = DW'(imm_j_32);


  // ============================================================
  // 性能优化核心区：数据通路提前，物理直连
  // ============================================================
  // 1. 寄存器地址：无论什么指令，直接硬连线，消除 MUX 延迟！
  assign rf_rs1_raddr_o = rs1; // 等价于 instr32[19:15]
  assign rf_rs2_raddr_o = rs2; // 等价于 instr32[24:20]
  assign rd_o           = rd;  // 等价于 instr32[11:7]

  // 2. Store 数据：永远直连 rs2，由 mem_we_o 控制是否有效
  assign store_data_o = rf_rs2_rdata_i;

  // 3. 立即数选择：独立的极简 MUX，不进主 case
  always_comb begin
    unique case (opcode)
      OPCODE_LUI, OPCODE_AUIPC: imm_o = imm_u;
      OPCODE_JAL:               imm_o = imm_j;
      OPCODE_BRANCH:            imm_o = imm_b;
      OPCODE_STORE:             imm_o = imm_s;
      default:                  imm_o = imm_i; // LOAD, OP_IMM, JALR 等
    endcase
  end

  // 4. 操作数选择 (op1 / op2)：独立的极简 MUX
  always_comb begin
    // op1 选择逻辑
    unique case (opcode)
      OPCODE_LUI:   op1_o = '0;               // LUI: 0 + imm
      OPCODE_AUIPC,
      OPCODE_JAL:   op1_o = DW'(pc_i);        // PC-rel: pc + imm
      default:      op1_o = rf_rs1_rdata_i;   // 绝大多数: rs1 + ...
    endcase
  end

  always_comb begin
    // op2 选择逻辑
    unique case (opcode)
      OPCODE_OP, OPCODE_BRANCH: op2_o = rf_rs2_rdata_i; // R-type / Branch
      default:                  op2_o = imm_o;           // I/S/U/J-type
    endcase
  end


  // ============================================================
  // 主解码逻辑：只负责生成控制信号
  // ============================================================
  always_comb begin
    // --- 控制信号安全默认值 ---
    use_rs1_o       = 1'b0;
    use_rs2_o       = 1'b0;
    rf_we_o         = 1'b0;
    alu_op_o        = ALU_NONE;
    branch_op_o     = BR_NONE;
    jump_op_o       = JMP_NONE;
    mem_req_o       = 1'b0;
    mem_we_o        = 1'b0;
    mem_size_o      = MEM_SIZE_WORD;
    mem_unsigned_o  = 1'b0;
    wb_sel_o        = WB_NONE;
    muldiv_valid_o  = 1'b0;
    muldiv_op_o     = MULDIV_NONE;
    illegal_instr_o = 1'b0;
    ecall_o         = 1'b0;
    ebreak_o        = 1'b0;

    unique case (opcode)
      // --------------------------------------------------------
      // LUI
      // --------------------------------------------------------
      OPCODE_LUI: begin
        rf_we_o  = 1'b1;
        alu_op_o = ALU_COPY_B; // op1=0, op2=imm, 透传op2即可
        wb_sel_o = WB_ALU;
      end

      // --------------------------------------------------------
      // AUIPC
      // --------------------------------------------------------
      OPCODE_AUIPC: begin
        rf_we_o  = 1'b1;
        alu_op_o = ALU_ADD;    // op1=pc, op2=imm
        wb_sel_o = WB_ALU;
      end

      // --------------------------------------------------------
      // JAL
      // --------------------------------------------------------
      OPCODE_JAL: begin
        rf_we_o   = 1'b1;
        jump_op_o = JMP_JAL;
        wb_sel_o  = WB_PC4;
      end

      // --------------------------------------------------------
      // JALR
      // --------------------------------------------------------
      OPCODE_JALR: begin
        if (funct3 == 3'b000) begin
          use_rs1_o = 1'b1;
          rf_we_o   = 1'b1;
          jump_op_o = JMP_JALR;
          wb_sel_o  = WB_PC4;
        end else begin
          illegal_instr_o = 1'b1;
        end
      end

      // --------------------------------------------------------
      // Branch
      // --------------------------------------------------------
      OPCODE_BRANCH: begin
        use_rs1_o  = 1'b1;
        use_rs2_o  = 1'b1;
        unique case (funct3)
          FUNCT3_BEQ:  branch_op_o = BR_BEQ;
          FUNCT3_BNE:  branch_op_o = BR_BNE;
          FUNCT3_BLT:  branch_op_o = BR_BLT;
          FUNCT3_BGE:  branch_op_o = BR_BGE;
          FUNCT3_BLTU: branch_op_o = BR_BLTU;
          FUNCT3_BGEU: branch_op_o = BR_BGEU;
          default:     illegal_instr_o = 1'b1;
        endcase
      end

      // --------------------------------------------------------
      // Load
      // --------------------------------------------------------
      OPCODE_LOAD: begin
        use_rs1_o = 1'b1;
        rf_we_o   = 1'b1;
        alu_op_o  = ALU_ADD;    // op1=rs1, op2=imm
        mem_req_o = 1'b1;
        wb_sel_o  = WB_MEM;

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
            use_rs1_o       = 1'b0;
            use_rs2_o       = 1'b0;
            illegal_instr_o = 1'b1;
          end
        endcase
      end

      // --------------------------------------------------------
      // Store
      // --------------------------------------------------------
      OPCODE_STORE: begin
        use_rs1_o = 1'b1;
        use_rs2_o = 1'b1;
        alu_op_o  = ALU_ADD;    // op1=rs1, op2=imm
        mem_req_o = 1'b1;
        mem_we_o  = 1'b1;

        unique case (funct3)
          FUNCT3_SB: mem_size_o = MEM_SIZE_BYTE;
          FUNCT3_SH: mem_size_o = MEM_SIZE_HALF;
          FUNCT3_SW: mem_size_o = MEM_SIZE_WORD;
          default: begin
            mem_req_o       = 1'b0;
            mem_we_o        = 1'b0;
            illegal_instr_o = 1'b1;
          end
        endcase
      end

      // --------------------------------------------------------
      // OP-IMM
      // --------------------------------------------------------
      OPCODE_OP_IMM: begin
        use_rs1_o = 1'b1;
        rf_we_o   = 1'b1;
        wb_sel_o  = WB_ALU;

        unique case (funct3)
          FUNCT3_ADDI:  alu_op_o = ALU_ADD;
          FUNCT3_SLTI:  alu_op_o = ALU_SLT;
          FUNCT3_SLTIU: alu_op_o = ALU_SLTU;
          FUNCT3_XORI:  alu_op_o = ALU_XOR;
          FUNCT3_ORI:   alu_op_o = ALU_OR;
          FUNCT3_ANDI:  alu_op_o = ALU_AND;
          FUNCT3_SLLI: begin
            if (funct7 == FUNCT7_BASE) alu_op_o = ALU_SLL;
            else                       illegal_instr_o = 1'b1;
          end
          FUNCT3_SRI: begin
            if (funct7 == FUNCT7_BASE)      alu_op_o = ALU_SRL;
            else if (funct7 == FUNCT7_ALT)  alu_op_o = ALU_SRA;
            else                            illegal_instr_o = 1'b1;
          end
          default: illegal_instr_o = 1'b1;
        endcase
      end

      // --------------------------------------------------------
      // OP
      // --------------------------------------------------------
      OPCODE_OP: begin
        use_rs1_o = 1'b1;
        use_rs2_o = 1'b1;

        unique case (funct7)
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
              default:        illegal_instr_o = 1'b1;
            endcase
          end

          FUNCT7_ALT: begin
            rf_we_o  = 1'b1;
            wb_sel_o = WB_ALU;
            unique case (funct3)
              FUNCT3_ADD_SUB: alu_op_o = ALU_SUB;
              FUNCT3_SR:      alu_op_o = ALU_SRA;
              default:        illegal_instr_o = 1'b1;
            endcase
          end

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
              default: illegal_instr_o = 1'b1;
            endcase
          end
          default: illegal_instr_o = 1'b1;
        endcase
      end

      // --------------------------------------------------------
      // MISC-MEM (fence as NOP)
      // --------------------------------------------------------
      OPCODE_MISC_MEM: begin
        if (funct3 != 3'b000) illegal_instr_o = 1'b1;
      end

      // --------------------------------------------------------
      // SYSTEM
      // --------------------------------------------------------
      OPCODE_SYSTEM: begin
        if (instr32 == INST_ECALL)       ecall_o = 1'b1;
        else if (instr32 == INST_EBREAK) ebreak_o = 1'b1;
        else                             illegal_instr_o = 1'b1;
      end

      // --------------------------------------------------------
      // Unknown opcode
      // --------------------------------------------------------
      default: illegal_instr_o = 1'b1;
    endcase
  end

endmodule
`default_nettype wire