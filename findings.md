# Findings

## Baseline

- The current synchronous trap decision is constructed directly in `riscv.sv` from `ex2wb_pkt_out`.
- `csr_regfile.sv` currently applies mutually exclusive priority: trap entry, then MRET, then CSR write.
- `wb_csr_wdata_effective` already provides a WARL-filtered preview for same-address CSR and MEPC bypass.
- `core_bus_req_t` and `core_bus_rsp_t` are payload structs; valid/ready signals remain explicit.
- `riscv_soc.sv`, not `riscv.sv`, owns the data fabric and RAM target hierarchy.
- `soc_data_fabric.sv` currently has RAM and default response owners only.
- The pre-change directed smoke baseline is 22/22 passing on 2026-08-09.

## Accepted architecture

- `retire_stage.sv` owns architectural retirement decisions and commands.
- `core_ctrl.sv` owns pipeline movement, kills, flushes, and redirect arbitration.
- `csr_regfile.sv` owns CSR storage, WARL policy, hardware pending-bit composition, and ordered state updates.
- Interrupt eligibility uses a post-retirement CSR context rather than choosing between separate current/effective paths.
- A CSR write and an interrupt trap entry may coexist at the same retirement boundary.
- WFI retires once and then enters a logical wait state.
- SystemVerilog `interface` conversion is deferred; explicit handshakes plus packed payloads remain the standard.

## Remote Phase 3 guide review

- The remote-only `docs/phase3-guide.md` is useful as a requirement checklist but is not an implementation specification.
- It routes the timer through CSR-style signals instead of the accepted `core_bus_req_t`/`core_bus_rsp_t` target contract.
- Its WFI proposal holds a live pipeline WFI instruction, which risks repeated retirement; the accepted design retires WFI once and stores only a logical wait state plus resume PC.
- It makes `interrupt_taken` level-sensitive without a retirement/safe-boundary qualifier.
- It makes `mtimecmp` reset to zero and then latches IRQ until a write. The accepted architectural signal is level-sensitive `mtime >= mtimecmp`; reset policy must avoid an unintended immediate interrupt or document it explicitly.
- It introduces gated clocks and `BUFGCE` in Phase 3. Physical clock gating remains deferred until the logical wait/interrupt protocol is verified and the board clocking boundary is known.
- It proposes a timer read latch that is not the standard software high/low/high consistency sequence and does not provide a full bus response protocol.

## Scope and files

- The generated address constants live in `src/generated/soc_mem_map_pkg.sv`.
- `sim/filelist.f` is the central compile-order list; new packages/types must precede their users, and new modules must precede `riscv.sv`/`riscv_soc.sv`.
- The required living documents are `doc/PROJECT_KNOWLEDGE_BASE.md`, `doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md`, a focused `doc/AR*.md` report, diagrams/risk tables, and `TODO.md` when phase status or gates change.

## Retirement/control audit

- `wb_stage.sv` already computes the final RF write data, while `riscv.sv` independently reconstructs CSR, trap, MRET, and commit behavior. The extraction should replace this split with `retire_stage.sv`, then remove or narrow `wb_stage.sv` to avoid two retirement owners.
- `commit_order_q` currently increments for every valid EX/WB packet, including synchronous trapped instructions; the public commit packet reports those with `valid=1, trap=1`.
- The current `pipe_kill` is exactly the retirement trap redirect, so expanding the retirement redirect to include interrupts naturally reuses the precise younger-instruction kill path.
- `core_ctrl.sv` has an unused `wb_trap_event` input and several observation ports retained from earlier control logic. Cleanup should occur only after the new contract is stable.
- Decode recognizes WFI and carries `is_wfi` into ID/EX, but `ex_wb_pkt_t` does not currently carry it; execute therefore drops the semantic marker before retirement.
- `pc4_data` is not sufficient as the interrupt resume PC for a retiring taken branch or jump. Add explicit `next_pc`: resolved target for taken control flow, otherwise `pc + 4`; suppress interrupt entry on the MRET boundary initially.
- `MIP` WARL policy already makes software writes produce zero, matching the future hardware-owned MTIP rule. The missing work is composing `irq_mti_i` into reads and the retirement preview without storing software MTIP state.

## Phase 1 evidence

- Baseline smoke: 22/22 GREEN before RTL changes.
- Focused retirement contract: expected RED because `retire_stage.sv` did not yet exist. This distinguishes the new contract from accidental reuse of the old scattered WB logic.
- The semantic signal specification is now the normative naming, ownership, packet, retirement, CSR, redirect, bus, and timer contract for Phase 3.

## Phase 2 evidence and principles

