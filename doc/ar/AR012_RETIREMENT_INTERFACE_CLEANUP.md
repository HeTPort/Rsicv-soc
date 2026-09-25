# AR-012 — Retirement and public-interface cleanup

**Date:** 2026-08-17
**State:** Implemented and verified
**Stage:** Cross-stage release cleanup

## Problem

The core once exposed `halt_o` as a test-completion signal. Precise traps,
architectural retirement, and memory-mapped `tohost` later replaced that
behavior, but the port remained in `riscv`, tied permanently low. The SoC left
it unconnected and the core testbench declared a signal only to receive it.

Keeping a dead public port made the interface describe behavior the core no
longer provided. It also created two completion stories: an obsolete halt
signal in RTL and the real committed-store protocol used by every regression.

## Root cause

The project evolved from an early EBREAK-oriented test environment to precise
M-mode traps and an ordered commit interface. Internal retirement ownership was
cleaned up incrementally, but the compatibility port was deliberately deferred
until the architectural and test completion contracts were stable.

## Options considered

1. Keep the port tied low. This avoids an interface edit but preserves a false
   capability and forces every integration to understand an obsolete signal.
2. Repurpose it as a generic completion output. Rejected because completion is
   a software/testbench ABI, not an architectural CPU output, and a one-bit
   signal would lose failure codes and ordering information.
3. Remove it and retain committed `tohost` plus `commit_pkt_t`. Selected because
   these are already the verified architectural observation mechanisms.

## Decision

- Remove `halt_o` from `src/core/riscv.sv`.
- Remove the empty SoC connection and testbench-only signal.
- Keep test completion as a committed store to the configured `tohost` address:
  value 1 is PASS and another nonzero value is a test-defined failure code.
- Keep `commit_pkt_t` and `trap_entry_t` as ordered verification interfaces.

No instruction, pipeline, trap, memory, firmware, or FPGA behavior changes.

## Consequences

- The public core interface now contains only active contracts.
- Test completion has one documented source of truth.
- Existing integrations that instantiated `riscv` directly must remove their
  `halt_o` connection. `riscv_soc` is already updated.
- The cleanup does not imply production readiness or close the physical UART,
  reset, speed-grade, FreeRTOS soak, or FPGA FreeRTOS gates.

## Verification

Fresh evidence after removal on 2026-08-17:

| Gate | Result |
|---|---:|
| Full SoC file-list compilation | PASS, 0 errors |
| Focused data-fabric protocol test | PASS at 196 ns, 0 errors |
| Directed smoke regression | 22/22 PASS, all simulator exits 0 |
| Official ACT4 4.0.0 applicable RV32I | 39/39 PASS |
| Official ACT4 4.0.0 applicable RV32M | 8/8 PASS |
| ELF converter/importer unit tests | 12/12 PASS |
| SoC-map generator unit tests | 9/9 PASS |
| Regression classifier negative test | PASS |

The ACT4 artifacts were regenerated from the pinned configuration before the
47-case ModelSim run. This is preservation evidence, not an ISA compliance
certification claim.

## Learning note

A public signal should represent a real, owned contract. Keeping a dead output
can appear harmless, but it makes integration and verification ambiguous. When
an architectural observation interface supersedes an early debug shortcut,
remove the shortcut after the replacement has stable tests and documentation.
