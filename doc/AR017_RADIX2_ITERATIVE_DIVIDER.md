# AR-017 — Radix-2 iterative divider timing optimization

## Status

**Implemented and functionally verified on 2026-08-01. The refreshed
out-of-context post-synthesis design meets the internal 25 MHz and 50 MHz
constraints for both RAM profiles. Exact-board placement/routing closure is
still open.**

## Problem

`execute.sv` previously used SystemVerilog `/` and `%` operators for
DIV/DIVU/REM/REMU. Vivado synthesized a single-cycle combinational divider into
an 87.102 ns, 305-level path. Both 16 KiB and 64 KiB RAM configurations had the
same path, so neither 25 MHz nor 50 MHz could pass the AR-015 early timing
checkpoint.

The problem was architectural, not a synthesis-switch issue: a complete
32-bit quotient and remainder were being calculated between one ID/EX register
and one EX/WB register in a single cycle.

## Options considered

| Option | Benefit | Cost / decision |
|---|---|---|
| Keep combinational `/` and `%` | No latency change | Rejected: fails even 25 MHz and consumes more than 4,000 extra LUTs |
| Use a vendor divider IP | Configurable and potentially faster | Deferred: reduces RTL portability and adds an IP-generation dependency |
| Use a higher-radix or pipelined divider | Better divide throughput | Deferred: more datapath/control complexity than the FreeRTOS milestone needs |
| Use a restoring Radix-2 iterative divider | Small, portable, one quotient bit per cycle, reuses EX backpressure | Accepted and implemented |

## Underlying principle

The divider first converts signed operands to unsigned magnitudes. It then
holds three working values:

- a 32-bit divisor;
- a 32-bit quotient register initialized with the dividend magnitude;
- a 33-bit partial remainder initialized to zero.

Each `DIV_RUN` cycle performs one restoring Radix-2 step:

```text
{remainder, quotient} = {remainder, quotient} << 1

if shifted_remainder >= divisor:
    remainder = shifted_remainder - divisor
    quotient[0] = 1
else:
    remainder = shifted_remainder
    quotient[0] = 0
```

After 32 iterations, the module applies the RISC-V signed-result rules:

- quotient sign = dividend sign XOR divisor sign;
- remainder sign = dividend sign;
- division by zero returns an all-ones quotient and the original dividend as
  the remainder;
- `0x8000_0000 / 0xffff_ffff` returns `0x8000_0000` with remainder zero.

The signed overflow result falls out naturally from magnitude division and
two's-complement sign correction. Divide-by-zero requires an explicit flag so
the all-ones quotient is not sign-corrected.

## Module and control relationship

```text
decode / riscv_pkg
  muldiv_valid + muldiv_op + op1 + op2
                     |
                     v
               ID/EX packet held
                     |
          +----------+-----------+
          |                      |
          v                      v
  radix2_divider           div_wait
  start/busy/complete          |
  quotient/remainder           v
          |             ex_wait = lsu_busy | div_wait
          |                      |
          |                      v
          |              core_ctrl stalls PC,
          |              IF/ID, and ID/EX
          v
  selected div_result
          |
          v
  execute WB_MULDIV result -> EX/WB -> WB/commit

  ex_kill -----------------> cancel divider and bubble EX/WB
```

| Module/file | Change and responsibility |
|---|---|
| `src/core/radix2_divider.sv` | New 32-iteration restoring divider, signed adaptation, completion pulse, and kill handling |
| `src/core/riscv.sv` | Detects the four divide operations, starts the divider, combines `div_wait` with `lsu_busy`, holds ID/EX, bubbles EX/WB until completion, and selects quotient/remainder |
| `src/core/execute.sv` | Removes synthesizable `/` and `%`; multiplication remains combinational and completed divide data enters through `div_result_i` |
| `src/core/core_ctrl.sv` | No interface change; its existing generic `ex_wait_i` now represents LSU or divider work |
| `src/core/riscv_pkg.sv` and `src/core/decode.sv` | No functional change; existing MULDIV packet fields and operation encodings are reused |
| `sim/filelist.f` and `sim/synth/*.tcl` | Add the divider to simulation and all explicit Vivado source lists |
| `sim/tb/tb_radix2_divider.sv` | Checks arithmetic, fixed latency, busy/completion behavior, cancellation, and recovery |

## Relevant signals

