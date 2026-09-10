# Divider Digital-Design Learning Lab Results

**Phase:** divider-design-lab

**Status:** Verified

**Owner:** project learner

**Last updated:** 2026-09-10

**Depends on:** current divider RTL at commit `9403326414482406d1cd17768c61cf636fdf757c`

**Related evidence:** [waveform](evidence/divider_wave.png), [tutorial](../../DIVIDER_DIGITAL_DESIGN_LAB.md)

## Tested identity

- Production RTL SHA256:
  `033d5a55d55cdb25a1546a61a8e46b7dfb09cc0667d3e60d693f81b988997707`;
  unchanged after experiment.
- ModelSim SE-64 2019.2, Vivado 2019.2, Verilator 5.032.
- FPGA part `xc7z010clg400-1`; divider-only OOC; default `DW=32`.

## Simulation and negative evidence

- Existing focused suite: 42/42 completed cases PASS, seed 20260909.
- Teaching suite: five completed operations PASS; kill-over-start and 34-cycle
  no-orphan-completion guard PASS; 213 JSONL samples validated.
- Wrong expected quotient 13 for `100/7`: expected exact assertion fired with
  actual quotient 14 and remainder 2; the negative run was accepted as RED.
- Generated explicit-width lint candidate: existing 42-case suite PASS.

## Synthesis, route and timing

| Metric | Observed |
| --- | ---: |
| Routed Slice LUT / FF / latch | 355 / 171 / 0 |
| CARRY4 / DSP / BRAM | 45 / 0 / 0 |
| 40 ns worst internal setup path | `quotient_work_q_reg[31]` to `quotient_o_reg[29]` |
| Data delay | 9.352 ns: logic 4.079 ns, route 5.273 ns |
| Logic levels | 16: CARRY4 13, LUT1 1, LUT4 1, LUT5 1 |
| Internal setup / hold slack | +30.402 ns / +0.107 ns |
| Same-route 5 ns setup slack | -4.598 ns; data delay unchanged |
| Blocking DRC error/critical warning | 0 |

The isolated Zynq block has expected DRC warning ZPS7-1 because no PS7 is
instantiated. All 329 routable nets were routed. `check_timing` reports zero
unclocked registers, unconstrained internal endpoints and combinational loops.
OOC data ports lack physical
partition pin locations, so boundary routing is partial; the global hold report
has WHS -0.579 ns on 103 interface endpoints under illustrative IO assumptions.
This is not board timing closure. Reset paths are false-pathed and reset release
safety is not proven.

## Lint

- Original: WIDTHEXPAND at line 115 and UNUSEDSIGNAL for
  `remainder_work_q[32]`; Verilator exit 1 as configured.
- Generated explicit-width copy: WIDTHEXPAND removed; unused warning remains.
- Copy plus narrow reviewed waiver: zero warnings, exit 0.
- Deliberate bad/good combinational fixtures: LATCH RED then zero-warning GREEN.
- Generated copy elaboration/lint at DW 2, 8 and 64: zero warnings; this is not
  functional proof of those parameter values.

## Experiment errors and resolution

The first simulation logger used a packed string concatenation as an `$fdisplay`
format and the runner treated normal `$finish` as an error; exact trace parsing
exposed both assumptions and they were corrected. The first Vivado run completed
route and wrote the DCP but post-processing requested unsupported 2019.2 property
`TIMING_POINTS`; it correctly returned failure. Replacing it with
`get_pins -of_objects $path` produced the verified full run.

## Verdict

PASS for the stated learning-lab requirements. No production RTL or project
phase behavior changed. Not evidence for whole-SoC/board timing, power, reset
signoff, CDC/RDC, formal equivalence or ASIC signoff.
