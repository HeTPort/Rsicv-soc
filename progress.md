# Progress

## 2026-08-09 — Phase 4 UART RX

- Started the user-requested polling RX extension from the pushed TX checkpoint.
- Accepted a parameterized FIFO with default depth 16, separate synchronized
  receiver/sampler ownership, explicit overflow/framing policy, polling MMIO,
  end-to-end echo verification, and comprehensive README refresh.
- The first map-generation command was sandbox-blocked while writing generated
  files in this worktree, leaving the stale-file check and one unit test RED.
  Re-run the same canonical generator with explicit workspace write approval;
  the failure is environmental, not a map-contract error.
- Added canonical RXDATA/RXERROR definitions, regenerated all consumers, and
  passed the freshness check plus 9/9 generator tests after approved rerun.
- Added receiver timing/false-start/framing RED tests and native-bus 16-byte
  FIFO/MMIO RED tests. Both fail for the intended reason: `uart_rx.sv` is not
  implemented yet. Phase 1 is complete and Phase 2 implementation begins.
- Implemented `uart_rx.sv` with an attributed two-flop synchronizer, midpoint
  start confirmation, LSB-first data sampling, valid-byte events, and separate
  framing-error events. Its focused test passes with zero warnings/errors.
- Extended `core_bus_uart.sv` with a parameterized default-16 FIFO, explicit
  pointer wrap, nonblocking RXDATA pop, occupancy/status, drop-newest overrun,
  bad-frame rejection, and event-wins W1C sticky errors. The 16-byte FIFO/MMIO
  test passes, including fill/order/overrun/empty/error-clear behavior.
- Exposed `uart_rx_i` and the default-16 FIFO parameter at `riscv_soc`, added
  generated RX register offsets, and updated simulation/Vivado source lists.
- Added 16-byte polling echo firmware plus asynchronous pin stimulus and
  independent TX pin decoding. Both Phase 4 SoC tests pass: the original
  `Hello, UART!\r\n` TX case and `RX FIFO 16 OK!\r\n` RX-to-TX echo case.
- Preservation verification is GREEN: TX shifter, TX bus target, RX receiver,
  16-byte RX FIFO/MMIO, and fabric focused tests; 2/2 Phase 4 SoC UART tests;
  2/2 Phase 3 timer/WFI tests; and 22/22 general smoke tests.
- Vivado AR-003 OOC synthesis passes with 0 errors and 0 critical warnings,
  retaining 32 BRAMs, 2 LSU-state cells, and 398 UART-hierarchy objects. The
  report shows `core_bus_uart` 390 cells, nested `uart_rx` 71, and nested
  `uart_tx` 89. Phase 4 verification/synthesis closure is complete.

## 2026-08-09

- Started the Phase 3 staged implementation task.
- Confirmed the target worktree is clean and the local branch is one commit behind its remote.
- Created the persistent implementation plan and initial findings record.
- Phase 1 is in progress: baseline audit and semantic signal specification.
- Audited the roadmap and simulator file list. One inspection used the obsolete
  `src/bus/soc_mem_map_pkg.sv` path; the actual generated package is
  `src/generated/soc_mem_map_pkg.sv` and subsequent work will use that path.
- Reviewed the remote-only Phase 3 guide. Retained its requirement coverage but
  rejected its CSR-style timer port, live-pipeline WFI stall, unqualified
  level-sensitive interrupt-take logic, and premature physical clock gating.
- Ran the pre-change smoke regression: 22/22 tests passed. The first sandboxed
  run could not create the ModelSim log; the approved worktree run completed
  successfully with simulator exit zero for every test.
- Completed the initial retirement/control audit. Confirmed that WFI is lost
  before EX/WB, commit construction is still top-level logic, and an explicit
  resolved `next_pc` is required for precise interrupts after control flow.
- Added `doc/SEMANTIC_SIGNAL_SPEC.md`, defining current signal semantics,
  ownership, naming, packing criteria, retirement/CSR/redirect/bus/timer
  contracts, required assertions, and the review standard for future signals.
- Added the focused retirement-stage contract test before the implementation.
  It covers ordinary RF retirement, synchronous-effect suppression, typed trap
  redirect, commit observation, and CSR preview/commit command generation.
- Captured the expected RED result: ModelSim compilation fails because
  `src/core/retire_stage.sv` does not exist. Phase 1 is complete and Phase 2,
  behavior-preserving retirement extraction, is now in progress.
