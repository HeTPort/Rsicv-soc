

```markdown
# Phase 3 Implementation Guide — Machine Timer Interrupts (Revised)

**Purpose:** Provide concrete, file-by-file guidance for implementing Phase 3 (precise machine timer interrupts) and its power-saving extensions (gated clock WFI, AVS interface).

**Prerequisites:** Phase 0/0A/1/2 complete. Track A ACT4 passing.

---

## 1. Task Map & Files

| Task | Target File(s) | Action |
|------|----------------|--------|
| Hardware Interrupt Input | `src/core/riscv.sv` | Add `irq_mti_i`, detect & gate interrupt |
| CSR mip.MTIP Drive | `src/core/csr_regfile.sv` | Hardwire `mip_q[7]` to `irq_mti_i` |
| Exception Priority | `src/core/riscv.sv` | Mux exception/interrupt entry |
| Precise Interrupt Entry | `src/core/riscv.sv`, `csr_regfile.sv` | Save `next_pc` to `mepc`, flush pipeline |
| `mret` Resume | `src/core/riscv.sv` | Redirect PC to `mepc` |
| WFI Behavior | `src/core/core_ctrl.sv`, `riscv.sv` | Stall pipeline until `interrupt_pending` |
| Timer Peripheral | `src/timer/mtime_timer.sv` (new) | 64-bit `mtime`/`mtimecmp` + safe read |
| Clock Gating (WFI) | `src/soc/soc_clock_ctrl.sv` (new) | 2-state FSM driving `BUFGCE` |
| SoC Integration | `src/riscv_soc.sv`, `soc_data_fabric.sv` | Wire timer, CCU, and gated clock |

---

## 2. CPU Core Logic

### 2.1 `src/core/csr_regfile.sv`
**Changes:**
1. Add input port:
```systemverilog
input  logic irq_mti_i,    // Machine timer interrupt from CLINT
```
2. Drive `mip_q[7]` (MTIP) from hardware. Remove `CSR_MIP` from the `csr_we_i` write case entirely.
```systemverilog
// After the csr_we_i block:
mip_q[7] <= irq_mti_i;   // MTIP driven strictly by timer hardware
```

### 2.2 `src/core/riscv.sv`
**Changes:**
1. Add ports:
```systemverilog
input  logic irq_mti_i,
output logic wfi_active_o,
output logic wfi_done_o
```
2. Add interrupt detection:
```systemverilog
logic interrupt_pending;
assign interrupt_pending = csr_mip[7];

logic interrupt_enabled;
assign interrupt_enabled = csr_mstatus[3] && csr_mie[7];

logic interrupt_taken;
assign interrupt_taken = interrupt_pending && interrupt_enabled;

// Exception priority over interrupt
logic interrupt_entry;
assign interrupt_entry = ex2wb_pkt_out.valid && !wb_trap_event && interrupt_taken;
```
3. Unified trap mux (Fix: Save `next_pc` for interrupts, not current `pc`):
```systemverilog
logic trap_entry;
logic [AW-1:0] trap_pc;
logic [DW-1:0] trap_cause;
logic [DW-1:0] trap_val;

always_comb begin
    if (wb_trap_event) begin
        trap_entry  = 1'b1;
        trap_pc     = ex2wb_pkt_out.pc;       // Exception: current PC
        trap_cause  = ex2wb_pkt_out.trap_cause;
        trap_val    = ex2wb_pkt_out.trap_val;
    end else if (interrupt_entry) begin
        trap_entry  = 1'b1;
        trap_pc     = ex2wb_pkt_out.next_pc;  // Interrupt: NEXT PC
        trap_cause  = 32'h8000_0007;          // MCAUSE_IRQ_M_TIMER
        trap_val    = '0;
    end else begin
        trap_entry  = 1'b0;
        trap_pc     = '0;
        trap_cause  = '0;
        trap_val    = '0;
    end
end

assign trap_redirect_en = wb_trap_event || interrupt_entry;
assign trap_redirect_pc = csr_mtvec;

assign wb_mret_event = ex2wb_pkt_out.valid && ex2wb_pkt_out.is_mret;
assign pc_redirect_en = ex_redirect_en || trap_redirect_en || wb_mret_event;
assign pc_redirect_pc = trap_redirect_en ? trap_redirect_pc :
                        ex_redirect_en  ? ex_redirect_pc   :
                        wb_mret_event   ? csr_mepc : '0;
