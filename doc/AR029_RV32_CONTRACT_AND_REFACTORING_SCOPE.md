# AR-029 — RV32 Contract and Refactoring Scope

**Date:** 2026-09-24

**State:** Implemented and verified

**Stage:** Post-FreeRTOS RTL contract cleanup before registered multiplier

## Problem

The RTL described itself as RV32IM but exposed a `RISCV_XLEN_64` macro and
shadow `AW`/`DW` parameters across core, SoC, bus, and peripheral modules.
Those settings were not coherent contracts: packet types came from one global
package while decode, LSU lanes, CSR access, commit masks, peripherals,
firmware, and verification contained RV32-specific behavior.

The accompanying refactoring checklist also mixed naming preferences, measured
timing work, speculative S/U/RV64/PMP support, and control-ownership changes in
one proposed edit.

## Root cause

The design accumulated local width parameters as future-looking placeholders.
They did not carry requirements, supported-value matrices, or regressions.
This made the code appear more reusable than it was and obscured the real
product boundary: a deterministic RV32IM control core with independent 64-bit
time/counter state and possible future accelerators.

The reset input was also used in combinational register-file reads even though
those processes own no state and the architectural pipeline is invalid during
reset. This added a reset-to-read-data path without protecting an architectural
effect.

## Options considered

1. **Complete RV64 parameterization now.** This requires RV64 decode, word
   operations, load/store lanes, CSRs, traps, bus/software contracts, ACT tests,
   and new PPA evidence. Rejected because the power-management target has no
   requirement that justifies the cost.
2. **Leave the hooks as future placeholders.** Lowest immediate edit cost but
   continues a misleading public contract and allows unsupported elaborations.
   Rejected.
3. **Freeze RV32 while retaining explicit wide state and genuinely generic
   primitives.** Selected.

## Decision

- Fix scalar XLEN, architectural address width, and core-bus data width at 32
  bits in `riscv_pkg`.
- Remove the `RISCV_XLEN_64` branches and unsupported RV64-only enums/constants.
- Remove `AW`/`DW` parameters from modules whose interfaces already use fixed
  package packet types.
- Retain RAM dimension parameters and the standalone divider width parameter,
  because those are real independently testable IP contracts.
- Retain 64-bit `mtime`, `mtimecmp`, `mcycle`, `minstret`, and retirement order;
  RV32 accesses architecturally visible 64-bit state as paired words.
- Remove reset gating from combinational GPR reads while retaining asynchronous
  reset of the register array.
- Keep future NPU/MAC width and data movement independent of CPU XLEN.

## Consequences

- Unsupported configurations fail by absence rather than compiling partway.
- Core and SoC instantiations are shorter and have one authoritative width.
- Firmware ABI, memory map, bus pins, ISA results, and peripheral behavior do
  not change.
- A future RV64 effort must create an explicit architecture variant and evidence
  package rather than silently reusing this core.
- The next multiplier experiment remains attributable: it is not mixed with
  forwarding, RV64, or accelerator integration.

## Control and accelerator follow-up

The review confirmed one separate control issue: `core_ctrl` owns holds/flushes
but redirect priority still lives in `riscv.sv`, and MRET redirect ownership is
not fully aligned with the semantic specification. This is accepted as a later
focused control phase, not changed by the width cleanup.

The first registered multiplier candidate will be single-outstanding and
blocking behind `rv32m_unit`. A future NPU/MAC array should normally use a
decoupled MMIO/DMA/scratchpad boundary; it must not be forced through the scalar
MDU merely because both contain multipliers.

## Verification evidence

- ModelSim 2019.2 full SoC/testbench compile: PASS, zero errors. Existing
  relaxed-input-port warnings remain and are not caused by this change.
- Focused divider (42 cases), RV32M (172 cases), LSU, CSR retire ordering,
  timer, fabric, UART TX/RX, GPIO, retirement, decode fetch-error, and fetch
  error timing tests: PASS.
- Directed architectural smoke: 23/23 PASS.
- Existing generated official ACT4 manifest: 47/47 PASS (39 RV32I, 8 RV32M).
- Verilator 5.032 layered leaf/core/SoC strict lint: PASS.
- Vivado 2019.2 AR-003 OOC synthesis for `xc7z010clg400-1`: PASS with zero
  errors, 32 RAMB36E1 and 4 DSP48E1; LSU state and UART/GPIO logic retained.
- Focused and full regression results are recorded in
  [`plans/rv32-contract-cleanup/results.md`](plans/rv32-contract-cleanup/results.md).

## Learning conclusion

Parameterization is a verified product contract, not a promise embedded in an
identifier. Wide peripherals and accelerators do not require a wide scalar ISA.
