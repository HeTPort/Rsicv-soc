`timescale 1ns / 1ps
`include "define.sv"
module execute #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic [AW-1:0]       instr_addr,
  input  logic [DW-1:0]       instr,
  input  logic [DW-1:0]       op1,
  input  logic [DW-1:0]       op2,
  input  logic [DW-1:0]       store_data,
  // write back to regfile
  output logic                wr_reg_en,
  output logic [4:0]          wr_reg_addr,
  output logic [DW-1:0]       wr_reg_data,
  // control-flow redirect
  output logic                jump_en,
  output logic [AW-1:0]       jump_addr,
  // flush request for younger instructions in pipeline
  output logic                jump_hold,
  // data memory interface
  output logic                mem_wr_en,
  output logic [DW/8-1:0]     mem_wr_strb,
  output logic [AW-1:0]       mem_addr,
  output logic [DW-1:0]       mem_wdata,
  input  logic [DW-1:0]       mem_rdata
);
  // =========================================================
  // instruction fields
  // =========================================================
  logic [6:0]  opcode;
  logic [4:0]  rd;
  logic [2:0]  func3;
  logic [6:0]  func7;
  // branch immediate
  logic [DW-1:0] imm_b;
  // compare results
  logic equal;
  logic less_signed;
  logic less_unsigned;
  // shift helper
  logic [DW-1:0] sr_shift;
  logic [DW-1:0] sr_shift_mask;
  // effective address
  logic [AW-1:0] eff_addr;
  logic [1:0]    byte_offset;
  // load extraction helper
  logic [7:0]    load_byte;
  logic [15:0]   load_half;
  // =========================================================
  // decode fields
  // =========================================================
  assign opcode = instr[6:0];
  assign rd     = instr[11:7];
  assign func3  = instr[14:12];
  assign func7  = instr[31:25];
  // B-type immediate:
  // imm[12|10:5|4:1|11|0]
  assign imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  // compare
  assign equal         = (op1 == op2);
  assign less_signed   = ($signed(op1) < $signed(op2));
  assign less_unsigned = (op1 < op2);
  // shift helper
  assign sr_shift      = op1 >> op2[4:0];
  assign sr_shift_mask = {DW{1'b1}} >> op2[4:0];
  // effective memory address
  assign eff_addr    = op1 + op2;
  assign byte_offset = eff_addr[1:0];
  // memory address output
  assign mem_addr = eff_addr;
  // =========================================================
  // load data extraction
  // 当前 data_ram 为 32-bit word 读口，因此按 byte_offset 选字节/半字
  // =========================================================
  always_comb begin
    unique case (byte_offset)
      2'd0:    load_byte = mem_rdata[7:0];
      2'd1:    load_byte = mem_rdata[15:8];
      2'd2:    load_byte = mem_rdata[23:16];
      2'd3:    load_byte = mem_rdata[31:24];
      default: load_byte = mem_rdata[7:0];
    endcase
  end
  always_comb begin
    unique case (byte_offset[1])
      1'b0:    load_half = mem_rdata[15:0];
      1'b1:    load_half = mem_rdata[31:16];
      default: load_half = mem_rdata[15:0];
    endcase
  end
  // =========================================================
  // main execute logic
  // =========================================================
  always_comb begin
    // -------------------------------------------------------
    // defaults
    // -------------------------------------------------------
    wr_reg_en   = 1'b0;
    wr_reg_addr = 5'd0;
    wr_reg_data = '0;
    jump_en     = 1'b0;
    jump_addr   = '0;
    jump_hold   = 1'b0;
    mem_wr_en   = 1'b0;
    mem_wr_strb = '0;
    mem_wdata   = '0;
    // -------------------------------------------------------
    // execute by opcode
    // -------------------------------------------------------
    unique case (opcode)
      // =====================================================
      // OP-IMM
      // =====================================================
      `INST_TYPE_I: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        unique case (func3)
          `INST_ADDI: begin
            wr_reg_data = op1 + op2;
          end
          `INST_SLTI: begin
            wr_reg_data = less_signed ? DW'(1) : DW'(0);
          end
          // 修复原代码中的拼写 bug
          `INST_SLTIU: begin
            wr_reg_data = less_unsigned ? DW'(1) : DW'(0);
          end
          `INST_XORI: begin
            wr_reg_data = op1 ^ op2;
          end
          `INST_ORI: begin
            wr_reg_data = op1 | op2;
          end
          `INST_ANDI: begin
            wr_reg_data = op1 & op2;
          end
          `INST_SLLI: begin
            wr_reg_data = op1 << op2[4:0];
          end
          `INST_SRI: begin
            // instr[30] = 0 -> SRLI
            // instr[30] = 1 -> SRAI
            if (instr[30]) begin
              wr_reg_data = (sr_shift & sr_shift_mask) |
                            ({DW{op1[DW-1]}} & (~sr_shift_mask));
            end
            else begin
              wr_reg_data = op1 >> op2[4:0];
            end
          end
          default: begin
            wr_reg_en   = 1'b0;
            wr_reg_addr = 5'd0;
            wr_reg_data = '0;
          end
        endcase
      end
      // =====================================================
      // OP
      // =====================================================
      `INST_TYPE_R_M: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        unique case (func3)
          `INST_ADD_SUB: begin
            if (func7 == 7'b0100000)
              wr_reg_data = op1 - op2; // SUB
            else
              wr_reg_data = op1 + op2; // ADD
          end
          `INST_SLL: begin
            wr_reg_data = op1 << op2[4:0];
          end
          `INST_SLT: begin
            wr_reg_data = less_signed ? DW'(1) : DW'(0);
          end
          `INST_SLTU: begin
            wr_reg_data = less_unsigned ? DW'(1) : DW'(0);
          end
          `INST_XOR: begin
            wr_reg_data = op1 ^ op2;
          end
          `INST_SR: begin
            if (func7 == 7'b0100000) begin
              wr_reg_data = (sr_shift & sr_shift_mask) |
                            ({DW{op1[DW-1]}} & (~sr_shift_mask));
            end
            else begin
              wr_reg_data = op1 >> op2[4:0];
            end
          end
          `INST_OR: begin
            wr_reg_data = op1 | op2;
          end
          `INST_AND: begin
            wr_reg_data = op1 & op2;
          end
          default: begin
            wr_reg_en   = 1'b0;
            wr_reg_addr = 5'd0;
            wr_reg_data = '0;
          end
        endcase
      end
      // =====================================================
      // LOAD
      // =====================================================
      `INST_TYPE_L: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        unique case (func3)
          `INST_LB: begin
            wr_reg_data = {{24{load_byte[7]}}, load_byte};
          end
          `INST_LH: begin
            wr_reg_data = {{16{load_half[15]}}, load_half};
          end
          `INST_LW: begin
            wr_reg_data = mem_rdata;
          end
          `INST_LBU: begin
            wr_reg_data = {24'h0, load_byte};
          end
          `INST_LHU: begin
            wr_reg_data = {16'h0, load_half};
          end
          default: begin
            wr_reg_en   = 1'b0;
            wr_reg_addr = 5'd0;
            wr_reg_data = '0;
          end
        endcase
      end
      // =====================================================
      // STORE
      // =====================================================
      `INST_TYPE_S: begin
        mem_wr_en = 1'b1;
        unique case (func3)
          `INST_SB: begin
            unique case (byte_offset)
              2'd0: begin
                mem_wr_strb = 4'b0001;
                mem_wdata   = {24'h0, store_data[7:0]};
              end
              2'd1: begin
                mem_wr_strb = 4'b0010;
                mem_wdata   = {16'h0, store_data[7:0], 8'h0};
              end
              2'd2: begin
                mem_wr_strb = 4'b0100;
                mem_wdata   = {8'h0, store_data[7:0], 16'h0};
              end
              2'd3: begin
                mem_wr_strb = 4'b1000;
                mem_wdata   = {store_data[7:0], 24'h0};
              end
              default: begin
                mem_wr_strb = 4'b0000;
                mem_wdata   = '0;
              end
            endcase
          end
          `INST_SH: begin
            if (byte_offset[1] == 1'b0) begin
              mem_wr_strb = 4'b0011;
              mem_wdata   = {16'h0, store_data[15:0]};
            end
            else begin
              mem_wr_strb = 4'b1100;
              mem_wdata   = {store_data[15:0], 16'h0};
            end
          end
          `INST_SW: begin
            mem_wr_strb = 4'b1111;
            mem_wdata   = store_data;
          end
          default: begin
            mem_wr_en   = 1'b0;
            mem_wr_strb = '0;
            mem_wdata   = '0;
          end
        endcase
      end
      // =====================================================
      // BRANCH
      // branch taken 时：
      //   1) jump_en   = 1, 让 PC 重定向
      //   2) jump_hold = 1, 请求冲刷前面年轻指令
      // =====================================================
      `INST_TYPE_B: begin
        unique case (func3)
          `INST_BEQ: begin
            jump_en   = equal;
            jump_addr = instr_addr + imm_b;
          end
          `INST_BNE: begin
            jump_en   = ~equal;
            jump_addr = instr_addr + imm_b;
          end
          `INST_BLT: begin
            jump_en   = less_signed;
            jump_addr = instr_addr + imm_b;
          end
          `INST_BGE: begin
            jump_en   = ~less_signed;
            jump_addr = instr_addr + imm_b;
          end
          `INST_BLTU: begin
            jump_en   = less_unsigned;
            jump_addr = instr_addr + imm_b;
          end
          `INST_BGEU: begin
            jump_en   = ~less_unsigned;
            jump_addr = instr_addr + imm_b;
          end
          default: begin
            jump_en   = 1'b0;
            jump_addr = '0;
          end
        endcase
        // branch 只有在真正跳转成立时才需要 flush
        jump_hold = jump_en;
      end
      // =====================================================
      // JAL
      // 无条件跳转，一定 redirect + flush
      // =====================================================
      `INST_TYPE_JAL: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = instr_addr + DW'(32'd4);
        jump_en     = 1'b1;
        jump_addr   = instr_addr + op2;
        jump_hold   = 1'b1;
      end
      // =====================================================
      // JALR
      // 无条件跳转，一定 redirect + flush
      // =====================================================
      `INST_TYPE_JALR: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = instr_addr + DW'(32'd4);
        jump_en     = 1'b1;
        jump_addr   = (op1 + op2) & AW'(32'hffff_fffe);
        jump_hold   = 1'b1;
      end
      // =====================================================
      // LUI
      // =====================================================
      `INST_LUI: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = op2;
      end
      // =====================================================
      // AUIPC
      // =====================================================
      `INST_AUIPC: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = op1 + op2;
      end
      // =====================================================
      // default / unsupported
      // =====================================================
      default: begin
        wr_reg_en   = 1'b0;
        wr_reg_addr = 5'd0;
        wr_reg_data = '0;
        jump_en     = 1'b0;
        jump_addr   = '0;
        jump_hold   = 1'b0;
        mem_wr_en   = 1'b0;
        mem_wr_strb = '0;
        mem_wdata   = '0;
      end
    endcase
  end
endmodule