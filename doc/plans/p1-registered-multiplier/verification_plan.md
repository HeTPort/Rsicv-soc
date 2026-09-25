# P1 Registered Blocking Multiplier Verification Plan

**Phase:** p1-registered-multiplier
**Status:** Active
**Last updated:** 2026-09-25

## Traceability

| Requirement | Check | Status |
|---|---|---|
| REQ-MUL-001/002/003 | Focused latency, all variants, randomized, overlap tests | RED confirmed; registered GREEN 175 cases PASS |
| REQ-MUL-004 | Multi-cycle response backpressure and stability assertion | PASS |
| SAFE-MUL-001 | Kill in arithmetic/RESP states, reset, recovery, no late response | PASS |
| SAFE-MUL-002 | Divider protocol 42 cases and RV32M facade regression | PASS |
| SAFE-MUL-003 | Full compile, smoke 23/23, ACT4 47/47 | PASS |
| PERF-MUL-001/002 | Exact-board 100 MHz route and routed reports | PASS for multiplier bottleneck removal; whole SoC remains -0.312 ns on timer path |
| PERF-MUL-003 | `p0_mix` marker-window capture and reviewed power flow | PASS, two runs, 0.0% power difference |
| PERF-MUL-004 | `p0_idle_spin` marker-window capture and reviewed power flow | PASS, two runs, zero multiplier activity |

## RED/GREEN sequence

1. Update focused tests to require non-combinational acceptance, exact fixed
   latency, ownership, response stability, kill in each state, and recovery.
2. Run against the combinational backend and retain the expected RED reason.
3. Implement the registered backend and rerun GREEN.
4. Run compile, affected focused tests, smoke, ACT4, and layered lint.
5. Run same-part/XDC 100 MHz route and resource comparison.
6. Capture fresh `p0_mix` and `p0_idle_spin` SAIF, build matching 95 MHz routed
   checkpoints, import reviewed activity, and compute energy per fixed work.

## Pass/fail oracle

Every simulator/tool command exits zero and contains its native PASS marker.
Power analysis is rejected for negative routed slack, missing activity, failed
functional oracle, or failed mapping/coverage policy.
