`timescale 1ns / 1ps
`default_nettype wire
import riscv_pkg::*;

// Phase 2 SoC integration testbench. Firmware performs the contract-specific
// checks; this testbench supplies the accepted 64 KiB configuration and treats
// a committed store to tohost as the architectural result.
module tb_riscv_soc #(
  parameter string PROGRAM_FILE = "../testdata/soc_unmapped_load_fault_test.hex",
  parameter string DATA_FILE = "",
  parameter bit TRACE_ENABLE = 1'b0,
  parameter bit DUMP_WAVES = 1'b0,
  parameter int TIMEOUT_CYCLES = 2000,
  parameter logic [31:0] TOHOST_ADDR = 32'h8000_FFFC,
  parameter int PROG_RAM_DEPTH = 16384,
  parameter int DATA_RAM_DEPTH = 16384,
  // RAM wait controls are forwarded through the SoC. Error-injection controls
  // remain runner-compatible but are intentionally unused here; SoC address
  // faults must come from real fabric decode rather than injected RAM errors.
  parameter int DATA_REQ_WAIT_CYCLES = 0,
  parameter int DATA_RSP_WAIT_CYCLES = 0,
  parameter bit UART_CHECK_ENABLE = 1'b0,
  parameter bit UART_RX_ECHO_ENABLE = 1'b0,
  parameter bit GPIO_CHECK_ENABLE = 1'b0,
  parameter bit TIMER_IRQ_CHECK_ENABLE = 1'b0,
  parameter int TIMER_IRQ_EXPECTED_COUNT = 10,
  parameter bit FREERTOS_CHECK_ENABLE = 1'b0,
  parameter int FREERTOS_MIN_TIMER_IRQS = 10,
  parameter bit DATA_FORCE_ERROR = 1'b0,
  parameter bit DATA_ERROR_ADDR_ENABLE = 1'b0,
  parameter logic [31:0] DATA_ERROR_ADDR = '0
);
  localparam int AW = 32;
  localparam int DW = 32;
  localparam int CLK_PERIOD_NS = 10;
  localparam int UART_CLK_FREQ_HZ = 16;
  localparam int UART_BAUD_RATE = 4;
  localparam int UART_CLKS_PER_BIT =
      (UART_CLK_FREQ_HZ + (UART_BAUD_RATE / 2)) / UART_BAUD_RATE;
  localparam int UART_EXPECTED_BYTES =
      FREERTOS_CHECK_ENABLE ? 28 : (UART_RX_ECHO_ENABLE ? 16 : 14);
  localparam int GPIO_EXPECTED_TRANSITIONS = FREERTOS_CHECK_ENABLE ? 2 : 5;

  logic clk;
  logic rst_n;
  logic load_done;
  logic prog_wr_en;
  logic [AW-1:0] prog_wr_addr;
  logic [DW-1:0] prog_wr_data;
  logic [DW-1:0] test_case;
  logic [DW-1:0] reg_s10;
  logic [DW-1:0] reg_s11;
  commit_pkt_t commit;
  trap_entry_t trap_entry;
  logic cpu_rst_n;
  logic uart_tx;
  logic uart_rx;
  logic [7:0] gpio_out;

  logic [DW-1:0] tohost_val;
  logic tohost_seen;
  logic [63:0] expected_commit_order;
  integer cycle_count;
  integer uart_byte_count;
  integer gpio_transition_count;
  integer timer_irq_count;

  assign cpu_rst_n = rst_n && load_done;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD_NS / 2) clk = ~clk;
  end

  initial begin
    rst_n       = 1'b0;
    load_done   = 1'b0;
    prog_wr_en  = 1'b0;
    prog_wr_addr = '0;
    prog_wr_data = '0;

    // Delay past prog_ram's time-zero initialization before installing the
    // selected image. CPU reset stays asserted until the image is complete.
    #1ns;
    $display("[SOC-TB] Loading program image: %s", PROGRAM_FILE);
    $readmemh(PROGRAM_FILE, u_dut.u_prog_ram.mem);
    if (DATA_FILE != "") begin
      $display("[SOC-TB] Loading data image: %s", DATA_FILE);
      $readmemh(DATA_FILE, u_dut.u_data_target.u_data_ram.mem);
    end
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    load_done = 1'b1;
  end

  riscv_soc #(
    .AW(AW),
    .DW(DW),
    .PROG_RAM_DEPTH(PROG_RAM_DEPTH),
    .DATA_RAM_DEPTH(DATA_RAM_DEPTH),
    .DATA_REQ_WAIT_CYCLES(DATA_REQ_WAIT_CYCLES),
    .DATA_RSP_WAIT_CYCLES(DATA_RSP_WAIT_CYCLES),
    .UART_CLK_FREQ_HZ(UART_CLK_FREQ_HZ),
    .UART_BAUD_RATE(UART_BAUD_RATE),
    .UART_RX_FIFO_DEPTH(16)
  ) u_dut (
    .clk         (clk),
    .rst_n       (rst_n),
    .prog_wr_en  (prog_wr_en),
    .prog_wr_addr(prog_wr_addr),
    .prog_wr_data(prog_wr_data),
    .load_done   (load_done),
    .uart_rx_i   (uart_rx),
    .test_case   (test_case),
    .reg_s10     (reg_s10),
    .reg_s11     (reg_s11),
    .commit_o    (commit),
    .trap_entry_o(trap_entry),
    .uart_tx_o  (uart_tx),
    .gpio_out_o (gpio_out)
  );

  function automatic logic [7:0] expected_gpio_value(input integer index);
    begin
      if (FREERTOS_CHECK_ENABLE) begin
        unique case (index % 2)
          0: expected_gpio_value = 8'h01;
          1: expected_gpio_value = 8'h00;
          default: expected_gpio_value = 8'hxx;
        endcase
      end else begin
        unique case (index)
          0: expected_gpio_value = 8'h01;
          1: expected_gpio_value = 8'h02;
          2: expected_gpio_value = 8'h04;
          3: expected_gpio_value = 8'h08;
          4: expected_gpio_value = 8'ha5;
          default: expected_gpio_value = 8'hxx;
        endcase
      end
    end
  endfunction

  function automatic logic [7:0] expected_uart_byte(input integer index);
    integer freertos_index;
    begin
      if (FREERTOS_CHECK_ENABLE) begin
        freertos_index = (index < 17) ? index : (17 + ((index - 17) % 11));
        unique case (freertos_index)
          0:  expected_uart_byte = "F";
          1:  expected_uart_byte = "r";
          2:  expected_uart_byte = "e";
          3:  expected_uart_byte = "e";
          4:  expected_uart_byte = "R";
          5:  expected_uart_byte = "T";
          6:  expected_uart_byte = "O";
          7:  expected_uart_byte = "S";
          8:  expected_uart_byte = " ";
          9:  expected_uart_byte = "R";
          10: expected_uart_byte = "V";
          11: expected_uart_byte = "3";
          12: expected_uart_byte = "2";
          13: expected_uart_byte = "I";
          14: expected_uart_byte = "M";
          15: expected_uart_byte = 8'h0d;
          16: expected_uart_byte = 8'h0a;
          17: expected_uart_byte = "h";
          18: expected_uart_byte = "e";
          19: expected_uart_byte = "a";
          20: expected_uart_byte = "r";
          21: expected_uart_byte = "t";
          22: expected_uart_byte = "b";
          23: expected_uart_byte = "e";
          24: expected_uart_byte = "a";
          25: expected_uart_byte = "t";
          26: expected_uart_byte = 8'h0d;
          27: expected_uart_byte = 8'h0a;
          default: expected_uart_byte = 8'hxx;
        endcase
      end else if (UART_RX_ECHO_ENABLE) begin
        unique case (index)
          0:  expected_uart_byte = 8'h52; // R
          1:  expected_uart_byte = 8'h58; // X
          2:  expected_uart_byte = 8'h20;
          3:  expected_uart_byte = 8'h46; // F
          4:  expected_uart_byte = 8'h49; // I
          5:  expected_uart_byte = 8'h46; // F
          6:  expected_uart_byte = 8'h4f; // O
          7:  expected_uart_byte = 8'h20;
          8:  expected_uart_byte = 8'h31; // 1
          9:  expected_uart_byte = 8'h36; // 6
          10: expected_uart_byte = 8'h20;
          11: expected_uart_byte = 8'h4f; // O
          12: expected_uart_byte = 8'h4b; // K
          13: expected_uart_byte = 8'h21; // !
          14: expected_uart_byte = 8'h0d;
          15: expected_uart_byte = 8'h0a;
          default: expected_uart_byte = 8'hxx;
        endcase
      end else begin
        unique case (index)
          0:  expected_uart_byte = 8'h48; // H
          1:  expected_uart_byte = 8'h65; // e
          2:  expected_uart_byte = 8'h6c; // l
          3:  expected_uart_byte = 8'h6c; // l
          4:  expected_uart_byte = 8'h6f; // o
          5:  expected_uart_byte = 8'h2c; // ,
          6:  expected_uart_byte = 8'h20;
          7:  expected_uart_byte = 8'h55; // U
          8:  expected_uart_byte = 8'h41; // A
          9:  expected_uart_byte = 8'h52; // R
          10: expected_uart_byte = 8'h54; // T
          11: expected_uart_byte = 8'h21; // !
          12: expected_uart_byte = 8'h0d;
          13: expected_uart_byte = 8'h0a;
          default: expected_uart_byte = 8'hxx;
        endcase
      end
    end
  endfunction

  task automatic decode_uart_byte;
    logic [7:0] sampled_byte;
    integer bit_index;
    begin
      @(negedge uart_tx);
      repeat (UART_CLKS_PER_BIT / 2) @(posedge clk);
      #1;
      assert (!uart_tx)
        else $fatal(1, "UART start bit was not low at its center");

      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        repeat (UART_CLKS_PER_BIT) @(posedge clk);
        #1;
        sampled_byte[bit_index] = uart_tx;
      end

      repeat (UART_CLKS_PER_BIT) @(posedge clk);
      #1;
      assert (uart_tx)
        else $fatal(1, "UART stop bit was not high at its center");
      if (!FREERTOS_CHECK_ENABLE) begin
        assert (uart_byte_count < UART_EXPECTED_BYTES)
          else $fatal(1, "UART emitted more bytes than expected");
      end
      assert (sampled_byte == expected_uart_byte(uart_byte_count))
        else $fatal(1,
          "UART byte %0d mismatch: got 0x%02h expected 0x%02h",
          uart_byte_count, sampled_byte,
          expected_uart_byte(uart_byte_count));
      uart_byte_count = uart_byte_count + 1;
    end
  endtask

  task automatic drive_uart_rx_bit(input logic value);
    begin
      @(negedge clk);
      uart_rx = value;
      repeat (UART_CLKS_PER_BIT) @(posedge clk);
    end
  endtask

  task automatic drive_uart_rx_byte(input logic [7:0] value);
    integer bit_index;
    begin
      drive_uart_rx_bit(1'b0);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
        drive_uart_rx_bit(value[bit_index]);
      drive_uart_rx_bit(1'b1);
      @(negedge clk);
      uart_rx = 1'b1;
    end
  endtask

  initial begin
    uart_byte_count = 0;
    if (UART_CHECK_ENABLE || UART_RX_ECHO_ENABLE || FREERTOS_CHECK_ENABLE) begin
      wait (cpu_rst_n == 1'b1);
      forever decode_uart_byte();
    end
  end

  initial begin
    uart_rx = 1'b1;
    if (UART_RX_ECHO_ENABLE) begin
      wait (cpu_rst_n == 1'b1);
      repeat (20) @(posedge clk);
      for (integer rx_index = 0; rx_index < UART_EXPECTED_BYTES;
           rx_index = rx_index + 1)
        drive_uart_rx_byte(expected_uart_byte(rx_index));
    end
  end

  initial begin
    gpio_transition_count = 0;
    if (GPIO_CHECK_ENABLE || FREERTOS_CHECK_ENABLE) begin
      wait (cpu_rst_n == 1'b1);
      assert (gpio_out == 8'h00)
        else $fatal(1, "GPIO reset value mismatch: got 0x%02h", gpio_out);
      forever begin
        @(gpio_out);
        if (cpu_rst_n) begin
          if (!FREERTOS_CHECK_ENABLE) begin
            assert (gpio_transition_count < GPIO_EXPECTED_TRANSITIONS)
              else $fatal(1, "GPIO produced more transitions than expected");
          end
          assert (gpio_out == expected_gpio_value(gpio_transition_count))
            else $fatal(1,
              "GPIO transition %0d mismatch: got 0x%02h expected 0x%02h",
              gpio_transition_count, gpio_out,
              expected_gpio_value(gpio_transition_count));
          gpio_transition_count = gpio_transition_count + 1;
        end
      end
    end
  end

  initial begin
    if (DUMP_WAVES) begin
      $dumpfile("tb_riscv_soc.vcd");
      $dumpvars(0, tb_riscv_soc);
    end
  end

  always_ff @(posedge clk or negedge cpu_rst_n) begin
    if (!cpu_rst_n) begin
      expected_commit_order <= '0;
      tohost_val             <= '0;
      tohost_seen            <= 1'b0;
    end else if (commit.valid) begin
      assert (commit.order == expected_commit_order)
        else $fatal(1, "SoC commit order mismatch: got %0d expected %0d",
                    commit.order, expected_commit_order);
      assert (!commit.trap || !commit.rd_we)
        else $fatal(1, "Trapping SoC commit also wrote a register");
      expected_commit_order <= expected_commit_order + 64'd1;

      if (TRACE_ENABLE) begin
        $display("[SOC-COMMIT] order=%0d pc=0x%08h instr=0x%08h mem=%0b/%0b addr=0x%08h trap=%0b cause=0x%08h mtval=0x%08h",
                 commit.order, commit.pc, commit.instr,
                 commit.mem_valid, commit.mem_we, commit.mem_addr,
                 commit.trap, commit.trap_cause, commit.trap_val);
      end

      if (commit.mem_valid && commit.mem_we &&
          commit.mem_addr == TOHOST_ADDR) begin
        assert (!commit.trap)
          else $fatal(1, "tohost store completed as a trap");
        tohost_val  <= commit.mem_wdata;
        tohost_seen <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (!cpu_rst_n) begin
      timer_irq_count <= 0;
    end else if (trap_entry.valid) begin
      if (trap_entry.interrupt) begin
        assert (trap_entry.cause == MCAUSE_IRQ_M_TIMER && trap_entry.tval == '0)
          else $fatal(1, "Malformed machine-timer trap entry observation");
        timer_irq_count <= timer_irq_count + 1;
      end
    end
  end

  initial begin
    cycle_count = 0;
    wait (cpu_rst_n == 1'b1);
    forever begin
      @(posedge clk);
      cycle_count = cycle_count + 1;
      if (cycle_count >= TIMEOUT_CYCLES) begin
        $display("[SOC-TB] RESULT: FAIL");
        $fatal(1, "SoC test timeout after %0d cycles", cycle_count);
      end
    end
  end

  initial begin
    wait (cpu_rst_n == 1'b1);
    wait (tohost_seen == 1'b1);
    repeat (2) @(posedge clk);
    $display("============================================================");
    $display("[SOC-TB] cycle  = %0d", cycle_count);
    $display("[SOC-TB] tohost = 0x%08h", tohost_val);
    $display("[SOC-TB] x10    = 0x%08h", reg_s10);
    $display("[SOC-TB] x11    = 0x%08h", reg_s11);
    $display("[SOC-TB] timer IRQs = %0d", timer_irq_count);
    $display("[SOC-TB] GPIO pins  = 0x%02h", gpio_out);
    if (tohost_val == 32'd1) begin
      if (FREERTOS_CHECK_ENABLE) begin
        assert (uart_byte_count >= UART_EXPECTED_BYTES)
          else $fatal(1, "FreeRTOS UART byte count mismatch: got %0d expected >= %0d",
                      uart_byte_count, UART_EXPECTED_BYTES);
      end else if (UART_CHECK_ENABLE || UART_RX_ECHO_ENABLE) begin
        assert (uart_byte_count == UART_EXPECTED_BYTES)
          else $fatal(1, "UART byte count mismatch: got %0d expected %0d",
                      uart_byte_count, UART_EXPECTED_BYTES);
      end
      if (FREERTOS_CHECK_ENABLE) begin
        assert (gpio_transition_count >= GPIO_EXPECTED_TRANSITIONS)
          else $fatal(1,
            "FreeRTOS GPIO transition count mismatch: got %0d expected >= %0d",
            gpio_transition_count, GPIO_EXPECTED_TRANSITIONS);
      end else if (GPIO_CHECK_ENABLE) begin
        assert (gpio_transition_count == GPIO_EXPECTED_TRANSITIONS)
          else $fatal(1,
            "GPIO transition count mismatch: got %0d expected %0d",
            gpio_transition_count, GPIO_EXPECTED_TRANSITIONS);
      end
      if (TIMER_IRQ_CHECK_ENABLE) begin
        assert (timer_irq_count == TIMER_IRQ_EXPECTED_COUNT)
          else $fatal(1,
            "Timer interrupt count mismatch: got %0d expected %0d",
            timer_irq_count, TIMER_IRQ_EXPECTED_COUNT);
      end
      if (FREERTOS_CHECK_ENABLE) begin
        assert (timer_irq_count >= FREERTOS_MIN_TIMER_IRQS)
          else $fatal(1,
            "FreeRTOS timer interrupt count too small: got %0d expected >= %0d",
            timer_irq_count, FREERTOS_MIN_TIMER_IRQS);
      end
      $display("[TB] RESULT: PASS");
      $display("============================================================");
      $finish;
    end else begin
      $display("[TB] RESULT: FAIL");
      $display("[SOC-TB] Failure code = %0d / 0x%08h", tohost_val, tohost_val);
      $display("============================================================");
      $fatal(1, "Phase 2 SoC contract test failed");
    end
  end

endmodule
`default_nettype wire
