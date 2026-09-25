# RV32 Contract Cleanup Requirements

**Phase:** rv32-contract-cleanup
**Status:** Verified
**Owner:** RTL architecture
**Last updated:** 2026-09-24
**Depends on:** AR-017, AR-027, fixed RV32IM software/ACT baseline
**Related evidence:** [AR-029](../../AR029_RV32_CONTRACT_AND_REFACTORING_SCOPE.md)

## Scope and outcome

Make the production RV32 contract honest and remove unsupported width knobs
without changing architectural behavior.

## Requirements

| ID | Requirement | Verification | Priority |
|---|---|---|---|
| REQ-RV32-001 | Scalar XLEN, architectural address width, and core-bus data width are fixed at 32 bits | Compile/lint/source audit | Must |
| REQ-RV32-002 | No `RISCV_XLEN_64` build path or RV64-only decode/control enum remains | Source audit | Must |
| REQ-RV32-003 | Core/bus/peripheral modules using `riscv_pkg` packets expose no shadow `AW`/`DW` parameters | Source audit and compile | Must |
| REQ-RV32-004 | Genuine RAM and standalone divider parameters remain supported | Focused divider and synthesis compile | Must |
| REQ-RV32-005 | `mtime`, `mtimecmp`, `mcycle`, and `minstret` remain 64-bit | Timer/CSR focused tests | Must |
| REQ-RV32-006 | Register-file combinational reads do not depend directly on reset | Source audit and smoke | Should |
| SAFE-RV32-001 | ISA results, traps, bus protocol, memory map, and peripheral behavior do not change | Focused plus full regressions | Must |
| PERF-RV32-001 | This cleanup adds no pipeline stage or CPI change | Commit/regression comparison | Must |

## Non-goals

- RV64, RVC, S/U mode, PMP, forwarding, registered multiplication, or NPU RTL.
- Renaming every width symbol in genuinely generic memory/divider IP.
- Changing memory capacity or software-visible registers.

## Failure consequences

An incomplete cleanup can leave type/parameter mismatches, unsupported tool
generics, or reset-only X differences. Compilation, focused reset tests, full
architectural regression, and synthesis elaboration are required before exit.

## Exit gate

All requirements trace to passing evidence; zero compile errors; focused
protocol/CSR/peripheral tests and 23/23 smoke pass; strict lint passes; official
RV32 ACT remains green or is explicitly recorded as not rerun with justification.
