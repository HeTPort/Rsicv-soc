`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: execute
// Description:
//   RV32IM execute stage (memory interaction moved to LSU).
// ============================================================
module execute #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  id_ex_pkt_t   pkt_exe_i,

  // LSU feedback: misalignment result (computed in LSU)
  input  logic          mem_misaligned_i,

  // CSR feedback
  input  logic [DW-1:0] csr_rdata_i,
  input  logic [AW-1:0] mepc_i,

  // 横向输出信号
  output logic          redirect_en_o,
  output logic [AW-1:0] redirect_pc_o,
  output logic          flush_req_o,

  // 输出结构体
  output ex_wb_pkt_t   pkt_exe_o
);
  localparam int SHAMT_W = (DW == 64) ? 6 : 5;

  logic          valid_i;
  logic [AW-1:0] pc_i;
  logic [DW-1:0] instr_i, op1_i, op2_i, store_data_i, imm_i;
  logic [4:0]    rd_i;
  logic          rf_we_i;
  alu_op_e       alu_op_i;
  branch_op_e    branch_op_i;
  jump_op_e      jump_op_i;
  logic          mem_req_i, mem_we_i, mem_unsigned_i;
  mem_size_e     mem_size_i;
  wb_sel_e       wb_sel_i;
  logic          muldiv_valid_i;
  muldiv_op_e    muldiv_op_i;
  logic          illegal_instr_i, ecall_i, ebreak_i;
  logic          is_mret_i, is_wfi_i;
  csr_pkt_t      csr_i;

  assign valid_i         = pkt_exe_i.valid;
  assign pc_i            = pkt_exe_i.pc;
  assign instr_i         = pkt_exe_i.instr;
  assign op1_i           = pkt_exe_i.ex_data.op1;
  assign op2_i           = pkt_exe_i.ex_data.op2;
  assign store_data_i    = pkt_exe_i.ex_data.store_data;
  assign imm_i           = pkt_exe_i.ex_data.imm;
  assign rd_i            = pkt_exe_i.rf.addr;
  assign rf_we_i         = pkt_exe_i.rf.we;
  assign alu_op_i        = pkt_exe_i.ex_ctrl.alu_op;
  assign branch_op_i     = pkt_exe_i.ex_ctrl.branch_op;
  assign jump_op_i       = pkt_exe_i.ex_ctrl.jump_op;
  assign mem_req_i       = pkt_exe_i.ex_ctrl.mem_req;
  assign mem_we_i        = pkt_exe_i.ex_ctrl.mem_we;
  assign mem_size_i      = pkt_exe_i.ex_ctrl.mem_size;
  assign mem_unsigned_i  = pkt_exe_i.ex_ctrl.mem_unsigned;
  assign wb_sel_i        = pkt_exe_i.ex_ctrl.wb_sel;
  assign muldiv_valid_i  = pkt_exe_i.ex_ctrl.muldiv_valid;
  assign muldiv_op_i     = pkt_exe_i.ex_ctrl.muldiv_op;
  assign illegal_instr_i = pkt_exe_i.exc.illegal_instr;
  assign ecall_i         = pkt_exe_i.exc.ecall;
  assign ebreak_i        = pkt_exe_i.exc.ebreak;
  assign is_mret_i       = pkt_exe_i.is_mret;
  assign is_wfi_i        = pkt_exe_i.is_wfi;
  assign csr_i           = pkt_exe_i.csr;

  // Suppress unused warnings for signals now handled by LSU
  logic _unused_mem;
  assign _unused_mem = mem_req_i | mem_we_i | (&store_data_i) | mem_unsigned_i | (mem_size_i == MEM_SIZE_BYTE);

  logic [DW-1:0] instr_dbg_unused;
  assign instr_dbg_unused = instr_i;

  // ------------------------------------------------------------
  // Effective address (still needed for JALR target)
  // ------------------------------------------------------------
  logic [AW-1:0] eff_addr;
  assign eff_addr = op1_i[AW-1:0] + imm_i[AW-1:0];

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
  // CSR write data computation
  // ------------------------------------------------------------
  logic [DW-1:0] csr_wdata_final;
  always_comb begin
    csr_wdata_final = csr_i.wdata;
    unique case (csr_i.op)
      CSR_OP_RW, CSR_OP_RWI: csr_wdata_final = csr_i.wdata;
      CSR_OP_RS, CSR_OP_RSI: csr_wdata_final = csr_rdata_i | csr_i.wdata;
      CSR_OP_RC, CSR_OP_RCI: csr_wdata_final = csr_rdata_i & ~csr_i.wdata;
      default:               csr_wdata_final = csr_i.wdata;
    endcase
  end

  // ------------------------------------------------------------
  // Main output control
  // ------------------------------------------------------------
  logic exception_like;
  assign exception_like =
      illegal_instr_i |
      ecall_i |
      ebreak_i |
      mem_misaligned_i;

  logic          wb_valid_o, wb_rf_wen_o, wb_illegal_instr_o, wb_ecall_o, wb_ebreak_o, wb_mem_misaligned_o;
  logic [4:0]    wb_rf_waddr_o;
  wb_sel_e       wb_sel_o;
  logic [DW-1:0] wb_alu_data_o, wb_pc4_data_o;
  mem_size_e     wb_mem_size_o;
  logic          wb_mem_unsigned_o;
  logic [AW-1:0] wb_trap_pc_o;
  logic [DW-1:0] wb_trap_cause_o;
  logic [DW-1:0] wb_trap_val_o;
  logic          wb_is_mret_o;
  csr_pkt_t      wb_csr_o;

  always_comb begin
    wb_valid_o          = valid_i;
    wb_rf_wen_o         = 1'b0;
    wb_rf_waddr_o       = rd_i;
    wb_sel_o            = wb_sel_i;
    wb_alu_data_o       = alu_result;
    wb_pc4_data_o       = pc4_data;
    wb_mem_size_o       = mem_size_i;
    wb_mem_unsigned_o   = mem_unsigned_i;
    wb_illegal_instr_o  = valid_i && illegal_instr_i;
    wb_ecall_o          = valid_i && ecall_i;
    wb_ebreak_o         = valid_i && ebreak_i;
    wb_mem_misaligned_o = valid_i && mem_misaligned_i;
    wb_trap_pc_o        = pc_i;
    wb_trap_cause_o     = '0;
    wb_trap_val_o       = '0;
    wb_is_mret_o        = valid_i && is_mret_i;
    wb_csr_o            = '0;
    redirect_en_o       = 1'b0;
    redirect_pc_o       = '0;
    flush_req_o         = 1'b0;

    if (valid_i && !exception_like) begin
      // CSR instruction
      if (csr_i.valid) begin
        wb_rf_wen_o   = rf_we_i;
        wb_alu_data_o = csr_rdata_i;   // CSR read data goes to RF
        wb_csr_o      = csr_i;
        wb_csr_o.wdata = csr_wdata_final;
      end
      // MULDIV result reuses wb_alu_data_o path.
      else if (muldiv_valid_i && wb_sel_i == WB_MULDIV) begin
        wb_alu_data_o = muldiv_result;
      end

      // MRET redirect
      if (is_mret_i) begin
        redirect_en_o = 1'b1;
        redirect_pc_o = mepc_i;
        flush_req_o   = 1'b1;
      end
      // Branch redirect
      else if (branch_taken) begin
        redirect_en_o = 1'b1;
        redirect_pc_o = pc_i + imm_i[AW-1:0];
        flush_req_o   = 1'b1;
      end
      // Jump redirect
      else begin
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
          default: begin
            redirect_en_o = 1'b0;
            redirect_pc_o = '0;
            flush_req_o   = 1'b0;
          end
        endcase
      end
    end else begin
      wb_rf_wen_o = 1'b0;
      wb_sel_o    = WB_NONE;
      // Compute trap cause / val for exception-like instructions
      if (valid_i) begin
        if (illegal_instr_i) begin
          wb_trap_cause_o = MCAUSE_ILLEGAL_INST;
          wb_trap_val_o   = instr_i;
        end else if (ebreak_i) begin
          wb_trap_cause_o = MCAUSE_BREAKPOINT;
          wb_trap_val_o   = DW'(pc_i);
        end else if (ecall_i) begin
          wb_trap_cause_o = MCAUSE_ECALL_M;
          wb_trap_val_o   = '0;
        end else if (mem_misaligned_i) begin
          wb_trap_cause_o = mem_we_i ? MCAUSE_STORE_MISALIGNED : MCAUSE_LOAD_MISALIGNED;
          wb_trap_val_o   = DW'(op1_i[AW-1:0] + imm_i[AW-1:0]);
        end
      end
    end
  end

  assign pkt_exe_o.valid               = wb_valid_o;
  assign pkt_exe_o.rf.we               = wb_rf_wen_o;
  assign pkt_exe_o.rf.addr             = wb_rf_waddr_o;
  assign pkt_exe_o.wb_sel              = wb_sel_o;
  assign pkt_exe_o.alu_data            = wb_alu_data_o;
  assign pkt_exe_o.pc4_data            = wb_pc4_data_o;
  assign pkt_exe_o.mem_info.mem_size     = wb_mem_size_o;
  assign pkt_exe_o.mem_info.mem_unsigned = wb_mem_unsigned_o;
  assign pkt_exe_o.mem_info.load_offset  = '0;  // overridden by LSU in top
  assign pkt_exe_o.mem_misaligned      = wb_mem_misaligned_o;
  assign pkt_exe_o.exc.illegal_instr   = wb_illegal_instr_o;
  assign pkt_exe_o.exc.ecall           = wb_ecall_o;
  assign pkt_exe_o.exc.ebreak          = wb_ebreak_o;
  assign pkt_exe_o.csr                 = wb_csr_o;
  assign pkt_exe_o.trap_pc             = wb_trap_pc_o;
  assign pkt_exe_o.trap_cause          = wb_trap_cause_o;
  assign pkt_exe_o.trap_val            = wb_trap_val_o;
  assign pkt_exe_o.is_mret             = wb_is_mret_o;

endmodule
`default_nettype wire