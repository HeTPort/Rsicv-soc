`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_retire_stage;
  logic clk;
  logic rst_n;
  ex_wb_pkt_t pkt;
  csr_irq_context_t irq_context;
  csr_write_req_t csr_preview_req;
  rf_write_cmd_t rf_write_cmd;
  csr_retire_cmd_t csr_retire_cmd;
  redirect_t redirect;
  trap_entry_t trap_entry;
  commit_pkt_t commit;
  logic sync_trap;
  logic irq_taken;
  logic wfi_enter;
  logic wfi_wait;
  logic irq_defer;

  retire_stage u_dut (
    .clk_i             (clk),
    .rst_ni            (rst_n),
    .pkt_i             (pkt),
    .csr_irq_context_i (irq_context),
    .irq_defer_i       (irq_defer),
    .csr_preview_req_o (csr_preview_req),
    .rf_write_cmd_o    (rf_write_cmd),
    .csr_retire_cmd_o  (csr_retire_cmd),
    .redirect_o        (redirect),
    .trap_entry_o      (trap_entry),
    .commit_o          (commit),
    .sync_trap_o       (sync_trap),
    .irq_taken_o       (irq_taken),
    .wfi_enter_o       (wfi_enter),
    .wfi_wait_o        (wfi_wait)
  );

  always #5 clk = ~clk;

  task automatic clear_inputs;
    begin
      pkt         = EX_WB_PKT_BUBBLE;
      irq_context = '0;
      irq_context.mtvec = 32'h0000_0100;
      irq_defer = 1'b0;
    end
  endtask

  initial begin
    clk   = 1'b0;
    rst_n = 1'b0;
    clear_inputs();
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    // Ordinary ALU retirement: exactly one RF write and one instret event.
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid     = 1'b1;
    pkt.pc        = 32'h20;
    pkt.next_pc   = 32'h24;
    pkt.instr     = 32'h0010_0193;
    pkt.rf.we     = 1'b1;
    pkt.rf.addr   = 5'd3;
    pkt.wb_sel    = WB_ALU;
    pkt.alu_data  = 32'h1234_5678;
    #1;
    assert (rf_write_cmd.valid && rf_write_cmd.addr == 5'd3 &&
            rf_write_cmd.data == 32'h1234_5678)
      else $fatal(1, "ordinary retirement RF command is wrong");
    assert (csr_retire_cmd.instret && !csr_retire_cmd.trap.valid &&
            !csr_retire_cmd.csr_write.valid)
      else $fatal(1, "ordinary retirement CSR command is wrong");
    assert (commit.valid && !commit.trap && commit.rd_we)
      else $fatal(1, "ordinary retirement commit observation is wrong");

    @(posedge clk);
    @(negedge clk);

    // A synchronous fault remains observable but suppresses normal effects.
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid                   = 1'b1;
    pkt.pc                      = 32'h40;
    pkt.next_pc                 = 32'h44;
    pkt.instr                   = 32'hffff_ffff;
    pkt.rf.we                   = 1'b1;
    pkt.rf.addr                 = 5'd5;
    pkt.wb_sel                  = WB_ALU;
    pkt.alu_data                = 32'hdead_beef;
    pkt.exc.illegal_instr       = 1'b1;
    pkt.trap_pc                 = 32'h40;
    pkt.trap_cause              = MCAUSE_ILLEGAL_INST;
    pkt.trap_val                = 32'hffff_ffff;
    pkt.csr.valid               = 1'b1;
    pkt.csr.write               = 1'b1;
    pkt.csr.addr                = CSR_MSTATUS;
    pkt.csr.wdata               = 32'h8;
    irq_context.mstatus         = 32'h0000_0008;
    irq_context.mie             = 32'h0000_0080;
    irq_context.mip             = 32'h0000_0080;
    #1;
    assert (sync_trap && trap_entry.valid && !trap_entry.interrupt)
      else $fatal(1, "synchronous trap entry was not generated");
    assert (!rf_write_cmd.valid && !csr_preview_req.valid &&
            !csr_retire_cmd.csr_write.valid && !csr_retire_cmd.instret)
      else $fatal(1, "synchronous trap did not suppress normal effects");
    assert (redirect.valid && redirect.reason == REDIRECT_SYNC_TRAP &&
            redirect.pc == irq_context.mtvec)
      else $fatal(1, "synchronous trap redirect is wrong");
    assert (commit.valid && commit.trap && !commit.rd_we)
      else $fatal(1, "faulting commit observation is wrong");

    @(posedge clk);
    @(negedge clk);

    // A legal CSR retirement exposes a preview request and commit command.
    irq_context = '0;
    irq_context.mtvec = 32'h0000_0100;
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid       = 1'b1;
    pkt.pc          = 32'h60;
    pkt.next_pc     = 32'h64;
    pkt.instr       = 32'h3000_9073;
    pkt.csr.valid   = 1'b1;
    pkt.csr.write   = 1'b1;
    pkt.csr.addr    = CSR_MSTATUS;
    pkt.csr.wdata   = 32'h8;
    #1;
    assert (csr_preview_req.valid && csr_preview_req.addr == CSR_MSTATUS &&
            csr_preview_req.wdata == 32'h8)
      else $fatal(1, "CSR preview request is wrong");
    assert (csr_retire_cmd.csr_write == csr_preview_req &&
            csr_retire_cmd.instret)
      else $fatal(1, "CSR retirement command is wrong");

    // An interrupt after a CSR instruction preserves the retiring write and
    // uses the post-instruction next PC. It is not a synchronous commit trap.
    irq_context.mstatus = 32'h0000_0008;
    irq_context.mie     = 32'h0000_0080;
    irq_context.mip     = 32'h0000_0080;
    irq_context.mtvec   = 32'h0000_0180;
    #1;
    assert (irq_taken && csr_retire_cmd.csr_write.valid &&
            csr_retire_cmd.instret && csr_retire_cmd.trap.valid &&
            csr_retire_cmd.trap.interrupt)
      else $fatal(1, "interrupt discarded the retiring CSR instruction");
    assert (csr_retire_cmd.trap.pc == pkt.next_pc &&
            csr_retire_cmd.trap.cause == MCAUSE_IRQ_M_TIMER &&
            redirect.reason == REDIRECT_INTERRUPT &&
            redirect.pc == irq_context.mtvec)
      else $fatal(1, "interrupt trap metadata/redirect is wrong");
    assert (commit.valid && !commit.trap)
      else $fatal(1, "asynchronous interrupt was mislabeled as commit trap");

    // MRET keeps its existing redirect/status split and excludes an interrupt
    // from the same retirement boundary.
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid   = 1'b1;
    pkt.pc      = 32'h80;
    pkt.next_pc = 32'h200;
    pkt.is_mret = 1'b1;
    #1;
    assert (csr_retire_cmd.mret && !irq_taken &&
            !csr_retire_cmd.trap.valid && !redirect.valid)
      else $fatal(1, "MRET boundary incorrectly selected an interrupt");

    // A retiring taken branch supplies its resolved target as next_pc.
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid   = 1'b1;
    pkt.pc      = 32'h84;
    pkt.next_pc = 32'h200;
    pkt.instr   = 32'h0000_0063;
    pkt.wb_sel  = WB_NONE;
    pkt.is_mret = 1'b0;
    #1;
    assert (irq_taken && csr_retire_cmd.trap.pc == 32'h200)
      else $fatal(1, "interrupt after branch did not save resolved next_pc");

    // A completed load may retire normally and then take an interrupt. The
    // memory observation is preserved because it belongs to the older packet.
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid              = 1'b1;
    pkt.pc                 = 32'h88;
    pkt.next_pc            = 32'h8c;
    pkt.mem_valid          = 1'b1;
    pkt.mem_we             = 1'b0;
    pkt.mem_addr           = 32'h8000_0000;
    pkt.mem_rdata          = 32'ha5a5_5a5a;
    pkt.mem_info.mem_size  = MEM_SIZE_WORD;
    #1;
    assert (irq_taken && commit.mem_valid && !commit.mem_we &&
            commit.mem_rdata == 32'ha5a5_5a5a && csr_retire_cmd.instret)
      else $fatal(1, "interrupt after completed load lost retirement effects");

    // A younger LSU/divider owner defers the interrupt without suppressing the
    // current ordinary retirement.
    irq_defer = 1'b1;
    #1;
    assert (!irq_taken && !csr_retire_cmd.trap.valid && commit.valid &&
            csr_retire_cmd.instret)
      else $fatal(1, "multi-cycle ownership did not defer interrupt selection");
    irq_defer = 1'b0;

    // WFI retires once, kills younger work through wfi_enter, and leaves only
    // a logical wait record containing its sequential resume PC.
    irq_context = '0;
    irq_context.mtvec = 32'h0000_0180;
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid   = 1'b1;
    pkt.pc      = 32'h90;
    pkt.next_pc = 32'h94;
    pkt.instr   = INST_WFI;
    pkt.is_wfi  = 1'b1;
    #1;
    assert (wfi_enter && !wfi_wait && csr_retire_cmd.instret &&
            commit.valid && !irq_taken)
      else $fatal(1, "WFI did not retire once before entering wait");
    @(posedge clk);
    #1;
    pkt = EX_WB_PKT_BUBBLE;
    #1;
    assert (wfi_wait && !wfi_enter && !commit.valid &&
            !csr_retire_cmd.instret)
      else $fatal(1, "WFI wait retained a live retirement packet");

    // An eligible IRQ wakes WFI without a second retirement and saves the
    // previously recorded post-WFI PC.
    irq_context.mstatus = 32'h0000_0008;
    irq_context.mie     = 32'h0000_0080;
    irq_context.mip     = 32'h0000_0080;
    #1;
    assert (irq_taken && csr_retire_cmd.trap.valid &&
            csr_retire_cmd.trap.interrupt &&
            csr_retire_cmd.trap.pc == 32'h94 &&
            !csr_retire_cmd.instret && !commit.valid)
      else $fatal(1, "WFI wake duplicated retirement or lost resume PC");
    @(posedge clk);
    #1;
    assert (!wfi_wait)
      else $fatal(1, "WFI wait state did not clear after interrupt entry");

    $display("[RETIRE-STAGE-TB] RESULT: PASS");
    $finish;
  end
endmodule
`default_nettype wire
