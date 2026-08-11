`timescale 1ns/1ps
`default_nettype wire

import riscv_pkg::*;

// Registered CPU-local bus target for output-only GPIO.
//
// The fabric supplies target-local byte addresses. GPIO_OUT is architecturally
// a 32-bit register, while GPIO_WIDTH selects how many low bits reach pins.
module core_bus_gpio #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,

  parameter int unsigned GPIO_WIDTH = 8,

  parameter logic [GPIO_WIDTH-1:0] RESET_VALUE = '0,

  parameter logic [AW-1:0] GPIO_OUT_OFFSET = 'h0
)(
  input  logic clk_i,
  input  logic rst_ni,

  input  logic          req_valid_i,
  output logic          req_ready_o,
  input  core_bus_req_t req_i,

  output logic          rsp_valid_o,
  output core_bus_rsp_t rsp_o,

  output logic [GPIO_WIDTH-1:0] gpio_out_o
);

  // Persistent software-visible output state.
  logic [GPIO_WIDTH-1:0] gpio_out_q;

  // Register value expanded to the architectural 32-bit bus width.
  logic [DW-1:0] gpio_out_word;

  // Byte-lane write support.
  logic [DW/8-1:0] expected_wstrb;
  logic [DW-1:0]   write_mask;
  logic [DW-1:0]   merged_write_data;

  // Access validation.
  logic address_legal;
  logic size_legal;
  logic strobe_legal;
  logic access_legal;

  // Handshake and side-effect events.
  logic accept;
  logic gpio_write;

  // Registered response state.
  logic          rsp_valid_q;
  core_bus_rsp_t rsp_q;

  /*
   * GPIO_OUT occupies one 32-bit word.
   *
   * Local addresses +0, +1, +2 and +3 refer to byte lanes within that word.
   * +4 and above refer to unsupported registers.
   */
  assign address_legal =
      req_i.addr[AW-1:2] == GPIO_OUT_OFFSET[AW-1:2];

  /*
   * Validate that address, size and write strobes describe the same transfer.
   *
   * Examples:
   *
   *   byte at +0: wstrb = 0001
   *   byte at +1: wstrb = 0010
   *   half at +0: wstrb = 0011
   *   half at +2: wstrb = 1100
   *   word at +0: wstrb = 1111
   */
  always_comb begin
    size_legal     = 1'b0;
    expected_wstrb = '0;

    unique case (req_i.size)
      MEM_SIZE_BYTE: begin
        size_legal     = 1'b1;
        expected_wstrb = 4'b0001 << req_i.addr[1:0];
      end

      MEM_SIZE_HALF: begin
        size_legal = !req_i.addr[0];

        if (!req_i.addr[1])
          expected_wstrb = 4'b0011;
        else
          expected_wstrb = 4'b1100;
      end

      MEM_SIZE_WORD: begin
        size_legal     = req_i.addr[1:0] == 2'b00;
        expected_wstrb = 4'b1111;
      end

      default: begin
        size_legal     = 1'b0;
        expected_wstrb = '0;
      end
    endcase
  end

  /*
   * Reads do not have write strobes.
   *
   * Writes must have exactly the strobes implied by address and size. This
   * prevents contradictory requests such as size=WORD with wstrb=0011.
   */
  always_comb begin
    if (req_i.write)
      strobe_legal = req_i.wstrb == expected_wstrb;
    else
      strobe_legal = req_i.wstrb == '0;
  end

  assign access_legal =
      address_legal &&
      size_legal &&
      strobe_legal;

  /*
   * This target has one response register.
   *
   * It can accept a request when it is not already presenting a response.
   */
  assign req_ready_o = !rsp_valid_q;

  assign accept =
      req_valid_i &&
      req_ready_o;

  /*
   * This is the sole GPIO state-changing event.
   *
   * Invalid requests still receive an error response, but gpio_write remains
   * false, so they cannot affect the output register.
   */
  assign gpio_write =
      accept &&
      access_legal &&
      req_i.write;

  /*
   * Convert one strobe bit into an eight-bit data mask.
   */
  always_comb begin
    write_mask = '0;

    for (int byte_index = 0;
         byte_index < DW/8;
         byte_index = byte_index + 1) begin
      write_mask[8*byte_index +: 8] =
          {8{req_i.wstrb[byte_index]}};
    end
  end

  /*
   * Expand the parameterized register to the bus width, then merge only the
   * selected byte lanes.
   */
  always_comb begin
    gpio_out_word = '0;
    gpio_out_word[GPIO_WIDTH-1:0] = gpio_out_q;

    merged_write_data =
        (gpio_out_word & ~write_mask) |
        (req_i.wdata   &  write_mask);
  end

  assign gpio_out_o = gpio_out_q;

  /*
   * GPIO output storage.
   *
   * Storage changes only for gpio_write. Reads and invalid accesses cannot
   * enter this block's update condition.
   */
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_out_q <= RESET_VALUE;
    end else if (gpio_write) begin
      gpio_out_q <= merged_write_data[GPIO_WIDTH-1:0];
    end
  end

  /*
   * One registered response for every accepted request.
   *
   * - Legal read: current GPIO state
   * - Legal write: zero data, no error
   * - Invalid access: zero data, error
   */
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q <= 1'b0;
      rsp_q       <= '0;
    end else begin
      rsp_valid_q <= accept;

      if (accept) begin
        if (access_legal && !req_i.write)
          rsp_q.rdata <= gpio_out_word;
        else
          rsp_q.rdata <= '0;

        rsp_q.error <= !access_legal;
      end else begin
        rsp_q <= '0;
      end
    end
  end

  assign rsp_valid_o = rsp_valid_q;
  assign rsp_o       = rsp_q;

  /*
   * Elaboration-time contract checks.
   */
  initial begin
    if (DW != 32)
      $fatal(1, "core_bus_gpio currently requires DW=32");

    if (GPIO_WIDTH == 0 || GPIO_WIDTH > DW)
      $fatal(
        1,
        "core_bus_gpio GPIO_WIDTH must be between 1 and DW"
      );

    if (GPIO_OUT_OFFSET[1:0] != 2'b00)
      $fatal(
        1,
        "core_bus_gpio GPIO_OUT_OFFSET must be word aligned"
      );
  end

`ifndef SYNTHESIS
  /*
   * Protocol assertions.
   */
  always @(negedge clk_i) begin
    if (rst_ni) begin
      assert (!(rsp_valid_o && req_ready_o))
        else $error(
          "GPIO advertised request readiness while returning a response"
        );

      if (gpio_write) begin
        assert (accept && access_legal && req_i.write)
          else $error(
            "GPIO output changed without an accepted legal write"
          );
      end
    end
  end
`endif

endmodule

`default_nettype wire