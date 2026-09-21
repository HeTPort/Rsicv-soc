# AR-028 — P0 95 MHz Activity Mapping and Workload Baseline

**Status:** All six P0 scenario classes verified; direct-name mapping remains limited
**Date:** 2026-09-20
**Scope:** Measurement tooling and workload firmware only; no RTL/MMIO change.

## Problem and root cause

The first ModelSim backward-SAIF imported into a clockless, older OOC SoC
checkpoint matched 419/10,927 design nets (about 4%); its 17.583 W diagnostic
number was invalid for a board-clocked baseline. After moving to workload-
matched 95 MHz routed checkpoints, direct matches remained low: 481/8,746
for `p0_mix` and 483/8,762 for each of the other five scenarios
(all about 5.5%). ModelSim
names packed RTL struct fields differently from Vivado's synthesized register
names, and synthesis absorbs or renames combinational and optimized nets.
The low match is therefore not repaired merely by choosing a better workload
or changing the strip path. It does not mean that 95% of the chip is inactive.

## Options considered

| Option | Decision/reason |
|---|---|
| Use the old 4% OOC number | Rejected: wrong implementation, no valid user clock, reset-inclusive capture. |
| Claim the matching-route 5.5% direct import as sufficient | Rejected: too much unexamined vectorless fallback. |
| Rename broad RTL hierarchies or insert power-only RTL | Rejected for P0: changes the measured design and risks functional/timing regressions. |
| Full post-route gate simulation | Feasibility smoke did not reach START promptly; not a scalable default on this host. |
| Reviewed block-level alternative permitted by REQ-P0-004 | Selected: direct boundary/state observations plus explicit measured-to-routed bridges and failure gates. |

## Decision and measurement path

Each workload owns a `design.md` for question, intent, boundaries, oracle, and
KPIs, and a structured manifest. Firmware writes committed START/END marker
stores after reset/warmup and fixed work; a separate committed `tohost=1`
proves functional completion. `tb_power/u_soc` captures the marker window.
Vivado imports SAIF with `-strip_path tb_power` to the workload-matched
`top/u_soc` checkpoint routed at exactly 95 MHz. Vectorless and activity
reports use that same checkpoint. The production 25 MHz profile is separate.

For optimized DSP nets, measured SAIF operand/result toggle rates are applied
to the four routed DSP48 cells. For WFI/timer and FreeRTOS, measured per-bit
`mtime` and `mtimecmp` activity is mapped to all 128 routed timer Q nets. The latter bridge
records a tiny bit-0 clock-quantization clamp; it rejects material excess.
The clocked spin-idle DSP bridge similarly records a bounded `2.218e-6`
operand and `1.361e-6` product probability adjustment after Vivado rejected
the unadjusted quantized pair. Inconsistent pairs greater than 0.0001 fail.
Per-workload block policies require activity or deliberate idle evidence at
CPU, fabric, BRAM, timer, DSP, divider, and peripheral boundaries. This is
explicitly the **reviewed alternative**, not 80% direct net mapping.

## Consequences and verification

| Evidence | `p0_mix` | `p0_wfi_timer` | `p0_ram_stream` |
|---|---:|---:|---:|
| Fixed work | 2,048 iterations / 338,043 cycles | 64 validated wakes / 274,900 cycles | 64 KiB / 213,145 cycles |
| Routed setup WNS/TNS | +0.006 / 0 ns | +0.003 / 0 ns | +0.003 / 0 ns |
| Direct SAIF match | 481/8,746 | 483/8,762 | 483/8,762 |
| Reviewed policy | 10/10 PASS | 13/13 PASS | 10/10 PASS |
| Vectorless dynamic | 0.115 W | 0.119 W | 0.119 W |
| Reviewed activity dynamic | 0.127 W | 0.117 W | 0.129 W |
| Two-run dynamic variance | 0.0% | 0.0% | 0.0% |

| Evidence | `p0_freertos` | `p0_idle_spin` | `p0_uart_poll` |
|---|---:|---:|---:|
| Fixed work | 16 ordered receives / 1,709,023 cycles | 65,536 spins / 458,759 cycles | 14 TX bytes / 115,574 cycles |
| Routed setup WNS/TNS | +0.003 / 0 ns | +0.003 / 0 ns | +0.003 / 0 ns |
| Direct SAIF match | 483/8,762 | 483/8,762 | 483/8,762 |
| Reviewed policy | 13/13 PASS | 10/10 PASS | 12/12 PASS |
| Vectorless dynamic | 0.119 W | 0.119 W | 0.119 W |
| Reviewed activity dynamic | 0.120 W | 0.158 W | 0.119 W |
| Two-run dynamic variance | 0.0% | 0.0% | 0.0% |

The first WFI route used `TIMER_TICK_CYCLES=3` while simulation used 1; it
was rejected and rebuilt at 1 before power analysis. All six final routes have
zero Error/Critical Warning DRC; advisory warnings including `REQP-1839`
remain. A deliberate missing-SAIF negative test fails explicitly. Optional
WFI marker-window VCD generation passed. See the
[`p0_mix` results](../power/workloads/p0_mix/results.md),
[`p0_wfi_timer` results](../power/workloads/p0_wfi_timer/results.md),
[`p0_ram_stream` results](../power/workloads/p0_ram_stream/results.md),
[`p0_freertos` results](../power/workloads/p0_freertos/results.md),
[`p0_idle_spin` results](../power/workloads/p0_idle_spin/results.md),
[`p0_uart_poll` results](../power/workloads/p0_uart_poll/results.md), and
[P0 phase verdict](plans/p0-power-baseline/results.md) for commands and hashes.

These are comparative Vivado estimates: functional RTL SAIF omits routed
glitches, optimized unmatched logic uses probabilistic propagation, PS7
properties are not fully specified, and physical board-rail/ASIC power is
unmeasured. Do not combine different scenario averages into a single chip
power claim. The two-workload infrastructure gate and all six scenario-class
technical gates pass. The spin-idle result is deliberately **not** a low-power
sleep result: repeated fetches and changing register operands drive program
BRAM and the combinational DSP network even with no MUL instruction. The
WFI/timer case is the separate sleep/wake comparison.
