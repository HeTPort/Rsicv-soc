# P2 Core Control Ownership Verification Plan

**Phase:** p2-core-control-ownership
**Status:** Complete
**Owner:** RTL verification
**Last updated:** 2026-09-25
**Depends on:** focused core/retirement/protocol tests and exact-board flow
**Related evidence:** [AR-031](../../AR031_CORE_CONTROL_OWNERSHIP.md)

## Traceability

| Requirement | Test/assertion | Level | Status |
|---|---|---|---|
| REQ-CTRL-001, SAFE-CTRL-001 | `tb_core_ctrl`: EX-only, retirement-only, simultaneous redirect priority | Unit | PASS, 10-case matrix |
| REQ-CTRL-002, SAFE-CTRL-002 | `tb_core_ctrl`: RAW, wait, overlap, delayed fetch kill; `tb_fetch_error_timing` | Unit/core | PASS |
| REQ-CTRL-003, SAFE-CTRL-003 | `tb_core_ctrl` exception/WFI matrix; LSU/RV32M/divider protocols | Unit/core | PASS |
| REQ-CTRL-004 | `tb_retire_stage`, CSR order, MRET firmware/smoke | Unit/core | PASS |
| PERF-CTRL-001 | fixed-work smoke/ACT4/power workload cycle comparison | Core/SoC | PASS; `p0_mix` unchanged, 64-wake window +1 cycle |
| PERF-CTRL-002 | exact 95/100 MHz implementation report | FPGA | PASS: +0.078/+0.098 ns WNS |
| PERF-CTRL-003 | matching `p0_mix` SAIF/routed power report | SoC | PASS: 0.119 W dynamic in both runs |

## RED/GREEN sequence

1. Compile the typed focused control test against the old scalar interface;
   missing `pipe_ctrl_t`/typed ports must produce RED.
2. Implement the package, execute, retirement, control, and top-level changes.
3. Run focused control, retirement, CSR ordering, fetch timing, LSU, RV32M, and
   divider tests.
4. Run full compile, 23-test smoke, 47-test ACT4, and layered lint.
5. Route matching exact-board builds and compare critical paths/resources.
6. Run matching activity-power evidence when the accepted routed design is
   timing-clean.

## Assertions and pass/fail oracle

- Retirement redirect always wins simultaneous EX redirect.
- `pipe_kill` implies no younger EX/WB side effect or new LSU/RV32M request.
- Wait holds ID/EX and does not inject a bubble until ownership completes.
- MRET redirect is present exactly with the MRET retirement command.
- Tool exit must be zero and the native PASS marker must be present.

There are no MMIO registers in this phase, so `registers.rdl` is intentionally
omitted.
