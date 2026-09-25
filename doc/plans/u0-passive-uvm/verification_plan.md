# U0 Passive UVM Toolchain Verification Plan

**Phase:** U0 passive UVM — toolchain confirmation
**Status:** Verified
**Owner:** Verification
**Last updated:** 2026-09-16
**Depends on:** [requirements](requirements.md), [architecture](architecture.md)
**Related evidence:** [results](results.md)

## Verification scope and strategy

Run an isolated command-line compile and simulation using only the installed
simulator and its supplied UVM support. Validate both positive execution and
the result gate's ability to reject missing/incorrect success.

## Requirement traceability

| Requirement ID | Test/assertion/coverage | Level | Expected result | Status |
|---|---|---|---|---|
| REQ-U0-001 | Tool inventory commands | Host/tool | Exact paths and versions captured | PASS |
| REQ-U0-002 | Compile/runtime UVM banner and library inspection | Tool | Selected version identified | PASS |
| REQ-U0-003 | Minimal `uvm_test` compile | Compile | Native exit zero | PASS |
| REQ-U0-004 | `run_test` smoke | Simulation | Exact pass marker, zero UVM errors/fatals | PASS |
| REQ-U0-005 | Command/evidence audit | Repository | Reproducible without vendored source | PASS |
| VER-U0-001 | Positive runner mode | Infrastructure | PASS and exit zero | PASS |
| VER-U0-002 | Deliberate negative runner mode | Infrastructure | FAIL and nonzero exit | PASS |
| VER-U0-003 | Git scope audit | Repository | No RTL change | PASS |

## Test categories

### Positive/nominal

- Compile the registered UVM test and static top.
- Run it in command-line mode to completion.

### Boundary and corner cases

- Use explicit library/version selection if multiple supplied UVM libraries
  exist; record which one wins.

### Negative and protocol-error cases

- Run the result gate against a deliberately missing or wrong success marker.

### Fault injection and recovery

- Not applicable beyond the negative infrastructure mode.

### Reset/clock/CDC and race cases

- Not applicable; there is no DUT clock or reset.

### Performance, timing, area, and power measurements

- Record wall time only as diagnostic context. No performance claim.

## Assertions and invariants

- A PASS verdict requires native exit zero and the exact pass marker.
- Any UVM error/fatal or missing marker prevents PASS.

## Coverage model

No functional or code coverage is required for the toolchain smoke test.

## Regression and reproducibility

Retain exact executable versions, compile/run commands, result markers, and
compact logs. Generated simulator work libraries remain under ignored build
output.

## Pass/fail oracle

The PowerShell runner combines native process status, the exact marker, and
UVM report counts. A deliberate negative mode proves this oracle rejects a
false success.

## Exit criteria and waivers

All traceability rows must be PASS. Host portability is explicitly waived; it
must be re-proved on another tool installation.
