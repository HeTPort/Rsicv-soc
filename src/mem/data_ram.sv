`timescale 1ns / 1ps
`default_nettype none
// ============================================================
// Module: data_ram
// Description:
//   Simple synchronous data RAM with byte write enable.
//
// Improvements:
//   - Keeps original interface.
//   - Adds full address range checking.
//   - Prevents high address bits from being silently ignored.
//   - Illegal write is ignored.
//   - Illegal read returns zero.
//   - Simulation reports $error on invalid access.
//
// Notes:
//   - Little-endian byte lane layout.
//   - FPGA BRAM usually should not reset entire memory.
//     This implementation uses initial zero initialization for
//     simulation friendliness.
// ============================================================
module data_ram #(
  parameter int AW    = 32,
  parameter int DW    = 32,
  parameter int DEPTH = 4096
)(
  input  wire logic            clk_i,
  input  wire logic            rst_ni,
  input  wire logic            ren_i,
  input  wire logic            wen_i,
  input  wire logic [DW/8-1:0] wstrb_i,
  input  wire logic [AW-1:0]   addr_i,
  input  wire logic [DW-1:0]   wdata_i,
  output      logic [DW-1:0]   rdata_o
);
  localparam int BYTE_NUM   = DW / 8;
  localparam int ADDR_LSB   = (BYTE_NUM > 1) ? $clog2(BYTE_NUM) : 0;
  localparam int DEPTH_SAFE = (DEPTH > 0) ? DEPTH : 1;
  localparam int ADDR_W     = (DEPTH_SAFE > 1) ? $clog2(DEPTH_SAFE) : 1;
  localparam int WORD_AW    = (AW > ADDR_LSB) ? (AW - ADDR_LSB) : 1;
  localparam int COPY_W     = (ADDR_W < WORD_AW) ? ADDR_W : WORD_AW;
  logic [DW-1:0] mem [0:DEPTH_SAFE-1];
  logic [WORD_AW-1:0] word_addr_full;
  logic [ADDR_W-1:0]  word_addr;
  logic               addr_in_range;
  integer init_i;
  integer byte_i;
  initial begin
    if (DW <= 0) begin
      $fatal(1, "data_ram parameter error: DW must be greater than 0");
    end
    if ((DW % 8) != 0) begin
      $fatal(1, "data_ram parameter error: DW must be a multiple of 8");
    end
    if (DEPTH <= 0) begin
      $fatal(1, "data_ram parameter error: DEPTH must be greater than 0");
    end
    if (AW <= 0) begin
      $fatal(1, "data_ram parameter error: AW must be greater than 0");
    end
    for (init_i = 0; init_i < DEPTH_SAFE; init_i = init_i + 1) begin
      mem[init_i] = '0;
    end
  end
  generate
    if (AW > ADDR_LSB) begin : gen_word_addr_extract
      assign word_addr_full = addr_i[AW-1:ADDR_LSB];
    end
    else begin : gen_word_addr_zero
      assign word_addr_full = '0;
    end
  endgenerate
  always_comb begin
    word_addr = '0;
    word_addr[COPY_W-1:0] = word_addr_full[COPY_W-1:0];
  end
  function automatic logic f_addr_in_range(
    input logic [WORD_AW-1:0] word_addr_i
  );
    f_addr_in_range = $unsigned(word_addr_i) < $unsigned(DEPTH_SAFE);
  endfunction
  assign addr_in_range = f_addr_in_range(word_addr_full);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o <= '0;
    end
    else begin
      if (wen_i) begin
        if (addr_in_range) begin
          for (byte_i = 0; byte_i < BYTE_NUM; byte_i = byte_i + 1) begin
            if (wstrb_i[byte_i]) begin
              mem[word_addr][8*byte_i +: 8] <= wdata_i[8*byte_i +: 8];
            end
          end
        end
        else begin
          // Illegal write ignored.
        end
      end
      if (ren_i) begin
        if (addr_in_range) begin
          rdata_o <= mem[word_addr];
        end
        else begin
          rdata_o <= '0;
        end
      end
    end
  end
`ifndef SYNTHESIS
  always_ff @(posedge clk_i) begin
    if ((ren_i || wen_i) && !addr_in_range) begin
      $error("data_ram address out of range: addr = 0x%h, word_addr = 0x%h, DEPTH = %0d",
             addr_i,
             word_addr_full,
             DEPTH_SAFE);
    end
  end
`endif
endmodule
`default_nettype wire