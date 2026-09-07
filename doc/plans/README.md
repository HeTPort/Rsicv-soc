# Phase Planning and Evidence Index

New substantial phases use the evidence-package convention defined in
[`../PHASE_EVIDENCE_TEMPLATE.md`](../PHASE_EVIDENCE_TEMPLATE.md).

Create `doc/plans/<phase-id>/` only when that phase becomes active. Do not add
empty future directories. The repository-wide sequence, prerequisites,
learning topics, and exit gates are in
[`../ROADMAP_AND_LEARNING_PATH.md`](../ROADMAP_AND_LEARNING_PATH.md).

Historical `doc/AR*.md` reports and `docs/phase*-guide.md` files remain where
they are. New packages should link to them when they provide relevant evidence.

## Phase packages

| ID | Package | Status / creation trigger |
| --- | --- | --- |
| P0 | [`p0-power-baseline/`](p0-power-baseline/) | **Active:** requirements/capture plan accepted; results `NOT RUN` |
| U0 | `u0-passive-uvm/` | Create when UVM tool-version smoke becomes active |
| U1 | `u1-iss-differential/` | Create after U0 exit gate passes |
| U2 | `u2-generated-isa/` | Create after U1 has stable architectural comparison |
| U3 | `u3-active-agents-ral/` | Create when memory/register contracts are frozen |
| P1 | `p1-sleep-counters/` | Create after P0 produces a reproducible baseline |
| C0 | `c0-safe-control-slice/` | Create after PWM/fault/capture/watchdog requirements are accepted |
| C1 | `c1-sampled-data-path/` | Create after representative ADC and interrupt semantics are chosen |
| M0 | `m0-model-and-sil/` | Create after model parameters/units and simulation contract are frozen |
| A0 | `a0-mmio-accelerator/` | Create only when profiling proves a stable hot kernel |
| A1 | `a1-vector-npu-study/` | Create only if A0 cannot meet two measured workload needs |
| G0 | `g0-gpu-research/` | Create only for a real graphics/GPGPU requirement and memory budget |
