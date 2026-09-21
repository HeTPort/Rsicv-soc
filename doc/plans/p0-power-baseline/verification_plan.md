# P0 Reproducible Power Baseline — Verification Plan

**Phase:** P0 — Reproducible power baseline
**Status:** Accepted
**Owner:** HeTPort
**Last updated:** 2026-09-20
**Depends on:** [`requirements.md`](requirements.md), [`architecture.md`](architecture.md)
**Related evidence:** [`results.md`](results.md)

## Verification scope and strategy

P0 validates measurement infrastructure, not a new RTL feature. Every captured
workload must first pass its existing functional oracle. The activity file is
then checked for identity/size/duration, imported into the matching implemented
design, and compared with its vectorless report. UVM is out of scope.

## Requirement traceability

| Requirement ID | Test/assertion/coverage | Level | Expected result | Status |
| --- | --- | --- | --- | --- |
| REQ-P0-001 | Workload-manifest audit and selected regression runs | RTL/firmware | Every selected workload has exact image and PASS oracle | PASS: all six classes, including FreeRTOS, spin idle, and UART polling |
| REQ-P0-002 | Capture-window log review | Testbench | Reset excluded; start/stop/duration recorded | PASS for six measured workloads |
| REQ-P0-003 | Windowed VCD and backward-SAIF | Simulator | Nonempty activity; functional PASS | PASS: backward-SAIF all six; WFI optional debug VCD |
| REQ-P0-004 | Same-DCP SAIF mapping and reviewed block policy | Implemented design | Parse succeeds and accepted coverage rationale retained | PASS via reviewed alternative; direct 5.5% is not a direct-mapping pass |
| REQ-P0-005 | Same-checkpoint vectorless/activity comparison | Vivado | Both reports exist with category breakdown | PASS for six workloads |
| REQ-P0-006 | Artifact/hash/command audit | Repository | Large activity ignored; compact evidence retained | PASS for six workloads |
| PERF-P0-001 | Duplicate deterministic capture/import | End to end | Dynamic estimate differs by at most 2% | PASS: 0.0% for all six workloads at report resolution |
| PERF-P0-002 | File size and hierarchy/window check | Infrastructure | Bounded artifact with recorded size | PASS for all six workloads |
| VER-P0-001 | Deliberate missing file or invalid strip path | Infrastructure | Native error or explicit FAIL; never PASS | PASS: missing-file test rejects |

## Test categories

### Positive/nominal

1. Run one short directed compute/memory workload using `-DumpWaves`.
2. Capture WFI+timer activity after boot.
3. Capture UART polling and FreeRTOS steady-state windows.
4. Import each accepted SAIF into the matching routed checkpoint and report
   vectorless/activity-based power.

### Boundary and corner cases

- minimum nonzero capture window;
- activity window ending exactly at the functional terminal marker;
- no-UART and idle-heavy scenarios;
- hierarchy paths containing generated or optimized names;
- BRAM/DSP-heavy scenario versus mostly clock/control activity.

### Negative and protocol-error cases

- missing or empty activity file;
- mismatched top/strip path producing unacceptable mapping;
- activity from a different RTL/checkpoint identity;
- workload timeout or FAIL with a partial activity file;
- routed timing/DRC failure even when `report_power` emits output.

### Fault injection and recovery

P0 does not inject RTL power faults. The required infrastructure-negative test
changes only an activity-file path or hierarchy mapping and verifies that the
wrapper reports failure. Recovery is a clean rerun with the correct identity.

### Reset/clock/CDC and race cases

Confirm capture is off through reset and warmup. Confirm the logged clock period
matches the XDC clock. P0 creates no CDC/RDC path.

### Performance, timing, area, and power measurements

Record implementation WNS/TNS, LUT/FF/BRAM/DSP, DRC, clock, environment
assumptions, activity match percentage, static/dynamic/total power, component
breakdown, activity duration, file size, and runtime.

## Assertions and invariants

- A functional FAIL cannot yield an accepted power result.
- The activity and Vivado checkpoint identities must match.
- Capture duration must be positive and exclude reset.
- Activity-based results must retain the annotation summary.
- Same-scenario comparisons use the same clock/environment assumptions.

## Coverage model

Scenario coverage is six workload classes: mixed compute, WFI/timer, RAM
stream, FreeRTOS, clocked spin idle, and UART polling. Infrastructure coverage is
VCD generation, backward-SAIF generation, positive mapping, negative mapping,
vectorless baseline, activity report, and duplicate-run comparison. Code and
UVM functional coverage are unchanged and not P0 exit criteria.

## Regression and reproducibility

Record exact commands, simulator/Vivado versions, manifest/test name, firmware
and checkpoint hashes, start/stop cycles, hierarchy/strip paths, file sizes,
and report hashes. Never rely on a GUI-only sequence.

## Pass/fail oracle

PASS requires the pre-existing functional oracle plus successful nonempty
capture, acceptable documented mapping, timing/DRC-valid implementation, and
complete report fields. Any tool crash, timeout, missing file, parse failure,
or silent vectorless fallback is FAIL/PARTIAL rather than PASS.

## Exit criteria and waivers

The measurement-infrastructure two-workload gate and all six scenario-class
gates pass. RTL activity is accepted only with the
documented direct-mapping/glitch limitations; board/ASIC accuracy is not
claimed. See [actual results](results.md) and the per-workload evidence.
