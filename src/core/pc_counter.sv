`timescale 1ns / 1ps
module pc_counter #(
  parameter AW = 32
)(
  input  logic          clk,
  input  logic          rst_n,
  input  logic          jump_en,
  input  logic [AW-1:0] jump_addr,
  output logic [AW-1:0] pc_pointer
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      pc_pointer <= '0;
    else if (jump_en)
      pc_pointer <= jump_addr;
    else
      pc_pointer <= pc_pointer + 32'd4;
  end
endmodule