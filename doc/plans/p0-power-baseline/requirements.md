# P0 Reproducible Power Baseline — Requirements

**Phase:** P0 — Reproducible power baseline
**Status:** Accepted
**Owner:** HeTPort
**Last updated:** 2026-09-07
**Depends on:** Phase 7 routed FPGA flow; stable directed/firmware workloads
**Related evidence:** [`results.md`](results.md),
[`../../AR027_RTL_COMMON_AND_MULTIPLIER_PIPELINE_REVIEW.md`](../../AR027_RTL_COMMON_AND_MULTIPLIER_PIPELINE_REVIEW.md)

## Scope and user/system outcome

P0 creates a repeatable workload-to-switching-activity-to-Vivado-power flow.
It measures the present RTL without adding clock gating, power domains, new
counters, or power-management registers. The result is the comparison baseline
for later sleep, clock-enable, and multiplier architecture changes.

## Preconditions and assumptions

- ModelSim SE-64 2019.2 is currently installed and exposes VCD plus backward-
  SAIF commands. Its legal entitlement remains the user's responsibility.
- Vivado 2019.2 and the ZYNQ MINI REVB `xc7z010clg400-1` flow are the first
  measurement target; exact tool, part, speed grade, clock, voltage, process,
  temperature, and constraints must be recorded per result.
- RTL functional activity does not model routed glitches. SAIF hierarchy
  matching may be incomplete after synthesis/implementation transforms.
- Existing regression pass/fail oracles remain authoritative for function.

## Functional requirements

| ID | Requirement | Rationale | Verification method | Priority |
| --- | --- | --- | --- | --- |
| REQ-P0-001 | Define fixed reset/idle, WFI+timer, UART polling, FreeRTOS, and compute/memory activity workloads, each with an exact image and terminal oracle. | Power depends on activity, not design name. | Manifest review and one passing functional run per workload. | Must |
| REQ-P0-002 | Capture a named measurement window after reset/initialization and record start, stop, cycle count, and clock. | Reset and boot can hide steady-state behavior. | Inspect capture command/log and activity duration. | Must |
| REQ-P0-003 | Produce a VCD for debug and a backward-SAIF candidate for compact activity annotation without requiring UVM. | Existing tools already support directed capture. | ModelSim output exists, is nonempty, and its generating run passes. | Must |
| REQ-P0-004 | Import activity into the same implemented design used for the vectorless baseline and retain Vivado's match/unmatched report. Accept at least 80% overall design-net mapping, or document a reviewed block-level alternative that covers all selected state/boundary nets and dominant power blocks. | An unread or poorly mapped SAIF is false precision. | `read_saif` completes; hierarchy strip path, annotation summary, and coverage rationale retained. | Must |
| REQ-P0-005 | Report vectorless and activity-based total/static/dynamic power plus clock, logic, signal, BRAM, DSP, and I/O contributions under identical implementation/environment assumptions. | Changes need comparable decomposition. | Compact comparison table and source report hashes. | Must |
| REQ-P0-006 | Keep large VCD/SAIF/build products outside Git; retain commands, workload identity, compact reports, hashes, and tool versions. | Evidence must be reproducible without bloating the repository. | Release/evidence review. | Must |

## Non-functional requirements

| ID | Requirement | Acceptance |
| --- | --- | --- |
| PERF-P0-001 | Repeating an identical deterministic workload twice shall produce the same terminal result and an activity-based dynamic-power estimate within 2%, or the difference shall be explained and the gate marked FAIL/PARTIAL. | Two independent runs with compared hashes/statistics/reports. |
| PERF-P0-002 | Activity capture shall be scoped/windowed so one run does not consume unbounded storage. | Explicit hierarchy, start/stop event, and measured file size recorded. |
| VER-P0-001 | Simulator, SAIF-import, hierarchy mapping, and functional failures shall produce a nonzero or explicit FAIL result; a generated file alone is not PASS. | One deliberate bad-path check, such as invalid strip path or missing activity file. |

## Safety and failure consequences

| Hazard/failure | Consequence | Detection | Safe response | Residual risk |
| --- | --- | --- | --- | --- |
| Nonrepresentative stimulus | Optimizes the wrong activity pattern | Workload review and multiple scenarios | Label scenario; do not average unrelated workloads | Real flight/control workload does not yet exist |
| Reset/boot included accidentally | Biased switching estimate | Window markers and cycle log | Reject and rerun | Initialization may still affect caches later |
| Poor SAIF mapping | False confidence from vectorless fallback | Retain matched/unmatched summary | Mark PARTIAL; fix hierarchy | Optimized internal names can remain unmatched |
| Functional RTL activity treated as hardware truth | Under-counted glitches and board losses | Results disclaimer | Use only comparative FPGA estimate | No rail measurement or ASIC sign-off |

## Non-goals

- No claim of silicon, board-rail, ASIC, thermal, battery, motor, or propulsion
  power accuracy.
- No clock gating, power gating, isolation, retention, DVFS, or new MMIO.
- No UVM requirement and no purchase/download of unauthorized software.
- No conclusion that the multiplier must be pipelined until timing and workload
  evidence are compared.

`registers.rdl` and `registers.md` are intentionally omitted because P0 adds no
software-visible register.

## Acceptance and exit gate

At least two representative workloads must pass functionally, produce readable
activity, map into the same routed checkpoint with a retained annotation
summary, and repeat within `PERF-P0-001`. Results must distinguish vectorless
estimate, RTL-activity estimate, and unmeasured real hardware.

## Open questions

| Question | Owner | Decision point |
| --- | --- | --- |
| Which exact firmware interval represents steady-state FreeRTOS? | HeTPort | Before first accepted FreeRTOS SAIF |
| Does Vivado 2019.2 accept this ModelSim backward-SAIF directly with adequate mapping? | P0 implementer | First capture spike |
| Should later activity use post-synthesis timing simulation for glitch realism? | Architecture review | After RTL-SAIF mapping/results are known |
