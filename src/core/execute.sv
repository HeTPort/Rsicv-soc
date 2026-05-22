`timescale 1ns / 1ps
`include "define.sv"
module execute #(
  parameter AW = 32,
  parameter DW = 32
)(
  input  logic [AW-1:0] instr_addr,
  input  logic [DW-1:0] instr,
  input  logic [DW-1:0] op1,
  input  logic [DW-1:0] op2,
  input  logic [DW-1:0] store_data,
  output logic              wr_reg_en,
  output logic [4:0]        wr_reg_addr,
  output logic [DW-1:0]     wr_reg_data,
  output logic              jump_en,
  output logic [AW-1:0]     jump_addr,
  output logic              jump_hold,
  output logic              mem_wr_en,
  output logic [DW/8-1:0]   mem_wr_strb,
  output logic [AW-1:0]     mem_addr,
  output logic [DW-1:0]     mem_wdata,
  input  logic [DW-1:0]     mem_rdata
);
  logic [6:0] opcode;
  logic [4:0] rd;
  logic [2:0] func3;
  logic [6:0] func7;
  logic [DW-1:0] imm_b;
  logic equal, less_signed, less_unsigned;
  logic [DW-1:0] sr_shift, sr_shift_mask;
  logic [AW-1:0] eff_addr;
  logic [1:0]    byte_offset;
  logic [7:0]    load_byte;
  logic [15:0]   load_half;
  assign opcode        = instr[6:0];
  assign rd            = instr[11:7];
  assign func3         = instr[14:12];
  assign func7         = instr[31:25];
  assign imm_b         = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
  assign equal         = (op1 == op2);
  assign less_signed   = ($signed(op1) < $signed(op2));
  assign less_unsigned = (op1 < op2);
  assign sr_shift      = op1 >> op2[4:0];
  assign sr_shift_mask = {DW{1'b1}} >> op2[4:0];
  assign eff_addr      = op1 + op2;
  assign byte_offset   = eff_addr[1:0];
  always_comb begin
    case (byte_offset)
      2'd0: load_byte = mem_rdata[7:0];
      2'd1: load_byte = mem_rdata[15:8];
      2'd2: load_byte = mem_rdata[23:16];
      2'd3: load_byte = mem_rdata[31:24];
      default: load_byte = mem_rdata[7:0];
    endcase
  end
  always_comb begin
    case (byte_offset[1])
      1'b0: load_half = mem_rdata[15:0];
      1'b1: load_half = mem_rdata[31:16];
      default: load_half = mem_rdata[15:0];
    endcase
  end
  always_comb begin
    wr_reg_en   = 1'b0;
    wr_reg_addr = 5'd0;
    wr_reg_data = '0;
    jump_en     = 1'b0;
    jump_addr   = '0;
    jump_hold   = 1'b0;
    mem_wr_en   = 1'b0;
    mem_wr_strb = '0;
    mem_addr    = eff_addr;
    mem_wdata   = '0;
    unique case (opcode)
      `INST_TYPE_I: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        unique case (func3)
          `INST_ADDI:  wr_reg_data = op1 + op2;
          `INST_SLTI:  wr_reg_data = less_signed   ? 32'd1 : 32'd0;
          `INST_SLTIU:_reg_data = less_unsigned ? 32'd1 : 32'd0;
          `INST_XORI:  wr_reg_data = op1 ^ op2;
          `INST_ORI:   wr_reg_data = op1 | op2;
          `INST_ANDI:  wr_reg_data = op1 & op2;
          `INST_SLLI:  wr_reg_data = op1 << op2[4:0];
          `INST_SRI: begin
            if (instr[30])
              wr_reg_data = (sr_shift & sr_shift_mask) | ({DW{op1[DW-1]}} & (~sr_shift_mask));
            else
              wr_reg_data = op1 >> op2[4:0];
          end
          default: begin
            wr_reg_en = 1'b0;
          end
        endcase
      end
      `INST_TYPE_R_M: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        unique case (func3)
          `INST_ADD_SUB: wr_reg_data = (func7 == 7'b0100000) ? (op1 - op2) : (op1 + op2);
          `INST_SLL:     wr_reg_data = op1 << op2[4:0];
          `INST_SLT:     wr_reg_data = less_signed   ? 32'd1 : 32'd0;
          `INST_SLTU:    wr_reg_data = less_unsigned ? 32'd1 : 32'd0;
          `INST_XOR:     wr_reg_data = op1 ^ op2;
          `INST_SR: begin
            if (func7 == 7'b0100000)
              wr_reg_data = (sr_shift & sr_shift_mask) | ({DW{op1[DW-1]}} & (~sr_shift_mask));
            else
              wr_reg_data = op1 >> op2[4:0];
          end
          `INST_OR:      wr_reg_data = op1 | op2;
          `INST_AND:     wr_reg_data = op1 & op2;
          default: wr_reg_en = 1'b0;
        endcase
      end
      `INST_TYPE_L: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        unique case (func3)
          `INST_LB:  wr_reg_data = {{24{load_byte[7]}}, load_byte};
          `INST_LH:  wr_reg_data = {{16{load_half[15]}}, load_half};
          `INST_LW:  wr_reg_data = mem_rdata;
          `INST_LBU: wr_reg_data = {24'h0, load_byte};
          `INST_LHU: wr_reg_data = {16'h0, load_half};
          default: wr_reg_en = 1'b0;
        endcase
      end
      `INST_TYPE_S: begin
        mem_wr_en = 1'b1;
        unique case (func3)
          `INST_SB: begin
            case (byte_offset)
              2'd0: begin mem_wr_strb = 4'b0001; mem_wdata = {24'h0, store_data[7:0]}; end
              2'd1: begin mem_wr_strb = 4'b0010; mem_wdata = {16'h0, store_data[7:0], 8'h0}; end
              2'd2: begin mem_wr_strb = 4'b0100; mem_wdata = {8'h0, store_data[7:0], 16'h0}; end
              2'd3: begin mem_wr_strb = 4'b1000; mem_wdata = {store_data[7:0], 24'h0}; end
            endcase
          end
          `INST_SH: begin
            if (byte_offset[1] == 1'b0) begin
              mem_wr_strb = 4'b0011;
              mem_wdata   = {16'h0, store_data[15:0]};
            end else begin
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
          end
        endcase
      end
      `INST_TYPE_B: begin
        unique case (func3)
          `INST_BEQ:  begin jump_en = equal;         jump_addr = instr_addr + imm_b; end
          `INST_BNE:  begin jump_en = ~equal;        jump_addr = instr_addr + imm_b; end
          `INST_BLT:  begin jump_en = less_signed;   jump_addr = instr_addr + imm_b; end
          `INST_BGE:  begin jump_en = ~less_signed;  jump_addr = instr_addr + imm_b; end
          `INST_BLTU: begin jump_en = less_unsigned; jump_addr = instr_addr + imm_b; end
          `INST_BGEU: begin jump_en = ~less_unsigned;jump_addr = instr_addr + imm_b; end
          default: begin end
        endcase
      end
      `INST_TYPE_JAL: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = instr_addr + 32'd4;
        jump_en     = 1'b1;
        jump_addr   = instr_addr + op2;
      end
      `INST_TYPE_JALR: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = instr_addr + 32'd4;
        jump_en     = 1'b1;
        jump_addr   = (op1 + op2) & 32'hffff_fffe;
      end
      `INST_LUI: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = op2;
      end
      `INST_AUIPC: begin
        wr_reg_en   = 1'b1;
        wr_reg_addr = rd;
        wr_reg_data = op1 + op2;
      end
      default: begin end
    endcase
  end
endmodule