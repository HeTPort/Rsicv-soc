# `p0_mix` Power Workload Design

## Status and identity

| Item | Value |
|---|---|
| Workload version | `1.0` |
| Lifecycle state | `verified` |
| Owner | HeTPort |
| Target clock | Exact 95 MHz routed profile; timing `PASS` |
| Firmware/images | `sw/apps/p0_mix/main.c`; installed split images under `testdata/` |
| Last evidence run | Two independent captures and reviewed power runs passed 2026-09-17 |

## Purpose

Establish the first deterministic active-power baseline for the RV32IM CPU,
instruction/data BRAM, LSU, and local SoC fabric while proving the complete
functional-run-to-SAIF-to-routed-Vivado measurement pipeline.

## Design intent

The workload will be original repository code with a fixed seed and iteration
count. Its repeated body will combine:

- integer add/subtract, Boolean, shift, and comparison operations;
- data-dependent branches with deterministic outcomes;
- RV32M multiply and bounded nonzero divide/remainder operations;
- sequential and deterministic strided word loads/stores in a static buffer;
- a rolling checksum that makes every phase architecturally observable.

The loop should be long enough to dominate one-time startup activity but short
enough for repeated ModelSim power tracking. The compiler must not be able to
constant-fold the result or remove memory traffic.

## Non-goals

- It is not an official CoreMark, Dhrystone, or standards score.
- It does not represent FreeRTOS scheduling, WFI, interrupts, UART, GPIO, DMA,
  external memory, a future accelerator, or a control plant.
- It does not establish board-rail, thermal, ASIC, or maximum-frequency power.
- It does not by itself characterize worst-case CPU or BRAM power.

## Fixed inputs and useful work

The fixed inputs are seed `0x6D5A56E9`, a 256-word statically allocated
volatile buffer, and 2,048 iterations. One useful-work unit is one complete
mixed iteration. The independently modelled golden checksum is `0x46FC5BC9`.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Reset complete | SoC reset/load handshake complete and C runtime initialized |
| Warmup complete / START | Buffer initialized and checked; store `0x504F5752` to ELF symbol `p0_mix_marker` |
| Measurement END | 2,048 iterations complete; store `0x454E4421` to the same symbol |
| Final PASS | Golden checksum/canaries pass, then committed `tohost = 1` |

No UART/GPIO diagnostic operation may occur between START and END. Failure
reporting and final `tohost` completion occur after activity collection stops.

## Expected block activity

| Block | Expected state | Reason/check |
|---|---|---|
| CPU pipeline | Active | Mixed arithmetic, branches, dependencies, and RV32M operations |
| Program BRAM | Active | Continuous instruction fetch during repeated loop |
| Data BRAM | Active | Static buffer loads/stores plus checksum state |
| LSU/fabric | Active | Word transactions throughout the repeated body |
| Divider | Active | Bounded nonzero DIV/REM operations occur at declared cadence |
| Timer/interrupt | Idle | Interrupts remain disabled for the diagnostic baseline |
| UART/GPIO | Idle | No peripheral traffic inside the measurement window |
| PS7/board wrapper | Constraint-derived | Not driven by the direct `riscv_soc` RTL activity harness |

## Functional oracle and failure consequences

The firmware will validate buffer canaries and an exact final checksum before
writing `tohost = 1`. Unique nonzero failure codes will identify initialization,
canary, checksum, and unexpected-trap failures. Timeout, missing markers,
duplicate markers, failure `tohost`, or a checksum mismatch invalidates the
measurement even if a SAIF file exists.

Failure codes are `0xBAD71001` for initialization canaries,
`0xBAD71002` for post-work canaries, and `0xBAD71003` for checksum mismatch.
An unexpected trap retains the common startup/trap failure behavior.

## Key performance indicators

| KPI ID | Metric | Unit | Acceptance/comparison rule | Evidence |
|---|---|---|---|---|
| P0MIX-KPI-001 | Functional oracle | pass/fail | Exact checksum/canaries and `tohost = 1` | `PASS`: RTL regression reached `tohost = 1` at cycle 345,948 |
| P0MIX-KPI-002 | Completed iterations | iterations | Exact declared fixed count | `PASS`: 2,048; success is reachable only after the fixed loop and checks |
| P0MIX-KPI-003 | Cycles per iteration | cycles/iteration | Report from marker interval | `PASS`: 165.0601 (338,043 / 2,048) |
| P0MIX-KPI-004 | Retired instructions per iteration | instructions/iteration | Report from marker interval | `PASS`: 57.5039 (117,768 / 2,048) |
| P0MIX-KPI-005 | Routed timing | ns | 95 MHz WNS >= 0 and TNS = 0 | `PASS`: WNS +0.006, TNS 0.000 |
| P0MIX-KPI-006 | Blocking routed DRC | count | Zero errors/critical warnings | `PASS`: 0; 38 advisory warnings retained |
| P0MIX-KPI-007 | SAIF design-net mapping | percent | >= 80% or reviewed dominant-block alternative | `PASS via alternative`: 5.500% automatic plus all 10 required block gates and 540 explicit DSP-bridge nets |
| P0MIX-KPI-008 | Dynamic power repeatability | percent difference | <= 2% across two independent runs | `PASS`: 0.0% (0.127 W / 0.127 W) |
| P0MIX-KPI-009 | Dynamic energy per iteration | J/iteration | Same workload, route, clock, and environment identity | `2.2066e-7 J/iteration` reviewed estimate |

## Reproducibility identity

The resolved run must retain Git tree state, compiler/version/flags, source and
image hashes, buffer/iteration/seed values, golden checksum, marker mechanism,
simulation parameters, ModelSim version, SAIF hierarchy/strip path/duration,
Vivado version, part/speed-grade assumption, exact 95 MHz clock, routed DCP
hash, timing/DRC/utilization, power environment, and exact commands.

## Risks and limitations

- RTL SAIF omits routed glitch activity.
- A mixed loop can hide which sub-operation caused a power change; later RAM and
  WFI workloads provide diagnostic separation.
- Direct `riscv_soc` simulation will not annotate all wrapper/MMCM/PS7 nets;
  constraints and a reviewed mapping breakdown must cover that limitation.
- A compiler or arithmetic-backend change can alter both instruction mix and
  placement; comparisons require a resolved identity and fixed work.

## Verification and evidence

The no-capture functional prerequisite passed with:

```powershell
cd sim/regress
.\run_regression.ps1 -Manifest .\power_tests.json -Test p0_mix
```

The simulator reported `tohost = 1` at cycle 345,948, zero timer interrupts,
zero UART bytes, zero GPIO transitions, and no errors. Two marker-window runs
then produced identical activity payloads and passed the reviewed block-level
mapping alternative on the same timing-clean 95 MHz checkpoint. See
`results.md` for commands, hashes, power values, limitations, and the exact
coverage breakdown.
