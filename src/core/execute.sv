`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
module execute #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic          valid_i,
  input  logic [AW-1:0] pc_i,
  input  logic [DW-1:0] instr_i,
  input  logic [DW-1:0] op1_i,
  input  logic [DW-1:0] op2_i,
  input  logic [DW-1:0] store_data_i,
  // 送往 WB 阶段的写回信息
  output logic          wb_valid_o,
  output logic          wb_rf_wen_o,
  output logic [4:0]    wb_rf_waddr_o,
  output logic [DW-1:0] wb_alu_data_o,
  // load 写回控制
  output logic          wb_is_load_o,
  output logic [2:0]    wb_load_funct3_o,
  output logic [1:0]    wb_load_offset_o,
  // PC 重定向
  output logic          redirect_en_o,
  output logic [AW-1:0] redirect_pc_o,
  output logic          flush_req_o,
  // 同步 data RAM 请求
  output logic          dmem_ren_o,
  output logic          dmem_wen_o,
  output logic [DW/8-1:0] dmem_wstrb_o,
  output logic [AW-1:0] dmem_addr_o,
  output logic [DW-1:0] dmem_wdata_o
);
  logic [6:0] opcode;
  logic [4:0] rd;
  logic [2:0] funct3;
  logic [6:0] funct7;
  assign opcode = instr_i[6:0];
  assign rd     = instr_i[11:7];
  assign funct3 = instr_i[14:12];
  assign funct7 = instr_i[31:25];
  logic [DW-1:0] imm_b;
  assign imm_b = {{19{instr_i[31]}},
                  instr_i[31],
                  instr_i[7],
                  instr_i[30:25],
                  instr_i[11:8],
                  1'b0};
  logic equal;
  logic less_signed;
  logic less_unsigned;
  assign equal         = op1_i == op2_i;
  assign less_signed   = $signed(op1_i) < $signed(op2_i);
  assign less_unsigned = op1_i < op2_i;
  logic [AW-1:0] eff_addr;
  logic [1:0]    byte_offset;
  assign eff_addr    = op1_i[AW-1:0] + op2_i[AW-1:0];
  assign byte_offset = eff_addr[1:0];
  logic load_misaligned;
  logic store_misaligned;
  always_comb begin
    load_misaligned  = 1'b0;
    store_misaligned = 1'b0;
    if (opcode == OPCODE_LOAD) begin
      unique case (funct3)
        FUNCT3_LH,
        FUNCT3_LHU: load_misaligned = byte_offset[0];
        FUNCT3_LW:  load_misaligned = |byte_offset;
        default:    load_misaligned = 1'b0;
      endcase
    end
    if (opcode == OPCODE_STORE) begin
      unique case (funct3)
        FUNCT3_SH: store_misaligned = byte_offset[0];
        FUNCT3_SW: store_misaligned = |byte_offset;
        default:   store_misaligned = 1'b0;
      endcase
    end
  end
  always_comb begin
    wb_valid_o        = valid_i;
    wb_rf_wen_o       = 1'b0;
    wb_rf_waddr_o     = 5'd0;
    wb_alu_data_o     = '0;
    wb_is_load_o      = 1'b0;
    wb_load_funct3_o  = funct3;
    wb_load_offset_o  = byte_offset;
    redirect_en_o     = 1'b0;
    redirect_pc_o     = '0;
    flush_req_o       = 1'b0;
    dmem_ren_o        = 1'b0;
    dmem_wen_o        = 1'b0;
    dmem_wstrb_o      = '0;
    dmem_addr_o       = eff_addr;
    dmem_wdata_o      = '0;
    if (valid_i) begin
      unique case (opcode)
        OPCODE_OP_IMM: begin
          wb_rf_wen_o   = 1'b1;
          wb_rf_waddr_o = rd;
          unique case (funct3)
            FUNCT3_ADDI:  wb_alu_data_o = op1_i + op2_i;
            FUNCT3_SLTI:  wb_alu_data_o = less_signed   ? DW'(1) : '0;
            FUNCT3_SLTIU: wb_alu_data_o = less_unsigned ? DW'(1) : '0;
            FUNCT3_XORI:  wb_alu_data_o = op1_i ^ op2_i;
            FUNCT3_ORI:   wb_alu_data_o = op1_i | op2_i;
            FUNCT3_ANDI:  wb_alu_data_o = op1_i & op2_i;
            FUNCT3_SLLI: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i << instr_i[24:20];
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_SRI: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i >> instr_i[24:20];
              else if (funct7 == FUNCT7_ALT)
                wb_alu_data_o = $signed(op1_i) >>> instr_i[24:20];
              else
                wb_rf_wen_o = 1'b0;
            end
            default: wb_rf_wen_o = 1'b0;
          endcase
        end
        OPCODE_OP: begin
          wb_rf_wen_o   = 1'b1;
          wb_rf_waddr_o = rd;
          unique case (funct3)
            FUNCT3_ADD_SUB: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i + op2_i;
              else if (funct7 == FUN7_ALT)
                wb_alu_data_o = op1_i - op2_i;
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_SLL: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i << op2_i[4:0];
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_SLT: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = less_signed ? DW'(1) : '0;
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_SLTU: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = less_unsigned ? DW'(1) : '0;
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_XOR: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i ^ op2_i;
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_SR: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i >> op2_i[4:0];
              else if (funct7 == FUNCT7_ALT)
                wb_alu_data_o = $signed(op1_i) >>> op2_i[4:0];
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_OR: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i | op2_i;
              else
                wb_rf_wen_o = 1'b0;
            end
            FUNCT3_AND: begin
              if (funct7 == FUNCT7_BASE)
                wb_alu_data_o = op1_i & op2_i;
              else
                wb_rf_wen_o = 1'b0;
            end
            default: wb_rf_wen_o = 1'b0;
          endcase
        end
        OPCODE_LOAD: begin
          if (!load_misaligned) begin
            dmem_ren_o       = 1'b1;
            wb_rf_wen_o      = 1'b1;
            wb_rf_waddr_o    = rd;
            wb_is_load_o     = 1'b1;
            wb_load_funct3_o = funct3;
            wb_load_offset_o = byte_offset;
          end
        end
        OPCODE_STORE: begin
          if (!store_misaligned) begin
            dmem_wen_o = 1'b1;
            unique case (funct3)
              FUNCT3_SB: begin
                unique case (byte_offset)
                  2'd0: begin dmem_wstrb_o = 4'b0001; dmem_wdata_o = {24'h0, store_data_i[7:0]}; end
                  2'd1: begin dmem_wstrb_o = 4'b0010; dmem_wdata_o = {16'h0, store_data_i[7:0], 8'h0}; end
                  2'd2: begin dmem_wstrb_o = 4'b0100; dmem_wdata_o = {8'h0, store_data_i[7:0], 16'h0}; end
                  2'd3: begin dmem_wstrb_o = 4'b1000; dmem_wdata_o = {store_data_i[7:0], 24'h0}; end
                endcase
              end
              FUNCT3_SH: begin
                if (byte_offset[1] == 1'b0) begin
                  dmem_wstrb_o = 4'b0011;
                  dmem_wdata_o = {16'h0, store_data_i[15:0]};
                end
                else begin
                  dmem_wstrb_o = 4'b1100;
                  dmem_wdata_o = {store_data_i[15:0], 16'h0};
                end
              end
              FUNCT3_SW: begin
                dmem_wstrb_o = 4'b1111;
                dmem_wdata_o = store_data_i;
              end
              default: begin
                dmem_wen_o   = 1'b0;
                dmem_wstrb_o = '0;
              end
            endcase
          end
        end
        OPCODE_BRANCH: begin
          unique case (funct3)
            FUNCT3_BEQ:  redirect_en_o = equal;
            FUNCT3_BNE:  redirect_en_o = ~equal;
            FUNCT3_BLT:  redirect_en_o = less_signed;
            FUNCT3_BGE:  redirect_en_o = ~less_signed;
            FUNCT3_BLTU: redirect_en_o = less_unsigned;
            FUNCT3_BGEU: redirect_en_o = ~less_unsigned;
            default:     redirect_en_o = 1'b0;
          endcase
          redirect_pc_o = pc_i + imm_b[AW-1:0];
          flush_req_o   = redirect_en_o;
        end
        OPCODE_JAL: begin
          wb_rf_wen_o   = 1'b1;
          wb_rf_waddr_o = rd;
          wb_alu_data_o = pc_i + DW'(4);
          redirect_en_o = 1'b1;
          redirect_pc_o = pc_i + op2_i[AW-1:0];
          flush_req_o   = 1'b1;
        end
        OPCODE_JALR: begin
          wb_rf_wen_o   = 1'b1;
          wb_rf_waddr_o = rd;
          wb_alu_data_o = pc_i + DW'(4);
          redirect_en_o = 1'b1;
          redirect_pc_o = {eff_addr[AW-1:1], 1'b0};
          flush_req_o   = 1'b1;
        end
        OPCODE_LUI: begin
          wb_rf_wen_o   = 1'b1;
          wb_rf_waddr_o = rd;
          wb_alu_data_o = op2_i;
        end
        OPCODE_AUIPC: begin
          wb_rf_wen_o   = 1'b1;
          wb_rf_waddr_o = rd;
          wb_alu_data_o = op1_i + op2_i;
        end
        OPCODE_MISC_MEM,
        OPCODE_SYSTEM: begin
          // 当前阶段先按 NOP 处理。
        end
        default: begin
          wb_rf_wen_o = 1'b0;
        end
      endcase
    end
  end
endmodule
`default_nettype wire