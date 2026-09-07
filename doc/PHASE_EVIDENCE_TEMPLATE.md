# Phase Evidence Package Template

**Purpose:** define the minimum durable records for every new substantial
feature, IP block, architecture change, verification expansion, or system
experiment.

This template is prospective. Existing `doc/AR*.md` reports and
`docs/phase*-guide.md` files remain valid historical evidence and do not need
mechanical migration.

## 1. Where the files belong

Create one directory per independently reviewable phase or vertical slice:

```text
doc/plans/<phase-id>/
  requirements.md
  architecture.md
  registers.rdl       # when the phase has software-visible registers
  registers.md        # generated from RDL, or hand-written only during a pilot
  verification_plan.md
  results.md
  evidence/           # compact logs, reports, traces, screenshots, hashes
```

Examples of useful phase IDs are `u0-passive-uvm`, `p0-power-baseline`,
`c0-safe-pwm`, and `m0-sil-loop`. Do not create empty directories for distant
ideas. Create a package when a phase becomes the next accepted implementation
slice.

`doc/AR*.md` remains the home for focused problem/root-cause/decision and
RED/GREEN evidence. Link the relevant AR report from the phase package instead
of duplicating it.

## 2. Package status and traceability

Put this header in every file:

```markdown
**Phase:** <stable phase ID and title>
**Status:** Draft | Accepted | Implemented | Verified | Deferred | Superseded
**Owner:** <person or role>
**Last updated:** YYYY-MM-DD
**Depends on:** <phase IDs / decisions / interfaces>
**Related evidence:** <links>
```

Every requirement gets a stable ID. Recommended prefixes:

- `REQ-<PHASE>-NNN` — functional or interface requirement;
- `SAFE-<PHASE>-NNN` — hazard mitigation or fail-safe behavior;
- `PERF-<PHASE>-NNN` — latency, throughput, resource, or power target;
- `VER-<PHASE>-NNN` — verification obligation.

The same IDs should appear in architecture decisions, register behavior,
verification-plan rows, tests/assertions, and results. A requirement is not
complete because code exists; it is complete when its evidence is linked.

## 3. `requirements.md`

Required sections:

```markdown
# <Phase> Requirements

## Scope and user/system outcome
What observable outcome does this phase enable?

## Preconditions and assumptions
Tool versions, clocks, memory map, plant/model assumptions, board constraints.

## Functional requirements
| ID | Requirement | Rationale | Verification method | Priority |

## Non-functional requirements
Timing, throughput, area, power, wake/fault latency, determinism, portability.

## Safety and failure consequences
| Hazard/failure | Consequence | Detection | Safe response | Residual risk |

## Non-goals
What this phase explicitly does not claim or implement.

## Acceptance and exit gate
The smallest objective evidence that allows the next phase to start.

## Open questions
Unresolved choices with owner and decision deadline.
```

Rules:

- Prefer measurable thresholds to adjectives such as "fast" or "low power".
- State measurement conditions; a number without workload, clock, tool, and
  confidence is not a reproducible requirement.
- Long-term product wishes belong in the roadmap unless this phase has a
  credible implementation and verification path for them.

## 4. `architecture.md`

Required sections:

```markdown
# <Phase> Architecture

## Context and boundary
What is inside/outside the phase and which existing blocks it touches.

## Block/data-flow diagram
Inputs, outputs, owners, state, and error/fault paths.

## Interfaces and protocols
Signal/register/software/model contracts; valid/ready and ordering rules.

## Clock, reset, CDC/RDC, and safe-state strategy
Clock domains, reset assertion/deassertion, synchronizers, clock enables.

## State machines and timing
State transitions, cycle/latency guarantees, abort/timeout behavior.

## Data representation
Widths, signedness, endianness, units, fixed-point scale, saturation/rounding.

## Error and fault containment
Detection, latching, propagation, recovery, and CPU-independent protection.

## Alternatives and decision links
Why this design was selected; link the living decision record or AR report.

## Implementation partition
RTL, firmware, verification, host model, FPGA/vendor wrapper, generated files.
```

Update the consolidated architecture diagrams and risk table when this design
changes the system data/control path.

## 5. `registers.rdl` and `registers.md`

Use these only when software-visible registers exist. The intended end state
is one machine-readable source that generates RTL register logic, C headers,
documentation, and UVM RAL metadata. Pilot this on one new peripheral before
converting existing blocks.

