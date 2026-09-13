# 100 MHz RTL Cleanup Progress

- 2026-09-13: Re-audited requested cleanup after user challenge.
- 2026-09-13: Confirmed earlier work removed `_unused_*` shims and the physical
  RAM reset, but left dead CSR observation ports, an assertion alias, an unused
  retirement observation, and display-only register debug wiring.
- 2026-09-13: Confirmed exact-board wrapper is fixed at 25 MHz and must be made
  explicitly configurable before a meaningful 100 MHz route.
- 2026-09-13: Removed 14 observation/debug output ports across regfile, core,
  CSR, retire, and SoC boundaries; removed the MRET alias and obsolete waivers.
- 2026-09-13: Enabled strict nettype checking in the modified ownership-boundary
  modules using explicit input net kinds and EOF restoration.
- 2026-09-13: Focused RV32M, CSR order, retirement, and fetch timing tests pass;
  smoke 23/23 and strict leaf/core/SoC lint pass.
- 2026-09-13: Exact-board 100 MHz route completed but failed timing at WNS
  -0.387 ns/TNS -3.637 ns. Critical path is the shared multiplier from ID/EX
  operand to EX/WB result; no 100 MHz bitstream was emitted.
- 2026-09-13: Resumed the interrupted Phase 6 regression with the correct
  manifest selection; `firmware_freertos_demo` passed at 500,000 cycles.
- 2026-09-13: The extended `firmware_freertos_soak` also passed with its
  15,000,000-cycle timeout in 202.20 seconds.
- 2026-09-13: Added `doc/MODULE_DEPENDENCY_VIEW.md`, derived from the current
  RTL instantiations and canonical source lists.