```
4. WFI status outputs:
```systemverilog
assign wfi_active_o = id2ex_pkt_out.valid && id2ex_pkt_out.is_wfi && !interrupt_taken;
assign wfi_done_o   = id2ex_pkt_out.valid && id2ex_pkt_out.is_mret;
```

### 2.3 `src/core/core_ctrl.sv`
**Changes:**
1. Add inputs: `mret_i`, `wfi_active_i`, `interrupt_pending_i`
2. Simplify WFI stall logic (No cross-domain deadlock):
```systemverilog
logic wfi_stall;
// Stall only if WFI active and no interrupt pending
assign wfi_stall = wfi_active_i && !interrupt_pending_i;

// Update pipeline stalls
assign pc_stall   = hazard_stall | ex_stall | pipe_kill | wfi_stall;
assign ifid_stall = hazard_stall | ex_stall | wfi_stall;
assign idex_stall = ex_stall | wfi_stall;
```
3. Add `mret_i` to `fetch_kill_q`:
```systemverilog
always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) fetch_kill_q <= 1'b0;
    else         fetch_kill_q <= ex_flush_req || trap_redirect_en || mret_i;
end
```

---

## 3. Timer Peripheral

### `src/timer/mtime_timer.sv` (New File)
```systemverilog
`timescale 1ns / 1ps
`default_nettype wire
module mtime_timer #(
    parameter int AW = 32, parameter int DW = 32,
    parameter logic [AW-1:0] MTIME_ADDR    = 32'h0200BFF8,
    parameter logic [AW-1:0] MTIMECMP_ADDR = 32'h02004000
)(
    input  logic       clk_i, rst_ni,
    input  logic [AW-1:0] csr_addr_i,
    input  logic          csr_we_i,
    input  logic [DW-1:0] csr_wdata_i,
    output logic [DW-1:0] csr_rdata_o,
    output logic          irq_mti_o
);
    logic [63:0] mtime_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mtime_q <= '0;
        else mtime_q <= mtime_q + 64'd1;
    end

    logic [63:0] mtimecmp_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mtimecmp_q <= '0;
        else if (csr_we_i && (csr_addr_i == MTIMECMP_ADDR))
            mtimecmp_q[31:0] <= csr_wdata_i;
        else if (csr_we_i && (csr_addr_i == MTIMECMP_ADDR + 4))
            mtimecmp_q[63:32] <= csr_wdata_i;
    end

    logic irq_mti_raw;
    assign irq_mti_raw = (mtime_q >= mtimecmp_q);

    logic irq_mti_q;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) irq_mti_q <= 1'b0;
        else if (csr_we_i && (csr_addr_i == MTIMECMP_ADDR || csr_addr_i == MTIMECMP_ADDR + 4))
            irq_mti_q <= 1'b0; // Clear on write
        else if (irq_mti_raw)
            irq_mti_q <= 1'b1; // Set on compare match
    end
    assign irq_mti_o = irq_mti_q;

    // Safe RV32 high/low-word read latch
    logic [31:0] mtime_hi_latch;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) mtime_hi_latch <= '0;
        else if (csr_addr_i == MTIME_ADDR) mtime_hi_latch <= mtime_q[63:32];
    end

    always_comb begin
        csr_rdata_o = '0;
        if (csr_addr_i == MTIME_ADDR)              csr_rdata_o = mtime_q[31:0];
        else if (csr_addr_i == MTIME_ADDR + 4)     csr_rdata_o = mtime_hi_latch;
        else if (csr_addr_i == MTIMECMP_ADDR)      csr_rdata_o = mtimecmp_q[31:0];
        else if (csr_addr_i == MTIMECMP_ADDR + 4)  csr_rdata_o = mtimecmp_q[63:32];
    end
endmodule
`default_nettype wire
```

---

## 4. Clock Control Unit (CCU)

