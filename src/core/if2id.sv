`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;
module if2id (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        flush_i,
  input  logic        stall_i,
  input  fetch_pkt_t  pkt2id_i, 
  output fetch_pkt_t  pkt2id_o
);
  fetch_pkt_t pkt2id_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pkt2id_q <= FETCH_PKT_BUBBLE;
    end
    else if (flush_i) begin
      pkt2id_q <= FETCH_PKT_BUBBLE;
    end
    else if (!stall_i) begin
      if (pkt2id_i.valid)
        pkt2id_q <= pkt2id_i;
      else
        pkt2id_q <= FETCH_PKT_BUBBLE;
    end
  end

  assign pkt2id_o = pkt2id_q;

`ifndef SYNTHESIS
  // Sample after the rising-edge nonblocking assignments have settled.
  always @(negedge clk_i) begin
    if (rst_ni && !pkt2id_q.valid) begin
      assert (pkt2id_q === FETCH_PKT_BUBBLE)
        else $error("IF/ID invalid packet is not the canonical bubble");
    end
  end
`endif
endmodule
`default_nettype wire
