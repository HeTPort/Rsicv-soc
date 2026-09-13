`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;

// Combinational RV32M multiply backend. All four multiply variants share one
// signed 33-by-33 product; operand extension selects the required signedness.
module rv32m_mul_comb #(
  parameter int DW = riscv_pkg::DW
)(
  input  wire rv32m_req_t req_i,
  output logic [DW-1:0] result_o
);
  logic lhs_signed;
  logic rhs_signed;
  logic signed [DW:0] lhs_ext;
  logic signed [DW:0] rhs_ext;
  logic signed [(2*DW)+1:0] product_ext;

  always_comb begin
    lhs_signed = (req_i.op == MULDIV_MULH) ||
                 (req_i.op == MULDIV_MULHSU);
    rhs_signed = (req_i.op == MULDIV_MULH);
    lhs_ext     = $signed({lhs_signed && req_i.lhs[DW-1], req_i.lhs});
    rhs_ext     = $signed({rhs_signed && req_i.rhs[DW-1], req_i.rhs});
    product_ext = lhs_ext * rhs_ext;

    unique case (req_i.op)
      MULDIV_MUL:    result_o = product_ext[DW-1:0];
      MULDIV_MULH,
      MULDIV_MULHSU,
      MULDIV_MULHU:  result_o = product_ext[(2*DW)-1:DW];
      default:       result_o = '0;
    endcase
  end

  initial begin
    if (DW != 32)
      $fatal(1, "rv32m_mul_comb currently supports RV32 only");
  end
endmodule

`default_nettype wire
