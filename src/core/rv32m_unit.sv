`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;

// Single-outstanding RV32M facade. Multiplication uses a fixed-latency
// registered blocking backend; division uses the existing kill-safe iterative
// implementation.
// A divider response is captured only when downstream backpressure overlaps
// its one-cycle completion pulse.
module rv32m_unit (
  input  wire logic       clk_i,
  input  wire logic       rst_ni,
  input  wire logic       req_valid_i,
  output logic       req_ready_o,
  input  wire rv32m_req_t req_i,
  output logic       rsp_valid_o,
  input  wire logic       rsp_ready_i,
  output rv32m_rsp_t rsp_o,
  input  wire logic       kill_i,
  output logic       wait_o,
  output logic       busy_o
);
  logic is_mul;
  logic is_div;
  logic div_signed;
  logic div_select_remainder;
  logic div_select_remainder_q;
  logic div_start;
  logic div_busy;
  logic div_complete;
  logic mul_req_valid;
  logic mul_req_ready;
  logic mul_rsp_valid;
  logic mul_rsp_ready;
  logic mul_wait;
  logic mul_busy;
  rv32m_rsp_t mul_rsp;
  logic [DW-1:0] div_quotient;
  logic [DW-1:0] div_remainder;
  logic [DW-1:0] div_result;
  logic rsp_hold_valid_q;
  rv32m_rsp_t rsp_hold_q;

  always_comb begin
    is_mul = 1'b0;
    is_div = 1'b0;
    div_signed = 1'b0;
    div_select_remainder = 1'b0;

    unique case (req_i.op)
      MULDIV_MUL,
      MULDIV_MULH,
      MULDIV_MULHSU,
      MULDIV_MULHU: is_mul = 1'b1;
      MULDIV_DIV: begin
        is_div = 1'b1;
        div_signed = 1'b1;
      end
      MULDIV_DIVU: is_div = 1'b1;
      MULDIV_REM: begin
        is_div = 1'b1;
        div_signed = 1'b1;
        div_select_remainder = 1'b1;
      end
      MULDIV_REMU: begin
        is_div = 1'b1;
        div_select_remainder = 1'b1;
      end
      default: begin
        is_mul = 1'b0;
        is_div = 1'b0;
      end
    endcase
  end

  assign mul_req_valid = req_valid_i && is_mul &&
                         !div_busy && !div_complete && !rsp_hold_valid_q;
  assign mul_rsp_ready = rsp_ready_i &&
                         !rsp_hold_valid_q && !div_complete;

  rv32m_mul_reg u_rv32m_mul_reg (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .req_valid_i (mul_req_valid),
    .req_ready_o (mul_req_ready),
    .req_i       (req_i),
    .rsp_valid_o (mul_rsp_valid),
    .rsp_ready_i (mul_rsp_ready),
    .rsp_o       (mul_rsp),
    .kill_i      (kill_i),
    .wait_o      (mul_wait),
    .busy_o      (mul_busy)
  );

  assign req_ready_o = !kill_i &&
                       ((is_mul && mul_req_ready &&
                         !div_busy && !div_complete && !rsp_hold_valid_q) ||
                        (is_div && !div_busy && !div_complete &&
                         !rsp_hold_valid_q && !mul_busy));
  assign div_start = req_valid_i && req_ready_o && is_div;
  assign div_result = div_select_remainder_q ? div_remainder : div_quotient;

  radix2_divider #(
    .DW(DW)
  ) u_radix2_divider (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .start_i     (div_start),
    .kill_i      (kill_i),
    .signed_i    (div_signed),
    .dividend_i  (req_i.lhs),
    .divisor_i   (req_i.rhs),
    .busy_o      (div_busy),
    .complete_o  (div_complete),
    .quotient_o  (div_quotient),
    .remainder_o (div_remainder)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_hold_valid_q <= 1'b0;
      rsp_hold_q       <= '0;
      div_select_remainder_q <= 1'b0;
    end else if (kill_i) begin
      rsp_hold_valid_q <= 1'b0;
      rsp_hold_q       <= '0;
      div_select_remainder_q <= 1'b0;
    end else begin
      if (div_start)
        div_select_remainder_q <= div_select_remainder;

      if (rsp_hold_valid_q && rsp_ready_i)
        rsp_hold_valid_q <= 1'b0;

      if (div_complete && !rsp_ready_i) begin
        rsp_hold_valid_q <= 1'b1;
        rsp_hold_q.result <= div_result;
      end
    end
  end

  always_comb begin
    rsp_valid_o = 1'b0;
    rsp_o       = '0;

    if (!kill_i) begin
      if (rsp_hold_valid_q) begin
        rsp_valid_o = 1'b1;
        rsp_o       = rsp_hold_q;
      end else if (div_complete) begin
        rsp_valid_o   = 1'b1;
        rsp_o.result  = div_result;
      end else if (mul_rsp_valid) begin
        rsp_valid_o = 1'b1;
        rsp_o       = mul_rsp;
      end
    end
  end

  assign busy_o = mul_busy || div_busy || div_complete || rsp_hold_valid_q;
  // This ownership signal intentionally does not depend on kill_i. The core's
  // retirement redirect can generate kill_i, so coupling kill back into its
  // interrupt-deferral input would create a combinational control loop.
  assign wait_o = mul_wait || div_busy ||
                  (req_valid_i && is_div && !div_complete &&
                   !rsp_hold_valid_q);

`ifndef SYNTHESIS
  rv32m_rsp_t stalled_rsp_q;
  logic stalled_rsp_valid_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni || kill_i) begin
      stalled_rsp_q       <= '0;
      stalled_rsp_valid_q <= 1'b0;
    end else begin
      if (stalled_rsp_valid_q) begin
        assert (rsp_valid_o && rsp_o == stalled_rsp_q)
          else $error("RV32M response changed while backpressured");
      end
      stalled_rsp_valid_q <= rsp_valid_o && !rsp_ready_i;
      if (rsp_valid_o && !rsp_ready_i)
        stalled_rsp_q <= rsp_o;

      assert (!(div_start && div_busy))
        else $error("RV32M facade restarted divider while busy");
    end
  end
`endif
endmodule

`default_nettype wire
