# Power Workload and Measurement Framework

This directory is the source-controlled operational entry point for repeatable
SoC power workloads. Its purpose is to keep every workload consistent in four
ways:

1. the workload states a specific question and design intent;
2. the functional result is proved before activity is measured;
3. the capture window represents a named, fixed amount of useful work; and
4. the SAIF is applied only to the matching routed Vivado design identity.

The authoritative P0 requirements and evidence status remain in
[`doc/plans/p0-power-baseline/`](../doc/plans/p0-power-baseline/). This directory
turns that contract into reusable workload packages and tooling. A file existing
under `power/` is not proof that its workload has run; status and actual evidence
must say so explicitly.

## Directory hierarchy

```text
power/
├── README.md                         governing purpose and common flow
├── WORKLOAD_MANIFEST.md              machine-readable manifest contract
├── common/
│   ├── README.md                     shared hierarchy/marker/oracle contracts
│   └── capture_window.do             ModelSim marker-window SAIF/VCD control
├── templates/
│   └── WORKLOAD_DESIGN_TEMPLATE.md   mandatory per-workload design record
├── scripts/
│   ├── README.md                     stage-by-stage commands and gates
│   ├── run_modelsim_saif.ps1          capture and run identity
│   ├── analyze_vivado_power.tcl       same-DCP vectorless/activity reports
│   ├── make_saif_*_bridge.py          reviewed optimized-net activity
│   ├── check_block_coverage.py       per-block mapping alternative
│   ├── summarize_power_run.py         one-run verdict and KPIs
│   ├── compare_power_runs.py          two-run reproducibility gate
│   └── validate_workloads.py          manifest/document gate
├── workloads/
│   ├── p0_mix/                       CPU/RAM/MUL/DIV baseline
│   ├── p0_wfi_timer/                 timer wake/idle baseline
│   ├── p0_ram_stream/               sequential LSU/fabric/BRAM baseline
│   ├── p0_freertos/                 scheduler/task/tick/system workload
│   ├── p0_idle_spin/                clocked busy-idle reference
│   └── p0_uart_poll/                polled serial TX reference
│       (each package starts with design.md and workload.json;
│        verified packages add mapping_coverage.json and results.md)
├── evidence/
│   └── README.md                     compact retained-result policy
└── planning/                          ignored agent working state

build/power/                           ignored generated run artifacts
└── <workload>/<run-id>/
    ├── modelsim/                     isolated compiled work library
    ├── workload.saif
    ├── workload.vcd                optional debugging only
    ├── simulation.log
    ├── run.json
    ├── dsp_bridge.{tcl,json}       when required
    ├── timer_bridge.{tcl,json}     when required
    ├── vivado_reviewed/            vectorless/activity/switching reports
    ├── block_coverage.json
    └── power_summary.json
```

Only directories needed by the active slice are created. Add later workload
packages when their requirements become active; do not create empty speculative
trees.

Capture runs use separate ignored `modelsim/` libraries inside each run
directory, so independent workloads can be simulated without sharing a work
library or recompilation state.

## Required workload lifecycle

Every workload moves through these states:

| State | Meaning |
|---|---|
| `design` | Intent and gates exist; implementation or evidence is incomplete. |
| `implemented` | Firmware/harness exists and passes its functional oracle. |
| `verified` | Matching SAIF mapping, routed timing/DRC, and repeat runs pass. |
| `accepted` | Results are reviewed and recorded in the P0 evidence package. |
| `superseded` | A newer version replaces it; old evidence remains traceable. |

Changing a workload's algorithm, compiler flags, memory placement, clock,
parameters, marker semantics, or expected work creates a new measurement
identity. Do not silently compare results across different identities.

## Common measurement pipeline

```text
design contract
    -> firmware/image build
    -> functional simulation and oracle
    -> matching routed implementation
    -> deterministic post-warmup activity capture
    -> SAIF hierarchy/mapping validation
    -> vectorless and activity-based power reports
    -> independent repeat and KPI comparison
    -> compact reviewed evidence
```

Each stage must be independently rerunnable. Firmware correctness must not
depend on SAIF capture, and report formatting must not require rerunning the
simulator or router.

## Mandatory per-workload records

Each `power/workloads/<name>/` package must contain:

- `design.md`, based on the template, with design intent and KPIs;
- `workload.json`, following [`WORKLOAD_MANIFEST.md`](WORKLOAD_MANIFEST.md);
- links to firmware, testbench, build, and regression files once implemented;
- a deterministic oracle and failure codes;
- explicit `NOT RUN` entries for evidence that does not yet exist.

