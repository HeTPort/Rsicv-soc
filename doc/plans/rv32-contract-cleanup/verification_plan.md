# RV32 Contract Cleanup Verification Plan

**Phase:** rv32-contract-cleanup
**Status:** Complete
**Owner:** RTL verification
**Last updated:** 2026-09-24
**Depends on:** existing focused scripts and smoke/ACT manifests
**Related evidence:** [results](results.md)

## Traceability

| Requirement | Test/check | Expected | Status |
|---|---|---|---|
| REQ-RV32-001/002/003 | `rg` source audit; `run_compile_soc.do` | no fake hooks/parameters; compile zero errors | PASS |
| REQ-RV32-004 | divider protocol; AR-003 synthesis compile | generic leaf behavior preserved | PASS |
| REQ-RV32-005 | CSR retire-order and timer tests | 64-bit behavior unchanged | PASS |
| REQ-RV32-006 | directed smoke/reset behavior | no architectural reset regression | PASS |
| SAFE-RV32-001 | LSU, fabric, UART, GPIO, RV32M, 23-test smoke, ACT | all PASS | PASS |
| PERF-RV32-001 | commit behavior and source review | no added state/latency | PASS |

## Commands

- `cd sim; vsim -c -do run_compile_soc.do`
- focused: divider, RV32M, LSU, CSR, timer, fabric, UART, GPIO
- `sim/regress/run_regression.ps1 -Tag smoke`
- strict lint through `sim/lint/run_lint.ps1`
- AR-003 SoC synthesis after functional gates

The ACT gate uses the existing generated `build/act4/tests.json` identity; the
test binaries were not regenerated because this phase changes no toolchain or
software input.

## Pass/fail oracle

Every simulator command must exit zero and contain no unexpected fatal/error.
Regression manifests use committed `tohost` PASS and native exit status.
