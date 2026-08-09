`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// CLINT-compatible machine timer register target for the CPU-local bus.
// The fabric supplies local byte offsets, not full architectural addresses.
module mtime_timer #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter int unsigned TICK_CYCLES = 1,
  parameter logic [63:0] RESET_MTIME = 64'd0,
  parameter logic [63:0] RESET_MTIMECMP = 64'hffff_ffff_ffff_ffff,
  parameter logic [AW-1:0] MTIMECMP_OFFSET = 32'h0000_4000,
  parameter logic [AW-1:0] MTIME_OFFSET = 32'h0000_bff8
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          req_valid_i,
  output logic          req_ready_o,
  input  core_bus_req_t req_i,
  output logic          rsp_valid_o,
  output core_bus_rsp_t rsp_o,
  output logic          irq_mti_o
);
  localparam int TICK_COUNT_W =
      (TICK_CYCLES <= 1) ? 1 : $clog2(TICK_CYCLES);

  logic [63:0] mtime_q;
  logic [63:0] mtimecmp_q;
  logic [TICK_COUNT_W-1:0] tick_count_q;
  logic tick_due;
  logic rsp_valid_q;
  core_bus_rsp_t rsp_q;
  logic accept;
  logic address_supported;
  logic access_legal;
  logic [DW-1:0] read_data;
  logic write_mtime_low;
  logic write_mtime_high;
  logic write_mtimecmp_low;
  logic write_mtimecmp_high;

  assign req_ready_o = !rsp_valid_q;
  assign accept      = req_valid_i && req_ready_o;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_o       = rsp_q;
  assign tick_due    = (TICK_CYCLES <= 1) ||
                       (tick_count_q == TICK_CYCLES - 1);
  assign irq_mti_o   = (mtime_q >= mtimecmp_q);

  always_comb begin
    address_supported = 1'b1;
    read_data          = '0;
    unique case (req_i.addr)
      MTIMECMP_OFFSET:          read_data = mtimecmp_q[31:0];
      MTIMECMP_OFFSET + AW'(4): read_data = mtimecmp_q[63:32];
      MTIME_OFFSET:             read_data = mtime_q[31:0];
      MTIME_OFFSET + AW'(4):    read_data = mtime_q[63:32];
      default: begin
        address_supported = 1'b0;
        read_data          = '0;
      end
    endcase
  end

  assign access_legal = address_supported &&
                        (req_i.size == MEM_SIZE_WORD) &&
                        (!req_i.write || (req_i.wstrb == 4'b1111));
  assign write_mtimecmp_low = accept && access_legal && req_i.write &&
                              (req_i.addr == MTIMECMP_OFFSET);
  assign write_mtimecmp_high = accept && access_legal && req_i.write &&
                               (req_i.addr == MTIMECMP_OFFSET + AW'(4));
  assign write_mtime_low = accept && access_legal && req_i.write &&
                           (req_i.addr == MTIME_OFFSET);
  assign write_mtime_high = accept && access_legal && req_i.write &&
                            (req_i.addr == MTIME_OFFSET + AW'(4));

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
      tick_count_q <= '0;
    else if (tick_due)
      tick_count_q <= '0;
    else
      tick_count_q <= tick_count_q + 1'b1;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mtime_q    <= RESET_MTIME;
      mtimecmp_q <= RESET_MTIMECMP;
    end else begin
      // Timer writes suppress the tick for that cycle, so an RV32 word write
      // has a deterministic result.
      if (write_mtime_low)
        mtime_q[31:0] <= req_i.wdata;
      else if (write_mtime_high)
        mtime_q[63:32] <= req_i.wdata;
      else if (tick_due)
        mtime_q <= mtime_q + 64'd1;

      if (write_mtimecmp_low)
        mtimecmp_q[31:0] <= req_i.wdata;
      if (write_mtimecmp_high)
        mtimecmp_q[63:32] <= req_i.wdata;
    end
  end

  // One registered response per accepted request. Invalid writes are
  // side-effect-free because every write enable includes access_legal.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_q       <= '0;
    end else begin
      rsp_valid_q <= accept;
      if (accept) begin
        rsp_q.rdata <= access_legal ? read_data : '0;
        rsp_q.error <= !access_legal;
      end else begin
        rsp_q <= '0;
      end
    end
  end

  initial begin
    if (DW != 32)
      $fatal(1, "mtime_timer currently requires DW=32");
    if (TICK_CYCLES == 0)
      $fatal(1, "mtime_timer TICK_CYCLES must be nonzero");
    if (MTIMECMP_OFFSET[1:0] != 2'b00 || MTIME_OFFSET[1:0] != 2'b00)
      $fatal(1, "mtime_timer register offsets must be word aligned");
  end

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(rsp_valid_o && req_ready_o))
        else $error("Timer advertised request readiness while responding");
      if (accept && !access_legal && req_i.write) begin
        assert (!(write_mtime_low || write_mtime_high ||
                  write_mtimecmp_low || write_mtimecmp_high))
          else $error("Erroneous timer write enabled a side effect");
      end
    end
  end
`endif
endmodule
`default_nettype wire
