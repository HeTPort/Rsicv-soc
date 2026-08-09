# Phase 3 Retirement, Interrupt, WFI, and Timer Plan

## Goal

Implement the accepted Phase 3 architecture incrementally: introduce semantic signal contracts and a retirement owner, add post-retirement CSR interrupt semantics, implement timer interrupts and one-time WFI retirement, extend the SoC fabric, verify each boundary, and update all living documentation.

## Guiding principles

- Architectural state changes have one owner and one retirement boundary.
- Pack signals by shared meaning and lifetime, not merely to reduce port count.
- Preview and commit must use the same CSR WARL policy.
- A retired instruction's effects precede an interrupt taken after that instruction.
- Synchronous exceptions suppress the faulting instruction's normal effects.
- Protocol handshakes remain explicit; payloads may be packed.
- Each phase must be independently testable and documentation-complete.

## Phases

1. **Complete — Baseline and semantic specification**
   - Audit current RTL/tests/docs and remote-only guide.
   - Add `doc/SEMANTIC_SIGNAL_SPEC.md` with current definitions and future standards.
   - Establish focused RED tests for retirement/CSR/interrupt contracts.
2. **Complete — Behavior-preserving retirement extraction**
   - Add semantic packet types and `retire_stage.sv`.
   - Move current WB architectural decisions without changing behavior.
   - Verify existing regressions remain GREEN.
3. **Complete — Post-retirement CSR preview and ordered commit**
   - Add CSR preview/context contract.
   - Support CSR write plus asynchronous trap entry at one boundary.
   - Add assertions and directed tests for mstatus/mie/mtvec ordering.
4. **Complete — Interrupt boundary and WFI**
   - Add `next_pc`, timer interrupt eligibility, trap entry, and logical WFI wait.
   - Define MRET exclusion and long-operation deferral.
   - Verify precise PC/cause/side-effect behavior.
5. **Complete — Timer target and fabric owner**
   - Add the timer as a `core_bus_req_t/core_bus_rsp_t` target.
   - Decode local offsets `0x4000` and `0xBFF8`.
   - Extend the registered response-owner mux and SoC integration.
6. **Complete — Full verification and living documentation closure**
   - Run focused and full regressions plus synthesis-boundary checks where available.
   - Update knowledge base, ADR, focused AR report, diagrams, risk tables, and TODO milestones.

## Errors encountered

| Error | Attempt | Resolution |
|---|---:|---|
| Read of `src/bus/soc_mem_map_pkg.sv` failed because the generated package is under `src/generated/`. | 1 | Use `src/generated/soc_mem_map_pkg.sv`; do not repeat the incorrect path. |
| Baseline regression could not write `sim/logs/regression/compile.log` under the sandbox. | 1 | Re-ran the same read/build verification with approved worktree write access; 22/22 smoke tests passed. |
| Focused retirement test failed to compile because `retire_stage.sv` did not exist. | Expected RED | This is the intentional pre-implementation contract failure; implement the typed packets and module next. |
| Initial combined RTL patch could not match an encoded comment beside `INST_MRET`. | 1 | Split the patch into smaller semantic edits anchored on ASCII-only lines; no source change from the failed patch. |
| First post-extraction smoke run was sandboxed from updating an existing compile log. | 1 | Re-ran with approved worktree access; 22/22 tests passed. |
| Post-CSR smoke command omitted the process-local PowerShell execution-policy override. | 1 | Re-run with the documented `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` prefix. |
| WFI focused test reported an assertion error even though functional checks passed. | 1 | The old bubble assertion incorrectly forbade the intentional no-instruction WFI wake trap; narrow it to forbid normal retirement effects and allow trap/redirect only while `wfi_wait_q` is active. |
| Timer patch could not create the new `src/periph` parent directory. | 1 | Create the requested module directory explicitly, then reapply the file patch; no partial timer change was made. |
| First timer-owner fabric test changed a still-asserted CPU request while back-pressured, triggering the existing stability assertion. | 1 | Deassert `cpu_req_valid` before changing the observational payload; owner routing is still tested through the timer response. |
| WSL could not execute `build_tests_wsl.sh` directly because its worktree copy has a CRLF shebang (`bash\r`). | 1 | Invoke the script explicitly through `bash`, which does not depend on the shebang. |
| Explicit `bash` still failed because CRLF also corrupts `set -o pipefail`. | 2 | Normalize the WSL shell script to LF before executing it; record this as a build compatibility fix. |
| One knowledge-base patch failed to match a mojibake phase-range dash. | 1 | Split the documentation edit around ASCII-only rows; no partial change from the failed patch. |
| A combined documentation patch failed because one later README context did not match. | 1 | Split unrelated files into separate patches so one stale context cannot block valid edits. |
| Final Phase 3 regression invocation was blocked by Windows script policy. | 1 | Use the documented process-local `Set-ExecutionPolicy ... Bypass` before invoking the runner. |
| CSR-order test omitted the new `wfi_enter_o` observation port. | 1 | Connect the port explicitly and rerun; the focused test passes without the missing-port warning. |
| Vivado source list still referenced deleted `wb_stage.sv`. | 1 | Replace it with `retire_stage.sv`, add `mtime_timer.sv`, and prove the corrected list with successful OOC synthesis. |

## Repository state note

- Worktree: `D:/Rsicv-soc-worktrees/phase2-act4-cleanup`
- Local branch: `codex/phase2-act4-cleanup`
- The local branch began one commit behind its remote; no pull/merge was performed because the remote-only change must first be reviewed and deliberately integrated.
