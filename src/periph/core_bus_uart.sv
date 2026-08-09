`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Registered polling UART target. TX uses one holding byte plus an active
// shifter. RX uses an asynchronous-input receiver plus a parameterized FIFO;
// the default depth is the architectural first-milestone value of 16 bytes.
module core_bus_uart #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter int unsigned CLK_FREQ_HZ = 25_000_000,
  parameter int unsigned BAUD_RATE   = 115_200,
  parameter int unsigned RX_FIFO_DEPTH = 16,
  parameter logic [AW-1:0] TXDATA_OFFSET  = 'h0,
  parameter logic [AW-1:0] STATUS_OFFSET  = 'h4,
  parameter logic [AW-1:0] RXDATA_OFFSET  = 'h8,
  parameter logic [AW-1:0] RXERROR_OFFSET = 'hc
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          req_valid_i,
  output logic          req_ready_o,
  input  core_bus_req_t req_i,
  output logic          rsp_valid_o,
  output core_bus_rsp_t rsp_o,
  input  logic          uart_rx_i,
  output logic          uart_tx_o,
  output logic          tx_ready_o,
  output logic          tx_busy_o
);
  localparam int unsigned RX_PTR_W =
      (RX_FIFO_DEPTH <= 1) ? 1 : $clog2(RX_FIFO_DEPTH);
  localparam int unsigned RX_COUNT_W =
      (RX_FIFO_DEPTH <= 1) ? 1 : $clog2(RX_FIFO_DEPTH + 1);

  logic hold_full_q;
  logic [7:0] hold_data_q;
  logic shifter_valid;
  logic shifter_ready;
  logic shifter_busy;
  logic shifter_done;
  logic dequeue;
  logic enqueue;
  logic hold_can_accept;

  logic rx_byte_valid;
  logic [7:0] rx_byte_data;
  logic rx_frame_error;
  logic rx_receiver_busy;
  logic [7:0] rx_fifo_q [0:RX_FIFO_DEPTH-1];
  logic [RX_PTR_W-1:0] rx_write_ptr_q;
  logic [RX_PTR_W-1:0] rx_read_ptr_q;
  logic [RX_COUNT_W-1:0] rx_count_q;
  logic rx_overrun_q;
  logic rx_frame_error_q;
  logic rx_empty;
  logic rx_full;
  logic rx_pop;
  logic rx_push;
  logic rx_can_push;
  logic rx_overrun_event;
  logic clear_rx_overrun;
  logic clear_rx_frame_error;

  logic txdata_write;
  logic status_read;
  logic rxdata_read;
  logic rxerror_read;
  logic rxerror_clear_write;
  logic access_legal;
  logic blocked_txdata_write;
  logic accept;
  logic [DW-1:0] status_rdata;
  logic [DW-1:0] rxerror_rdata;

  logic rsp_valid_q;
  core_bus_rsp_t rsp_q;

  function automatic logic [RX_PTR_W-1:0] rx_ptr_next(
    input logic [RX_PTR_W-1:0] ptr
  );
    begin
      if (ptr == RX_FIFO_DEPTH - 1)
        rx_ptr_next = '0;
      else
        rx_ptr_next = ptr + 1'b1;
    end
  endfunction

  assign shifter_valid   = hold_full_q;
  assign dequeue         = shifter_valid && shifter_ready;
  assign hold_can_accept = !hold_full_q || dequeue;
  assign tx_ready_o      = hold_can_accept;
  assign tx_busy_o       = shifter_busy || hold_full_q;

  assign rx_empty = rx_count_q == 0;
  assign rx_full  = rx_count_q == RX_FIFO_DEPTH;

  assign txdata_write = (req_i.addr == TXDATA_OFFSET) && req_i.write &&
                        (req_i.size == MEM_SIZE_WORD) &&
                        (req_i.wstrb == {DW/8{1'b1}});
  assign status_read = (req_i.addr == STATUS_OFFSET) && !req_i.write &&
                       (req_i.size == MEM_SIZE_WORD);
  assign rxdata_read = (req_i.addr == RXDATA_OFFSET) && !req_i.write &&
                       (req_i.size == MEM_SIZE_WORD);
  assign rxerror_read = (req_i.addr == RXERROR_OFFSET) && !req_i.write &&
                        (req_i.size == MEM_SIZE_WORD);
  assign rxerror_clear_write =
      (req_i.addr == RXERROR_OFFSET) && req_i.write &&
      (req_i.size == MEM_SIZE_WORD) &&
      (req_i.wstrb == {DW/8{1'b1}});
  assign access_legal = txdata_write || status_read || rxdata_read ||
                        rxerror_read || rxerror_clear_write;
  assign blocked_txdata_write = txdata_write && !hold_can_accept;

  assign req_ready_o = !rsp_valid_q &&
                       !(req_valid_i && blocked_txdata_write);
  assign accept      = req_valid_i && req_ready_o;
  assign enqueue     = accept && txdata_write;

  // RXDATA reads never block. A read pops only when a byte was already
  // present. A simultaneous full-FIFO pop makes room for the arriving byte.
  assign rx_pop           = accept && rxdata_read && !rx_empty;
  assign rx_can_push      = !rx_full || rx_pop;
  assign rx_push          = rx_byte_valid && rx_can_push;
  assign rx_overrun_event = rx_byte_valid && !rx_can_push;
  assign clear_rx_overrun = accept && rxerror_clear_write && req_i.wdata[0];
  assign clear_rx_frame_error =
      accept && rxerror_clear_write && req_i.wdata[1];

  always_comb begin
    status_rdata = '0;
    status_rdata[0] = tx_ready_o;
    status_rdata[1] = tx_busy_o;
    status_rdata[2] = !rx_empty;
    status_rdata[3] = rx_full;
    status_rdata[4] = rx_overrun_q;
    status_rdata[5] = rx_frame_error_q;
    status_rdata[15:8] = rx_count_q;

    rxerror_rdata = '0;
    rxerror_rdata[0] = rx_overrun_q;
    rxerror_rdata[1] = rx_frame_error_q;
  end

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

  uart_rx #(
    .CLK_FREQ_HZ(CLK_FREQ_HZ),
    .BAUD_RATE  (BAUD_RATE)
  ) u_uart_rx (
    .clk_i            (clk_i),
    .rst_ni           (rst_ni),
    .uart_rx_i        (uart_rx_i),
    .rx_byte_valid_o  (rx_byte_valid),
    .rx_byte_data_o   (rx_byte_data),
    .rx_frame_error_o (rx_frame_error),
    .rx_busy_o        (rx_receiver_busy)
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

  // FIFO memory is intentionally not reset. Occupancy and pointers define
  // which entries are valid, avoiding unnecessary reset logic on storage.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_write_ptr_q <= '0;
      rx_read_ptr_q  <= '0;
      rx_count_q     <= '0;
    end else begin
      if (rx_push) begin
        rx_fifo_q[rx_write_ptr_q] <= rx_byte_data;
        rx_write_ptr_q <= rx_ptr_next(rx_write_ptr_q);
      end
      if (rx_pop)
        rx_read_ptr_q <= rx_ptr_next(rx_read_ptr_q);

      unique case ({rx_push, rx_pop})
        2'b10: rx_count_q <= rx_count_q + 1'b1;
        2'b01: rx_count_q <= rx_count_q - 1'b1;
        default: ;
      endcase
    end
  end

  // New hardware events win over a same-cycle software clear, preventing an
  // error that occurs on the clear edge from being lost.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rx_overrun_q     <= 1'b0;
      rx_frame_error_q <= 1'b0;
    end else begin
      rx_overrun_q <= (rx_overrun_q && !clear_rx_overrun) ||
                      rx_overrun_event;
      rx_frame_error_q <=
          (rx_frame_error_q && !clear_rx_frame_error) || rx_frame_error;
    end
  end

  // One registered response per accepted request. Unsupported operations are
  // accepted immediately, return an error, and have no UART side effect.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_q       <= '0;
    end else begin
      rsp_valid_q <= accept;
      if (accept) begin
        if (status_read)
          rsp_q.rdata <= status_rdata;
        else if (rxdata_read && !rx_empty)
          rsp_q.rdata <= {{(DW-8){1'b0}}, rx_fifo_q[rx_read_ptr_q]};
        else if (rxerror_read)
          rsp_q.rdata <= rxerror_rdata;
        else
          rsp_q.rdata <= '0;
        rsp_q.error <= !access_legal;
      end else begin
        rsp_q <= '0;
      end
    end
  end

  initial begin
    if (DW != 32)
      $fatal(1, "core_bus_uart currently requires DW=32");
    if (RX_FIFO_DEPTH == 0 || RX_FIFO_DEPTH > 255)
      $fatal(1, "core_bus_uart RX_FIFO_DEPTH must be in 1..255");
    if (TXDATA_OFFSET[1:0] != 2'b00 || STATUS_OFFSET[1:0] != 2'b00 ||
        RXDATA_OFFSET[1:0] != 2'b00 || RXERROR_OFFSET[1:0] != 2'b00)
      $fatal(1, "core_bus_uart register offsets must be word aligned");
    if (TXDATA_OFFSET == STATUS_OFFSET || TXDATA_OFFSET == RXDATA_OFFSET ||
        TXDATA_OFFSET == RXERROR_OFFSET || STATUS_OFFSET == RXDATA_OFFSET ||
        STATUS_OFFSET == RXERROR_OFFSET || RXDATA_OFFSET == RXERROR_OFFSET)
      $fatal(1, "core_bus_uart register offsets must be distinct");
  end

`ifndef SYNTHESIS
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(rsp_valid_o && req_ready_o))
        else $error("UART target advertised readiness while responding");
      assert (rx_count_q <= RX_FIFO_DEPTH)
        else $error("UART RX FIFO count exceeded configured depth");
      assert (rx_empty == (rx_count_q == 0))
        else $error("UART RX empty flag disagrees with count");
      assert (rx_full == (rx_count_q == RX_FIFO_DEPTH))
        else $error("UART RX full flag disagrees with count");
      if (accept && !access_legal)
        assert (!(enqueue || rx_pop || clear_rx_overrun ||
                  clear_rx_frame_error))
          else $error("Invalid UART access caused a side effect");
      if (req_valid_i && blocked_txdata_write)
        assert (!req_ready_o)
          else $error("Full UART TX holding slot did not apply backpressure");
      if (dequeue)
        assert (hold_full_q)
          else $error("UART TX dequeued an empty holding slot");
      if (rx_pop)
        assert (!rx_empty)
          else $error("UART RX popped an empty FIFO");
      if (rx_overrun_event)
        assert (rx_full && !rx_pop)
          else $error("UART RX overrun policy fired while a slot existed");
      assert (!(rx_byte_valid && rx_frame_error))
        else $error("UART RX delivered a bad frame as valid data");
    end
  end
`endif
endmodule

`default_nettype wire