| Signal | Source -> destination | Meaning |
|---|---|---|
| `id2ex_pkt_out.valid` | ID/EX -> divide detector | The held EX packet is architecturally active |
| `id2ex_pkt_out.ex_ctrl.muldiv_valid` | Decode packet -> divide detector | Instruction belongs to RV32M MULDIV |
| `id2ex_pkt_out.ex_ctrl.muldiv_op` | Decode packet -> divider integration | Selects DIV, DIVU, REM, or REMU and signed/result behavior |
| `id2ex_pkt_out.ex_data.op1/op2` | ID/EX -> divider | Dividend and divisor |
| `div_start` | `riscv.sv` -> divider | One accepted operation starts while idle |
| `div_signed` | `riscv.sv` -> divider | Enables signed magnitude and sign correction for DIV/REM |
| `div_busy` | divider -> integration/assertions | The 32 iterative cycles are active |
| `div_complete` | divider -> EX/WB gating | One-cycle completed quotient/remainder are available |
| `div_quotient/div_remainder` | divider -> result selector | Raw architectural results |
| `div_wait` | divide detector -> `ex_wait` | Includes the initial start cycle and every incomplete cycle |
| `ex_wait` | `riscv.sv` -> `core_ctrl.ex_wait_i` | `lsu_busy OR div_wait`; holds PC, IF/ID, and ID/EX |
| `ex_kill` | pipeline control -> LSU/divider | Cancels younger multi-cycle work on a pipeline kill/EX exception |
| `EX_WB_PKT_BUBBLE` | `riscv.sv` -> EX/WB input | Prevents an incomplete held divide instruction from retiring repeatedly |
| `div_result_i` | `riscv.sv` -> `execute.sv` | Selected quotient or remainder for `WB_MULDIV` |

## Timing and latency contract

The cycle in which a divide first appears in ID/EX asserts `div_wait` before
the divider's registered busy state is visible. The start edge captures the
operands. Exactly 32 `DIV_RUN` iterations follow, then `DIV_COMPLETE` exposes a
one-cycle result and releases ID/EX. EX/WB receives canonical bubbles throughout
the incomplete interval.

This increases DIV/REM instruction latency, but it does not slow ordinary ALU,
load/store, branch, CSR, or multiply instructions. The initial FreeRTOS target
does not depend on high divide throughput.

## Functional verification

Focused divider test:

```powershell
Set-Location D:\Rsicv-soc\sim
vsim -c -do run_divider_protocol.do
```

Result:

```text
[DIVIDER-TB] RESULT: PASS cases=42
Errors: 0, Warnings: 0
```

The 42 completions cover fixed signed/unsigned cases, positive/negative sign
combinations, zero dividend, signed and unsigned divide-by-zero, signed
overflow, maximum unsigned operands, 32 randomized comparisons, and recovery
after a killed operation. The killed operation itself produces no completion.

Pipeline integration results:

- `rv32im` and `rv32im_waitstate`: 2/2 PASS, simulator exit 0;
- full directed smoke regression: 22/22 PASS, every simulator exit 0;
- standalone LSU protocol: PASS;
- regression exit-status classifier: PASS.

## Utilization comparison

Vivado 2019.2, provisional `xc7z010clg400-1`, OOC synthesis:

| RAM profile | Design | Slice LUTs | Registers | RAMB36 | DSP |
|---|---|---:|---:|---:|---:|
| 16 KiB/bank | Combinational baseline | 7,861 | 2,465 | 8 | 12 |
| 16 KiB/bank | Iterative divider | 3,504 | 2,601 | 8 | 12 |
| 64 KiB/bank | Combinational baseline | 7,902 | 2,467 | 32 | 12 |
| 64 KiB/bank | Iterative divider | 3,542 | 2,601 | 32 | 12 |

The iterative implementation removes approximately 4,360 LUTs while adding
about 135 registers. RAM and DSP consumption are unchanged.

## Post-synthesis timing comparison

| RAM profile | Target | Baseline WNS | Iterative WNS | Iterative worst path |
|---|---:|---:|---:|---:|
| 16 KiB/bank | 50 MHz | -67.124 ns | +7.373 ns | 12.605 ns / 19 levels |
| 64 KiB/bank | 50 MHz | -67.124 ns | +7.373 ns | 12.605 ns / 19 levels |
| 16 KiB/bank | 25 MHz | -47.124 ns | +27.373 ns | 12.605 ns / 19 levels |
| 64 KiB/bank | 25 MHz | -47.124 ns | +27.373 ns | 12.605 ns / 19 levels |

Both refreshed profiles have zero failing setup endpoints. The new worst path
is a multiply-high path through two DSP48E1 elements and a carry chain from an
ID/EX operand to EX/WB `alu_data[31]`. Division is no longer the critical path.

The reciprocal of 12.605 ns is about 79.3 MHz, but this is not a routed Fmax.
The appropriate plan remains conservative 25 MHz board bring-up followed by a
50 MHz attempt after exact-part XDC, placement, and routing pass with margin.

## Consequences and remaining risks

- The AR-011/AR-015 combinational-divider blocker is closed at the early OOC
  checkpoint.
- Exact-board clock/reset constraints, placement, routing, I/O timing, power,
  and bitstream validation remain Phase 7 gates.
- Multiply-high is now the first optimization candidate only if routed 50 MHz
  timing later fails; no further MULDIV redesign is justified by current data.
- Official RV32M architectural tests should remain part of the continuous ACT4
  track even though directed and randomized divider checks are green.
- A future interrupt controller must preserve the existing rule that
  `ex_kill` cancels outstanding multi-cycle work without retirement.

## Evidence

The durable summary is
[`evidence/ar017_divider/optimization_results.txt`](evidence/ar017_divider/optimization_results.txt).
The complete reproducible commands and interpretation are recorded above;
Vivado's larger generated checkpoints and reports remain under ignored
`build/vivado_ram_16k` and `build/vivado_ram_64k` directories.
