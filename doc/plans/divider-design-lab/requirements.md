# Divider Digital-Design Learning Lab Requirements

**Phase:** divider-design-lab

**Status:** Verified

**Owner:** project learner

**Last updated:** 2026-09-10

**Depends on:** AR-017 production divider

**Related evidence:** [results](results.md), [tutorial](../../DIVIDER_DIGITAL_DESIGN_LAB.md)

## Scope and outcome

Provide a reproducible, beginner-oriented lab using the current divider for
simulation, waveform debugging, routed STA, RTL/netlist correlation and lint.

## Requirements

| ID | Requirement | Verification |
| --- | --- | --- |
| REQ-DDL-001 | Preserve production divider RTL | Before/after SHA256 and git diff |
| VER-DDL-001 | Run the existing deterministic 42-case divider test | Exact PASS marker and no simulator errors |
| VER-DDL-002 | Record post-NBA protocol/datapath samples for nominal, signed, corner, kill and recovery cases | Validated JSONL plus WLF/VCD |
| VER-DDL-003 | Prove the test gate rejects a deliberately wrong quotient oracle | Exact expected fatal signature |
| PERF-DDL-001 | Report routed internal reg-to-reg setup and hold at 25 MHz | Vivado timing paths |
| VER-DDL-004 | Contrast the same routed path under a deliberately tight 5 ns requirement | Same data delay and negative slack |
| VER-DDL-005 | Establish and triage a dedicated lint baseline, including one LATCH RED/GREEN fixture | Warning-ID and exit-code checks |

## Safety, assumptions and non-goals

All generated checkpoints and logs stay under ignored `build/divider_lab`.
No board programming or production RTL mutation is allowed. OOC IO delays,
clock root and reset false path are educational assumptions; they do not prove
board IO timing, reset release safety, whole-SoC timing, P0 power or ASIC signoff.
There is no MMIO, so `registers.rdl` and `registers.md` are intentionally omitted.

## Exit gate

All requirement rows have reproducible commands and observed evidence; deliberate
negative cases fail for the intended reason; limitations are stated alongside
positive results.
