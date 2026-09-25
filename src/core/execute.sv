`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
// ============================================================
// Module: execute
// Description:
//   RV32IM execute stage (memory interaction moved to LSU).
// ============================================================
module execute (
  input  wire id_ex_pkt_t   pkt_exe_i,

  // LSU feedback: misalignment result (computed in LSU)
  input  wire logic          mem_misaligned_i,

  // CSR feedback
  input  wire logic [DW-1:0] csr_rdata_i,
  input  wire logic          csr_implemented_i,
  input  wire logic          csr_read_only_i,
  input  wire logic          csr_privilege_ok_i,
  input  wire logic [AW-1:0] mepc_i,

  // Completed RV32M result selected by the replaceable arithmetic facade.
  input  wire logic [DW-1:0] rv32m_result_i,

  // EX produces a candidate; core_ctrl owns selection and movement.
  output redirect_t     redirect_candidate_o,

  output ex_wb_pkt_t   pkt_exe_o
);
  logic          valid;
  logic [AW-1:0] pc;
  logic [DW-1:0] instr, operand1, operand2, immediate;
  logic [4:0]    rd_addr;
  logic          rf_write;
  alu_op_e       alu_op;
  branch_op_e    branch_op;
  jump_op_e      jump_op;
  logic          mem_write, mem_unsigned;
  mem_size_e     mem_size;
  wb_sel_e       wb_sel;
  logic          muldiv_valid;
  muldiv_op_e    muldiv_op;
  logic          illegal_instr, instr_access_fault, ecall, ebreak;
  logic          is_mret, is_wfi;
  csr_pkt_t      csr_intent;

  assign valid              = pkt_exe_i.valid;
  assign pc                 = pkt_exe_i.pc;
  assign instr              = pkt_exe_i.instr;
  assign operand1           = pkt_exe_i.ex_data.op1;
  assign operand2           = pkt_exe_i.ex_data.op2;
  assign immediate          = pkt_exe_i.ex_data.imm;
  assign rd_addr            = pkt_exe_i.rf.addr;
  assign rf_write           = pkt_exe_i.rf.we;
  assign alu_op             = pkt_exe_i.ex_ctrl.alu_op;
  assign branch_op          = pkt_exe_i.ex_ctrl.branch_op;
  assign jump_op            = pkt_exe_i.ex_ctrl.jump_op;
  assign mem_write          = pkt_exe_i.ex_ctrl.mem_we;
  assign mem_size           = pkt_exe_i.ex_ctrl.mem_size;
  assign mem_unsigned       = pkt_exe_i.ex_ctrl.mem_unsigned;
  assign wb_sel             = pkt_exe_i.ex_ctrl.wb_sel;
  assign muldiv_valid       = pkt_exe_i.ex_ctrl.muldiv_valid;
  assign muldiv_op          = pkt_exe_i.ex_ctrl.muldiv_op;
  assign illegal_instr      = pkt_exe_i.exc.illegal_instr;
  assign instr_access_fault = pkt_exe_i.exc.instr_access_fault;
  assign ecall              = pkt_exe_i.exc.ecall;
  assign ebreak             = pkt_exe_i.exc.ebreak;
  assign is_mret            = pkt_exe_i.is_mret;
  assign is_wfi             = pkt_exe_i.is_wfi;
  assign csr_intent         = pkt_exe_i.csr;

  // ------------------------------------------------------------
  // Effective address (still needed for JALR target)
  // ------------------------------------------------------------
  logic [AW-1:0] eff_addr;
  assign eff_addr = operand1[AW-1:0] + immediate[AW-1:0];

  logic [DW-1:0] pc4_data;
  assign pc4_data = DW'(pc) + DW'(4);

  // ------------------------------------------------------------
  // ALU
  // ------------------------------------------------------------
  logic [DW-1:0] alu_result;
  always_comb begin
    alu_result = '0;
    unique case (alu_op)
      ALU_NONE:   alu_result = '0;
      ALU_ADD:    alu_result = operand1 + operand2;
      ALU_SUB:    alu_result = operand1 - operand2;
      ALU_SLL:    alu_result = operand1 << operand2[SHAMT_W-1:0];
      ALU_SLT:    alu_result = ($signed(operand1) < $signed(operand2)) ? DW'(1) : '0;
      ALU_SLTU:   alu_result = (operand1 < operand2) ? DW'(1) : '0;
      ALU_XOR:    alu_result = operand1 ^ operand2;
      ALU_SRL:    alu_result = operand1 >> operand2[SHAMT_W-1:0];
      ALU_SRA:    alu_result = $signed(operand1) >>> operand2[SHAMT_W-1:0];
      ALU_OR:     alu_result = operand1 | operand2;
      ALU_AND:    alu_result = operand1 & operand2;
      ALU_COPY_B: alu_result = operand2;
      default:    alu_result = '0;
    endcase
  end

  // ------------------------------------------------------------
  // Branch compare
  // ------------------------------------------------------------
  logic branch_taken;
  always_comb begin
    branch_taken = 1'b0;
    unique case (branch_op)
      BR_NONE: branch_taken = 1'b0;
      BR_BEQ:  branch_taken = (operand1 == operand2);
      BR_BNE:  branch_taken = (operand1 != operand2);
      BR_BLT:  branch_taken = ($signed(operand1) < $signed(operand2));
      BR_BGE:  branch_taken = ($signed(operand1) >= $signed(operand2));
      BR_BLTU: branch_taken = (operand1 < operand2);
      BR_BGEU: branch_taken = (operand1 >= operand2);
      default: branch_taken = 1'b0;
    endcase
  end

  // ------------------------------------------------------------
  // Resolved branch/jump target and IALIGN=32 check
  // ------------------------------------------------------------
  logic          control_transfer;
  logic [AW-1:0] control_target;
  logic          instr_misaligned;

  always_comb begin
    control_transfer = 1'b0;
    control_target   = '0;

    if (branch_taken) begin
      control_transfer = 1'b1;
      control_target   = pc + immediate[AW-1:0];
    end
    else begin
      unique case (jump_op)
        JMP_JAL: begin
          control_transfer = 1'b1;
          control_target   = pc + immediate[AW-1:0];
        end
        JMP_JALR: begin
          control_transfer = 1'b1;
          control_target   = {eff_addr[AW-1:1], 1'b0};
        end
        default: begin
          control_transfer = 1'b0;
          control_target   = '0;
        end
      endcase
    end
  end

  assign instr_misaligned =
      valid &&
      control_transfer &&
      (control_target[IALIGN_LSB-1:0] != '0);

  // ------------------------------------------------------------
  // RV32M arithmetic is owned by rv32m_unit.
  // ------------------------------------------------------------
  logic [DW-1:0] muldiv_result;
  assign muldiv_result = (muldiv_op == MULDIV_NONE) ? '0 : rv32m_result_i;

  // ------------------------------------------------------------
  // CSR write data computation
  // ------------------------------------------------------------
  logic [DW-1:0] csr_wdata_final;
  always_comb begin
    csr_wdata_final = csr_intent.wdata;
    unique case (csr_intent.op)
      CSR_OP_RW, CSR_OP_RWI: csr_wdata_final = csr_intent.wdata;
      CSR_OP_RS, CSR_OP_RSI: csr_wdata_final = csr_rdata_i | csr_intent.wdata;
      CSR_OP_RC, CSR_OP_RCI: csr_wdata_final = csr_rdata_i & ~csr_intent.wdata;
      default:               csr_wdata_final = csr_intent.wdata;
    endcase
  end

  // ------------------------------------------------------------
  // Main output control
  // ------------------------------------------------------------
  logic csr_illegal;
  logic illegal_effective;
  logic exception_like;

  assign csr_illegal =
      valid &&
      csr_intent.valid &&
      (!csr_implemented_i ||
       !csr_privilege_ok_i ||
       (csr_intent.write && csr_read_only_i));
  assign illegal_effective = illegal_instr | csr_illegal;
  assign exception_like =
      instr_access_fault |
      illegal_effective |
      ecall |
      ebreak |
      instr_misaligned |
      mem_misaligned_i;

  logic          result_rf_write;
  logic          result_illegal_instr, result_instr_access_fault;
  logic          result_ecall, result_ebreak;
  wb_sel_e       result_wb_sel;
  logic [DW-1:0] result_data;
  logic [DW-1:0] result_trap_cause;
  logic [DW-1:0] result_trap_val;
  csr_pkt_t      result_csr;

  always_comb begin
    result_rf_write         = 1'b0;
    result_wb_sel            = wb_sel;
    result_data       = alu_result;
    result_illegal_instr  = valid && illegal_effective;
    result_instr_access_fault = valid && instr_access_fault;
    result_ecall          = valid && ecall;
    result_ebreak         = valid && ebreak;
    result_trap_cause     = '0;
    result_trap_val       = '0;
    result_csr            = '0;
    redirect_candidate_o = '0;

    if (valid && !exception_like) begin
      result_rf_write = rf_write;
      // CSR instruction
      if (csr_intent.valid) begin
        result_rf_write   = rf_write;
        result_data = csr_rdata_i;   // CSR read data goes to RF
        result_csr      = csr_intent;
        result_csr.wdata = csr_wdata_final;
      end
      // MULDIV result reuses result_data path.
      else if (muldiv_valid && wb_sel == WB_MULDIV) begin
        result_data = muldiv_result;
      end

      // Taken branch or jump redirect candidate. A misaligned target is excluded by
      // exception_like and therefore cannot redirect or write its link register.
      if (control_transfer) begin
        redirect_candidate_o.valid = 1'b1;
        redirect_candidate_o.pc = control_target;
        redirect_candidate_o.reason =
            (branch_op != BR_NONE) ? REDIRECT_BRANCH : REDIRECT_JUMP;
      end
    end else begin
      result_rf_write = 1'b0;
      result_wb_sel    = WB_NONE;
      // Compute trap cause / val for exception-like instructions
      if (valid) begin
        if (instr_access_fault) begin
          result_trap_cause = MCAUSE_INST_ACCESS;
          result_trap_val   = DW'(pc);
        end else if (illegal_effective) begin
          result_trap_cause = MCAUSE_ILLEGAL_INST;
          result_trap_val   = instr;
        end else if (instr_misaligned) begin
          result_trap_cause = MCAUSE_INST_MISALIGNED;
          result_trap_val   = DW'(control_target);
        end else if (ebreak) begin
          result_trap_cause = MCAUSE_BREAKPOINT;
          result_trap_val   = DW'(pc);
        end else if (ecall) begin
          result_trap_cause = MCAUSE_ECALL_M;
          result_trap_val   = '0;
        end else if (mem_misaligned_i) begin
          result_trap_cause = mem_write ? MCAUSE_STORE_MISALIGNED : MCAUSE_LOAD_MISALIGNED;
          result_trap_val   = DW'(operand1[AW-1:0] + immediate[AW-1:0]);
        end
      end
    end
  end

  // EX owns these execution/trap facts. Memory completion fields intentionally
  // remain zero until the LSU-owned merge in riscv.sv.
  always_comb begin
    pkt_exe_o = EX_WB_PKT_BUBBLE;
    pkt_exe_o.valid = valid;
    pkt_exe_o.pc    = pc;
    // Capture the architectural MRET target with the instruction. Retirement
    // emits the redirect in the same cycle as mstatus restoration.
    pkt_exe_o.next_pc = is_mret ? mepc_i :
                        (control_transfer ? control_target : AW'(pc4_data));
    pkt_exe_o.instr         = instr[31:0];
    pkt_exe_o.rf.we         = result_rf_write;
    pkt_exe_o.rf.addr       = rd_addr;
    pkt_exe_o.wb_sel        = result_wb_sel;
    pkt_exe_o.alu_data      = result_data;
    pkt_exe_o.pc4_data      = pc4_data;
    pkt_exe_o.mem_info.mem_size     = mem_size;
    pkt_exe_o.mem_info.mem_unsigned = mem_unsigned;
    pkt_exe_o.instr_misaligned = instr_misaligned;
    pkt_exe_o.mem_misaligned   = valid && mem_misaligned_i;
    pkt_exe_o.exc.illegal_instr      = result_illegal_instr;
    pkt_exe_o.exc.instr_access_fault = result_instr_access_fault;
    pkt_exe_o.exc.ecall               = result_ecall;
    pkt_exe_o.exc.ebreak              = result_ebreak;
    pkt_exe_o.csr        = result_csr;
    pkt_exe_o.trap_pc    = pc;
    pkt_exe_o.trap_cause = result_trap_cause;
    pkt_exe_o.trap_val   = result_trap_val;
    pkt_exe_o.is_mret    = valid && is_mret;
    pkt_exe_o.is_wfi     = valid && is_wfi;
  end

endmodule
`default_nettype wire
