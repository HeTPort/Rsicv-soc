# U0 Passive UVM Toolchain Architecture

**Phase:** U0 passive UVM — toolchain confirmation
**Status:** Implemented
**Owner:** Verification
**Last updated:** 2026-09-16
**Depends on:** REQ-U0-001 through REQ-U0-005
**Related evidence:** [requirements](requirements.md), [verification plan](verification_plan.md), [results](results.md)

## Context and boundary

This experiment sits before the AR-026 passive retirement environment. It
tests only the simulator/UVM launch path. The DUT and all production RTL remain
outside the boundary.

## Block/data-flow diagram

```text
u0_uvm_smoke.sv
    -> vlog + selected UVM package/macros
    -> work library
    -> vsim -c u0_uvm_smoke_top
    -> UVM factory/run phases
    -> exact PASS marker + native exit status
    -> runner verdict
```

## Interfaces and protocols

The standalone top has no DUT interface. It calls `run_test` after importing
`uvm_pkg` and including `uvm_macros.svh`. The registered test raises an
objection, emits the exact marker, and drops the objection.

## Clock, reset, CDC/RDC, and safe-state strategy

No clock, reset, CDC, or RDC exists in this toolchain-only smoke test.

## State machines and timing

Only standard UVM factory construction and phase execution are exercised. The
test must terminate without a simulation timeout.

## Data representation

Not applicable.

## Error and fault containment

The runner requires native zero exit, the exact pass marker, zero UVM errors,
and zero UVM fatals. Any compile failure, license failure, missing marker, or
nonzero UVM error/fatal count is a failed toolchain verdict.

## Alternatives and decision links

Inferring support from a directory or release number was rejected because it
does not prove compilation, library selection, licensing, or runtime phases.
See [AR-026](../../ar/AR026_SCALABLE_UVM_VERIFICATION_ARCHITECTURE.md).

## Implementation partition

- SystemVerilog: minimal standalone UVM top and test.
- PowerShell/ModelSim command script: isolated build, run, and result gate.
- Documentation: exact observed tool identity and verdict.
- Generated work library/transcript: ignored build output, not committed.
