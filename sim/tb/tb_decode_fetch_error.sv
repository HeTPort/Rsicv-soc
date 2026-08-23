`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

module tb_decode_fetch_error;
  fetch_pkt_t fetch_pkt;
  id_ex_pkt_t decoded_pkt;
  logic [4:0] rs1_addr;
  logic [4:0] rs2_addr;

  decode dut (
    .pktd_i           (fetch_pkt),
    .rf_rs1_raddr_o  (rs1_addr),
    .rf_rs2_raddr_o  (rs2_addr),
    .rf_rs1_rdata_i  (32'h1122_3344),
    .rf_rs2_rdata_i  (32'h5566_7788),
    .pktd_o           (decoded_pkt)
  );

  task automatic check_fetch_fault(
    input logic [31:0] replacement_instr,
    input string       scenario
  );
    id_ex_pkt_t expected;
    begin
      fetch_pkt       = FETCH_PKT_BUBBLE;
      fetch_pkt.valid = 1'b1;
      fetch_pkt.error = 1'b1;
      fetch_pkt.pc    = 32'h0001_0000;
      fetch_pkt.instr = replacement_instr;
      #1ns;

      expected = ID_EX_PKT_BUBBLE;
      expected.valid = 1'b1;
      expected.pc = 32'h0001_0000;
      expected.exc.instr_access_fault = 1'b1;

      assert (decoded_pkt === expected)
        else $fatal(1, "%s replacement data escaped the canonical fault packet", scenario);
    end
  endtask

  initial begin
    // Confirm the non-error path still emits ordinary decoded controls.
    fetch_pkt       = FETCH_PKT_BUBBLE;
    fetch_pkt.valid = 1'b1;
    fetch_pkt.pc    = 32'h0000_0040;
    fetch_pkt.instr = 32'h0010_0293; // addi x5, x0, 1
    #1ns;
    assert (decoded_pkt.valid && decoded_pkt.rf.we &&
            decoded_pkt.rf.addr == 5'd5 &&
            decoded_pkt.ex_ctrl.alu_op == ALU_ADD &&
            decoded_pkt.ex_ctrl.wb_sel == WB_ALU &&
            !decoded_pkt.exc.instr_access_fault)
      else $fatal(1, "normal decode path changed during fetch-fault canonicalization");

    // Each replacement word would normally enable a different side effect or
    // multi-cycle owner. With error=1 they must all produce the same packet.
    check_fetch_fault(32'h0001_2083, "LOAD");
    check_fetch_fault(32'h0031_2023, "STORE");
    check_fetch_fault(32'h0000_00ef, "JAL");
    check_fetch_fault(32'h0000_0063, "BRANCH");
    check_fetch_fault(32'h3001_10f3, "CSR");
    check_fetch_fault(32'h0231_40b3, "DIV");
    check_fetch_fault(32'h3020_0073, "MRET");
    check_fetch_fault(32'h1050_0073, "WFI");

    $display("[DECODE-FETCH-ERROR-TB] RESULT: PASS");
    $finish;
  end
endmodule

`default_nettype wire
