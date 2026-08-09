`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Centralized single-master data fabric. The full architectural address is
// decoded once, the accepting target is registered until its response, and
// each peripheral/RAM-facing copy is translated to a local byte address.
module soc_data_fabric #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter logic [AW-1:0] TIMER_BASE = 32'h0200_0000,
  parameter logic [AW-1:0] TIMER_END  = 32'h0200_ffff,
  parameter logic [AW-1:0] UART_BASE = 32'h1000_0000,
  parameter logic [AW-1:0] UART_END  = 32'h1000_0fff,
  parameter logic [AW-1:0] DATA_RAM_BASE = 32'h8000_0000,
  parameter logic [AW-1:0] DATA_RAM_END  = 32'h8000_ffff,
  parameter logic [DW-1:0] DEFAULT_RDATA = '0,
  parameter bit DEFAULT_ERROR = 1'b1
)(
  input  logic          clk_i,
  input  logic          rst_ni,

  input  logic          cpu_req_valid_i,
  output logic          cpu_req_ready_o,
  input  core_bus_req_t cpu_req_i,
  output logic          cpu_rsp_valid_o,
  output core_bus_rsp_t cpu_rsp_o,

  output logic          timer_req_valid_o,
  input  logic          timer_req_ready_i,
  output core_bus_req_t timer_req_o,
  input  logic          timer_rsp_valid_i,
  input  core_bus_rsp_t timer_rsp_i,

  output logic          uart_req_valid_o,
  input  logic          uart_req_ready_i,
  output core_bus_req_t uart_req_o,
  input  logic          uart_rsp_valid_i,
  input  core_bus_rsp_t uart_rsp_i,

  output logic          data_req_valid_o,
  input  logic          data_req_ready_i,
  output core_bus_req_t data_req_o,
  input  logic          data_rsp_valid_i,
  input  core_bus_rsp_t data_rsp_i
);
  typedef enum logic [1:0] {
    TARGET_TIMER,
    TARGET_UART,
    TARGET_DATA_RAM,
    TARGET_DEFAULT
  } target_e;

  logic timer_selected;
  logic uart_selected;
  logic data_selected;
  logic default_req_valid;
  logic default_req_ready;
  logic default_rsp_valid;
  core_bus_rsp_t default_rsp;

  logic outstanding_q;
  target_e owner_q;
  logic accept;

  assign timer_selected = (cpu_req_i.addr >= TIMER_BASE) &&
                          (cpu_req_i.addr <= TIMER_END);
  assign uart_selected = (cpu_req_i.addr >= UART_BASE) &&
                         (cpu_req_i.addr <= UART_END);
  assign data_selected = (cpu_req_i.addr >= DATA_RAM_BASE) &&
                         (cpu_req_i.addr <= DATA_RAM_END);

  always_comb begin
    timer_req_o      = cpu_req_i;
    timer_req_o.addr = cpu_req_i.addr - TIMER_BASE;
    uart_req_o      = cpu_req_i;
    uart_req_o.addr = cpu_req_i.addr - UART_BASE;
    data_req_o      = cpu_req_i;
    data_req_o.addr = cpu_req_i.addr - DATA_RAM_BASE;

    timer_req_valid_o = 1'b0;
    uart_req_valid_o = 1'b0;
    data_req_valid_o = 1'b0;
    default_req_valid = 1'b0;
    cpu_req_ready_o = 1'b0;

    if (!outstanding_q) begin
      if (timer_selected) begin
        timer_req_valid_o = cpu_req_valid_i;
        cpu_req_ready_o   = timer_req_ready_i;
      end else if (uart_selected) begin
        uart_req_valid_o = cpu_req_valid_i;
        cpu_req_ready_o  = uart_req_ready_i;
      end else if (data_selected) begin
        data_req_valid_o = cpu_req_valid_i;
        cpu_req_ready_o  = data_req_ready_i;
      end else begin
        default_req_valid = cpu_req_valid_i;
        cpu_req_ready_o   = default_req_ready;
      end
    end
  end

  assign accept = cpu_req_valid_i && cpu_req_ready_o;

  always_comb begin
    cpu_rsp_valid_o = 1'b0;
    cpu_rsp_o       = '0;

    if (outstanding_q) begin
      unique case (owner_q)
        TARGET_TIMER: begin
          cpu_rsp_valid_o = timer_rsp_valid_i;
          cpu_rsp_o       = timer_rsp_i;
        end

        TARGET_UART: begin
          cpu_rsp_valid_o = uart_rsp_valid_i;
          cpu_rsp_o       = uart_rsp_i;
        end

        TARGET_DATA_RAM: begin
          cpu_rsp_valid_o = data_rsp_valid_i;
          cpu_rsp_o       = data_rsp_i;
        end

        TARGET_DEFAULT: begin
          cpu_rsp_valid_o = default_rsp_valid;
          cpu_rsp_o       = default_rsp;
        end

        default: begin
          cpu_rsp_valid_o = 1'b0;
          cpu_rsp_o       = '0;
        end
      endcase
    end
  end

  core_bus_default_target #(
    .AW(AW),
    .DW(DW),
    .DEFAULT_RDATA(DEFAULT_RDATA),
    .DEFAULT_ERROR(DEFAULT_ERROR)
  ) u_default_target (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .req_valid_i (default_req_valid),
    .req_ready_o (default_req_ready),
    .req_i       (cpu_req_i),
    .rsp_valid_o (default_rsp_valid),
    .rsp_o       (default_rsp)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      outstanding_q <= 1'b0;
      owner_q       <= TARGET_DEFAULT;
    end else begin
      if (accept) begin
        outstanding_q <= 1'b1;
        if (timer_selected)
          owner_q <= TARGET_TIMER;
        else if (uart_selected)
          owner_q <= TARGET_UART;
        else if (data_selected)
          owner_q <= TARGET_DATA_RAM;
        else
          owner_q <= TARGET_DEFAULT;
      end else if (cpu_rsp_valid_o) begin
        outstanding_q <= 1'b0;
      end
    end
  end

  initial begin
    if (DATA_RAM_END < DATA_RAM_BASE)
      $fatal(1, "soc_data_fabric parameter error: RAM end precedes base");
    if (TIMER_END < TIMER_BASE)
      $fatal(1, "soc_data_fabric parameter error: timer end precedes base");
    if (UART_END < UART_BASE)
      $fatal(1, "soc_data_fabric parameter error: UART end precedes base");
    if (!((TIMER_END < DATA_RAM_BASE) || (DATA_RAM_END < TIMER_BASE)))
      $fatal(1, "soc_data_fabric parameter error: timer and RAM overlap");
    if (!((TIMER_END < UART_BASE) || (UART_END < TIMER_BASE)))
      $fatal(1, "soc_data_fabric parameter error: timer and UART overlap");
    if (!((UART_END < DATA_RAM_BASE) || (DATA_RAM_END < UART_BASE)))
      $fatal(1, "soc_data_fabric parameter error: UART and RAM overlap");
    if (DW <= 0 || (DW % 8) != 0)
      $fatal(1, "soc_data_fabric parameter error: DW must be byte aligned");
  end

`ifndef SYNTHESIS
  core_bus_req_t stalled_req_q;
  logic stalled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stalled_req_q <= '0;
      stalled_q     <= 1'b0;
    end else begin
      assert (!((timer_req_valid_o && uart_req_valid_o) ||
                (timer_req_valid_o && data_req_valid_o) ||
                (timer_req_valid_o && default_req_valid) ||
                (uart_req_valid_o && data_req_valid_o) ||
                (uart_req_valid_o && default_req_valid) ||
                (data_req_valid_o && default_req_valid)))
        else $error("data fabric selected more than one target");
      assert (!(accept && outstanding_q))
        else $error("data fabric accepted more than one outstanding request");
      assert (!(cpu_rsp_valid_o && !outstanding_q))
        else $error("data fabric returned a response without an owner");
      assert (!((timer_rsp_valid_i && uart_rsp_valid_i) ||
                (timer_rsp_valid_i && data_rsp_valid_i) ||
                (timer_rsp_valid_i && default_rsp_valid) ||
                (uart_rsp_valid_i && data_rsp_valid_i) ||
                (uart_rsp_valid_i && default_rsp_valid) ||
                (data_rsp_valid_i && default_rsp_valid)))
        else $error("data fabric observed simultaneous target responses");

      if (timer_req_valid_o) begin
        assert (timer_req_o.addr <= TIMER_END - TIMER_BASE)
          else $error("data fabric emitted an out-of-range local timer address");
      end


      if (uart_req_valid_o) begin
        assert (uart_req_o.addr <= UART_END - UART_BASE)
          else $error("data fabric emitted an out-of-range local UART address");
      end

      if (data_req_valid_o) begin
        assert (data_req_o.addr <= DATA_RAM_END - DATA_RAM_BASE)
          else $error("data fabric emitted an out-of-range local RAM address");
      end

      if (outstanding_q && owner_q == TARGET_DATA_RAM) begin
        assert (!timer_rsp_valid_i)
          else $error("timer responded while RAM owned the request");
        assert (!uart_rsp_valid_i)
          else $error("UART responded while RAM owned the request");
        assert (!default_rsp_valid)
          else $error("default target responded while RAM owned the request");
      end
      if (outstanding_q && owner_q == TARGET_DEFAULT) begin
        assert (!timer_rsp_valid_i)
          else $error("timer responded while default target owned the request");
        assert (!uart_rsp_valid_i)
          else $error("UART responded while default target owned the request");
        assert (!data_rsp_valid_i)
          else $error("RAM responded while default target owned the request");
      end
      if (outstanding_q && owner_q == TARGET_TIMER) begin
        assert (!(uart_rsp_valid_i || data_rsp_valid_i || default_rsp_valid))
          else $error("non-timer target responded while timer owned the request");
      end
      if (outstanding_q && owner_q == TARGET_UART) begin
        assert (!(timer_rsp_valid_i || data_rsp_valid_i || default_rsp_valid))
          else $error("non-UART target responded while UART owned the request");
      end

      if (stalled_q && cpu_req_valid_i) begin
        assert (cpu_req_i === stalled_req_q)
          else $error("data fabric request changed under back-pressure");
      end

      stalled_q <= cpu_req_valid_i && !cpu_req_ready_o;
      if (cpu_req_valid_i && !cpu_req_ready_o)
        stalled_req_q <= cpu_req_i;
    end
  end
`endif

endmodule
`default_nettype wire