- The first combined RTL patch made no changes because an encoded legacy
  comment prevented context matching. The implementation is being split into
  smaller ASCII-anchored patches.
- Implemented the behavior-preserving retirement extraction and semantic packet
  types. The focused test passes and the full smoke suite remains 22/22 GREEN.
- Removed the superseded `wb_stage.sv` owner after verification. Phase 2 is
  complete; Phase 3 post-retirement CSR preview/ordered commit is in progress.
- Added the CSR preview/context interface, hardware MTIP composition, ordered
  CSR-write-then-trap state updates, and interrupt selection from the effective
  context. Added focused tests for same-boundary mstatus/mie/mtvec semantics.
- Both focused semantic tests are GREEN. The first full-regression invocation
  omitted the documented process-local script policy override and did not run;
  it will be retried with the established command.
- Completed Phase 3 CSR preview/ordered commit. Focused ordering tests pass and
  the complete directed smoke suite remains 22/22 GREEN. Phase 4 interrupt
  boundary and one-time WFI implementation is now in progress.
- The first WFI focused run passed its functional checks but exposed an overly
  broad bubble assertion: WFI wake intentionally enters a trap without a live
  instruction packet. The assertion was narrowed to distinguish wake events
  from forbidden normal retirement effects.
- Completed Phase 4 interrupt/WFI behavior. Focused retirement/WFI tests and a
  full-core RV32IM compile/run are GREEN. Phase 5 timer target and fabric-owner
  implementation is now in progress.
- The first timer patch made no partial change because `src/periph` did not yet
  exist. The directory will be created explicitly before adding the module.
- The isolated timer target test is GREEN. The first expanded fabric run exposed
  an invalid testbench stimulus that changed a valid back-pressured request;
  the stimulus was corrected without weakening the fabric assertion.
- Added precise WFI/timer and 10,000-interrupt firmware tests plus a dedicated
  Phase 3 manifest. Direct WSL script execution hit the repository's CRLF
  shebang; the build will be retried through explicit `bash`.
- Explicit `bash` also encountered CRLF in `set -o pipefail`. The script must
  use LF throughout before any WSL build can run.
- Normalized the WSL test builder to LF, generated both timer firmware images,
  and ran them successfully. The precise WFI test and the 10,000-interrupt
  stress test both pass.
- Phase 5 timer/fabric integration is complete. Phase 6 full verification and
  living-document closure is in progress.
- Added the focused AR-008 report, corrected Phase 3 implementation guide, and
  most knowledge-base architecture/status updates. One risk-table edit hit an
  encoded legacy dash and will be reapplied with smaller ASCII anchors.
- Reconciled the knowledge base, architecture/decision record, review plan,
  TODO milestone, repository guidance, regression README, and semantic signal
  specification with the implemented ownership and signal flow.
- Final focused retirement, CSR ordering, timer-target, and three-owner fabric
  tests pass. The corrected CSR test explicitly connects the WFI-entry output.
- Final end-to-end verification is GREEN: precise timer/WFI PASS, 10,000 timer
  interrupts PASS, 22/22 smoke PASS, 4/4 SoC fault PASS, 4/4 Python utilities
  PASS, and the regression classifier PASS.
- Updated the Vivado OOC source list for `retire_stage.sv` and
  `mtime_timer.sv`. Vivado 2019.2 synthesis passes with 0 errors, 0 critical
  warnings, 32 `RAMB36E1` cells, and retained LSU/retirement/timer hierarchy.
- Phase 6 verification and living-document closure is complete.

## 2026-08-09 — Phase 4 UART

- Started the minimal UART TX vertical slice after the user accepted the
  holding-register -> shifter architecture.
- Confirmed the FPGA board is not required for RTL, ModelSim, firmware, or OOC
  synthesis verification. Exact board data remains mandatory for final top,
  XDC, bitstream programming, and real serial-terminal validation.
- Recorded the accepted TX-only 8N1, core-bus, register-map, backpressure, and
  error semantics in the active plan. Phase 1 baseline audit/tests are in
  progress.
- Audited the canonical map generator, registered fabric, SoC integration, and
  regression runner. The existing contracts support UART as a fourth owner and
  dedicated focused test tops without adding APB or changing the runner.
- Added canonical `uart_txdata`/`uart_status` register definitions, regenerated
  all map consumers, and passed 9/9 generator tests.
