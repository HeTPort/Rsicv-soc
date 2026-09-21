# `p0_ram_stream` Power Workload Design

## Status and identity

Version `1.0`; lifecycle `verified`. Original firmware builds into the split
64 KiB program/data RAM profile. Both functional regressions, two marker-window
SAIF captures, the exact 95 MHz route, reviewed block coverage, and two-run
repeatability pass. See [measured results](results.md).

## Purpose

Isolate sequential LSU/fabric/data-BRAM transfer cost and throughput from the
mixed arithmetic, divider, and branch behavior of `p0_mix`.

## Design intent

After initializing two 256-word volatile data-RAM arrays, the measured kernel
performs 32 fixed passes. Every inner iteration loads one source word and
stores one transformed destination word, accumulating a 32-bit checksum.
The source is stable; each pass uses a deterministic salt. The measured kernel
contains no multiply or divide instruction (initialization may use MUL before
START). This is a repeatable sequential stream, not a DMA or cache test.

## Non-goals

- No FreeRTOS scheduling, UART traffic, timer interrupt, or GPIO output.
- No claim that an FPGA BRAM sequential stream predicts external DDR or ASIC
  SRAM power.
- No clock gating, physical board-rail measurement, or maximum-bandwidth DMA.

## Fixed inputs and useful work

The seed is `0x1A2B3C4D`, the LCG is `state*1664525+1013904223`, and pass
salt increments by `0x9E3779B9`. There are 32 × 256 = 8,192 source reads
and 8,192 destination writes of four bytes each: **65,536 bytes = 64 KiB**
of intended in-window data transfer. One work unit is one KiB transferred.
The independent [reference model](reference_model.py) yields checksum
`0x58873A00` and final salt `0xC6EF3720`.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Warmup / START | Both arrays and canaries initialized, then committed START store to ELF-resolved `p0_ram_stream_marker` (`0x80000008` for this image). |
| END | All 32 passes complete, then committed END marker store. |
| Final PASS | Checksum, all 256 final destination words, both canaries, then committed `tohost=1`. |

Markers use `0x504F5752` and `0x454E4421`. Initialization and the final
oracle are intentionally outside the activity window. A changed compiler or
link image requires a fresh ELF-address and hash check.

## Expected block activity

| Block | Expected behavior |
|---|---|
| Pipeline, LSU, fabric | Sustained loop and single-outstanding load/store requests. |
| Data BRAM | Repeated read/write traffic to two sequential arrays. |
| Program BRAM | Instruction-fetch activity from the compact loop. |
| Divider, timer interrupt, UART, GPIO | Architecturally idle in-window. |
| Combinational multiplier/DSP | May switch incidentally despite no in-window MUL instruction; measure rather than force zero. |

## Functional oracle and failure consequences

The independent reference model fixes the expected checksum. Firmware checks
the checksum, final destination contents, and canaries after END. Distinct
`0xBAD73001`–`0xBAD73004` `tohost` failures distinguish initialization,
checksum, data, and canary failures. Missing or duplicate markers, timeout,
or any non-PASS `tohost` invalidates the capture even if SAIF exists.

## Key performance indicators

| KPI ID | Metric | Unit | Gate | Evidence |
|---|---|---|---|---|
| P0RAM-KPI-001 | Functional oracle | pass/fail | Reference checksum and `tohost=1` | PASS, both regressions |
| P0RAM-KPI-002 | Intended transferred bytes | bytes | Exactly 65,536 | PASS by fixed disassembly/loop contract; not a pin-level counter |
| P0RAM-KPI-003 | Throughput | bytes/cycle | Report 65,536/window cycles | 0.30747144 |
| P0RAM-KPI-004 | Dynamic energy per transfer | J/KiB | Report dynamic W × window seconds / 64 | 4.52232e-6 |
| P0RAM-KPI-005 | Routed timing/DRC | ns/count | WNS >= 0, TNS 0, blocking DRC 0 | PASS, +0.003 ns / 0 / 0 blocking |
| P0RAM-KPI-006 | Activity coverage | pass/fail | >=80% direct or reviewed block alternative | PASS via 10-block review; raw 483/8,762 |
| P0RAM-KPI-007 | Dynamic-power repeatability | percent | <=2% across two captures | PASS, 0.0% (0.129 W twice) |

## Reproducibility identity

Retain source/model and image hashes, compiler/options, exact marker address,
reference checksum, array/pass counts, ModelSim/Vivado versions, 95 MHz routed
checkpoint and XDC, memory/timer parameters, capture window, coverage policy,
power category reports, and two-run comparison. Do not compare to 25 MHz or
other firmware images as the same identity.

## Risks and limitations

The intent assumes each volatile source read and destination write compiles
to one in-window `lw`/`sw`; audit disassembly and dynamic transaction evidence.
Instruction fetch and checksum ALU energy are inseparable from the measured
stream. RTL SAIF omits routed glitches and low direct-name mapping requires a
reviewed per-block alternative. The fixed 64 KiB byte count is logical
load-plus-store traffic, not a measured pin-level byte counter.

## Verification and evidence

Firmware build, independent host checksum calculation, SoC and power-TB
functional regressions pass. Disassembly confirms the in-window kernel is a
sequential `lw`/`sw` loop and its only MUL is in pre-window initialization.
Both SAIF captures, 95 MHz route, ten block gates, and <=2% repeatability
pass. Full identity, hashes, category reports, and limitations are in
[results.md](results.md).
