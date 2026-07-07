`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: csr_regfile
// Description:
//   Minimal M-mode CSR register file for RV32IM.
//   Supports CSR read/write, trap entry (mepc/mcause/mtval/mstatus),
//   and mret (mstatus restore).
// ============================================================
module csr_regfile #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic         clk_i,
  input  logic         rst_ni,

  // Combinational read port
  input  logic [11:0]  csr_addr_i,
  output logic [DW-1:0] csr_rdata_o,

  // Registered write port (driven from WB stage)
  input  logic         csr_we_i,
  input  logic [11:0]  csr_waddr_i,
  input  logic [DW-1:0] csr_wdata_i,

  // Trap entry (one-cycle pulse)
  input  logic         trap_entry_i,
  input  logic [AW-1:0] trap_pc_i,
  input  logic [DW-1:0] trap_cause_i,
  input  logic [DW-1:0] trap_val_i,

  // MRET (one-cycle pulse, asserted when mret is in WB)
  input  logic         mret_i,

  // Instruction retire (for minstret)
  input  logic         instret_i,

  // Outputs to the core
  output logic [AW-1:0] mtvec_o,
  output logic [AW-1:0] mepc_o,
  output logic [DW-1:0] mstatus_o,
  output logic [DW-1:0] mie_o,
  output logic [DW-1:0] mip_o
);

  // mstatus bit fields
  localparam int MSTATUS_MIE_BIT  = 3;
  localparam int MSTATUS_MPIE_BIT = 7;
  localparam int MSTATUS_MPP_LO   = 11;
  localparam int MSTATUS_MPP_HI   = 12;

  localparam logic [DW-1:0] MSTATUS_MPP_M = 2'b11 << MSTATUS_MPP_LO;
  localparam logic [DW-1:0] MSTATUS_RESET = MSTATUS_MPP_M;

  // misa value: RV32IM
  localparam logic [DW-1:0] MISA_VALUE = {2'b01, 4'b0000, 20'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1};
  // Bit mapping: 31:30 MXL=01 (32-bit), 12=M, 8=I

  // ------------------------------------------------------------
  // CSR state
  // ------------------------------------------------------------
  logic [DW-1:0] mstatus_q;
  logic [DW-1:0] misa_q;
  logic [DW-1:0] medeleg_q;
  logic [DW-1:0] mideleg_q;
  logic [DW-1:0] mie_q;
  logic [DW-1:0] mip_q;
  logic [AW-1:0] mtvec_q;
  logic [DW-1:0] mscratch_q;
  logic [AW-1:0] mepc_q;
  logic [DW-1:0] mcause_q;
  logic [DW-1:0] mtval_q;
  logic [DW-1:0] mcycle_q;
  logic [DW-1:0] minstret_q;

  // ------------------------------------------------------------
  // Read logic (combinational)
  // ------------------------------------------------------------
  always_comb begin
    csr_rdata_o = '0;
    unique case (csr_addr_i)
      CSR_MSTATUS:  csr_rdata_o = mstatus_q;
      CSR_MISA:     csr_rdata_o = misa_q;
      CSR_MEDELEG:  csr_rdata_o = medeleg_q;
      CSR_MIDELEG:  csr_rdata_o = mideleg_q;
      CSR_MIE:      csr_rdata_o = mie_q;
      CSR_MTVEC:    csr_rdata_o = DW'(mtvec_q);
      CSR_MSCRATCH: csr_rdata_o = mscratch_q;
      CSR_MEPC:     csr_rdata_o = DW'(mepc_q);
      CSR_MCAUSE:   csr_rdata_o = mcause_q;
      CSR_MTVAL:    csr_rdata_o = mtval_q;
      CSR_MIP:      csr_rdata_o = mip_q;
      CSR_MCYCLE:   csr_rdata_o = mcycle_q;
      CSR_MINSTRET: csr_rdata_o = minstret_q;
      default:      csr_rdata_o = '0;
    endcase
  end

  // ------------------------------------------------------------
  // Read-only predicate
  // ------------------------------------------------------------
  function automatic logic csr_read_only(logic [11:0] addr);
    unique case (addr)
      CSR_MISA,
      CSR_MEDELEG,
      CSR_MIDELEG,
      CSR_MCYCLE,
      CSR_MINSTRET: csr_read_only = 1'b1;
      default:      csr_read_only = 1'b0;
    endcase
  endfunction

  // ------------------------------------------------------------
  // State update
  // ------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mstatus_q  <= MSTATUS_RESET;
      misa_q     <= MISA_VALUE;
      medeleg_q  <= '0;
      mideleg_q  <= '0;
      mie_q      <= '0;
      mip_q      <= '0;
      mtvec_q    <= '0;
      mscratch_q <= '0;
      mepc_q     <= '0;
      mcause_q   <= '0;
      mtval_q    <= '0;
      mcycle_q   <= '0;
      minstret_q <= '0;
    end else begin
      // Counters
      mcycle_q <= mcycle_q + 1'b1;
      if (instret_i) begin
        minstret_q <= minstret_q + 1'b1;
      end

      // Trap entry has priority
      if (trap_entry_i) begin
        mepc_q   <= trap_pc_i;
        mcause_q <= trap_cause_i;
        mtval_q  <= trap_val_i;
        mstatus_q[MSTATUS_MPIE_BIT] <= mstatus_q[MSTATUS_MIE_BIT];
        mstatus_q[MSTATUS_MIE_BIT]  <= 1'b0;
        // MPP remains M (M-only core)
      end else if (mret_i) begin
        // Restore MIE from MPIE, set MPIE=1
        mstatus_q[MSTATUS_MIE_BIT]  <= mstatus_q[MSTATUS_MPIE_BIT];
        mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
      end else if (csr_we_i && !csr_read_only(csr_waddr_i)) begin
        unique case (csr_waddr_i)
          CSR_MSTATUS:  mstatus_q  <= csr_wdata_i;
          CSR_MIE:      mie_q      <= csr_wdata_i;
          CSR_MIP:      mip_q      <= csr_wdata_i;
          CSR_MTVEC:    mtvec_q    <= AW'(csr_wdata_i);
          CSR_MSCRATCH: mscratch_q <= csr_wdata_i;
          CSR_MEPC:     mepc_q     <= AW'(csr_wdata_i);
          CSR_MCAUSE:   mcause_q   <= csr_wdata_i;
          CSR_MTVAL:    mtval_q    <= csr_wdata_i;
          default: ; // read-only or unimplemented
        endcase
      end
    end
  end

  // ------------------------------------------------------------
  // Outputs
  // ------------------------------------------------------------
  assign mtvec_o   = mtvec_q;
  assign mepc_o    = mepc_q;
  assign mstatus_o = mstatus_q;
  assign mie_o     = mie_q;
  assign mip_o     = mip_q;

endmodule
`default_nettype wire
