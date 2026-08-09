`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_csr_retire_order;
  logic clk;
  logic rst_n;
  logic irq_mti;
  logic [11:0] csr_read_addr;
  logic [31:0] csr_read_data;
  logic csr_implemented;
  logic csr_read_only;
  logic csr_privilege_ok;
  logic [31:0] preview_effective;
  logic [31:0] mtvec;
  logic [31:0] mepc;
  logic [31:0] mstatus;
  logic [31:0] mie;
  logic [31:0] mip;

  ex_wb_pkt_t pkt;
  csr_write_req_t preview_req;
  rf_write_cmd_t rf_write_cmd;
  csr_retire_cmd_t retire_cmd;
  csr_irq_context_t irq_context;
  redirect_t redirect;
  trap_entry_t trap_entry;
  commit_pkt_t commit;
  logic sync_trap;
  logic irq_taken;
  logic wfi_enter;
  logic wfi_wait;

  retire_stage u_retire (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .pkt_i             (pkt),
    .csr_irq_context_i (irq_context),
    .irq_defer_i       (1'b0),
    .csr_preview_req_o (preview_req),
    .rf_write_cmd_o    (rf_write_cmd),
    .csr_retire_cmd_o  (retire_cmd),
    .redirect_o        (redirect),
    .trap_entry_o      (trap_entry),
    .commit_o          (commit),
    .sync_trap_o       (sync_trap),
    .irq_taken_o       (irq_taken),
    .wfi_enter_o       (wfi_enter),
    .wfi_wait_o        (wfi_wait)
  );

  csr_regfile u_csr (
    .clk_i                     (clk),
    .rst_ni                    (rst_n),
    .current_priv_i            (PRIV_MODE_M),
    .csr_addr_i                (csr_read_addr),
    .csr_rdata_o               (csr_read_data),
    .csr_implemented_o         (csr_implemented),
    .csr_read_only_o           (csr_read_only),
    .csr_privilege_ok_o        (csr_privilege_ok),
    .preview_req_i             (preview_req),
    .preview_wdata_effective_o (preview_effective),
    .irq_context_o             (irq_context),
    .retire_cmd_i              (retire_cmd),
    .irq_mti_i                 (irq_mti),
    .mtvec_o                    (mtvec),
    .mepc_o                     (mepc),
    .mstatus_o                  (mstatus),
    .mie_o                      (mie),
    .mip_o                      (mip)
  );

  always #5 clk = ~clk;

  task automatic set_csr_packet(
    input logic [31:0] pc,
    input logic [11:0] addr,
    input logic [31:0] wdata
  );
    begin
      pkt           = EX_WB_PKT_BUBBLE;
      pkt.valid     = 1'b1;
      pkt.pc        = pc;
      pkt.next_pc   = pc + 32'd4;
      pkt.instr     = 32'h0000_1073;
      pkt.csr.valid = 1'b1;
      pkt.csr.write = 1'b1;
      pkt.csr.addr  = addr;
      pkt.csr.wdata = wdata;
    end
  endtask

  task automatic clock_packet;
    begin
      @(posedge clk);
      #1;
      pkt = EX_WB_PKT_BUBBLE;
      @(negedge clk);
    end
  endtask

  initial begin
    clk           = 1'b0;
    rst_n         = 1'b0;
    irq_mti       = 1'b0;
    csr_read_addr = CSR_MSTATUS;
    pkt           = EX_WB_PKT_BUBBLE;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Establish an aligned direct-mode vector and enable MTIE while global
    // MIE remains clear, so neither setup instruction can take the IRQ.
    set_csr_packet(32'h20, CSR_MTVEC, 32'h0000_0183);
    #1;
    assert (!irq_taken && preview_effective == 32'h0000_0180)
      else $fatal(1, "mtvec WARL preview is wrong");
    clock_packet();
    assert (mtvec == 32'h0000_0180)
      else $fatal(1, "mtvec write did not commit");

    set_csr_packet(32'h24, CSR_MIE, 32'hffff_ffff);
    #1;
    assert (!irq_taken && irq_context.mie == 32'h0000_0080)
      else $fatal(1, "mie WARL preview is wrong");
    clock_packet();

    // Pending MTIP plus a retiring write that enables global MIE must take an
    // interrupt after preserving that write and save the instruction next PC.
    irq_mti = 1'b1;
    set_csr_packet(32'h28, CSR_MSTATUS, 32'h0000_0008);
    #1;
    assert (irq_context.mstatus[MSTATUS_MIE_BIT] && irq_taken)
      else $fatal(1, "post-retirement mstatus did not enable the interrupt");
    assert (retire_cmd.csr_write.valid && retire_cmd.trap.valid &&
            retire_cmd.trap.interrupt && retire_cmd.trap.pc == 32'h2c)
      else $fatal(1, "CSR write and interrupt were not composed");
    assert (redirect.pc == 32'h0000_0180)
      else $fatal(1, "interrupt did not use effective mtvec");
    clock_packet();

    assert (!mstatus[MSTATUS_MIE_BIT] && mstatus[MSTATUS_MPIE_BIT])
      else $fatal(1, "trap entry did not save post-write MIE into MPIE");
    assert (mepc == 32'h2c)
      else $fatal(1, "interrupt mepc is not the retiring instruction next PC");
    csr_read_addr = CSR_MCAUSE;
    #1;
    assert (csr_read_data == MCAUSE_IRQ_M_TIMER)
      else $fatal(1, "timer interrupt mcause is wrong");

    // MRET restores MIE but excludes a same-boundary interrupt.
    pkt         = EX_WB_PKT_BUBBLE;
    pkt.valid   = 1'b1;
    pkt.pc      = 32'h100;
    pkt.next_pc = mepc;
    pkt.is_mret = 1'b1;
    #1;
    assert (retire_cmd.mret && !irq_taken)
      else $fatal(1, "MRET did not exclude same-boundary interrupt");
    clock_packet();
    assert (mstatus[MSTATUS_MIE_BIT])
      else $fatal(1, "MRET did not restore MIE");

    // A retiring mtvec write is visible to an interrupt selected at that same
    // boundary.
    set_csr_packet(32'h104, CSR_MTVEC, 32'h0000_0243);
    #1;
    assert (irq_taken && redirect.pc == 32'h0000_0240)
      else $fatal(1, "same-boundary interrupt used stale mtvec");
    clock_packet();

    // Restore MIE once more, then prove that a retiring write which disables
    // MTIE prevents a pending interrupt.
    pkt         = EX_WB_PKT_BUBBLE;
    pkt.valid   = 1'b1;
    pkt.is_mret = 1'b1;
    clock_packet();
    set_csr_packet(32'h108, CSR_MIE, 32'h0000_0000);
    #1;
    assert (!irq_context.mie[MIE_MTIE_BIT] && !irq_taken &&
            !retire_cmd.trap.valid)
      else $fatal(1, "post-retirement mie disable did not mask pending MTIP");
    clock_packet();

    assert (mip[MIP_MTIP_BIT] && irq_mti)
      else $fatal(1, "hardware MTIP was not composed into mip");

    $display("[CSR-RETIRE-ORDER-TB] RESULT: PASS");
    $finish;
  end
endmodule
`default_nettype wire
