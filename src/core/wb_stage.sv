`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;
module wb_stage #(
  parameter int DW = riscv_pkg::DW
)(
  input  logic          valid_i,
  input  logic          rf_wen_i,
  input  logic [4:0]    rf_waddr_i,
  input  logic [DW-1:0] alu_data_i,
  input  logic          is_load_i,
  input  logic [2:0]    load_funct3_i,
  input  logic [1:0]    load_offset_i,
  input  logic [DW-1:0] dmem_rdata_i,
  output logic          rf_wen_o,
  output logic [4:0]    rf_waddr_o,
  output logic [DW-1:0] rf_wdata_o
);
  logic [7:0]  load_byte;
  logic [15:0] load_half;
  always_comb begin
    unique case (load_offset_i)
      2'd0: load_byte = dmem_rdata_i[7:0];
      2'd1: load_byte = dmem_rdata_i[15:8];
      2'd2: load_byte = dmem_rdata_i[23:16];
      2'd3: load_byte = dmem_rdata_i[31:24];
    endcase
  end
  always_comb begin
    unique case (load_offset_i[1])
      1'b0: load_half = dmem_rdata_i[15:0];
      1'b1: load_half = dmem_rdata_i[31:16];
    endcase
  end
  always_comb begin
    rf_wen_o   = valid_i && rf_wen_i;
    rf_waddr_o = rf_waddr_i;
    rf_wdata_o = alu_data_i;
    if (valid_i && rf_wen_i && is_load_i) begin
      unique case (load_funct3_i)
        FUNCT3_LB:  rf_wdata_o = {{24{load_byte[7]}}, load_byte};
        FUNCT3_LH:  rf_wdata_o = {{16{load_half[15]}}, load_half};
        FUNCT3_LW:  rf_wdata_o = dmem_rdata_i;
        FUNCT3_LBU: rf_wdata_o = {24'h0, load_byte};
        FUNCT3_LHU: rf_wdata_o = {16'h0, load_half};
        default: begin
          rf_wen_o   = 1'b0;
          rf_wdata_o = '0;
        end
      endcase
    end
  end
endmodule
`default_nettype wire