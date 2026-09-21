# <workload-name> Power Workload Design

## Status and identity

| Item | Value |
|---|---|
| Workload version | `<version>` |
| Lifecycle state | `design` |
| Owner | `<owner>` |
| Target clock | `<clock or NOT SET>` |
| Firmware/images | `NOT BUILT` |
| Last evidence run | `NOT RUN` |

## Purpose

State the single measurement question this workload answers.

## Design intent

Describe why the algorithm and traffic pattern represent that question. Name
the architectural behaviors that should dominate activity.

## Non-goals

List conclusions that this workload cannot support.

## Fixed inputs and useful work

Define seeds, buffers, iteration counts, external stimulus, and the fixed unit
of completed work used for performance and energy normalization.

## Window contract

| Boundary | Architectural condition |
|---|---|
| Reset complete | `<condition>` |
| Warmup complete / START | `<marker and meaning>` |
| Measurement END | `<marker and fixed work>` |
| Final PASS | `<oracle after capture>` |

Explain why reset, initialization, diagnostics, and final reporting are outside
the measurement interval.

## Expected block activity

| Block | Expected state | Reason/check |
|---|---|---|
| CPU pipeline | `<active/idle/N/A>` | `<reason>` |
| Program BRAM | `<active/idle/N/A>` | `<reason>` |
| Data BRAM | `<active/idle/N/A>` | `<reason>` |
| LSU/fabric | `<active/idle/N/A>` | `<reason>` |
| Timer/interrupt | `<active/idle/N/A>` | `<reason>` |
| UART/GPIO | `<active/idle/N/A>` | `<reason>` |
| Other/future block | `<active/idle/N/A>` | `<reason>` |

## Functional oracle and failure consequences

Define exact checksum/signature/counters, `tohost` PASS, failure-code ownership,
timeouts, and what invalidates the measurement.

## Key performance indicators

| KPI ID | Metric | Unit | Acceptance/comparison rule | Evidence |
|---|---|---|---|---|
| `<ID>` | Functional result | pass/fail | Exact oracle passes | `NOT RUN` |
| `<ID>` | Completed work | `<unit>` | Exact declared amount | `NOT RUN` |
| `<ID>` | Cycles per work | cycles/unit | Report; lower is better only for same identity | `NOT RUN` |
| `<ID>` | Energy per work | J/unit | Same routed/environment identity | `NOT RUN` |
| `<ID>` | SAIF mapping | percent | At least 80% or reviewed alternative | `NOT RUN` |
| `<ID>` | Dynamic repeatability | percent | At most 2% difference | `NOT RUN` |

## Reproducibility identity

List compiler/flags, parameters, memory placement, clock, routed part, external
conditions, hierarchy/strip path, seeds, artifact hashes, and exact commands
that a resolved run must retain.

## Risks and limitations

Describe RTL-SAIF glitch limitations, unexercised blocks, simulator acceleration,
representativeness limits, and conclusions that require board measurements.

## Verification and evidence

Record only actual commands/results. Use `NOT RUN` until executed.
