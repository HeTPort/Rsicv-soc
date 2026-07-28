`timescale 1ns/1ps
`default_nettype wire
import riscv_pkg::*;

// Single-outstanding adapter from the CPU-local data bus to synchronous RAM.
// Optional request/response delays exist for verification and model a target
// that applies back-pressure independently of its response latency.
module core_bus_data_ram #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter int DEPTH = 4096,
  parameter INIT_FILE = "",
  parameter int REQ_WAIT_CYCLES = 0,
  parameter int RSP_WAIT_CYCLES = 0,
  parameter bit FORCE_ERROR = 1'b0
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  input  logic          req_valid_i,
  output logic          req_ready_o,
  input  core_bus_req_t req_i,
  output logic          rsp_valid_o,
  output core_bus_rsp_t rsp_o
);
  localparam int REQ_COUNT_W =
      REQ_WAIT_CYCLES > 0 ? $clog2(REQ_WAIT_CYCLES + 1) : 1;
  localparam int RSP_COUNT_W =
      RSP_WAIT_CYCLES > 0 ? $clog2(RSP_WAIT_CYCLES + 1) : 1;

  typedef enum logic [1:0] {
    ADAPTER_IDLE,
    ADAPTER_REQ_WAIT,
    ADAPTER_RAM_CAPTURE,
    ADAPTER_RSP_WAIT
  } adapter_state_e;

  adapter_state_e state_q;
  core_bus_req_t req_q;
  core_bus_rsp_t rsp_q;
  logic [REQ_COUNT_W-1:0] req_wait_q;
  logic [RSP_COUNT_W-1:0] rsp_wait_q;
  logic rsp_valid_q;

  logic accept;
  logic ram_ren;
  logic ram_wen;
  logic [DW/8-1:0] ram_wstrb;
  logic [AW-1:0] ram_addr;
  logic [DW-1:0] ram_wdata;
  logic [DW-1:0] ram_rdata;
  core_bus_req_t active_req;

  always_comb begin
    active_req = req_q;
    if (state_q == ADAPTER_IDLE)
      active_req = req_i;
  end

  always_comb begin
    req_ready_o = 1'b0;
    if (state_q == ADAPTER_IDLE && REQ_WAIT_CYCLES == 0)
      req_ready_o = 1'b1;
    else if (state_q == ADAPTER_REQ_WAIT && req_wait_q == '0)
      req_ready_o = 1'b1;
  end

  assign accept      = req_valid_i && req_ready_o;
  assign ram_ren     = accept && !active_req.write;
  assign ram_wen     = accept && active_req.write && !FORCE_ERROR;
  assign ram_wstrb   = active_req.wstrb;
  assign ram_addr    = active_req.addr;
  assign ram_wdata   = active_req.wdata;
  assign rsp_valid_o = rsp_valid_q;
  assign rsp_o       = rsp_q;

  data_ram #(
    .AW(AW),
    .DW(DW),
    .DEPTH(DEPTH),
    .INIT_FILE(INIT_FILE)
  ) u_data_ram (
    .clk_i   (clk_i),
    .rst_ni  (rst_ni),
    .ren_i   (ram_ren),
    .wen_i   (ram_wen),
    .wstrb_i (ram_wstrb),
    .addr_i  (ram_addr),
    .wdata_i (ram_wdata),
    .rdata_o (ram_rdata)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= ADAPTER_IDLE;
      req_q        <= '0;
      rsp_q        <= '0;
      req_wait_q   <= '0;
      rsp_wait_q   <= '0;
      rsp_valid_q  <= 1'b0;
    end else begin
      rsp_valid_q <= 1'b0;

      unique case (state_q)
        ADAPTER_IDLE: begin
          if (req_valid_i) begin
            req_q <= req_i;
            if (REQ_WAIT_CYCLES == 0) begin
              if (accept)
                state_q <= ADAPTER_RAM_CAPTURE;
            end else begin
              req_wait_q <= REQ_COUNT_W'(REQ_WAIT_CYCLES);
              state_q    <= ADAPTER_REQ_WAIT;
            end
          end
        end

        ADAPTER_REQ_WAIT: begin
          // Dropping valid is legal only for a killed, not-yet-accepted
          // request. In that case the adapter discards its speculative copy.
          if (!req_valid_i) begin
            state_q <= ADAPTER_IDLE;
          end else if (accept) begin
            state_q <= ADAPTER_RAM_CAPTURE;
          end else if (req_wait_q != '0) begin
            req_wait_q <= req_wait_q - 1'b1;
          end
        end

        ADAPTER_RAM_CAPTURE: begin
          rsp_q.rdata <= ram_rdata;
          rsp_q.error <= FORCE_ERROR;
          if (RSP_WAIT_CYCLES == 0) begin
            rsp_valid_q <= 1'b1;
            state_q     <= ADAPTER_IDLE;
          end else begin
            rsp_wait_q <= RSP_COUNT_W'(RSP_WAIT_CYCLES);
            state_q    <= ADAPTER_RSP_WAIT;
          end
        end

        ADAPTER_RSP_WAIT: begin
          if (rsp_wait_q == '0) begin
            rsp_valid_q <= 1'b1;
            state_q     <= ADAPTER_IDLE;
          end else begin
            rsp_wait_q <= rsp_wait_q - 1'b1;
          end
        end

        default: begin
          state_q <= ADAPTER_IDLE;
        end
      endcase
    end
  end

`ifndef SYNTHESIS
  logic outstanding_q;
  core_bus_req_t stalled_req_q;
  logic stalled_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      outstanding_q <= 1'b0;
      stalled_req_q <= '0;
      stalled_q     <= 1'b0;
    end else begin
      if (stalled_q && req_valid_i) begin
        assert (req_i === stalled_req_q)
          else $error("RAM adapter request payload changed under back-pressure");
      end

      assert (!(accept && outstanding_q))
        else $error("RAM adapter accepted more than one outstanding request");
      assert (!(rsp_valid_o && !outstanding_q))
        else $error("RAM adapter responded without an accepted request");

      if (accept)
        outstanding_q <= 1'b1;
      if (rsp_valid_o)
        outstanding_q <= 1'b0;

      stalled_q <= req_valid_i && !req_ready_o;
      if (req_valid_i && !req_ready_o)
        stalled_req_q <= req_i;
    end
  end
`endif

endmodule
`default_nettype wire
