# P0 Reproducible Power Baseline — Measurement Architecture

**Phase:** P0 — Reproducible power baseline
**Status:** Accepted
**Owner:** HeTPort
**Last updated:** 2026-09-07
**Depends on:** `REQ-P0-*`; existing ModelSim regression and Vivado routed flow
**Related evidence:** [`requirements.md`](requirements.md), [`verification_plan.md`](verification_plan.md)

## Context and boundary

P0 wraps the existing testbenches and FPGA implementation. It does not alter
the DUT data/control path. Existing directed test manifests supply program,
timeouts, generics, and PASS/FAIL; a capture layer controls only the observation
hierarchy and measurement window.

## Block/data-flow diagram

```text
fixed workload + manifest + RTL
              |
              v
   ModelSim functional PASS  -----> VCD (debug, potentially large)
              |
              +-------------------> backward SAIF (aggregate activity)
                                         |
implemented Vivado checkpoint + XDC -----+
                                         v
                              read_saif + match report
                                         |
                                         v
                         report_power + compact comparison
                         vectorless vs activity-based
```

## Interfaces and protocols

- **Workload identity:** manifest name, firmware/hex hash, RAM configuration,
  timeout, testbench top, and terminal `tohost`/firmware oracle.
- **Capture identity:** DUT hierarchy, start event/cycle, stop event/cycle,
  simulated duration, clock period, VCD/SAIF hash, and file size.
- **Vivado identity:** implemented checkpoint/bitstream hash, part, speed grade,
  XDC clock, tool version, environment assumptions, `read_saif -strip_path`,
  and match/unmatched report.
- **Result identity:** vectorless and activity-based reports from the same
  implementation plus a compact scenario comparison.

The first spike reuses `sim/regress/run_regression.ps1 -Test <one-test>
-DumpWaves`. A follow-on Tcl capture uses ModelSim `power add`, `power on/off`,
and `power report -bsaif` only after the exact DUT hierarchy and window are
fixed. Generated activity belongs under `build/` or another ignored output
directory, not `doc/`.

## Clock, reset, CDC/RDC, and safe-state strategy

P0 introduces no clock/reset logic. Each activity window begins only after
reset deassertion and required boot initialization. Clock toggles come from the
XDC timing definition in Vivado; UG907 notes that SAIF import does not override
design clock activity. Existing asynchronous UART input synchronization and
timer behavior remain unchanged.

## State machines and timing

The capture controller has four observational states:

```text
SETUP -> FUNCTIONAL_WARMUP -> CAPTURE -> FLUSH_AND_REPORT
             |                  |
             +---- failure -----+----> FAIL
```

Capture start/stop must be deterministic: preferably a testbench event or a
known architectural marker, otherwise an exact post-reset cycle range. A
timeout or missing terminal oracle is failure even if an activity file exists.

## Data representation

- Time is recorded in simulator units and equivalent clock cycles.
- Power is reported in watts/milliwatts exactly as emitted by Vivado.
- Activity files are identified by SHA-256; large files are not committed.
- Percentage deltas always name baseline, workload, and denominator.

## Error and fault containment

- Missing/empty activity, SAIF parse failure, zero/poor mapping, negative timing,
  or functional FAIL prevents an accepted power result.
- Vectorless fallback is reported separately, never silently called activity-
  based evidence.
- Filesystem-size limits are enforced by narrow hierarchy/window selection,
  not by truncating a file and treating it as valid.

## Alternatives and decision links

- **UVM:** unnecessary for activity generation; directed workload correctness
  remains enough for P0.
- **cocotb:** useful later for workload orchestration, but adds Python/tool
  integration without solving SAIF mapping.
- **Verilator:** useful for fast legal open-source simulation, but the current
  project is already proven in ModelSim and tool migration is separate work.
- **Board rail measurement:** more physically meaningful later, but cannot
  isolate internal block activity and needs instrumentation/hardware.

See
[`../../AR027_RTL_COMMON_AND_MULTIPLIER_PIPELINE_REVIEW.md`](../../AR027_RTL_COMMON_AND_MULTIPLIER_PIPELINE_REVIEW.md)
for why P0 precedes multiplier and low-power RTL changes.

## Implementation partition

| Layer | Ownership |
| --- | --- |
| Existing manifests/testbenches | Functional workload and PASS/FAIL |
| New small ModelSim capture Tcl/wrapper | Window, hierarchy, VCD/backward-SAIF, hashes |
| Vivado power Tcl | Open implemented checkpoint, `read_saif`, retain match report, `report_power` |
| `doc/plans/p0-power-baseline/results.md` | Compact evidence and limitations |

No source/common RTL or MMIO register is part of P0.
