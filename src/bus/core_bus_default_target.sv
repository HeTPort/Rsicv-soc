`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Side-effect-free target for every unimplemented or unmapped data address.
// A request accepted in cycle N produces one registered error response during
// cycle N+1. Writes are acknowledged as errors but never reach a stateful
// device.
module core_bus_default_target #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter logic [DW-1:0] DEFAULT_RDATA = '0,
  parameter bit DEFAULT_ERROR = 1'b1
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          req_valid_i,
  output logic          req_ready_o,
  input  core_bus_req_t req_i,
  output logic          rsp_valid_o,
  output core_bus_rsp_t rsp_o
);
  logic response_pending_q;
  logic accept;

  assign req_ready_o = !response_pending_q;
  assign accept      = req_valid_i && req_ready_o;
  assign rsp_valid_o = response_pending_q;

  always_comb begin
    rsp_o       = '0;
    rsp_o.rdata = DEFAULT_RDATA;
    rsp_o.error = DEFAULT_ERROR;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      response_pending_q <= 1'b0;
    end else begin
      if (accept)
        response_pending_q <= 1'b1;
      else if (rsp_valid_o)
        response_pending_q <= 1'b0;
    end
  end

`ifndef SYNTHESIS
  logic accepted_q;
  core_bus_req_t stalled_req_q;
  logic stalled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      accepted_q    <= 1'b0;
      stalled_req_q <= '0;
      stalled_q     <= 1'b0;
    end else begin
      // The registered response is present for exactly the cycle following an
      // acceptance; there is no combinational request-to-response path.
      assert (rsp_valid_o == accepted_q)
        else $error("default target response latency is not exactly one cycle");

      if (stalled_q && req_valid_i) begin
        assert (req_i === stalled_req_q)
          else $error("default target request changed under back-pressure");
      end

      accepted_q <= accept;
      stalled_q  <= req_valid_i && !req_ready_o;
      if (req_valid_i && !req_ready_o)
        stalled_req_q <= req_i;
    end
  end
`endif

endmodule
`default_nettype wire
