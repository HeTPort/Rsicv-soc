`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: wb_stage
// Description:
//   Writeback stage (load alignment moved to LSU).
// ============================================================
module wb_stage #(
  parameter int DW = riscv_pkg::DW
)(
  input  ex_wb_pkt_t   pkt_wb_i,
  input  logic [DW-1:0] load_data_i,   // from LSU (already aligned & extended)

  output logic          rf_wen_o,
  output logic [4:0]    rf_waddr_o,
  output logic [DW-1:0] rf_wdata_o
);

  logic          valid_i, rf_wen_i, illegal_instr_i, ecall_i, ebreak_i, mem_misaligned_i;
  logic [4:0]    rf_waddr_i;
  wb_sel_e       wb_sel_i;
  logic [DW-1:0] alu_data_i, pc4_data_i;

  assign valid_i          = pkt_wb_i.valid;
  assign rf_wen_i         = pkt_wb_i.rf.we;
  assign rf_waddr_i       = pkt_wb_i.rf.addr;
  assign wb_sel_i         = pkt_wb_i.wb_sel;
  assign alu_data_i       = pkt_wb_i.alu_data;
  assign pc4_data_i       = pkt_wb_i.pc4_data;
  assign illegal_instr_i  = pkt_wb_i.exc.illegal_instr;
  assign ecall_i          = pkt_wb_i.exc.ecall;
  assign ebreak_i         = pkt_wb_i.exc.ebreak;
  assign mem_misaligned_i = pkt_wb_i.mem_misaligned;

  // ------------------------------------------------------------
  // Final writeback mux
  // ------------------------------------------------------------
  always_comb begin
    rf_wen_o   = 1'b0;
    rf_waddr_o = rf_waddr_i;
    rf_wdata_o = '0;
    if (valid_i &&
        rf_wen_i &&
        rf_waddr_i != 5'd0 &&
        !illegal_instr_i &&
        !ecall_i &&
        !ebreak_i &&
        !mem_misaligned_i) begin
      unique case (wb_sel_i)
        WB_NONE: begin
          rf_wen_o   = 1'b0;
          rf_wdata_o = '0;
        end
        WB_ALU: begin
          rf_wen_o   = 1'b1;
          rf_wdata_o = alu_data_i;
        end
        WB_MEM: begin
          rf_wen_o   = 1'b1;
          rf_wdata_o = load_data_i;   // from LSU
        end
        WB_PC4: begin
          rf_wen_o   = 1'b1;
          rf_wdata_o = pc4_data_i;
        end
        WB_MULDIV: begin
          rf_wen_o   = 1'b1;
          rf_wdata_o = alu_data_i;
        end
        default: begin
          rf_wen_o   = 1'b0;
          rf_wdata_o = '0;
        end
      endcase
    end
  end
endmodule
`default_nettype wire