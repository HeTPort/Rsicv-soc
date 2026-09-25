# Phase Planning and Evidence Index

New substantial phases use the evidence-package convention defined in
[`../PHASE_EVIDENCE_TEMPLATE.md`](../PHASE_EVIDENCE_TEMPLATE.md).

Create `doc/plans/<phase-id>/` only when that phase becomes active. Do not add
empty future directories. The repository-wide sequence, prerequisites,
learning topics, and exit gates are in
[`../ROADMAP_AND_LEARNING_PATH.md`](../ROADMAP_AND_LEARNING_PATH.md).

Historical `doc/ar/AR*.md` reports and `docs/phase*-guide.md` files remain where
they are. New packages should link to them when they provide relevant evidence.

The `p1-registered-multiplier`, `p2-core-control-ownership`, and
`p3-semantic-cleanup` names predate the current program-stage namespace. Their
directory prefixes are historical sequence labels, **not** the roadmap P1/M1
stages. Do not infer a program phase from those directory names.

## Verified historical engineering packages

| Package | Status |
| --- | --- |
| [`rv32-contract-cleanup/`](rv32-contract-cleanup/) | **Verified:** fixed RV32 contract and removal of unsupported width knobs |
| [`p1-registered-multiplier/`](p1-registered-multiplier/) | **Verified:** registered blocking multiplier accepted for 95 MHz; 100 MHz system guarantee remains gated |
| [`p2-core-control-ownership/`](p2-core-control-ownership/) | **Verified:** typed redirect arbitration, retirement-owned MRET, and centralized PC/pipeline movement and kill policy |
| [`p3-semantic-cleanup/`](p3-semantic-cleanup/) | **Verified:** behavior-preserving decode/execute naming and canonical packet construction cleanup |

## Current program phases

| ID | Package | Status / creation trigger |
| --- | --- | --- |
| R0 | No dedicated package | Ongoing documentation, provenance, and release-readiness discipline |
| U0 | [`u0-passive-uvm/`](u0-passive-uvm/) | **Partial:** toolchain-confirmation sub-gate verified; DUT-facing passive retirement monitor/scoreboard remains open |
| U1 | `u1-iss-differential/` | Create after the full U0 exit gate passes |
| U2 | `u2-generated-isa/` | Create after U1 has stable architectural comparison |
| U3 | `u3-active-agents-ral/` | Create when memory/register contracts are frozen |
| P0 | [`p0-power-baseline/`](p0-power-baseline/) | **Verified:** six-scenario 95 MHz technical portfolio; no physical board-rail/ASIC power sign-off |
| W0 | `w0-workload-discovery/` | Create when the first bounded workload implementation starts |
| P1 | `p1-sleep-counters/` | Eligible after verified P0; create when counters/safe-sleep implementation starts |
| C0 | `c0-safe-control-slice/` | Create after PWM/fault/capture/watchdog requirements are accepted |
| C1 | `c1-sampled-data-path/` | Create after representative ADC and interrupt semantics are chosen |
| M0 | `m0-model-and-sil/` | Create after model parameters/units and simulation contract are frozen |
| M1 | `m1-hil-bench/` | Create after stable M0 plus C0/C1 interfaces and low-energy safety boundary |
| A0 | `a0-mmio-accelerator/` | Create only when profiling proves a stable hot kernel |
| A1 | `a1-vector-npu-study/` | Create only if A0 cannot meet two measured workload needs |
| G0 | `g0-gpu-research/` | Create only for a real graphics/GPGPU requirement and memory budget |