The register contract must define:

- base address, offset, width, alignment, and byte-lane behavior;
- reset value and reset domain;
- access type (`RO`, `RW`, `WO`, `W1C`, `W1S`, read-to-clear, hardware-set);
- reserved-bit read/write behavior;
- side effects, atomicity, lock/unlock, shadow/update semantics;
- interrupt/fault pending, enable, mask, clear, and test behavior;
- legal/illegal values and error response;
- software initialization, normal-use, fault-clear, and shutdown sequences;
- version/feature discovery where software compatibility requires it.

`registers.md` must say whether it is generated and from which exact source.
Never maintain two supposedly authoritative maps by hand.

## 6. `verification_plan.md`

Required sections:

```markdown
# <Phase> Verification Plan

## Verification scope and strategy
Unit, integration, firmware, formal/SVA, UVM, SIL/HIL, FPGA, or bench layers.

## Requirement traceability
| Requirement ID | Test/assertion/coverage | Level | Expected result | Status |

## Test categories
### Positive/nominal
### Boundary and corner cases
### Negative and protocol-error cases
### Fault injection and recovery
### Reset/clock/CDC and race cases
### Performance, timing, area, and power measurements

## Assertions and invariants
Safety, ordering, exactly-once, no-overlap, liveness, timeout, and safe state.

## Coverage model
Feature, code, assertion, cross, scenario, and explicitly waived coverage.

## Regression and reproducibility
Commands, manifests, seeds, timeouts, tool/model versions, artifact retention.

## Pass/fail oracle
What independently decides PASS and how infrastructure failures become nonzero.

## Exit criteria and waivers
Required green gates and reviewed limitations.
```

At minimum, each feature needs one deliberate failing/negative infrastructure
case so the team knows the checker can detect the class of error it claims to
cover.

## 7. `results.md`

This file records observed facts, not intentions. Keep unexecuted rows marked
`NOT RUN`; never pre-fill expected results as if they were evidence.

Required sections:

```markdown
# <Phase> Results

## Tested identity
Commit/tree state, configuration, generated-file status, tools, host, date.

## Regression summary
Commands, passed/failed/skipped counts, runtime, seeds, retained logs.

## Focused evidence
Requirement IDs mapped to tests, assertions, traces, and fault injections.

## Synthesis/implementation
Part, constraints, LUT/FF/BRAM/DSP, WNS/TNS, DRC, generated artifacts.

## Power/performance
Workload, activity source/window, clock, assumptions, baseline and delta.

## Hardware/model evidence
Bitstream hash, run duration, instruments/model version, screenshots/data.

## Known limitations and confidence
What was not measured, model uncertainty, waivers, external blockers.

## Exit-gate verdict
PASS | FAIL | PARTIAL, with reviewer-readable reasons and next action.
```

Large generated outputs should normally stay out of Git. Retain compact reports,
summaries, hashes, failing seeds, and the commands needed to regenerate them.

## 8. Tailoring matrix

| Phase type | Requirements | Architecture | Registers | Verification | Results |
| --- | --- | --- | --- | --- | --- |
| RTL/IP with MMIO | Required | Required | Required | Required | Required |
| RTL without MMIO | Required | Required | Omit with reason | Required | Required |
| Firmware/runtime | Required | Required | Reference existing map | Required | Required |
| Verification infrastructure | Required | Required | RAL schema if relevant | Required | Required |
| Power measurement baseline | Required | Measurement architecture | Omit | Required | Required |
| MIL/SIL/HIL model | Required | Model/interface architecture | Omit | Required | Required |
| Research spike | Short form | Short form | Omit | Experiment plan | Results/decision |

## 9. Completion checklist

- [ ] Scope, non-goals, assumptions, and failure consequences are explicit.
- [ ] Interfaces, units, clocks/resets, owners, and safe states are unambiguous.
- [ ] Register source and generated consumers cannot silently diverge.
- [ ] Positive, boundary, negative, fault, reset/race, and recovery cases exist.
- [ ] Exit gate is measurable and all claims link to retained evidence.
- [ ] Known limitations distinguish simulation, synthesis, FPGA, and product
      assurance.
- [ ] `TODO.md`, living documents, diagrams, risks, and focused AR evidence are
      updated when required.
