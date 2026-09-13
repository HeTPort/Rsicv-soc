# 100 MHz RTL Cleanup Audit Plan

## Goal

Prove or correct the claimed cleanup and abstraction by removing genuinely
dead aliases/CSR/debug/reset/suppression wiring, introducing strict nettype
checking compatibly, and measuring the routed 100 MHz critical path.

## Phases

| Phase | Status | Exit condition |
|---|---|---|
| Source and consumer audit | Complete | Every candidate classified as dead, contract, or architectural |
| RTL/interface cleanup | Complete | Dead wiring removed and all consumers migrated |
| Strict-nettype rollout | Complete | Changed ownership-boundary RTL compiles with `default_nettype none` and restores `wire` at EOF |
| 100 MHz implementation | Complete | Routed failure and critical path retained and reported |
| Regression and documentation | Complete | Tests/lint pass and living evidence matches results |

## Constraints

- Preserve commit/trap interfaces used for architectural verification.
- Do not remove reset from stateful protocol/control blocks.
- Do not claim maximum frequency from a single 100 MHz run.
- Do not replace the multiplier backend unless the measured path justifies it.

## Errors

| Error | Resolution |
|---|---|
| Prior blanket `default_nettype none` attempt failed under Questa ANSI `input logic` ports | Use explicit `wire logic` for input/inout nets and strict nettype per migrated file |
| Parallel Questa runs collided on the shared `work` library mapping | Reran all focused simulations serially; all passed |
| First strict lint found an observation-only retire interrupt output | Removed the port and used the typed trap command as the test/assertion oracle |
