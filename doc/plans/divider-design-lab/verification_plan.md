# Divider Digital-Design Learning Lab Verification Plan

**Phase:** divider-design-lab

**Status:** Verified

**Owner:** project learner

**Last updated:** 2026-09-10

**Depends on:** requirements.md

**Related evidence:** [results](results.md)

## Traceability

| Requirement | Test/check | Expected | Status |
| --- | --- | --- | --- |
| REQ-DDL-001 | SHA256 production RTL before/after | unchanged | PASS |
| VER-DDL-001 | `run_sim.py --mode original` | 42 cases, no errors | PASS |
| VER-DDL-002 | `run_sim.py --mode green` | five completes, one kill, valid trace | PASS |
| VER-DDL-003 | `run_sim.py --mode negative` | exact case-1 mismatch; command nonzero | PASS |
| PERF-DDL-001 | `vivado_lab.tcl` | report internal max/min paths | PASS |
| VER-DDL-004 | same-route 5 ns report | same 9.352 ns data delay, slack below zero | PASS |
| VER-DDL-005 | `lint_lab.py` and candidate simulation | expected warning sets/exits; 42-case candidate PASS | PASS |

## Categories and oracles

Nominal/corner cases cover unsigned, signed, divide-by-zero, overflow and
post-kill recovery. Protocol checks cover 32 run cycles, one-cycle completion,
kill-over-start priority and no orphan completion. Infrastructure negatives are
a wrong arithmetic oracle, a deliberate latch, and the first rejected Vivado
post-processing command. A run passes only with exact markers, no simulator
error signature, valid trace contents, expected lint warning sets and required
timing-report properties.

Random behavior is fixed with seed `20260909`. Large WLF, VCD, DCP, netlist and
full reports remain ignored under `build/divider_lab`; compact facts are retained
in results.md. No code/assertion coverage, formal proof, CDC/RDC or gate-level
simulation was run.
