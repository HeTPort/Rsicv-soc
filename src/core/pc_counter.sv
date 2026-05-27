`timescale 1ns / 1ps
`default_nettype none
module pc_counter #(
  parameter int AW = 32,
  parameter logic [AW-1:0] RESET_PC = '0
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          stall_i,
  input  logic          redirect_en_i,
  input  logic [AW-1:0] redirect_pc_i,
  output logic [AW-1:0] pc_o
);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pc_o <= RESET_PC;
    end
    else if (redirect_en_i) begin
      pc_o <= redirect_pc_i;
    end
    else if (stall_i) begin
      pc_o <= pc_o;
    end
    else begin
      pc_o <= pc_o + AW'(4);
    end
  end
endmodule
`default_nettype wire