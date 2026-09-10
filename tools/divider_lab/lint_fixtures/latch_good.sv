// Teaching fixture, NOT connected to the SoC.
// Contract: sample_o equals data_i when enable_i=1, otherwise sample_o=0.
module latch_good (
  input  logic       enable_i,
  input  logic [7:0] data_i,
  output logic [7:0] sample_o
);
  always_comb begin
    sample_o = '0;
    if (enable_i)
      sample_o = data_i;
  end
endmodule