- The focused `retire_stage` test is GREEN for normal RF retirement, synchronous trap suppression, typed trap redirect, CSR preview/commit, and commit observation.
- The complete smoke suite remains 22/22 GREEN after moving retirement behavior.
- `retire_stage.sv` now owns final RF command selection, CSR retirement commands, synchronous trap entry/redirect, MRET/instret commands, and commit construction.
- `wb_stage.sv` became an uninstantiated second description of the same architectural boundary and was removed. Guiding principle: after a behavior-preserving extraction is verified, remove the superseded owner rather than retaining two sources of truth.
- `ex_wb_pkt_t` now carries `next_pc` and `is_wfi`; adding instruction semantics at the registered retirement boundary prevents top-level reconstruction from transient EX signals.

## Phase 3 evidence and principles

- Focused CSR/retirement ordering is GREEN for WARL-effective `mtvec`, effective `mie`, same-boundary `mstatus.MIE` enable plus interrupt, MRET exclusion, same-boundary `mtvec` update plus interrupt, and pending-interrupt masking by a retiring `mie` clear.
- Smoke remains 22/22 GREEN with the hardware IRQ tied inactive.
- CSR preview is a read-only projection, while `csr_retire_cmd_t` is the clocked state-changing contract. Separating preview from commit avoids a combinational loop while keeping WARL policy in one module.
- CSR write and asynchronous trap are independent valid bits, not enum alternatives. Ordered update is instruction write first, then trap-owned fields; this preserves retirement while giving trap entry final ownership of `mepc`, `mcause`, `mtval`, and MIE/MPIE.
- `mip.MTIP` is composed from the hardware level on reads and in `csr_irq_context_t`; software `mip` writes remain WARL-zero and cannot forge or clear MTIP.

## Phase 4 evidence and principles

- The focused retirement test is GREEN for ordinary interrupt entry, synchronous-exception priority, MRET same-boundary exclusion, one-time WFI retirement, logical wait, and later WFI wake without a second commit or `instret` increment.
- A full-core RV32IM compile/run remains GREEN after adding the interrupt port and WFI control path.
- WFI entry is a pipeline-kill event without a redirect; WFI wake is an interrupt trap/redirect without an instruction retirement. Treating these as distinct semantic events prevents duplicate retirement and preserves the saved resume PC.
- `core_ctrl.sv` now consumes only signals that affect pipeline movement. Unused WB observations and memory-intent ports were removed after the retirement contract stabilized.
- Physical clock gating remains deferred. Logical wait is sufficient to verify architectural behavior without creating a clock-domain or wakeup dependency.

## Phase 5 evidence and principles

- `mtime_timer.sv` is a one-cycle registered `core_bus_req_t`/`core_bus_rsp_t` target. It accepts only aligned RV32 word accesses to local `mtimecmp` offsets `0x4000/0x4004` and `mtime` offsets `0xBFF8/0xBFFC`; unsupported accesses are side-effect-free errors.
- `mtimecmp` resets to all ones, preventing an immediate reset-time interrupt. MTIP is the live comparison `mtime >= mtimecmp`, not a sticky pulse.
- Timer-target focused verification is GREEN for reset, tick division, reads, comparison crossing, MTIP deassertion during the safe RV32 update sequence, registered response lifetime, and invalid-access behavior.
- The fabric now registers three response owners: timer, RAM, and default. Focused fabric verification is GREEN for full-address timer decode, base subtraction to local `0x4000`, retained response ownership, and existing RAM/default cases.
- SoC timer/WFI firmware is GREEN for exact `mepc`, timer `mcause`, zero `mtval`, MIE/MPIE entry/return behavior, one WFI retirement, and MRET return.
- The long SoC test serviced 10,000 timer interrupts and returned correctly within its 1,500,000-cycle gate.
- Guiding principle: 64-bit timer atomicity on RV32 is a software-visible register-update protocol, not a fabricated hidden 64-bit bus transaction. The peripheral supplies ordinary word semantics and level-sensitive comparison.

## Phase 6 closure

- Final focused retirement, CSR-order, timer, and fabric tests are GREEN.
- Final end-to-end results are precise timer/WFI PASS, 10,000 interrupts PASS,
  22/22 smoke PASS, 4/4 SoC fault PASS, 4/4 Python utilities PASS, and the
  regression classifier PASS.
- The OOC synthesis source list must evolve with module ownership. Replacing
  deleted `wb_stage.sv` with `retire_stage.sv` and adding `mtime_timer.sv`
  produced a Vivado 2019.2 PASS with 0 errors, 0 critical warnings, 32
  `RAMB36E1`, and retained LSU/retirement/timer hierarchy.
- The OOC result does not authorize physical clock gating or claim exact-board
  timing closure; both require the later board clock/reset/XDC boundary.
