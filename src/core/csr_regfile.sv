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
  input  priv_mode_e   current_priv_i,

  // Combinational read port
  input  logic [11:0]  csr_addr_i,
  output logic [DW-1:0] csr_rdata_o,
  output logic          csr_implemented_o,
  output logic          csr_read_only_o,
  output logic          csr_privilege_ok_o,

  // Combinational preview and clocked architectural retirement command.
  input  csr_write_req_t  preview_req_i,
  output logic [DW-1:0]   preview_wdata_effective_o,
  output csr_irq_context_t irq_context_o,
  input  csr_retire_cmd_t retire_cmd_i,

  // Hardware-owned machine timer pending level.
  input  logic            irq_mti_i,

  // Outputs to the core
  output logic [AW-1:0] mtvec_o,
  output logic [AW-1:0] mepc_o,
  output logic [DW-1:0] mstatus_o,
  output logic [DW-1:0] mie_o,
  output logic [DW-1:0] mip_o
);

  // mstatus bit fields
  localparam int MSTATUS_MPP_LO   = 11;
  localparam int MSTATUS_MPP_HI   = 12;

  localparam logic [DW-1:0] MSTATUS_MPP_M = 2'b11 << MSTATUS_MPP_LO;
  localparam logic [DW-1:0] MSTATUS_RESET = MSTATUS_MPP_M;
  localparam logic [DW-1:0] MSTATUS_WRITABLE_MASK =
      (DW'(1) << MSTATUS_MIE_BIT) |
      (DW'(1) << MSTATUS_MPIE_BIT);
  localparam logic [DW-1:0] MIE_WRITABLE_MASK = DW'(32'h0000_0080);

  // misa value: MXL=01 (RV32), M bit 12, I bit 8.
  // Keep this explicit: the previous concatenation was 34 bits wide and was
  // silently truncated when assigned to a 32-bit CSR.
  localparam logic [DW-1:0] MISA_VALUE = DW'(32'h4000_1100);

  // ------------------------------------------------------------
  // CSR state
  // ------------------------------------------------------------
  logic [DW-1:0] mstatus_q;
  logic [DW-1:0] mie_q;
  logic [DW-1:0] mip_q;
  logic [AW-1:0] mtvec_q;
  logic [DW-1:0] mscratch_q;
  logic [AW-1:0] mepc_q;
  logic [DW-1:0] mcause_q;
  logic [DW-1:0] mtval_q;
  logic [63:0] mcycle_q;
  logic [63:0] minstret_q;
  logic [DW-1:0] mip_composed;
  logic [DW-1:0] retire_wdata_effective;

  // ------------------------------------------------------------
  // Explicit CSR contract
  // ------------------------------------------------------------
  function automatic logic csr_implemented(logic [11:0] addr);
    unique case (addr)
      CSR_MSTATUS,
      CSR_MISA,
      CSR_MEDELEG,
      CSR_MIDELEG,
      CSR_MIE,
      CSR_MTVEC,
      CSR_MSCRATCH,
      CSR_MEPC,
      CSR_MCAUSE,
      CSR_MTVAL,
      CSR_MIP,
      CSR_MCYCLE,
      CSR_MINSTRET,
      CSR_MCYCLEH,
      CSR_MINSTRETH,
      CSR_MVENDORID,
      CSR_MARCHID,
      CSR_MIMPID,
      CSR_MHARTID,
      CSR_MCONFIGPTR: csr_implemented = 1'b1;
      default:        csr_implemented = 1'b0;
    endcase
  endfunction

  function automatic logic csr_read_only_address(logic [11:0] addr);
    csr_read_only_address = (addr[11:10] == 2'b11);
  endfunction

  function automatic logic [DW-1:0] csr_warl_value(
      logic [11:0] addr,
      logic [DW-1:0] value
  );
    begin
      unique case (addr)
        CSR_MSTATUS:
          csr_warl_value = MSTATUS_MPP_M | (value & MSTATUS_WRITABLE_MASK);
        CSR_MISA:
          csr_warl_value = MISA_VALUE;
        CSR_MEDELEG,
        CSR_MIDELEG:
          csr_warl_value = '0;
        CSR_MIE:
          csr_warl_value = value & MIE_WRITABLE_MASK;
        // No mip field is software-writable in this single-hart M-only
        // milestone. Future MTIP is composed from a hardware input.
        CSR_MIP:
          csr_warl_value = '0;
        // Direct mtvec mode and IALIGN=32 both require word alignment.
        CSR_MTVEC,
        CSR_MEPC:
          csr_warl_value = {value[DW-1:2], 2'b00};
        default:
          csr_warl_value = value;
      endcase
    end
  endfunction

  assign csr_implemented_o = csr_implemented(csr_addr_i);
  assign csr_read_only_o = csr_read_only_address(csr_addr_i);
  assign csr_privilege_ok_o = (csr_addr_i[9:8] <= current_priv_i);
  assign preview_wdata_effective_o =
      csr_warl_value(preview_req_i.addr, preview_req_i.wdata);
  assign retire_wdata_effective =
      csr_warl_value(retire_cmd_i.csr_write.addr,
                     retire_cmd_i.csr_write.wdata);
  assign mip_composed = mip_q | (DW'(irq_mti_i) << MIP_MTIP_BIT);

  // Post-retirement preview used only for interrupt eligibility/vector
  // selection. WARL filtering remains owned by this module.
  always_comb begin
    irq_context_o.mstatus = mstatus_q;
    irq_context_o.mie     = mie_q;
    irq_context_o.mip     = mip_composed;
    irq_context_o.mtvec   = mtvec_q;

    if (preview_req_i.valid) begin
      unique case (preview_req_i.addr)
        CSR_MSTATUS:
          irq_context_o.mstatus = preview_wdata_effective_o;
        CSR_MIE:
          irq_context_o.mie = preview_wdata_effective_o;
        CSR_MIP:
          irq_context_o.mip = mip_composed;
        CSR_MTVEC:
          irq_context_o.mtvec = AW'(preview_wdata_effective_o);
        default: ;
      endcase
    end
  end

  // ------------------------------------------------------------
  // Read logic (combinational)
  // ------------------------------------------------------------
  always_comb begin
    csr_rdata_o = '0;
    unique case (csr_addr_i)
      CSR_MSTATUS:  csr_rdata_o = mstatus_q;
      CSR_MISA:     csr_rdata_o = MISA_VALUE;
      CSR_MEDELEG:  csr_rdata_o = '0;
      CSR_MIDELEG:  csr_rdata_o = '0;
      CSR_MIE:      csr_rdata_o = mie_q;
      CSR_MTVEC:    csr_rdata_o = DW'(mtvec_q);
      CSR_MSCRATCH: csr_rdata_o = mscratch_q;
      CSR_MEPC:     csr_rdata_o = DW'(mepc_q);
      CSR_MCAUSE:   csr_rdata_o = mcause_q;
      CSR_MTVAL:    csr_rdata_o = mtval_q;
      CSR_MIP:      csr_rdata_o = mip_composed;
      CSR_MCYCLE:   csr_rdata_o = mcycle_q[31:0];
      CSR_MINSTRET: csr_rdata_o = minstret_q[31:0];
      CSR_MCYCLEH:  csr_rdata_o = mcycle_q[63:32];
      CSR_MINSTRETH: csr_rdata_o = minstret_q[63:32];
      CSR_MVENDORID,
      CSR_MARCHID,
      CSR_MIMPID,
      CSR_MHARTID,
      CSR_MCONFIGPTR: csr_rdata_o = '0;
      default:      csr_rdata_o = '0;
    endcase
  end

  // ------------------------------------------------------------
  // State update
  // ------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mstatus_q  <= MSTATUS_RESET;
      mie_q      <= '0;
      mip_q      <= '0;
      mtvec_q    <= '0;
      mscratch_q <= '0;
      mepc_q     <= '0;
      mcause_q   <= '0;
      mtval_q    <= '0;
      mcycle_q   <= 64'd0;
      minstret_q <= 64'd0;
    end else begin
      // Counters
      mcycle_q <= mcycle_q + 64'd1;
      if (retire_cmd_i.instret) begin
        minstret_q <= minstret_q + 64'd1;
      end

      // Ordered boundary semantics: retire the instruction's CSR write first,
      // then apply MRET or trap entry. Later assignments intentionally win for
      // fields architecturally owned by the boundary event.
      if (retire_cmd_i.csr_write.valid) begin
        unique case (retire_cmd_i.csr_write.addr)
          CSR_MSTATUS:  mstatus_q  <= retire_wdata_effective;
          CSR_MIE:      mie_q      <= retire_wdata_effective;
          CSR_MIP:      mip_q      <= retire_wdata_effective;
          CSR_MTVEC:    mtvec_q    <= AW'(retire_wdata_effective);
          CSR_MSCRATCH: mscratch_q <= retire_wdata_effective;
          CSR_MEPC:     mepc_q     <= AW'(retire_wdata_effective);
          CSR_MCAUSE:   mcause_q   <= retire_wdata_effective;
          CSR_MTVAL:    mtval_q    <= retire_wdata_effective;
          CSR_MCYCLE:   mcycle_q[31:0] <= retire_wdata_effective;
          CSR_MINSTRET: minstret_q[31:0] <= retire_wdata_effective;
          CSR_MCYCLEH:  mcycle_q[63:32] <= retire_wdata_effective;
          CSR_MINSTRETH: minstret_q[63:32] <= retire_wdata_effective;
          // misa and the delegation registers are legal fixed-value WARL
          // CSRs. Machine identity CSRs cannot reach this write port because
          // their read-only encoding traps in EX.
          default: ;
        endcase
      end

      if (retire_cmd_i.mret) begin
        // Restore MIE from MPIE, set MPIE=1.
        mstatus_q[MSTATUS_MIE_BIT]  <= mstatus_q[MSTATUS_MPIE_BIT];
        mstatus_q[MSTATUS_MPIE_BIT] <= 1'b1;
      end

      if (retire_cmd_i.trap.valid) begin
        mepc_q   <= retire_cmd_i.trap.pc;
        mcause_q <= retire_cmd_i.trap.cause;
        mtval_q  <= retire_cmd_i.trap.tval;
        // irq_context_o includes the retiring instruction's effective CSR
        // write, so MPIE records the post-retirement MIE value.
        mstatus_q[MSTATUS_MPIE_BIT] <=
            irq_context_o.mstatus[MSTATUS_MIE_BIT];
        mstatus_q[MSTATUS_MIE_BIT] <= 1'b0;
        // MPP remains M (M-only core).
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
  assign mip_o     = mip_composed;

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(retire_cmd_i.trap.valid && retire_cmd_i.mret))
        else $error("CSR command selected trap entry and MRET together");
      if (retire_cmd_i.csr_write.valid) begin
        assert (retire_cmd_i.csr_write == preview_req_i)
          else $error("CSR preview request and committed write diverged");
      end
      assert (mip_composed[MIP_MTIP_BIT] == irq_mti_i)
        else $error("Hardware MTIP composition is inconsistent");
    end
  end
`endif

endmodule
`default_nettype wire
