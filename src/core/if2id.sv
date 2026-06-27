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
      pkt2id_q.valid <= 1'b0;
      pkt2id_q.pc    <= '0;
      pkt2id_q.instr <= INST_NOP;  
    end 
    else if (flush_i) begin
      pkt2id_q.valid <= 1'b0;
      pkt2id_q.pc    <= '0;
      pkt2id_q.instr <= INST_NOP; 
    end 
    else if (!stall_i) begin
      pkt2id_q <= pkt2id_i;           
    end
  end

  assign pkt2id_o = pkt2id_q;
endmodule
`default_nettype wire