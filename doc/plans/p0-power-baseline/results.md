# P0 Reproducible Power Baseline — Results

**Phase:** P0 — Reproducible power baseline
**Status:** Six-scenario technical portfolio VERIFIED; physical power sign-off not claimed
**Owner:** HeTPort
**Last updated:** 2026-09-20

The initial September 7 capability spike produced VCD/backward-SAIF from a
passing `rv32im` simulation, but captured reset/boot and mapped only 419 of
10,927 nets (about 4%) to an older, clockless OOC checkpoint. Its 17.583 W,
Low-confidence diagnostic report is **rejected**, not a baseline result.

The implemented flow now captures committed START-to-END windows under
`tb_power/u_soc`, imports backward-SAIF into each workload's exact 95 MHz
timing-clean board checkpoint, compares vectorless and reviewed activity power,
and repeats independently. Optional VCD was checked for `p0_wfi_timer`.

| Workload | Window | 95 MHz route | Direct SAIF match | Reviewed block alternative | Vectorless dynamic | Activity dynamic | Two-run variance |
|---|---:|---|---:|---|---:|---:|---:|
| [`p0_mix`](../../../power/workloads/p0_mix/results.md) | 338,043 cycles / 2,048 iterations | WNS +0.006 ns, TNS 0 | 481/8,746 (5.5%) | 10/10 gates PASS, measured DSP bridge | 0.115 W | 0.127 W | 0.0% |
| [`p0_wfi_timer`](../../../power/workloads/p0_wfi_timer/results.md) | 274,900 cycles / 64 wakes | WNS +0.003 ns, TNS 0 | 483/8,762 (5.5%) | 13/13 gates PASS, measured DSP/timer-Q bridges | 0.119 W | 0.117 W | 0.0% |
| [`p0_ram_stream`](../../../power/workloads/p0_ram_stream/results.md) | 213,145 cycles / 64 KiB | WNS +0.003 ns, TNS 0 | 483/8,762 (5.5%) | 10/10 gates PASS, measured DSP bridge | 0.119 W | 0.129 W | 0.0% |
| [`p0_freertos`](../../../power/workloads/p0_freertos/results.md) | 1,709,023 cycles / 16 queue receives | WNS +0.003 ns, TNS 0 | 483/8,762 (5.5%) | 13/13 gates PASS, measured DSP/timer-Q bridges | 0.119 W | 0.120 W | 0.0% |
| [`p0_idle_spin`](../../../power/workloads/p0_idle_spin/results.md) | 458,759 cycles / 65,536 spin iterations | WNS +0.003 ns, TNS 0 | 483/8,762 (5.5%) | 10/10 gates PASS, measured DSP bridge | 0.119 W | 0.158 W | 0.0% |
| [`p0_uart_poll`](../../../power/workloads/p0_uart_poll/results.md) | 115,574 cycles / 14 TX bytes | WNS +0.003 ns, TNS 0 | 483/8,762 (5.5%) | 12/12 gates PASS, measured DSP bridge | 0.119 W | 0.119 W | 0.0% |

All six routes use provisional `xc7z010clg400-1`, Vivado 2019.2, exact 95 MHz,
zero Error/Critical Warning DRC, and 16 program plus 16 data RAMB36 blocks.
The WFI simulation and routed implementation both use
`TIMER_TICK_CYCLES=1`; the first prescaler-3 route was rejected. Detailed
commands, tool identity, hashes, matching checkpoints, window metrics,
mapping rules, category reports, and limitations are retained in each linked
workload result. Generated SAIF/VCD/DCP files remain under ignored `build/`.

## Requirement trace and verdict

| Requirement | Result |
|---|---|
| REQ-P0-001 scenario portfolio | **PASS:** mixed compute/memory, WFI/timer, dedicated RAM stream, FreeRTOS, clocked fixed spin idle, and UART polling have exact images and functional oracles. Spin idle is not deep sleep. |
| REQ-P0-002 deterministic post-reset window | PASS for all six measured workloads; markers and cycle counts retained. |
| REQ-P0-003 VCD/backward-SAIF | PASS: backward-SAIF for all six; marker-window debug VCD for WFI. |
| REQ-P0-004 same-route import/mapping | PASS under the explicit reviewed block-level alternative; **80% direct mapping not achieved**. |
| REQ-P0-005 vectorless/activity decomposition | PASS for all six on the identical checkpoint per workload. |
| REQ-P0-006 evidence retention | PASS for all six; commands, hashes, reports, assumptions, and limits recorded. |
| PERF-P0-001 repeatability | PASS: 0.0% dynamic-power variance in all six two-run pairs at report resolution, threshold 2%. |
| PERF-P0-002 bounded scope/storage | PASS: `u_soc` START/END interval; WFI debug VCD 28,722,318 bytes. |
| VER-P0-001 negative infrastructure case | PASS: deliberate missing-SAIF path rejected rather than silently falling back. |

The two-workload measurement-infrastructure gate and the complete six-class
technical portfolio both pass. In the idle-spin reference, a register-only
loop still excites program BRAM and the un-gated multiplier; its 0.158 W
dynamic estimate is not a WFI/deep-sleep number. None of the results is a
board-rail, silicon, thermal, battery, or ASIC measurement. RTL functional
SAIF omits routed glitches; unmatched optimized logic still receives Vivado's
probabilistic propagation. The PS7 property warning and provisional speed
grade are retained limitations. Do not average these different scenarios into
one purported chip-wide power number.
