`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Sole owner of architectural retirement decisions. Combinational outputs
// select the current boundary's effects; small clocked state tracks commit
// order and the logical WFI wait/resume point.
module retire_stage #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW
)(
  input  logic             clk_i,
  input  logic             rst_ni,
  input  ex_wb_pkt_t       pkt_i,
  input  csr_irq_context_t csr_irq_context_i,
  input  logic             irq_defer_i,

  output csr_write_req_t   csr_preview_req_o,
  output rf_write_cmd_t    rf_write_cmd_o,
  output csr_retire_cmd_t  csr_retire_cmd_o,
  output redirect_t        redirect_o,
  output trap_entry_t      trap_entry_o,
  output commit_pkt_t      commit_o,
  output logic             sync_trap_o,
  output logic             irq_taken_o,
  output logic             wfi_enter_o,
  output logic             wfi_wait_o
);
  logic [63:0] retire_order_q;
  logic [DW-1:0] rf_write_data;
  logic irq_eligible;
  logic wfi_wait_q;
  logic [AW-1:0] wfi_resume_pc_q;

  assign sync_trap_o = pkt_i.valid &&
      (pkt_i.exc.illegal_instr || pkt_i.exc.instr_access_fault ||
       pkt_i.exc.ecall || pkt_i.exc.ebreak || pkt_i.instr_misaligned ||
       pkt_i.mem_misaligned || pkt_i.mem_error);
  assign irq_eligible =
      csr_irq_context_i.mstatus[MSTATUS_MIE_BIT] &&
      csr_irq_context_i.mie[MIE_MTIE_BIT] &&
      csr_irq_context_i.mip[MIP_MTIP_BIT];

  always_comb begin
    rf_write_data = '0;
    unique case (pkt_i.wb_sel)
      WB_ALU,
      WB_MULDIV,
      WB_CSR: rf_write_data = pkt_i.alu_data;
      WB_MEM: rf_write_data = pkt_i.mem_load_data;
      WB_PC4: rf_write_data = pkt_i.pc4_data;
      default: rf_write_data = '0;
    endcase
  end

  always_comb begin
    csr_preview_req_o       = '0;
    rf_write_cmd_o          = '0;
    csr_retire_cmd_o        = '0;
    redirect_o              = '0;
    trap_entry_o            = '0;
    commit_o                = '0;
    irq_taken_o             = 1'b0;
    wfi_enter_o             = 1'b0;

    if (pkt_i.valid && !sync_trap_o) begin
      csr_preview_req_o.valid = pkt_i.csr.valid && pkt_i.csr.write;
      csr_preview_req_o.addr  = pkt_i.csr.addr;
      csr_preview_req_o.wdata = pkt_i.csr.wdata;

      rf_write_cmd_o.valid = pkt_i.rf.we &&
                             (pkt_i.rf.addr != 5'd0) &&
                             (pkt_i.wb_sel != WB_NONE);
      rf_write_cmd_o.addr  = pkt_i.rf.addr;
      rf_write_cmd_o.data  = rf_write_data;

      csr_retire_cmd_o.csr_write = csr_preview_req_o;
      csr_retire_cmd_o.mret      = pkt_i.is_mret;
      csr_retire_cmd_o.instret    = 1'b1;
    end

    if (sync_trap_o) begin
      csr_retire_cmd_o.trap.valid     = 1'b1;
      csr_retire_cmd_o.trap.interrupt = 1'b0;
      csr_retire_cmd_o.trap.pc        = pkt_i.trap_pc;
      csr_retire_cmd_o.trap.cause     = pkt_i.trap_cause;
      csr_retire_cmd_o.trap.tval      = pkt_i.trap_val;

      redirect_o.valid  = 1'b1;
      redirect_o.pc     = csr_irq_context_i.mtvec;
      redirect_o.reason = REDIRECT_SYNC_TRAP;
    end

    // An interrupt is taken after the normal instruction effects have been
    // selected. MRET is excluded from same-boundary interrupt selection to
    // avoid two architectural redirects claiming one cycle.
    if (pkt_i.valid && !sync_trap_o && !pkt_i.is_mret &&
        irq_eligible && !irq_defer_i) begin
      irq_taken_o                         = 1'b1;
      csr_retire_cmd_o.trap.valid         = 1'b1;
      csr_retire_cmd_o.trap.interrupt     = 1'b1;
      csr_retire_cmd_o.trap.pc            = pkt_i.next_pc;
      csr_retire_cmd_o.trap.cause         = MCAUSE_IRQ_M_TIMER;
      csr_retire_cmd_o.trap.tval          = '0;

      redirect_o.valid                    = 1'b1;
      redirect_o.pc                       = csr_irq_context_i.mtvec;
      redirect_o.reason                   = REDIRECT_INTERRUPT;
    end

    // WFI is retired exactly once. If no interrupt is currently eligible,
    // the younger pipeline is killed and only the saved resume PC persists.
    if (pkt_i.valid && !sync_trap_o && pkt_i.is_wfi &&
        (!irq_eligible || irq_defer_i))
      wfi_enter_o = 1'b1;

    // A later eligible interrupt wakes logical WFI without another instruction
    // retirement or minstret increment.
    if (wfi_wait_q && irq_eligible && !irq_defer_i) begin
      irq_taken_o                         = 1'b1;
      csr_retire_cmd_o.trap.valid         = 1'b1;
      csr_retire_cmd_o.trap.interrupt     = 1'b1;
      csr_retire_cmd_o.trap.pc            = wfi_resume_pc_q;
      csr_retire_cmd_o.trap.cause         = MCAUSE_IRQ_M_TIMER;
      csr_retire_cmd_o.trap.tval          = '0;

      redirect_o.valid                    = 1'b1;
      redirect_o.pc                       = csr_irq_context_i.mtvec;
      redirect_o.reason                   = REDIRECT_INTERRUPT;
    end

    trap_entry_o = csr_retire_cmd_o.trap;

    // commit_o observes the retiring instruction. A future asynchronous
    // interrupt is reported through trap_entry_o, not by mislabeling the
    // normally retired instruction as a synchronous trap.
    commit_o.valid      = pkt_i.valid;
    commit_o.order      = retire_order_q;
    commit_o.pc         = pkt_i.pc;
    commit_o.instr      = pkt_i.instr;
    commit_o.rd_we      = rf_write_cmd_o.valid;
    commit_o.rd_addr    = rf_write_cmd_o.valid ? rf_write_cmd_o.addr : '0;
    commit_o.rd_data    = rf_write_cmd_o.valid ? rf_write_cmd_o.data : '0;
    commit_o.mem_valid  = pkt_i.mem_valid;
    commit_o.mem_we     = pkt_i.mem_we;
    commit_o.mem_addr   = pkt_i.mem_valid ? pkt_i.mem_addr : '0;
    commit_o.mem_wmask  = pkt_i.mem_we ? pkt_i.mem_wstrb : '0;
    commit_o.mem_rdata  = (pkt_i.mem_valid && !pkt_i.mem_we &&
                           !pkt_i.mem_error) ? pkt_i.mem_rdata : '0;
    commit_o.mem_wdata  = (pkt_i.mem_valid && pkt_i.mem_we) ?
                          pkt_i.mem_wdata : '0;
    commit_o.trap       = sync_trap_o;
    commit_o.trap_cause = pkt_i.trap_cause;
    commit_o.trap_val   = pkt_i.trap_val;

    if (pkt_i.mem_valid && !pkt_i.mem_we) begin
      unique case (pkt_i.mem_info.mem_size)
        MEM_SIZE_BYTE: commit_o.mem_rmask = 4'b0001 << pkt_i.mem_info.load_offset;
        MEM_SIZE_HALF: commit_o.mem_rmask = 4'b0011 << pkt_i.mem_info.load_offset;
        MEM_SIZE_WORD: commit_o.mem_rmask = 4'b1111;
        default:       commit_o.mem_rmask = '0;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      retire_order_q <= '0;
      wfi_wait_q      <= 1'b0;
      wfi_resume_pc_q <= '0;
    end else begin
      if (pkt_i.valid)
        retire_order_q <= retire_order_q + 64'd1;

      if (wfi_enter_o) begin
        wfi_wait_q      <= 1'b1;
        wfi_resume_pc_q <= pkt_i.next_pc;
      end else if (wfi_wait_q && irq_eligible && !irq_defer_i) begin
        wfi_wait_q <= 1'b0;
      end
    end
  end

  assign wfi_wait_o = wfi_wait_q;

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(sync_trap_o &&
                (rf_write_cmd_o.valid || csr_preview_req_o.valid ||
                 csr_retire_cmd_o.csr_write.valid ||
                 csr_retire_cmd_o.instret)))
        else $error("Synchronous trap retained a normal retirement effect");
      assert (!(csr_retire_cmd_o.trap.valid && csr_retire_cmd_o.mret))
        else $error("Trap entry and MRET were selected together");
      if (irq_taken_o) begin
        assert (csr_retire_cmd_o.trap.interrupt)
          else $error("IRQ selection did not generate interrupt trap entry");
        if (!wfi_wait_q) begin
          assert (pkt_i.valid && !sync_trap_o &&
                  csr_retire_cmd_o.instret &&
                  csr_retire_cmd_o.trap.pc == pkt_i.next_pc)
            else $error("Interrupt did not follow post-retirement semantics");
        end else begin
          assert (!csr_retire_cmd_o.instret && !commit_o.valid &&
                  csr_retire_cmd_o.trap.pc == wfi_resume_pc_q)
            else $error("WFI wake retired twice or saved the wrong PC");
        end
      end
      assert (!(wfi_enter_o && irq_taken_o))
        else $error("WFI entered wait while taking an interrupt");
      if (irq_defer_i) begin
        assert (!irq_taken_o)
          else $error("Interrupt was taken while a multi-cycle owner required deferral");
      end
      if (!pkt_i.valid) begin
        assert (!(rf_write_cmd_o.valid || csr_preview_req_o.valid ||
                  csr_retire_cmd_o.mret || csr_retire_cmd_o.instret ||
                  commit_o.valid))
          else $error("Invalid EX/WB packet caused a retirement effect");
        if (!wfi_wait_q) begin
          assert (!(csr_retire_cmd_o.trap.valid || redirect_o.valid))
            else $error("Bubble generated trap/redirect outside WFI wake");
        end
      end
    end
  end
`endif
endmodule
`default_nettype wire
