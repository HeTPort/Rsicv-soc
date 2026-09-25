`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;

module decode (
  input  wire fetch_pkt_t   pktd_i,
  // Register-file reads remain an explicit horizontal interface.
  output logic [4:0]    rf_rs1_raddr_o,
  output logic [4:0]    rf_rs2_raddr_o,
  input  wire logic [DW-1:0] rf_rs1_rdata_i,
  input  wire logic [DW-1:0] rf_rs2_rdata_i,
  output id_ex_pkt_t   pktd_o
);

  logic [AW-1:0] pc;
  logic [DW-1:0] instr;
  assign pc    = pktd_i.pc;
  assign instr = pktd_i.instr;

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

  assign instr32 = instr[31:0];
  assign opcode  = instr32[6:0];
  assign rd      = instr32[11:7];
  assign funct3  = instr32[14:12];
  assign rs1     = instr32[19:15];
  assign rs2     = instr32[24:20];
  assign funct7  = instr32[31:25];

  // ------------------------------------------------------------
  // Immediate generation
  // ------------------------------------------------------------
  logic signed [31:0] imm_i_32;
  logic signed [31:0] imm_s_32;
  logic signed [31:0] imm_b_32;
  logic signed [31:0] imm_u_32;
  logic signed [31:0] imm_j_32;
  logic [DW-1:0] imm_i_value;
  logic [DW-1:0] imm_s;
  logic [DW-1:0] imm_b;
  logic [DW-1:0] imm_u;
  logic [DW-1:0] imm_j;

  assign imm_i_32 = {{20{instr32[31]}}, instr32[31:20]};
  assign imm_s_32 = {{20{instr32[31]}}, instr32[31:25], instr32[11:7]};
  assign imm_b_32 = {{19{instr32[31]}}, instr32[31], instr32[7], instr32[30:25], instr32[11:8], 1'b0};
  assign imm_u_32 = {instr32[31:12], 12'b0};
  assign imm_j_32 = {{11{instr32[31]}}, instr32[31], instr32[19:12], instr32[20], instr32[30:21], 1'b0};

  assign imm_i_value = DW'(imm_i_32);
  assign imm_s = DW'(imm_s_32);
  assign imm_b = DW'(imm_b_32);
  assign imm_u = DW'(imm_u_32);
  assign imm_j = DW'(imm_j_32);


  logic [DW-1:0] operand1, operand2, store_data, selected_imm;
  logic          use_rs1, use_rs2;
  logic          rf_write;
  alu_op_e       alu_op;
  branch_op_e    branch_op;
  jump_op_e      jump_op;
  logic          mem_req, mem_write, mem_unsigned;
  mem_size_e     mem_size;
  wb_sel_e       wb_sel;
  logic          muldiv_valid;
  muldiv_op_e    muldiv_op;
  logic          illegal_instr, ecall, ebreak;
  logic          is_mret, is_wfi;
  csr_pkt_t      csr_intent;
  id_ex_pkt_t    decoded_pkt;

  // Keep register addresses and store data as direct field connections.
  assign rf_rs1_raddr_o = rs1;
  assign rf_rs2_raddr_o = rs2;

  // Store data is meaningful only when mem_write is asserted.
  assign store_data = rf_rs2_rdata_i;

  // Immediate selection remains separate from control decoding.
  always_comb begin
    unique case (opcode)
      OPCODE_LUI, OPCODE_AUIPC: selected_imm = imm_u;
      OPCODE_JAL:               selected_imm = imm_j;
      OPCODE_BRANCH:            selected_imm = imm_b;
      OPCODE_STORE:             selected_imm = imm_s;
      default:                  selected_imm = imm_i_value; // LOAD, OP_IMM, JALR 等
    endcase
  end

  // Operand selection remains separate from control decoding.
  always_comb begin
    unique case (opcode)
      OPCODE_LUI:   operand1 = '0;
      OPCODE_AUIPC,
      OPCODE_JAL:   operand1 = DW'(pc);
      default:      operand1 = rf_rs1_rdata_i;
    endcase
  end

  always_comb begin
    // op2 选择逻辑
    unique case (opcode)
      OPCODE_OP, OPCODE_BRANCH: operand2 = rf_rs2_rdata_i;
      default:                  operand2 = selected_imm;
    endcase
  end


  // ============================================================
  // 主解码逻辑：只负责生成控制信号
  // ============================================================
  always_comb begin
    // --- 控制信号安全默认值 ---
    use_rs1       = 1'b0;
    use_rs2       = 1'b0;
    rf_write         = 1'b0;
    alu_op        = ALU_NONE;
    branch_op     = BR_NONE;
    jump_op       = JMP_NONE;
    mem_req       = 1'b0;
    mem_write        = 1'b0;
    mem_size      = MEM_SIZE_WORD;
    mem_unsigned  = 1'b0;
    wb_sel        = WB_NONE;
    muldiv_valid  = 1'b0;
    muldiv_op     = MULDIV_NONE;
    illegal_instr = 1'b0;
    ecall         = 1'b0;
    ebreak        = 1'b0;
    is_mret       = 1'b0;
    is_wfi        = 1'b0;
    csr_intent           = '0;

    unique case (opcode)
      // --------------------------------------------------------
      // LUI
      // --------------------------------------------------------
      OPCODE_LUI: begin
        rf_write  = 1'b1;
        alu_op = ALU_COPY_B; // op1=0, op2=imm, 透传op2即可
        wb_sel = WB_ALU;
      end

      // --------------------------------------------------------
      // AUIPC
      // --------------------------------------------------------
      OPCODE_AUIPC: begin
        rf_write  = 1'b1;
        alu_op = ALU_ADD;    // op1=pc, op2=imm
        wb_sel = WB_ALU;
      end

      // --------------------------------------------------------
      // JAL
      // --------------------------------------------------------
      OPCODE_JAL: begin
        rf_write   = 1'b1;
        jump_op = JMP_JAL;
        wb_sel  = WB_PC4;
      end

      // --------------------------------------------------------
      // JALR
      // --------------------------------------------------------
      OPCODE_JALR: begin
        if (funct3 == 3'b000) begin
          use_rs1 = 1'b1;
          rf_write   = 1'b1;
          jump_op = JMP_JALR;
          wb_sel  = WB_PC4;
        end else begin
          illegal_instr = 1'b1;
        end
      end

      // --------------------------------------------------------
      // Branch
      // --------------------------------------------------------
      OPCODE_BRANCH: begin
        use_rs1  = 1'b1;
        use_rs2  = 1'b1;
        unique case (funct3)
          FUNCT3_BEQ:  branch_op = BR_BEQ;
          FUNCT3_BNE:  branch_op = BR_BNE;
          FUNCT3_BLT:  branch_op = BR_BLT;
          FUNCT3_BGE:  branch_op = BR_BGE;
          FUNCT3_BLTU: branch_op = BR_BLTU;
          FUNCT3_BGEU: branch_op = BR_BGEU;
          default:     illegal_instr = 1'b1;
        endcase
      end

      // --------------------------------------------------------
      // Load
      // --------------------------------------------------------
      OPCODE_LOAD: begin
        use_rs1 = 1'b1;
        rf_write   = 1'b1;
        alu_op  = ALU_ADD;    // op1=rs1, op2=imm
        mem_req = 1'b1;
        wb_sel  = WB_MEM;

        unique case (funct3)
          FUNCT3_LB: begin
            mem_size     = MEM_SIZE_BYTE;
            mem_unsigned = 1'b0;
          end
          FUNCT3_LH: begin
            mem_size     = MEM_SIZE_HALF;
            mem_unsigned = 1'b0;
          end
          FUNCT3_LW: begin
            mem_size     = MEM_SIZE_WORD;
            mem_unsigned = 1'b0;
          end
          FUNCT3_LBU: begin
            mem_size     = MEM_SIZE_BYTE;
            mem_unsigned = 1'b1;
          end
          FUNCT3_LHU: begin
            mem_size     = MEM_SIZE_HALF;
            mem_unsigned = 1'b1;
          end
          default: begin
            rf_write         = 1'b0;
            mem_req       = 1'b0;
            wb_sel        = WB_NONE;
            use_rs1       = 1'b0;
            use_rs2       = 1'b0;
            illegal_instr = 1'b1;
          end
        endcase
      end

      // --------------------------------------------------------
      // Store
      // --------------------------------------------------------
      OPCODE_STORE: begin
        use_rs1 = 1'b1;
        use_rs2 = 1'b1;
        alu_op  = ALU_ADD;    // op1=rs1, op2=imm
        mem_req = 1'b1;
        mem_write  = 1'b1;

        unique case (funct3)
          FUNCT3_SB: mem_size = MEM_SIZE_BYTE;
          FUNCT3_SH: mem_size = MEM_SIZE_HALF;
          FUNCT3_SW: mem_size = MEM_SIZE_WORD;
          default: begin
            mem_req       = 1'b0;
            mem_write        = 1'b0;
            illegal_instr = 1'b1;
          end
        endcase
      end

      // --------------------------------------------------------
      // OP-IMM
      // --------------------------------------------------------
      OPCODE_OP_IMM: begin
        use_rs1 = 1'b1;
        rf_write   = 1'b1;
        wb_sel  = WB_ALU;

        unique case (funct3)
          FUNCT3_ADDI:  alu_op = ALU_ADD;
          FUNCT3_SLTI:  alu_op = ALU_SLT;
          FUNCT3_SLTIU: alu_op = ALU_SLTU;
          FUNCT3_XORI:  alu_op = ALU_XOR;
          FUNCT3_ORI:   alu_op = ALU_OR;
          FUNCT3_ANDI:  alu_op = ALU_AND;
          FUNCT3_SLLI: begin
            if (funct7 == FUNCT7_BASE) alu_op = ALU_SLL;
            else                       illegal_instr = 1'b1;
          end
          FUNCT3_SRI: begin
            if (funct7 == FUNCT7_BASE)      alu_op = ALU_SRL;
            else if (funct7 == FUNCT7_ALT)  alu_op = ALU_SRA;
            else                            illegal_instr = 1'b1;
          end
          default: illegal_instr = 1'b1;
        endcase
      end

      // --------------------------------------------------------
      // OP
      // --------------------------------------------------------
      OPCODE_OP: begin
        use_rs1 = 1'b1;
        use_rs2 = 1'b1;

        unique case (funct7)
          FUNCT7_BASE: begin
            rf_write  = 1'b1;
            wb_sel = WB_ALU;
            unique case (funct3)
              FUNCT3_ADD_SUB: alu_op = ALU_ADD;
              FUNCT3_SLL:     alu_op = ALU_SLL;
              FUNCT3_SLT:     alu_op = ALU_SLT;
              FUNCT3_SLTU:    alu_op = ALU_SLTU;
              FUNCT3_XOR:     alu_op = ALU_XOR;
              FUNCT3_SR:      alu_op = ALU_SRL;
              FUNCT3_OR:      alu_op = ALU_OR;
              FUNCT3_AND:     alu_op = ALU_AND;
              default:        illegal_instr = 1'b1;
            endcase
          end

          FUNCT7_ALT: begin
            rf_write  = 1'b1;
            wb_sel = WB_ALU;
            unique case (funct3)
              FUNCT3_ADD_SUB: alu_op = ALU_SUB;
              FUNCT3_SR:      alu_op = ALU_SRA;
              default:        illegal_instr = 1'b1;
            endcase
          end

          FUNCT7_MULDIV: begin
            rf_write        = 1'b1;
            wb_sel       = WB_MULDIV;
            muldiv_valid = 1'b1;
            unique case (funct3)
              3'b000: muldiv_op = MULDIV_MUL;
              3'b001: muldiv_op = MULDIV_MULH;
              3'b010: muldiv_op = MULDIV_MULHSU;
              3'b011: muldiv_op = MULDIV_MULHU;
              3'b100: muldiv_op = MULDIV_DIV;
              3'b101: muldiv_op = MULDIV_DIVU;
              3'b110: muldiv_op = MULDIV_REM;
              3'b111: muldiv_op = MULDIV_REMU;
              default: illegal_instr = 1'b1;
            endcase
          end
          default: illegal_instr = 1'b1;
        endcase
      end

      // --------------------------------------------------------
      // MISC-MEM (fence as NOP)
      // --------------------------------------------------------
      OPCODE_MISC_MEM: begin
        if (funct3 != 3'b000) illegal_instr = 1'b1;
      end

      // --------------------------------------------------------
      // SYSTEM
      // --------------------------------------------------------
      OPCODE_SYSTEM: begin
        if (instr32 == INST_ECALL) begin
          ecall = 1'b1;
        end else if (instr32 == INST_EBREAK) begin
          ebreak = 1'b1;
        end else if (instr32 == INST_MRET) begin
          is_mret = 1'b1;
        end else if (funct3 == 3'b000 && instr32[31:20] == 12'h105) begin
          // Retirement owns the architectural WFI wait transition.
          is_wfi = 1'b1;
        end else begin
          unique case (funct3)
            3'b001, // CSRRW
            3'b010, // CSRRS
            3'b011, // CSRRC
            3'b101, // CSRRWI
            3'b110, // CSRRSI
            3'b111: // CSRRCI
            begin
              rf_write    = 1'b1;
              wb_sel   = WB_CSR;
              csr_intent.valid = 1'b1;
              csr_intent.addr  = instr32[31:20];
              csr_intent.rd    = rd;
              unique case (funct3)
                3'b001: begin
                  csr_intent.write = 1'b1;
                  csr_intent.op    = CSR_OP_RW;
                  csr_intent.wdata = rf_rs1_rdata_i;
                  use_rs1   = 1'b1;
                end
                3'b010: begin
                  csr_intent.write = (instr32[19:15] != 5'd0);
                  csr_intent.op    = CSR_OP_RS;
                  csr_intent.wdata = rf_rs1_rdata_i;
                  use_rs1   = 1'b1;
                end
                3'b011: begin
                  csr_intent.write = (instr32[19:15] != 5'd0);
                  csr_intent.op    = CSR_OP_RC;
                  csr_intent.wdata = rf_rs1_rdata_i;
                  use_rs1   = 1'b1;
                end
                3'b101: begin
                  csr_intent.write = 1'b1;
                  csr_intent.op    = CSR_OP_RWI;
                  csr_intent.wdata = DW'(instr32[19:15]);
                end
                3'b110: begin
                  csr_intent.write = (instr32[19:15] != 5'd0);
                  csr_intent.op    = CSR_OP_RSI;
                  csr_intent.wdata = DW'(instr32[19:15]);
                end
                3'b111: begin
                  csr_intent.write = (instr32[19:15] != 5'd0);
                  csr_intent.op    = CSR_OP_RCI;
                  csr_intent.wdata = DW'(instr32[19:15]);
                end
                default: ;
              endcase
            end
            default: illegal_instr = 1'b1;
          endcase
        end
      end

      // --------------------------------------------------------
      // Unknown opcode
      // --------------------------------------------------------
      default: illegal_instr = 1'b1;
    endcase
  end

  // Construct one complete typed packet from the canonical bubble. This keeps
  // every unowned or future field side-effect safe without scattering default
  // assignments across independent continuous drivers.
  always_comb begin
    decoded_pkt = ID_EX_PKT_BUBBLE;
    decoded_pkt.valid    = pktd_i.valid;
    decoded_pkt.pc       = pc;
    decoded_pkt.instr    = instr;
    decoded_pkt.use_rs1  = use_rs1;
    decoded_pkt.use_rs2  = use_rs2;
    decoded_pkt.is_mret  = is_mret;
    decoded_pkt.is_wfi   = is_wfi;

    decoded_pkt.rf.we    = rf_write;
    decoded_pkt.rf.addr  = rd;

    decoded_pkt.ex_data.op1        = operand1;
    decoded_pkt.ex_data.op2        = operand2;
    decoded_pkt.ex_data.imm        = selected_imm;
    decoded_pkt.ex_data.store_data = store_data;

    decoded_pkt.ex_ctrl.alu_op       = alu_op;
    decoded_pkt.ex_ctrl.branch_op    = branch_op;
    decoded_pkt.ex_ctrl.jump_op      = jump_op;
    decoded_pkt.ex_ctrl.mem_req      = mem_req;
    decoded_pkt.ex_ctrl.mem_we       = mem_write;
    decoded_pkt.ex_ctrl.mem_size     = mem_size;
    decoded_pkt.ex_ctrl.mem_unsigned = mem_unsigned;
    decoded_pkt.ex_ctrl.wb_sel       = wb_sel;
    decoded_pkt.ex_ctrl.muldiv_valid = muldiv_valid;
    decoded_pkt.ex_ctrl.muldiv_op    = muldiv_op;

    decoded_pkt.exc.illegal_instr = illegal_instr;
    decoded_pkt.exc.ecall         = ecall;
    decoded_pkt.exc.ebreak        = ebreak;
    decoded_pkt.csr               = csr_intent;
  end

  // A fetch-time error means instr is replacement data, not an instruction.
  // Preserve only the valid fault identity and clear every normal data/control
  // field so bogus LOAD/STORE, redirect, CSR, MRET/WFI, or MULDIV encodings
  // cannot start work, create a false hazard, or hold the pipeline waiting.
  always_comb begin
    pktd_o = decoded_pkt;
    if (pktd_i.error) begin
      pktd_o = ID_EX_PKT_BUBBLE;
      pktd_o.valid = pktd_i.valid;
      pktd_o.pc = pktd_i.pc;
      pktd_o.exc.instr_access_fault = pktd_i.valid;
    end
  end


endmodule
`default_nettype wire
