`timescale 1ns / 1ps
`default_nettype none
import riscv_pkg::*;

// Fixed-latency, single-outstanding RV32M multiply backend.
//
// IDLE:    accept and register one request.
// PARTIAL: form four independent signed/unsigned 17-bit partial products.
// REDUCE:  register two aligned 66-bit partial sums.
// COMBINE: register the final 66-bit product.
// RESP:    hold the selected architectural result until accepted or killed.
module rv32m_mul_reg (
  input  wire logic       clk_i,
  input  wire logic       rst_ni,
  input  wire logic       req_valid_i,
  output logic            req_ready_o,
  input  wire rv32m_req_t req_i,
  output logic            rsp_valid_o,
  input  wire logic       rsp_ready_i,
  output rv32m_rsp_t      rsp_o,
  input  wire logic       kill_i,
  output logic            wait_o,
  output logic            busy_o
);
  typedef enum logic [2:0] {
    MUL_IDLE,
    MUL_PARTIAL,
    MUL_REDUCE,
    MUL_COMBINE,
    MUL_RESP
  } mul_state_e;

  mul_state_e state_q;
  rv32m_req_t req_q;

  logic lhs_signed;
  logic rhs_signed;
  logic signed [DW:0] lhs_ext;
  logic signed [DW:0] rhs_ext;
  logic [33:0] pp_ll_q;
  logic signed [33:0] pp_lh_q;
  logic signed [33:0] pp_hl_q;
  logic signed [31:0] pp_hh_q;
  logic signed [(2*DW)+1:0] reduce_lo_d;
  logic signed [(2*DW)+1:0] reduce_hi_d;
  logic signed [(2*DW)+1:0] reduce_lo_q;
  logic signed [(2*DW)+1:0] reduce_hi_q;
  logic signed [(2*DW)+1:0] product_q;
  rv32m_rsp_t rsp_d;

  assign req_ready_o = !kill_i && state_q == MUL_IDLE;
  assign rsp_valid_o = !kill_i && state_q == MUL_RESP;
  assign rsp_o       = rsp_d;
  assign busy_o      = state_q != MUL_IDLE;

  // Do not couple wait_o to kill_i. In the core, wait participates in
  // interrupt deferral and retirement redirect generation, which produces
  // kill_i; gating wait with kill would create a combinational control loop.
  assign wait_o = (state_q == MUL_PARTIAL) ||
                  (state_q == MUL_REDUCE) ||
                  (state_q == MUL_COMBINE) ||
                  (state_q == MUL_RESP && !rsp_ready_i) ||
                  (state_q == MUL_IDLE && req_valid_i);

  always_comb begin
    lhs_signed = (req_q.op == MULDIV_MULH) ||
                 (req_q.op == MULDIV_MULHSU);
    rhs_signed = req_q.op == MULDIV_MULH;
    lhs_ext     = $signed({lhs_signed && req_q.lhs[DW-1], req_q.lhs});
    rhs_ext     = $signed({rhs_signed && req_q.rhs[DW-1], req_q.rhs});

    reduce_lo_d = $signed({32'b0, pp_ll_q}) +
                  ($signed({{32{pp_lh_q[33]}}, pp_lh_q}) <<< 17);
    reduce_hi_d = ($signed({{32{pp_hl_q[33]}}, pp_hl_q}) <<< 17) +
                  ($signed({{34{pp_hh_q[31]}}, pp_hh_q}) <<< 34);

    rsp_d = '0;
    unique case (req_q.op)
      MULDIV_MUL:    rsp_d.result = product_q[DW-1:0];
      MULDIV_MULH,
      MULDIV_MULHSU,
      MULDIV_MULHU:  rsp_d.result = product_q[(2*DW)-1:DW];
      default:       rsp_d.result = '0;
    endcase
  end

  // Only protocol validity is reset. Datapath registers are don't-care while
  // state_q is IDLE, which avoids asynchronous reset pins at DSP boundaries.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= MUL_IDLE;
    end else if (kill_i) begin
      state_q <= MUL_IDLE;
    end else begin
      unique case (state_q)
        MUL_IDLE: begin
          if (req_valid_i && req_ready_o) begin
            state_q <= MUL_PARTIAL;
          end
        end

        MUL_PARTIAL: state_q <= MUL_REDUCE;
        MUL_REDUCE:  state_q <= MUL_COMBINE;
        MUL_COMBINE: state_q <= MUL_RESP;

        MUL_RESP: begin
          if (rsp_ready_i)
            state_q <= MUL_IDLE;
        end

        default: begin
          state_q <= MUL_IDLE;
        end
      endcase
    end
  end

  always_ff @(posedge clk_i) begin
    if (!kill_i) begin
      if (state_q == MUL_IDLE && req_valid_i && req_ready_o)
        req_q <= req_i;

      if (state_q == MUL_PARTIAL) begin
        pp_ll_q <= lhs_ext[16:0] * rhs_ext[16:0];
        pp_lh_q <= $signed({1'b0, lhs_ext[16:0]}) *
                   $signed(rhs_ext[32:17]);
        pp_hl_q <= $signed(lhs_ext[32:17]) *
                   $signed({1'b0, rhs_ext[16:0]});
        pp_hh_q <= $signed(lhs_ext[32:17]) *
                   $signed(rhs_ext[32:17]);
      end

      if (state_q == MUL_REDUCE) begin
        reduce_lo_q <= reduce_lo_d;
        reduce_hi_q <= reduce_hi_d;
      end

      if (state_q == MUL_COMBINE)
        product_q <= reduce_lo_q + reduce_hi_q;
    end
  end

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
          else $error("Registered multiply response changed while backpressured");
      end
      stalled_rsp_valid_q <= rsp_valid_o && !rsp_ready_i;
      if (rsp_valid_o && !rsp_ready_i)
        stalled_rsp_q <= rsp_o;

      if (state_q != MUL_IDLE) begin
        assert (!req_ready_o)
          else $error("Registered multiplier accepted a restart while busy");
      end
    end
  end
`endif
endmodule

`default_nettype wire
