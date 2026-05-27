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
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            ren_i,
  input  logic            wen_i,
  input  logic [DW/8-1:0] wstrb_i,
  input  logic [AW-1:0]   addr_i,
  input  logic [DW-1:0]   wdata_i,
  output logic [DW-1:0]   rdata_o
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
  integer i;
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
    for (i = 0; i < DEPTH_SAFE; i = i + 1) begin
      mem[i] = '0;
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
    f_addr_in_range =
        longint unsigned'(word_addr_i) < longint unsigned'(DEPTH_SAFE);
  endfunction
  assign addr_in_range = f_addr_in_range(word_addr_full);
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o <= '0;
    end
    else begin
      if (wen_i) begin
        if (addr_in_range) begin
          for (i = 0; i < BYTE_NUM; i = i + 1) begin
            if (wstrb_i[i]) begin
              mem[word_addr][8*i +: 8] <= wdata_i[8*i +: 8];
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
  input  logic            clk_i,
  input  logic            rst_ni,
  input  logic            ren_i,
  input  logic            wen_i,
  input  logic [DW/8-1:0] wstrb_i,
  input  logic [AW-1:0]   addr_i,
  input  logic [DW-1:0]   wdata_i,
  output logic [DW-1:0]   rdata_o
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

  integer i;

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

    for (i = 0; i < DEPTH_SAFE; i = i + 1) begin
      mem[i] = '0;
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
    f_addr_in_range =
        longint unsigned'(word_addr_i) < longint unsigned'(DEPTH_SAFE);
  endfunction

  assign addr_in_range = f_addr_in_range(word_addr_full);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rdata_o <= '0;
    end
    else begin
      if (wen_i) begin
        if (addr_in_range) begin
          for (i = 0; i < BYTE_NUM; i = i + 1) begin
            if (wstrb_i[i]) begin
              mem[word_addr][8*i +: 8] <= wdata_i[8*i +: 8];
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

