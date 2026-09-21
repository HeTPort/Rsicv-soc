# `p0_wfi_timer` Power Workload Design

## Status and identity

| Item | Value |
|---|---|
| Workload version | `1.0` |
| Lifecycle state | `verified` |
| Owner | HeTPort |
| Target clock | Exact routed 95 MHz, timer tick period 1 core cycle; WNS +0.003 ns |
| Firmware/images | `sw/apps/p0_wfi_timer`; split images installed and hashed |
| Last evidence run | 2026-09-19, `run1`/`run2` plus `debug_vcd1` |

## Purpose

Measure the active-idle floor of the CPU while WFI suppresses instruction
retirement, together with the repeatable cost of machine-timer wake, trap entry,
handler execution, MRET, and return to WFI.

## Design intent

The original bare-metal workload schedules 64 interrupts at a fixed 4,096
`mtime`-tick interval. Between interrupts the core executes WFI. The handler
validates `mcause`/`mtval`, rearms the level-sensitive timer, increments one
volatile wake counter, and returns with MRET. No GPIO or UART traffic occurs in
the measurement window.

## Non-goals

- This is not a zero-clock or power-gated sleep measurement.
- It does not represent FreeRTOS context switching or application tasks.
- It does not measure board-rail, thermal, ASIC, or battery power.
- It does not characterize compute, multiplier, divider, or RAM throughput.

## Fixed inputs and useful work

One useful-work unit is one validated timer interrupt wake and return to WFI.
The workload performs exactly 64 units with a 4,096-tick interval and no
data-dependent inputs.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Warmup / START | Timer initialized; MTIE and global MIE enabled; marker store immediately before the first WFI |
| END | Exactly 64 handler increments observed; interrupts disabled and timer source moved inactive; marker store |
| Final PASS | Exact wake count remains 64, then committed `tohost = 1` |

## Expected block activity

| Block | Expected state | Reason/check |
|---|---|---|
| Core clock/control | Active | Clock continues; WFI state and wake control toggle |
| Pipeline/program BRAM | Mostly idle with bursts | Trap/handler/MRET bursts between WFI intervals |
| Timer/fabric/LSU/data BRAM | Active at fixed cadence | `mtime`, `mtimecmp`, counter, and stack accesses |
| Multiplier/divider | No MUL/DIV instruction | Divider state remains essentially idle; combinational DSP operands still switch incidentally and are measured/bridged, not forced to zero |
| UART/GPIO | Idle | No diagnostic peripheral traffic in-window |

## Functional oracle and failure consequences

PASS requires 64 validated machine-timer wakes followed by `tohost = 1`.
Unexpected trap metadata reports `0xBAD72001`; a final count mismatch reports
`0xBAD72002`. Missing/duplicate markers, timeout, or any other nonzero `tohost`
invalidates the run.

## Key performance indicators

| KPI ID | Metric | Unit | Acceptance/comparison rule | Evidence |
|---|---|---|---|---|
| P0WFI-KPI-001 | Functional oracle | pass/fail | 64 wakes and `tohost = 1` | PASS, SoC/power-TB and two captures |
| P0WFI-KPI-002 | Completed wakes | wakes | Exactly 64 | PASS, 64 |
| P0WFI-KPI-003 | Cycles per wake | cycles/wake | Report fixed marker interval / 64 | 4,295.3125 |
| P0WFI-KPI-004 | Retired instructions per wake | instructions/wake | Report | 107.296875 |
| P0WFI-KPI-005 | Routed timing/DRC | ns/count | WNS >= 0, TNS 0, no blocking DRC | PASS, +0.003 ns / 0.000 ns / 0 blocking |
| P0WFI-KPI-006 | Activity coverage | pass/fail | >=80% mapping or reviewed block alternative | PASS via 13-block review; raw 483/8,762 (5.512%) |
| P0WFI-KPI-007 | Dynamic repeatability | percent | <=2% | PASS, 0.0% (0.117 W twice) |
| P0WFI-KPI-008 | Dynamic energy per wake | J/wake | Same identity/environment | 5.2900e-6 J/wake |

## Reproducibility identity

Retain the firmware/image hashes, marker symbol/address, 64-wake and 4,096-tick
constants, simulator/Vivado versions, exact 95 MHz checkpoint, capture duration,
coverage decision, reports, hashes, and commands.

## Risks and limitations

- The timer clock is the core clock divided by the SoC timer parameter; changing
  either value creates a new workload identity.
- Average energy per wake includes the declared WFI interval, so comparison
  requires the same interval.
- RTL SAIF/glitch and optimized-name limitations are the same as `p0_mix`.

## Verification and evidence

The SoC and power-TB regressions pass. Two independent marker-window backward-
SAIF captures, the matching timing-clean 95 MHz route, the reviewed 13-block
coverage alternative, and the <=2% repeatability gate pass. An optional
windowed debug VCD was also generated. See [results.md](results.md) for exact
commands, hashes, coverage, power, and limitations.
