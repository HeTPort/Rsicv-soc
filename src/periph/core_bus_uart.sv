`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Registered CPU-local bus target for a minimal polling UART TX peripheral.
// The target owns one queued byte while uart_tx owns the actively shifted byte.
module core_bus_uart #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter int unsigned CLK_FREQ_HZ = 25_000_000,
  parameter int unsigned BAUD_RATE   = 115_200,
  parameter logic [AW-1:0] TXDATA_OFFSET = 'h0,
  parameter logic [AW-1:0] STATUS_OFFSET = 'h4
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          req_valid_i,
  output logic          req_ready_o,
  input  core_bus_req_t req_i,
  output logic          rsp_valid_o,
  output core_bus_rsp_t rsp_o,
  output logic          uart_tx_o,
  output logic          tx_ready_o,
  output logic          tx_busy_o
);
  logic hold_full_q;
  logic [7:0] hold_data_q;

  logic shifter_valid;
  logic shifter_ready;
  logic shifter_busy;
  logic shifter_done;
  logic dequeue;
  logic enqueue;
  logic hold_can_accept;

  logic txdata_write;
  logic status_read;
  logic access_legal;
  logic blocked_txdata_write;
  logic accept;

  logic rsp_valid_q;
  core_bus_rsp_t rsp_q;

  assign shifter_valid  = hold_full_q;
  assign dequeue        = shifter_valid && shifter_ready;
  assign hold_can_accept = !hold_full_q || dequeue;

  assign tx_ready_o = hold_can_accept;
  assign tx_busy_o  = shifter_busy || hold_full_q;

  assign txdata_write = (req_i.addr == TXDATA_OFFSET) && req_i.write &&
                        (req_i.size == MEM_SIZE_WORD) &&
                        (req_i.wstrb == {DW/8{1'b1}});
  assign status_read = (req_i.addr == STATUS_OFFSET) && !req_i.write &&
                       (req_i.size == MEM_SIZE_WORD);
  assign access_legal = txdata_write || status_read;
  assign blocked_txdata_write = txdata_write && !hold_can_accept;

  assign req_ready_o = !rsp_valid_q &&
                       !(req_valid_i && blocked_txdata_write);
  assign accept      = req_valid_i && req_ready_o;
  assign enqueue     = accept && txdata_write;

  assign rsp_valid_o = rsp_valid_q;
  assign rsp_o       = rsp_q;

  uart_tx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
  ) u_uart_tx (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .tx_valid_i (shifter_valid),
    .tx_ready_o (shifter_ready),
    .tx_data_i  (hold_data_q),
    .tx_o       (uart_tx_o),
    .tx_busy_o  (shifter_busy),
    .tx_done_o  (shifter_done)
  );

  // Simultaneous dequeue/enqueue moves the old byte into the shifter and
  // replaces it with the newly accepted CPU byte without clearing full.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hold_full_q <= 1'b0;
      hold_data_q <= '0;
    end else begin
      unique case ({enqueue, dequeue})
        2'b10: begin
          hold_full_q <= 1'b1;
          hold_data_q <= req_i.wdata[7:0];
        end
        2'b01: begin
          hold_full_q <= 1'b0;
        end
        2'b11: begin
          hold_full_q <= 1'b1;
          hold_data_q <= req_i.wdata[7:0];
        end
        default: ;
      endcase
    end
  end

  // One registered response per accepted request. Unsupported operations are
  // accepted immediately, return an error, and cannot enqueue a byte.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_q       <= '0;
    end else begin
      rsp_valid_q <= accept;
      if (accept) begin
        rsp_q.rdata <= status_read ?
            {{(DW-2){1'b0}}, tx_busy_o, tx_ready_o} : '0;
        rsp_q.error <= !access_legal;
      end else begin
        rsp_q <= '0;
      end
    end
  end

  initial begin
    if (DW != 32)
      $fatal(1, "core_bus_uart currently requires DW=32");
    if (TXDATA_OFFSET[1:0] != 2'b00 || STATUS_OFFSET[1:0] != 2'b00)
      $fatal(1, "core_bus_uart register offsets must be word aligned");
    if (TXDATA_OFFSET == STATUS_OFFSET)
      $fatal(1, "core_bus_uart register offsets must be distinct");
  end

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(rsp_valid_o && req_ready_o))
        else $error("UART target advertised readiness while responding");
      if (accept && !access_legal)
        assert (!enqueue)
          else $error("Invalid UART access enqueued a byte");
      if (req_valid_i && blocked_txdata_write)
        assert (!req_ready_o)
          else $error("Full UART holding slot did not apply backpressure");
      if (dequeue)
        assert (hold_full_q)
          else $error("UART dequeued an empty holding slot");
    end
  end
`endif
endmodule

`default_nettype wire
