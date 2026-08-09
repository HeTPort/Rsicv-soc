# Progress

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
