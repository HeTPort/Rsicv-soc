# `p0_idle_spin` Power Workload Design

## Status and identity

Version `1.0`; lifecycle `verified`: functional tests, exact 95 MHz route,
reviewed block mapping, and two-run repeatability pass. Original bare-metal
image on the split-RAM SoC profile. See [measured results](results.md).

## Purpose

Establish a deterministic, clocked CPU-busy-idle reference for comparison with
the active compute/RAM workloads and the distinct WFI/timer sleep scenario.

## Design intent

After reset and startup, one uninterruptible register-only loop repeats a
`nop`, `addi`, and `bnez` sequence exactly 65,536 times. There is continuous
instruction fetch and branch/redirection activity, but no intended in-window
data access, UART, GPIO, timer interrupt, or useful application work. This is
**spin idle**, not clock-gated sleep or a board's minimum power.

## Non-goals

- No WFI, OS idle task, DDR access, or external stimulus.
- No claim of isolated CPU power: FPGA MMCM, BRAM, and unclock-gated logic remain
  part of the whole-PL estimate.
- No inference about ASIC leakage or real board supply-rail power.

## Fixed inputs and useful work

The loop count is exactly 65,536. One reference unit is one completed spin
iteration, not one useful application operation. The disassembly must show the
three declared instructions in the loop; changed compiler/linker output is a
new identity. Normalization reports dynamic energy per spin iteration and per
core cycle, and the latter is the preferred cross-workload idle comparison.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Warmup / START | Runtime initialization ends; committed `0x504F5752` store to ELF-resolved `p0_idle_spin_marker` (`0x80000004` for this image). |
| END | The fixed assembly loop exhausts its counter, then commits `0x454E4421` to the same marker. |
| Final PASS | Firmware stores the zero result, checks the counter, then commits `tohost=1`; the testbench rejects missing/duplicate markers or timeout. |

## Expected block activity

| Block | Expected behavior |
|---|---|
| CPU pipeline and program BRAM | Clocked fetch/branch loop; active but lower variety than `p0_mix`. |
| LSU/fabric and data BRAM | No intentional data transfer between markers; boundary state can still switch. |
| Timer, UART, GPIO, divider | No architectural use in-window. |
| Combinational DSP | May switch incidentally despite no MUL; inspect bridge activity. |

## Functional oracle and failure consequences

The fixed loop must reach END, leave its counter zero, and report committed
`tohost=1`. Failure code `0xBAD74001` denotes a nonzero final counter. The
power TB independently verifies the marker order and result store. Missing
markers, trap, timeout, or a different `tohost` value invalidate the sample.

## Key performance indicators

| KPI ID | Metric | Unit | Gate | Evidence |
|---|---|---|---|---|
| P0IDLE-KPI-001 | Functional oracle | pass/fail | Both SoC and power TB PASS | PASS |
| P0IDLE-KPI-002 | Spin iterations | iterations | Exactly 65,536 | PASS, disassembly-fixed loop |
| P0IDLE-KPI-003 | Window cycles | cycles | Report exact | 458,759; 196,611 retirements |
| P0IDLE-KPI-004 | Dynamic energy per cycle | J/cycle | Report for same 95 MHz route | 1.66316e-9 |
| P0IDLE-KPI-005 | Routed timing/DRC | ns/count | WNS >= 0, TNS 0, blocking DRC 0 | PASS, +0.003 ns / 0 / 0 blocking |
| P0IDLE-KPI-006 | Activity mapping | pass/fail | >=80% direct or reviewed block alternative | PASS via 10/10 reviewed rules; direct 483/8,762 |
| P0IDLE-KPI-007 | Dynamic repeatability | percent | <=2% across independent captures | PASS, 0.0% |

## Reproducibility identity

Retain compiler/options, exact assembly loop, source and image hashes, marker
symbol address, 65,536 count, ModelSim/Vivado versions, 95 MHz routed part and
checkpoint hash, `TIMER_TICK_CYCLES=1`, SAIF hierarchy/strip path and hashes,
coverage policy, two-run power comparison, and limitations.

## Risks and limitations

The reference is a clocked busy loop: it intentionally burns fetch and branch
energy and cannot stand in for WFI, FreeRTOS idle, or a gated clock. RTL SAIF
does not capture routed glitches; low direct-name mapping requires a reviewed
block-level alternative with honest active/idle classifications.

## Verification and evidence

Firmware build and both functional regressions pass. The power TB observed
458,759 cycles, 196,611 retirements, and committed result zero. The matching
95 MHz route passes at WNS +0.003 ns, TNS 0, and zero blocking DRC. Both
SAIF imports pass all 10 reviewed block rules and agree at 0.158 W dynamic,
0.0% difference. The high value reflects continuous fetch and incidental
combinational DSP switching; this is not WFI/deep sleep. Full evidence and
limits are in [measured results](results.md).
