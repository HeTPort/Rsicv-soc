# Findings

## Phase 4 UART RX start — 2026-08-09

- The pushed TX checkpoint is clean at commit `a2250eb`; RX can evolve as a
  separate reviewable change without rewriting the verified shifter.
- RX cannot use TX-style backpressure at the pin. The receiver must convert an
  asynchronous stream into byte/error events, while a separate FIFO converts
  those events into persistent software-owned data.
- A 16-byte FIFO needs a five-bit occupancy counter (0..16). Explicit pointer
  wrap keeps the parameter contract correct for non-power-of-two depths too.
- Preserving TXDATA `+0x00`, STATUS `+0x04`, and STATUS bits 0/1 avoids an ABI
  break. New RX registers and higher status bits can extend the interface.
- Existing `tb_core_bus_uart` treats local `+0x08` as invalid; that assertion
  must move to a still-unimplemented offset when RXDATA becomes legal.
- `tb_riscv_soc` already owns accelerated UART timing and an independent TX
  pin decoder. It can add an optional RX stimulus/echo mode without creating a
  duplicate SoC testbench or weakening the existing TX-only test.
- `riscv_soc` needs only a new asynchronous `uart_rx_i` top port, local offsets,
  and `RX_FIFO_DEPTH=16` parameter forwarding; the CPU and fabric protocols do
  not change because RX is state inside the existing UART target.
- README is still TX-era and underspecifies Phase 3, WFI, timer, UART tests,
  register semantics, firmware image generation, and exact board boundaries.
  The requested refresh should reorganize it around current architecture,
  executable commands, implemented MMIO, verified evidence, and open gates.
- Final OOC synthesis retains 390 cells in `core_bus_uart`, including a 71-cell
  `uart_rx` and 89-cell `uart_tx`; the broad UART hierarchy query matches 398
  objects. The SoC still retains 32 `RAMB36E1` cells and two LSU-state cells.

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
- UART fits the existing two-bit fabric owner enum exactly as the fourth target.
  Registering `TARGET_UART` on request acceptance is essential: decode may use
  the current CPU address only while idle, but response routing must use the
  accepted target identity until completion.
- `riscv_soc.sv` can expose the serial line without changing the CPU boundary:
  the CPU still sees only `core_bus_req_t/core_bus_rsp_t`; UART timing and
  buffering remain entirely outside the core.
- The end-to-end polling firmware and independent pin decoder prove the full
  chain rather than merely observing internal enqueue events. The expected
  14-byte message completes before `tohost` because firmware polls `TX_BUSY`
  after its final write.
- Vivado retains 67 cells in `core_bus_uart` and 53 in its nested `uart_tx`
  instance (72 cells matched by the broad hierarchy query after optimization),
  with 32 BRAM cells unchanged. UART is therefore not optimized away at the
  SoC output boundary.
- FPGA presence is unnecessary for logical/synthesis closure. Exact board
  clock, reset, UART package pin, bank voltage/IOSTANDARD, and USB-UART path are
  mandatory inputs for the physical gate.
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

## Phase 4 UART start

- The two reviewed external UART examples are packet-oriented teaching designs
  with fixed-length framing, optional CRC/parity, no safe byte ready/valid
  contract, and an incorrect `CLK_FRE/BAUDRATE - 8` divisor. They are not being
  copied into the SoC; their copyright headers also do not state a reuse
  license.
- The APB variant does not match the CPU-local bus, uses misaligned register
  offsets `0/1/2/3`, ignores strobes and invalid-access errors, lacks polling
  ready/busy state, and accepts busy writes unconditionally.
- Accepted architecture: core bus target -> one-byte holding register -> 8N1
  valid/ready shifter -> TX pin.
- A one-byte holding register plus the shifter's active byte provides effective
  two-byte capacity without the control complexity of a general FIFO.
- Board connection is not needed until physical validation. Simulation can
  decode the TX waveform exactly, and OOC synthesis can prove structural
  compatibility before board identity is known.
- `config/soc_map.json` already owns the UART 4 KiB region but defines only the
  timer registers. Adding `uart_txdata` at `+0x00` and `uart_status` at `+0x04`
  will propagate absolute addresses into the generated SystemVerilog/C/sim
  artifacts without hand-maintained constants.
- The generator validates natural alignment and overlap but does not currently
  encode register access permissions. TXDATA write-only and STATUS read-only
  behavior must therefore be normative in the target RTL/specification and
  covered by invalid-direction tests.
- The current fabric is a single-outstanding registered-owner mux with a 2-bit
  owner enum. Timer/RAM/default use three encodings, so UART is the fourth and
  final encoding available without widening the enum.
- The regression runner compiles all sources from `sim/filelist.f` and permits
  a dedicated top per manifest test, so focused UART tests can be added without
  changing the runner.

## Phase 4 UART RX findings

- UART RX is an unsolicited producer: the sender cannot observe CPU
  backpressure, so a FIFO and a specified overrun policy are architectural
  behavior, not optional implementation detail.
- The receiver boundary is split deliberately. `uart_rx.sv` contains the
  two-flop synchronizer and midpoint 8N1 sampler; `core_bus_uart.sv` contains
  the software-visible FIFO, status, sticky errors, and MMIO side effects.
- `RX_FIFO_DEPTH` defaults to 16 and explicit pointer wrapping supports
  non-power-of-two depths. RTL constrains the exposed count to depths 1..255.
- A full FIFO drops the newest arrival and preserves older ordered data. A bad
  stop bit is not enqueued. Both conditions leave sticky software evidence.
- Empty RXDATA reads are legal and nonblocking. Returning zero avoids
  deadlocking the single-outstanding bus, while RX_VALID disambiguates empty
  from a received zero byte.
- Hardware error events take priority over same-cycle W1C. Otherwise software
  could erase an error it never had an opportunity to observe.
- Phase 4 echo verifies more than a register test: a 16-byte stream of real
  8N1 input waveforms traverses synchronization, sampling, the FIFO, polling
  firmware, TX buffering/shifting, and an independent output decoder. The
  focused target test separately fills all 16 FIFO entries.
- Physical-board proof is a later and distinct obligation: exact clock error,
  XDC pins, I/O voltage, reset polarity, and USB-UART crossover are not proven
  by simulation or OOC synthesis.
