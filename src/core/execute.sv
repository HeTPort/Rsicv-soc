`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
// ============================================================
// Module: execute
// Description:
//   RV32IM execute stage.
//
// Responsibilities:
//   - Execute ALU operation according to alu_op_i.
//   - Evaluate branch condition according to branch_op_i.
//   - Generate jump/branch redirect.
//   - Generate load/store memory request.
//   - Generate store byte enable and shifted write data.
//   - Execute RV32M multiply/divide operations.
//   - Check load/store alignment.
//   - Propagate illegal/ecall/ebreak information.
//
// Important:
//   - This module does not perform full instruction decode.
//   - instr_i is kept only for debug/exception reporting.
//   - Main behavior is controlled by decode-generated signals.
//
// RV32M notes:
//   - Current implementation is combinational.
//   - Division by zero and signed overflow follow RISC-V spec.
//   - Future multi-cycle mul/div can replace the combinational
//     logic and assert ex_stall_o at top level.
// ============================================================
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
  input  logic [4:0]    rd_i,
  input  logic          rf_we_i,
  input  logic [DW-1:0] imm_i,
  input  alu_op_e       alu_op_i,
  input  branch_op_e    branch_op_i,
  input  jump_op_e      jump_op_i,
  input  logic          mem_req_i,
  input  logic          mem_we_i,
  input  mem_size_e     mem_size_i,
  input  logic          mem_unsigned_i,
  input  wb_sel_e       wb_sel_i,
  input  logic          muldiv_valid_i,
  input  muldiv_op_e    muldiv_op_i,
  input  logic          illegal_instr_i,
  input  logic          ecall_i,
  input  logic          ebreak_i,
  // Writeback information
  output logic          wb_valid_o,
  output logic          wb_rf_wen_o,
  output logic [4:0]    wb_rf_waddr_o,
  output wb_sel_e       wb_sel_o,
  output logic [DW-1:0] wb_alu_data_o,
  output logic [DW-1:0] wb_pc4_data_o,
  output mem_size_e     wb_mem_size_o,
  output logic          wb_mem_unsigned_o,
  output logic [1:0]    wb_load_offset_o,
  // Exception/halt information propagated to WB/top
  output logic          wb_illegal_instr_o,
  output logic          wb_ecall_o,
  output logic          wb_ebreak_o,
  output logic          wb_mem_misaligned_o,
  // PC redirect
  output logic          redirect_en_o,
  output logic [AW-1:0] redirect_pc_o,
  output logic          flush_req_o,
  // Data memory request
  output logic            dmem_ren_o,
  output logic            dmem_wen_o,
  output logic [DW/8-1:0] dmem_wstrb_o,
  output logic [AW-1:0]   dmem_addr_o,
  output logic [DW-1:0]   dmem_wdata_o
);
  localparam int BYTE_NUM = DW / 8;
  localparam int SHAMT_W  = (DW == 64) ? 6 : 5;
  // Keep instr_i referenced for debug-oriented flows.
  logic [DW-1:0] instr_dbg_unused;
  assign instr_dbg_unused = instr_i;
  // ------------------------------------------------------------
  // Common derived values
  // ------------------------------------------------------------
  logic [AW-1:0] eff_addr;
  logic [1:0]    byte_offset;
  assign eff_addr    = op1_i[AW-1:0] + imm_i[AW-1:0];
  assign byte_offset = eff_addr[1:0];
  logic [DW-1:0] pc4_data;
  assign pc4_data = DW'(pc_i) + DW'(4);
  // ------------------------------------------------------------
  // ALU
  // ------------------------------------------------------------
  logic [DW-1:0] alu_result;
  always_comb begin
    alu_result = '0;
    unique case (alu_op_i)
      ALU_NONE:   alu_result = '0;
      ALU_ADD:    alu_result = op1_i + op2_i;
      ALU_SUB:    alu_result = op1_i - op2_i;
      ALU_SLL:    alu_result = op1_i << op2_i[SHAMT_W-1:0];
      ALU_SLT:    alu_result = ($signed(op1_i) < $signed(op2_i)) ? DW'(1) : '0;
      ALU_SLTU:   alu_result = (op1_i < op2_i) ? DW'(1) : '0;
      ALU_XOR:    alu_result = op1_i ^ op2_i;
      ALU_SRL:    alu_result = op1_i >> op2_i[SHAMT_W-1:0];
      ALU_SRA:    alu_result = $signed(op1_i) >>> op2_i[SHAMT_W-1:0];
      ALU_OR:     alu_result = op1_i | op2_i;
      ALU_AND:    alu_result = op1_i & op2_i;
      ALU_COPY_B: alu_result = op2_i;
      default:    alu_result = '0;
    endcase
  end
  // ------------------------------------------------------------
  // Branch compare
  // ------------------------------------------------------------
  logic branch_taken;
  always_comb begin
    branch_taken = 1'b0;
    unique case (branch_op_i)
      BR_NONE: branch_taken = 1'b0;
      BR_BEQ:  branch_taken = (op1_i == op2_i);
      BR_BNE:  branch_taken = (op1_i != op2_i);
      BR_BLT:  branch_taken = ($signed(op1_i) < $signed(op2_i));
      BR_BGE:  branch_taken = ($signed(op1_i) >= $signed(op2_i));
      BR_BLTU: branch_taken = (op1_i < op2_i);
      BR_BGEU: branch_taken = (op1_i >= op2_i);
      default: branch_taken = 1'b0;
    endcase
  end
  // ------------------------------------------------------------
  // RV32M combinational multiply/divide
  // ------------------------------------------------------------
  logic signed [DW-1:0] signed_op1;
  logic signed [DW-1:0] signed_op2;
  assign signed_op1 = signed'(op1_i);
  assign signed_op2 = signed'(op2_i);
  logic signed [(2*DW)-1:0] mul_op1_ss;
  logic signed [(2*DW)-1:0] mul_op2_ss;
  logic signed [(2*DW)-1:0] mul_op1_su;
  logic signed [(2*DW)-1:0] mul_op2_su;
  logic        [(2*DW)-1:0] mul_op1_uu;
  logic        [(2*DW)-1:0] mul_op2_uu;
  logic signed [(2*DW)-1:0] product_ss;
  logic signed [(2*DW)-1:0] product_su;
  logic        [(2*DW)-1:0] product_uu;
  assign mul_op1_ss = {{DW{op1_i[DW-1]}}, op1_i};
  assign mul_op2_ss = {{DW{op2_i[DW-1]}}, op2_i};
  assign mul_op1_su = {{DW{op1_i[DW-1]}}, op1_i};
  assign mul_op2_su = {DW'(0), op2_i};
  assign mul_op1_uu = {DW'(0), op1_i};
  assign mul_op2_uu = {DW'(0), op2_i};
  assign product_ss = mul_op1_ss * mul_op2_ss;
  assign product_su = mul_op1_su * mul_op2_su;
  assign product_uu = mul_op1_uu * mul_op2_uu;
  logic [DW-1:0] muldiv_result;
  logic          div_by_zero;
  logic          div_overflow;
  assign div_by_zero = (op2_i == '0);
  assign div_overflow =
      (op1_i == {1'b1, {(DW-1){1'b0}}}) &&
      (op2_i == {DW{1'b1}});
  always_comb begin
    muldiv_result = '0;
    unique case (muldiv_op_i)
      MULDIV_NONE: begin
        muldiv_result = '0;
      end
      MULDIV_MUL: begin
        muldiv_result = product_ss[DW-1:0];
      end
      MULDIV_MULH: begin
        muldiv_result = product_ss[(2*DW)-1:DW];
      end
      MULDIV_MULHSU: begin
        muldiv_result = product_su[(2*DW)-1:DW];
      end
      MULDIV_MULHU: begin
        muldiv_result = product_uu[(2*DW)-1:DW];
      end
      MULDIV_DIV: begin
        if (div_by_zero) begin
          muldiv_result = {DW{1'b1}};
        end
        else if (div_overflow) begin
          muldiv_result = {1'b1, {(DW-1){1'b0}}};
        end
        else begin
          muldiv_result = DW'($signed(signed_op1) / $signed(signed_op2));
        end
      end
      MULDIV_DIVU: begin
        if (div_by_zero) begin
          muldiv_result = {DW{1'b1}};
        end
        else begin
          muldiv_result = op1_i / op2_i;
        end
      end
      MULDIV_REM: begin
        if (div_by_zero) begin
          muldiv_result = op1_i;
        end
        else if (div_overflow) begin
          muldiv_result = '0;
        end
        else begin
          muldiv_result = DW'($signed(signed_op1) % $signed(signed_op2));
        end
      end
      MULDIV_REMU: begin
        if (div_by_zero) begin
          muldiv_result = op1_i;
        end
        else begin
          muldiv_result = op1_i % op2_i;
        end
      end
      default: begin
        muldiv_result = '0;
      end
    endcase
  end
  // ------------------------------------------------------------
  // Memory alignment check
  // ------------------------------------------------------------
  logic mem_misaligned;
  always_comb begin
    mem_misaligned = 1'b0;
    if (mem_req_i) begin
      unique case (mem_size_i)
        MEM_SIZE_BYTE: mem_misaligned = 1'b0;
        MEM_SIZE_HALF: mem_misaligned = byte_offset[0];
        MEM_SIZE_WORD: mem_misaligned = |byte_offset;
        default:       mem_misaligned = 1'b1;
      endcase
    end
  end
  // ------------------------------------------------------------
  // Store byte enable and shifted write data
  // ------------------------------------------------------------
  always_comb begin
    dmem_wstrb_o = '0;
    dmem_wdata_o = '0;
    if (valid_i && mem_req_i && mem_we_i && !mem_misaligned &&
        !illegal_instr_i && !ecall_i && !ebreak_i) begin
      unique case (mem_size_i)
        MEM_SIZE_BYTE: begin
          dmem_wstrb_o[byte_offset] = 1'b1;
          dmem_wdata_o[8*byte_offset +: 8] = store_data_i[7:0];
        end
        MEM_SIZE_HALF: begin
          if (byte_offset[1] == 1'b0) begin
            dmem_wstrb_o[1:0] = 2'b11;
            dmem_wdata_o[15:0] = store_data_i[15:0];
          end
          else begin
            dmem_wstrb_o[3:2] = 2'b11;
            dmem_wdata_o[31:16] = store_data_i[15:0];
          end
        end
        MEM_SIZE_WORD: begin
          dmem_wstrb_o = {BYTE_NUM{1'b1}};
          dmem_wdata_o = store_data_i;
        end
        default: begin
          dmem_wstrb_o = '0;
          dmem_wdata_o = '0;
        end
      endcase
    end
  end
  // ------------------------------------------------------------
  // Main output control
  // ------------------------------------------------------------
  logic exception_like;
  assign exception_like =
      illegal_instr_i |
      ecall_i |
      ebreak_i |
      mem_misaligned;
  always_comb begin
    wb_valid_o          = valid_i;
    wb_rf_wen_o         = 1'b0;
    wb_rf_waddr_o       = rd_i;
    wb_sel_o            = wb_sel_i;
    wb_alu_data_o       = alu_result;
    wb_pc4_data_o       = pc4_data;
    wb_mem_size_o       = mem_size_i;
    wb_mem_unsigned_o   = mem_unsigned_i;
    wb_load_offset_o    = byte_offset;
    wb_illegal_instr_o  = valid_i && illegal_instr_i;
    wb_ecall_o          = valid_i && ecall_i;
    wb_ebreak_o         = valid_i && ebreak_i;
    wb_mem_misaligned_o = valid_i && mem_misaligned;
    redirect_en_o       = 1'b0;
    redirect_pc_o       = '0;
    flush_req_o         = 1'b0;
    dmem_ren_o          = 1'b0;
    dmem_wen_o          = 1'b0;
    dmem_addr_o         = eff_addr;
    if (valid_i && !exception_like) begin
      // Writeback enable
      wb_rf_wen_o = rf_we_i;
      // MULDIV result currently reuses wb_alu_data_o path.
      if (muldiv_valid_i && wb_sel_i == WB_MULDIV) begin
        wb_alu_data_o = muldiv_result;
      end
      // Branch redirect
      if (branch_taken) begin
        redirect_en_o = 1'b1;
        redirect_pc_o = pc_i + imm_i[AW-1:0];
        flush_req_o   = 1'b1;
      end
      // Jump redirect
      unique case (jump_op_i)
        JMP_NONE: begin
          // no jump
        end
        JMP_JAL: begin
          redirect_en_o = 1'b1;
          redirect_pc_o = pc_i + imm_i[AW-1:0];
          flush_req_o   = 1'b1;
        end
        JMP_JALR: begin
          redirect_en_o = 1'b1;
          redirect_pc_o = {eff_addr[AW-1:1], 1'b0};
          flush_req_o   = 1'b1;
        end
        default:begin
          redirect_en_o = 1'b0;
          redirect_pc_o = '0;
          flush_req_o   = 1'b0;
        end
      endcase
      // Memory request
      if (mem_req_i) begin
        dmem_ren_o = !mem_we_i;
        dmem_wen_o = mem_we_i;
      end
    end
    else begin
      wb_rf_wen_o = 1'b0;
      wb_sel_o    = WB_NONE;
    end
  end
`ifndef SYNTHESIS
  always_comb begin
    if (valid_i && mem_misaligned) begin
      // Combinational warning intentionally avoided here to prevent
      // repeated messages in some simulators. Detailed check can be
      // added as sequential assertion in top/testbench if desired.
    end
  end
`endif
endmodule
`default_nettype wire