- Added focused shifter and core-bus/holding-register contract tests before the
  RTL. Both are intentionally RED because `uart_tx.sv` and
  `core_bus_uart.sv` do not exist yet.
- The initial RED `.do` files allowed a compile failure to escape with process
  exit zero; added explicit `onerror` failure propagation. Phase 1 is complete
  and Phase 2 implementation is in progress.
- Implemented the project-native 8N1 valid/ready shifter and registered
  core-bus UART target with one-byte holding storage. Exact shifter timing is
  GREEN for `0x00`, `0xA5`, and `0xFF` with zero compiler warnings.
- The first bus-target run exposed a testbench delta-cycle race when observing
  `req_ready` immediately after changing `req_valid`; the test now allows the
  combinational path to settle before measuring backpressure.
- The second bus run proved backpressure occurred but sampled its release on
  the accepting positive edge, then waited past the one-cycle response. Changed
  the driver to observe settled readiness on negative edges before acceptance.
- Phase 2 is complete: both the standalone 8N1 shifter and native-bus UART
  target pass focused protocol tests. Phase 3 fabric/SoC integration is now in
  progress.
- Extended the fabric with UART decode, local-offset translation, registered
  response ownership, range/overlap checks, and mutual-exclusion assertions.
  The focused fabric test passes with UART as the fourth owner.
- A direct `vlib` full-compile attempt was blocked by the workspace sandbox
  when creating a new ModelSim library. Use an approved `vsim -do` flow for
  compile verification instead; this is an execution-environment issue, not an
  RTL failure.
- The approved ModelSim `.do` compile flow then compiled the complete SoC
  source list with zero errors. Phase 3 is complete; Phase 4 end-to-end
  firmware/serial scoreboard work is in progress.
- While auditing the regression runner, an attempted read used the nonexistent
  `run_regression.py`; the repository uses `run_regression.ps1`. Located and
  inspected the PowerShell runner before extending its optional generics.
- The first Phase 4 manifest invocation selected the runner's default `smoke`
  tag, which is absent from the UART-only manifest, so no test ran. Reinvoke
  with the explicit `soc_uart_hello` test name.
- Built and installed `soc_uart_hello_test.hex`, then passed the Phase 4
  end-to-end regression. The CPU polling program transmitted all 14 bytes of
  `Hello, UART!\r\n`; the testbench decoded and checked the actual 8N1 output
  waveform, and PASS retired after the final stop bit in 625 CPU cycles.
- Regression preservation is GREEN: 2/2 Phase 3 timer/WFI tests (including the
  10,000-interrupt run) and 22/22 general smoke tests pass.
- Vivado AR-003 OOC synthesis passes with 0 errors, 0 critical warnings,
  32 BRAM cells, 2 LSU-state cells, and 72 UART-hierarchy cells. The corrected
  generated-map synthesis flow also passes with the accepted 64 KiB map and
  32 BRAM cells.
- Added AR-020, the Phase 4 UART guide, UART semantic-signal contracts, updated
  architecture diagrams/risks/roadmap, and refreshed README/AGENTS/regression
  instructions. Phases 1–5 of the active UART plan are complete; exact-board
  validation remains deferred pending board facts.

## Phase 4 UART RX completion

- Extended the canonical map with RXDATA/RXERROR and regenerated RTL, C,
  linker, simulation, synthesis, and ACT4 consumers; generator check and 9/9
  unit tests pass.
- Added `uart_rx.sv`, a synchronized midpoint-sampling 8N1 receiver, plus its
  focused false-start/data/framing test.
- Extended `core_bus_uart.sv` with a parameterized default 16-byte RX FIFO,
  status/count, nonblocking RXDATA, drop-newest overrun, framing error, and W1C
  error state. The focused bus suite proves ordering and fills all 16 entries.
- Exposed `uart_rx_i` through `riscv_soc`, updated all simulation/synthesis
  source lists, and added a 16-byte polling echo firmware regression.
- Verification is GREEN: focused RX/TX/fabric, Phase 4 2/2, Phase 3 2/2,
  smoke 22/22, and Vivado OOC with 0 errors/critical warnings and retained
  UART RX/TX hierarchy.
- Added AR-021 and updated the semantic specification, both consolidated living
  documents, TODO, Phase 4 guide, AGENTS, regression instructions, and README.
