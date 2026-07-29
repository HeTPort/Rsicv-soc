`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_ar004_packet_contract;
  ex_wb_pkt_t pkt;
  logic rf_wen;
  logic [4:0] rf_waddr;
  logic [DW-1:0] rf_wdata;

  wb_stage dut (
    .pkt_wb_i    (pkt),
    .rf_wen_o    (rf_wen),
    .rf_waddr_o  (rf_waddr),
    .rf_wdata_o  (rf_wdata),
    .csr_we_o    (),
    .csr_addr_o  (),
    .csr_wdata_o (),
    .mret_o      (),
    .trap_cause_o(),
    .trap_val_o  ()
  );

  initial begin
    pkt = EX_WB_PKT_BUBBLE;
    pkt.valid = 1'b1;
    pkt.rf.we = 1'b1;
    pkt.rf.addr = 5'd7;
    pkt.wb_sel = WB_MEM;
    pkt.mem_valid = 1'b1;
    pkt.mem_we = 1'b0;
    pkt.mem_rdata = 32'h1122_3344;
    pkt.mem_load_data = 32'hffff_ff80;
    pkt.mem_error = 1'b0;
    #1ns;

    assert (rf_wen && rf_waddr == 5'd7 &&
            rf_wdata == 32'hffff_ff80)
      else $fatal(1, "WB did not consume packet-owned aligned load data");
    assert (pkt.mem_rdata == 32'h1122_3344)
      else $fatal(1, "packet-owned raw response data was not retained");

    pkt.mem_error = 1'b1;
    #1ns;
    assert (!rf_wen)
      else $fatal(1, "faulting memory packet enabled GPR writeback");

    $display("[AR004-PACKET-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
