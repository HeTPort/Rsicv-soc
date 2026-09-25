# AR-032 — P3 Semantic and Code Cleanup

**Date:** 2026-09-25
**State:** Implemented and verified
**Stage:** P3 behavior-preserving cleanup

## Problem and root cause

The architecture contracts are now substantially clearer than the local RTL:
`decode.sv` and `execute.sv` still use `_i/_o` on internal aliases, making local
combinational values look like module ports. Both modules also assemble packed
pipeline packets through long lists of independent continuous assignments,
which makes canonical defaults and newly added fields harder to review.

This is naming and construction debt, not justification for a new pipeline,
generic register wrapper, ALU hierarchy, or changed instruction semantics.

## Decision

Perform small behavior-preserving slices. Reserve `_i/_o` for actual ports,
use names describing local meaning, and build output packets by assigning the
typed canonical bubble first and then the fields meaningful at that boundary.
Retain the fail-closed instruction-fetch fault replacement and all established
redirect, kill, wait, CSR, LSU, and RV32M ownership.

## Rejected expansion

- Do not extract ALU/immediate/alignment modules without their focused contract
  and tests.
- Do not delete simulation-only protocol observations merely to remove a lint
  waiver.
- Do not introduce floorplanning or fixed routing while architecture changes.
- Do not use line-count reduction as an acceptance criterion.

## Consequences and evidence

`decode.sv` and `execute.sv` now reserve `_i/_o` for actual ports. Local values
use semantic names, redundant result aliases were removed, and each outgoing
pipeline packet is built from its typed canonical bubble before meaningful
boundary-owned fields are assigned. The fetch-error path still replaces the
ordinary decoded value with a fault-only canonical packet; LSU completion data
is still merged only in `riscv.sv`.

The focused decode/fetch, core-control, retirement/CSR, LSU, RV32M, and divider
tests pass. Smoke is 23/23, ACT4 is 47/47, and Verilator 5.032 leaf/core/SoC
lint passes. Full hierarchy compilation reports zero errors. Structural search
finds neither selected internal `_i/_o` declarations nor the former scattered
packet-field continuous assignments. Details and commands are in
[`plans/p3-semantic-cleanup/results.md`](../plans/p3-semantic-cleanup/results.md).

No external port, pipeline stage, cycle contract, state element, arithmetic
equation, or physical constraint changed. Therefore no new area, timing, or
power improvement is claimed and no new Vivado route was run: place-and-route
variation would not be meaningful evidence for this source-level cleanup.