The design record must answer:

- What question does this workload answer?
- What does it intentionally exercise and exclude?
- What event ends warmup and starts measurement?
- What fixed unit of useful work ends measurement?
- Which blocks should be active, idle, or not applicable?
- Which KPIs determine success and comparison fairness?
- What exact functional result proves the run was valid?

## Hierarchy contract

The intended stable activity boundary is:

```text
ModelSim: tb_power/u_soc/...
Vivado:   top/u_soc/...
```

The implemented import removes only `tb_power`, leaving `u_soc/...` to match the
routed board design. Capturing only `u_riscv` is insufficient for a SoC
baseline. Capturing testbench scoreboards or stimulus processes is also invalid.

Recursive hierarchy capture provides name coverage; it does not prove that a
block performed meaningful work. Every workload must separately state expected
block activity and review transition evidence for the dominant blocks.

## Window contract

Each accepted window has four phases:

```text
reset -> initialization/warmup -> measurement -> final oracle
```

START and END are committed stores of fixed words to a volatile data-RAM marker
symbol resolved from the workload ELF. `tb_power` observes the architectural
commit interface and starts/stops the `u_soc` SAIF window; `tohost` remains the
independent final oracle. No marker MMIO is added to the routed hardware.
Optional VCD uses the same window and is for hierarchy/debug inspection.

For cross-design comparisons, prefer a fixed amount of useful work and report
both average power and energy per work unit. Fixed-time windows are allowed only
when the workload question explicitly concerns sustained average power.

## Current portfolio

| Workload | Purpose | State |
|---|---|---|
| [`p0_mix`](workloads/p0_mix/design.md) | Deterministic CPU/RAM/MUL/DIV active baseline | `verified` ([evidence](workloads/p0_mix/results.md)) |
| [`p0_wfi_timer`](workloads/p0_wfi_timer/design.md) | WFI interval and timer wake energy | `verified` ([evidence](workloads/p0_wfi_timer/results.md)) |
| [`p0_ram_stream`](workloads/p0_ram_stream/design.md) | LSU/fabric/BRAM throughput and energy per KiB | `verified` ([evidence](workloads/p0_ram_stream/results.md)) |
| [`p0_freertos`](workloads/p0_freertos/design.md) | Timer, scheduling, queues, tasks, UART, and GPIO | `verified` ([evidence](workloads/p0_freertos/results.md)) |
| [`p0_idle_spin`](workloads/p0_idle_spin/design.md) | Clocked CPU spin-idle reference, distinct from WFI | `verified` ([evidence](workloads/p0_idle_spin/results.md)) |
| [`p0_uart_poll`](workloads/p0_uart_poll/design.md) | Fixed 14-byte polled serial TX | `verified` ([evidence](workloads/p0_uart_poll/results.md)) |
| CoreMark-derived | External CPU-oriented reference after infrastructure is trusted | Deferred; third-party review required |

## Acceptance gates

No workload is accepted unless all applicable gates pass:

- exact firmware/configuration and functional oracle pass;
- reset and warmup are excluded from the capture window;
- routed target clock exists and timing/DRC gates pass;
- at least 80% design-net mapping, or a reviewed block-level alternative;
- dominant expected blocks have meaningful activity;
- vectorless and activity-based reports use the same routed checkpoint;
- two independent runs differ by no more than 2% in dynamic power, or the gate
  is marked `PARTIAL`/`FAIL` with an explanation;
- one missing-file or bad-strip-path run fails explicitly;
- tool versions, commands, hashes, assumptions, and limitations are retained.

All six verified workloads use workload-matched, timing-clean 95 MHz routed
checkpoints. Direct SAIF mapping is only about 5.5%, so none claims the
80% direct threshold. They pass the documented reviewed block-level alternative
with explicit activity bridges for synthesized DSP and, for WFI/FreeRTOS,
timer-Q nets. These are Vivado PL estimates, not board-rail or ASIC
measurements. Production 25 MHz builds are a separate identity. In particular,
the clocked spin-idle reference is **not** WFI/deep sleep: its changing loop
registers and repeated fetches produce substantial BRAM and incidental DSP
activity.

## Validation

Validate the source-controlled workload contracts with:

```powershell
python .\power\scripts\validate_workloads.py
```

This validation checks documentation and manifest structure only. It does not
claim functional, timing, mapping, repeatability, or power success.
