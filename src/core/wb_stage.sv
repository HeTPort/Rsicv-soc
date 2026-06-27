`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
// ============================================================
// Module: wb_stage
// Description:
//   Writeback stage.
//
// Responsibilities:
//   - Select final register writeback data according to wb_sel_i.
//   - Perform load data extraction and sign/zero extension.
//   - Suppress register write on invalid instruction or exception.
//
// Notes:
//   - Load/store memory format is little-endian.
//   - WB no longer depends on raw funct3 encoding.
// ============================================================
module wb_stage #(
  parameter int DW = riscv_pkg::DW
)(
  input  ex_wb_pkt_t   pkt_wb_i,
  input  logic [DW-1:0] dmem_rdata_i, // 横向总线读数据依然独立
  
  // 寄存器堆写回接口依然独立
  output logic          rf_wen_o,
  output logic [4:0]    rf_waddr_o,
  output logic [DW-1:0] rf_wdata_o
);


  logic          valid_i, rf_wen_i, illegal_instr_i, ecall_i, ebreak_i, mem_misaligned_i;
  logic [4:0]    rf_waddr_i;
  wb_sel_e       wb_sel_i;
  logic [DW-1:0] alu_data_i, pc4_data_i;
  mem_size_e     mem_size_i;
  logic          mem_unsigned_i;
  logic [1:0]    load_offset_i;

  assign valid_i          = pkt_wb_i.valid;
  assign rf_wen_i         = pkt_wb_i.rf.we;
  assign rf_waddr_i       = pkt_wb_i.rf.addr;
  assign wb_sel_i         = pkt_wb_i.wb_sel;
  assign alu_data_i       = pkt_wb_i.alu_data;
  assign pc4_data_i       = pkt_wb_i.pc4_data;
  assign mem_size_i       = pkt_wb_i.mem_info.mem_size;
  assign mem_unsigned_i   = pkt_wb_i.mem_info.mem_unsigned;
  assign load_offset_i    = pkt_wb_i.mem_info.load_offset;
  assign illegal_instr_i  = pkt_wb_i.exc.illegal_instr;
  assign ecall_i          = pkt_wb_i.exc.ecall;
  assign ebreak_i         = pkt_wb_i.exc.ebreak;
  assign mem_misaligned_i = pkt_wb_i.mem_misaligned;


  logic [7:0]  load_byte;
  logic [15:0] load_half;
  logic [DW-1:0] load_extend_data;
  // ------------------------------------------------------------
  // Little-endian byte select
  // ------------------------------------------------------------
  always_comb begin
    load_byte = 8'h00;
    unique case (load_offset_i)
      2'd0: load_byte = dmem_rdata_i[7:0];
      2'd1: load_byte = dmem_rdata_i[15:8];
      2'd2: load_byte = dmem_rdata_i[23:16];
      2'd3: load_byte = dmem_rdata_i[31:24];
      default: load_byte = 8'h00;
    endcase
  end
  // ------------------------------------------------------------
  // Little-endian halfword select
  // ------------------------------------------------------------
  always_comb begin
    load_half = 16'h0000;
    unique case (load_offset_i[1])
      1'b0: load_half = dmem_rdata_i[15:0];
      1'b1: load_half = dmem_rdata_i[31:16];
      default: load_half = 16'h0000;
    endcase
  end
  // ------------------------------------------------------------
  // Load sign/zero extension
  // ------------------------------------------------------------
  always_comb begin
    load_extend_data = '0;
    unique case (mem_size_i)
      MEM_SIZE_BYTE: begin
        if (mem_unsigned_i) begin
          load_extend_data = {{(DW-8){1'b0}}, load_byte};
        end
        else begin
          load_extend_data = {{(DW-8){load_byte[7]}}, load_byte};
        end
      end
      MEM_SIZE_HALF: begin
        if (mem_unsigned_i) begin
          load_extend_data = {{(DW-16){1'b0}}, load_half};
        end
        else begin
          load_extend_data = {{(DW-16){load_half[15]}}, load_half};
        end
      end
      MEM_SIZE_WORD: begin
        load_extend_data = dmem_rdata_i;
      end
      default: begin
        load_extend_data = '0;
      end
    endcase
  end
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
          rf_wdata_o = load_extend_data;
        end
        WB_PC4: begin
          rf_wen_o   = 1'b1;
          rf_wdata_o = pc4_data_i;
        end
        WB_MULDIV: begin
          // Current execute implementation sends mul/div result
          // through alu_data_i.
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