`timescale 1ns / 1ps
`default_nettype wire

// Unsigned restoring Radix-2 division with signed operand/result adaptation.
// One quotient bit is produced per DIV_RUN cycle. Architectural selection
// between quotient and remainder remains outside this module.
module radix2_divider #(
  parameter int DW = 32
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          start_i,
  input  logic          kill_i,
  input  logic          signed_i,
  input  logic [DW-1:0] dividend_i,
  input  logic [DW-1:0] divisor_i,
  output logic          busy_o,
  output logic          complete_o,
  output logic [DW-1:0] quotient_o,
  output logic [DW-1:0] remainder_o
);
  localparam int COUNT_W = $clog2(DW + 1);
  localparam logic [DW-1:0] ONE = {{(DW-1){1'b0}}, 1'b1};

  typedef enum logic [1:0] {
    DIV_IDLE,
    DIV_RUN,
    DIV_COMPLETE
  } div_state_e;

  div_state_e state_q;
  logic [DW-1:0] divisor_q;
  logic [DW-1:0] quotient_work_q;
  logic [DW:0]   remainder_work_q;
  logic [COUNT_W-1:0] iteration_q;
  logic quotient_negative_q;
  logic remainder_negative_q;
  logic divide_by_zero_q;

  logic [DW:0]   shifted_remainder;
  logic [DW-1:0] shifted_quotient;
  logic [DW:0]   next_remainder;
  logic [DW-1:0] next_quotient;

  function automatic logic [DW-1:0] magnitude(
    input logic [DW-1:0] value
  );
    begin
      magnitude = value[DW-1] ? (~value + ONE) : value;
    end
  endfunction

  assign busy_o     = state_q == DIV_RUN;
  assign complete_o = state_q == DIV_COMPLETE;

  // Restoring division step: shift the partial remainder and quotient, then
  // subtract the divisor when possible and emit the next quotient bit.
  always_comb begin
    shifted_remainder = {remainder_work_q[DW-1:0], quotient_work_q[DW-1]};
    shifted_quotient  = {quotient_work_q[DW-2:0], 1'b0};
    next_remainder    = shifted_remainder;
    next_quotient     = shifted_quotient;

    if (shifted_remainder >= {1'b0, divisor_q}) begin
      next_remainder    = shifted_remainder - {1'b0, divisor_q};
      next_quotient[0]  = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q               <= DIV_IDLE;
      divisor_q             <= '0;
      quotient_work_q       <= '0;
      remainder_work_q      <= '0;
      iteration_q           <= '0;
      quotient_negative_q   <= 1'b0;
      remainder_negative_q  <= 1'b0;
      divide_by_zero_q      <= 1'b0;
      quotient_o            <= '0;
      remainder_o           <= '0;
    end else if (kill_i) begin
      state_q               <= DIV_IDLE;
      divisor_q             <= '0;
      quotient_work_q       <= '0;
      remainder_work_q      <= '0;
      iteration_q           <= '0;
      quotient_negative_q   <= 1'b0;
      remainder_negative_q  <= 1'b0;
      divide_by_zero_q      <= 1'b0;
      quotient_o            <= '0;
      remainder_o           <= '0;
    end else begin
      unique case (state_q)
        DIV_IDLE: begin
          if (start_i) begin
            divisor_q            <= signed_i ? magnitude(divisor_i) : divisor_i;
            quotient_work_q      <= signed_i ? magnitude(dividend_i) : dividend_i;
            remainder_work_q     <= '0;
            iteration_q          <= '0;
            quotient_negative_q  <= signed_i &&
                                    (dividend_i[DW-1] ^ divisor_i[DW-1]);
            remainder_negative_q <= signed_i && dividend_i[DW-1];
            divide_by_zero_q     <= divisor_i == '0;
            quotient_o           <= '0;
            remainder_o          <= '0;
            state_q              <= DIV_RUN;
          end
        end

        DIV_RUN: begin
          quotient_work_q  <= next_quotient;
          remainder_work_q <= next_remainder;

          if (iteration_q == DW-1) begin
            // RISC-V defines a divide-by-zero quotient as all ones, even for
            // signed division. The iterative unsigned core already preserves
            // the dividend as the remainder.
            if (divide_by_zero_q)
              quotient_o <= {DW{1'b1}};
            else if (quotient_negative_q)
              quotient_o <= ~next_quotient + ONE;
            else
              quotient_o <= next_quotient;

            if (remainder_negative_q)
              remainder_o <= ~next_remainder[DW-1:0] + ONE;
            else
              remainder_o <= next_remainder[DW-1:0];

            state_q <= DIV_COMPLETE;
          end else begin
            iteration_q <= iteration_q + 1'b1;
          end
        end

        DIV_COMPLETE: begin
          state_q <= DIV_IDLE;
        end

        default: begin
          state_q <= DIV_IDLE;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  logic complete_q;

  initial begin
    assert (DW >= 2)
      else $fatal(1, "radix2_divider requires DW >= 2");
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      complete_q <= 1'b0;
    end else begin
      assert (!(complete_o && complete_q))
        else $error("Divider completion lasted more than one cycle");
      complete_q <= complete_o;
    end
  end
`endif

endmodule
`default_nettype wire