### `src/soc/soc_clock_ctrl.sv` (New File)
```systemverilog
`timescale 1ns / 1ps
`default_nettype wire
module soc_clock_ctrl (
    input  logic clk_i, rst_ni,
    input  logic cpu_wfi_active_i, // From CPU
    input  logic irq_mti_i,        // From Timer (ungated)
    output logic cpu_clk_en_o      // To BUFGCE
);
    logic irq_sync1, irq_sync2;
    logic wfi_sync1, wfi_sync2;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            irq_sync1 <= 1'b0; irq_sync2 <= 1'b0;
            wfi_sync1 <= 1'b0; wfi_sync2 <= 1'b0;
        end else begin
            irq_sync1 <= irq_mti_i;     irq_sync2 <= irq_sync1;
            wfi_sync1 <= cpu_wfi_active_i; wfi_sync2 <= wfi_sync1;
        end
    end

    typedef enum logic [1:0] { CLK_RUNNING = 2'd0, CLK_GATED = 2'd1 } clk_state_e;
    clk_state_e state_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= CLK_RUNNING;
            cpu_clk_en_o <= 1'b1;
        end else begin
            case (state_q)
                CLK_RUNNING: begin
                    cpu_clk_en_o <= 1'b1;
                    // Gate clock only if CPU requests WFI and no interrupt is pending
                    if (wfi_sync2 && !irq_sync2) begin
                        state_q <= CLK_GATED;
                        cpu_clk_en_o <= 1'b0;
                    end
                end
                CLK_GATED: begin
                    cpu_clk_en_o <= 1'b0;
                    // Re-enable clock immediately when interrupt arrives
                    if (irq_sync2) begin
                        state_q <= CLK_RUNNING;
                        cpu_clk_en_o <= 1'b1;
                    end
                end
                default: state_q <= CLK_RUNNING;
            endcase
        end
    end
endmodule
`default_nettype wire
```

---

## 5. SoC Integration

### 5.1 `src/bus/soc_data_fabric.sv`
Add CLINT address decode logic to route requests to `timer_req_*` outputs when `cpu_req_i.addr` falls in `0x0200_0000` - `0x0200_FFFF`.

### 5.2 `src/riscv_soc.sv`
```systemverilog
    // ============================================================
    // Clock Control Unit
    // ============================================================
    logic wfi_active_cpu;
    logic cpu_clk_en;
    logic irq_mti_raw;
    logic irq_mti_cpu;

    soc_clock_ctrl u_clock_ctrl (
        .clk_i            (clk),
        .rst_ni           (cpu_rst_n),
        .cpu_wfi_active_i (wfi_active_cpu),
        .irq_mti_i        (irq_mti_raw),
        .cpu_clk_en_o     (cpu_clk_en)
    );

    // Xilinx FPGA Safe Clock Gate
    logic cpu_gated_clk;
    BUFGCE u_cpu_clk_bufgce (
        .I  (clk),
        .CE (cpu_clk_en),
        .O  (cpu_gated_clk)
    );

    // Synchronize timer IRQ into CPU clock domain (in case of gating recovery delay)
    logic irq_sync1, irq_sync2;
    always_ff @(posedge cpu_gated_clk or negedge cpu_rst_n) begin
        if (!cpu_rst_n) begin
            irq_sync1 <= 1'b0; irq_sync2 <= 1'b0;
        end else begin
            irq_sync1 <= irq_mti_raw; irq_sync2 <= irq_sync1;
        end
    end
    assign irq_mti_cpu = irq_sync2;

    // ============================================================
    // CPU (gated clock)
    // ============================================================
    riscv u_riscv (
        .clk_i              (cpu_gated_clk),  // GATED CLOCK
        .rst_ni             (cpu_rst_n),
        // ... existing ports ...
        .irq_mti_i          (irq_mti_cpu),
        .wfi_active_o       (wfi_active_cpu),
        .wfi_done_o         ()
    );

    // ============================================================
    // Timer Peripheral (ungated clock)
    // ============================================================
    mtime_timer u_mtime_timer (
        .clk_i       (clk),            // UNGATED CLOCK
        .rst_ni      (cpu_rst_n),
        .csr_addr_i  (timer_req_addr),
        .csr_we_i    (timer_req_we),
        .csr_wdata_i (timer_req_wdata),
        .csr_rdata_o (timer_req_rdata),
        .irq_mti_o   (irq_mti_raw)
    );
```

---

## 6. Implementation Order

1. **`csr_regfile.sv`**: Add `irq_mti_i`, hardwire `mip_q[7]`, remove software write.
2. **`riscv.sv`**: Add interrupt detection, fix `trap_pc = next_pc` for interrupts, add WFI outputs.
3. **`core_ctrl.sv`**: Add simple `wfi_stall` logic based on `interrupt_pending_i`.
4. **`mtime_timer.sv`**: Create 64-bit timer with safe high-word read latch.
5. **`soc_clock_ctrl.sv`**: Create 2-state FSM for WFI clock gating.
6. **`soc_data_fabric.sv`**: Route `0x0200_0000` range to timer.
7. **`riscv_soc.sv`**: Instantiate CCU, `BUFGCE`, Timer, and wire gated clock to CPU.

## 7. Exit Gate
A bare-metal handler services at least 10,000 simulated timer interrupts and returns correctly, with the complete smoke regression green.
```
