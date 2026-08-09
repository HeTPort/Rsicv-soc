# AR-008 — Precise Machine-Timer Interrupt Retirement

**Status:** Implemented and verified

**Phase:** 3

**Date:** 2026-08-09

## 1. Problem

The pre-Phase-3 core supported synchronous exceptions but had no architectural
boundary for asynchronous interrupts. Trap decisions, CSR writes, register
writeback, MRET, and commit construction were distributed between `riscv.sv`,
`wb_stage.sv`, and `csr_regfile.sv`.

Adding a level-sensitive timer interrupt directly to the old logic would leave
several questions unanswered:

- Which PC becomes `mepc` after a retiring branch or jump?
- Does a CSR instruction that enables an interrupt commit before trap entry?
- Can trap priority silently discard a simultaneous CSR write?
- Can an interrupt kill an LSU/divider operation that already owns multi-cycle
  state?
- Does WFI retire once, or remain as a live packet and retire repeatedly?
- How is asynchronous trap entry observed without pretending that the retiring
  instruction synchronously faulted?

## 2. Root cause

The design had useful individual mechanisms but no single semantic owner for
architectural retirement. In particular:

1. `riscv.sv` independently reconstructed synchronous traps and CSR writes.
2. `wb_stage.sv` independently selected final GPR effects.
3. `csr_regfile.sv` used mutually exclusive `trap > mret > csr_write` priority.
4. `ex_wb_pkt_t` carried the current PC but not the resolved architectural
   `next_pc` or WFI marker.
5. The SoC fabric had only RAM/default owners and therefore could not retain a
   timer response owner.

The core needed an explicit architectural boundary before it needed more
control wires.

## 3. Options considered

### 3.1 Take interrupts in EX

Advantages:

- early redirect;
- easy reuse of branch redirect logic.

Rejected because EX does not prove that the instruction has retired, cannot
naturally preserve an older CSR write, and may observe an accepted younger
transaction. It also makes the correct resume PC after control flow harder to
state.

### 3.2 Treat interrupts as synthetic synchronous exceptions

Advantages:

- reuses the existing trap packet and commit `trap` bit.

Rejected because an interrupt is not caused by the retiring instruction. The
instruction normally commits; the interrupt occurs after it. Marking that
instruction as faulting would suppress valid effects and falsify the commit
trace.

### 3.3 Stall a live WFI pipeline packet

Advantages:

- few new registers.

Rejected because the same valid packet can be observed at the retirement
boundary repeatedly, duplicating `minstret`, commit order, or other effects.

### 3.4 Add a retirement owner and post-retirement CSR preview

Advantages:

- one precise boundary;
- explicit synchronous/interrupt priority;
- CSR write and asynchronous trap can coexist;
- WFI can retire once and leave a small logical state;
- verification receives separate instruction commit and trap-entry records.

Selected.

## 4. Decision

### 4.1 Retirement ownership

`retire_stage.sv` is the sole owner of:

- final GPR write commands;
- CSR preview requests and retirement commands;
- synchronous exception selection;
- machine-timer interrupt selection;
- MRET/`minstret` retirement commands;
- WFI logical wait state;
- retirement redirect generation;
- architectural instruction commit construction; and
- separate trap-entry observation.

`wb_stage.sv` was removed after the behavior-preserving extraction passed the
complete smoke regression.

### 4.2 Semantic contracts

The implementation adds:

- `rf_write_cmd_t`;
- `csr_write_req_t`;
- `csr_irq_context_t`;
- `csr_retire_cmd_t`;
- `trap_entry_t`;
- `redirect_t`; and
- `redirect_reason_e`.

The normative definitions and future naming/packing rules are in
[`SEMANTIC_SIGNAL_SPEC.md`](SEMANTIC_SIGNAL_SPEC.md).

### 4.3 Post-retirement CSR context

`csr_regfile.sv` receives a raw retiring CSR preview request and produces:

```text
effective mstatus
effective mie
hardware-composed mip
effective mtvec
```

Eligibility is:

```text
effective_mstatus.MIE && effective_mie.MTIE && effective_mip.MTIP
```

`mtvec` is carried in the same context because it supplies the selected trap
target, not because it participates in eligibility.

The preview and command paths are separate to avoid a combinational loop:

```text
ex_wb_pkt
    |
    v
retire_stage --raw preview--> csr_regfile WARL/context
    ^                              |
    |------------------------------|
    |
    +--clocked csr_retire_cmd------> csr_regfile state
```

The raw preview request is never gated by the interrupt decision. Therefore the
context can determine whether the retiring instruction enables, disables, or
redirects the pending interrupt.

### 4.4 Ordered CSR write and interrupt entry

`csr_retire_cmd_t` contains independent CSR-write and trap-entry validity.
When both are asserted:

1. the instruction CSR write is applied with normal WARL behavior;
2. interrupt entry then overwrites the trap-owned fields;
3. `MPIE` records the effective post-write `MIE`;
4. `MIE` becomes zero;
5. `mepc` receives the retiring instruction's `next_pc`;
6. `mcause` receives `0x8000_0007`; and
7. `mtval` receives zero.

This ordering also means:

- a retiring `mie` clear can mask pending MTIP;
- a retiring `mstatus.MIE` set can permit immediate interrupt entry; and
- a retiring `mtvec` write supplies the new interrupt vector.

### 4.5 Resume PC

`ex_wb_pkt_t.next_pc` means the architectural instruction that would execute
next if no interrupt were taken:

- sequential instruction: `pc + 4`;
- taken branch/JAL/JALR: resolved target;
- WFI: sequential PC saved before logical wait.

MRET retains its existing EX redirect plus retirement CSR-state restoration.
Interrupt selection is suppressed on the MRET retirement boundary and
reevaluated at the next safe boundary.

### 4.6 Multi-cycle deferral

`irq_defer_i` prevents interrupt selection while the LSU or divider owns an
incomplete multi-cycle operation. This is necessary even if an older packet is
visible at WB: taking that interrupt could otherwise kill a younger operation
after an external request was accepted.

The interrupt becomes eligible again when the owning operation reaches its
normal completion boundary.

### 4.7 WFI

WFI behavior is:

1. retire WFI once and increment `minstret` once;
2. save `next_pc`;
3. kill younger pipeline packets without redirecting;
4. retain only `wfi_wait_q` and the saved PC;
5. stall pipeline movement logically;
6. when an interrupt becomes eligible, generate trap entry with no instruction
   commit or extra `minstret`; and
7. clear wait and redirect to the effective `mtvec`.

Physical clock gating is explicitly deferred. Logical wait proves the
architectural protocol without adding FPGA clock-control or wakeup-domain risk.

### 4.8 Timer target

`mtime_timer.sv` is a normal registered CPU-local bus target.

| Local byte offset | Register word |
|---:|---|
| `0x4000` | `mtimecmp[31:0]` |
| `0x4004` | `mtimecmp[63:32]` |
| `0xBFF8` | `mtime[31:0]` |
| `0xBFFC` | `mtime[63:32]` |

The SoC fabric decodes full addresses in the accepted timer window and
subtracts `SOC_TIMER_BASE`. The timer never compares full SoC addresses.

The target:

- accepts aligned RV32 word accesses only;
- returns one registered response for each accepted request;
- returns side-effect-free errors for unsupported accesses;
- resets `mtime` to zero and `mtimecmp` to all ones;
- increments according to `TICK_CYCLES`; and
- asserts MTIP as the level `mtime >= mtimecmp`.

RV32 software updates `mtimecmp` safely by writing low=`0xFFFF_FFFF`, then the
new high word, then the new low word. The hardware does not invent a hidden
64-bit transaction that the bus cannot represent.

### 4.9 Fabric response ownership

The registered fabric owner enum now contains:

```text
TARGET_TIMER
TARGET_DATA_RAM
TARGET_DEFAULT
```

The owner is selected only when the CPU request transfers. It remains
registered until the selected target responds, so a changing or new live CPU
address cannot redirect an old response.

## 5. Consequences

### Positive

- Precise asynchronous interrupt semantics now have one owner.
- CSR bypass, WARL preview, interrupt eligibility, and committed state share
  one policy.
- WFI cannot retire more than once.
- Timer, RAM, and default targets use the same bus contract.
- The top-level wire count is reduced by semantic packet boundaries rather than
  a generic control bundle.
- The commit stream remains truthful: normal instructions followed by an IRQ
  are normal commits, while `trap_entry_t` reports the asynchronous event.

### Costs

- The CSR preview creates a combinational path from EX/WB through WARL/context
  generation back to retirement interrupt selection.
- `retire_stage.sv` has clocked state for order and WFI, so it is more than a
  pure mux.
- The timer exposes only word accesses in this milestone; byte/halfword MMIO
  accesses return errors.
- Physical clock power is unchanged until a later FPGA clock-gating phase.

## 6. Problems encountered and resolutions

| Problem | Root cause | Resolution / principle |
|---|---|---|
| A legacy encoded comment prevented one large patch from matching. | Large mechanical patch depended on non-ASCII context. | Use small ASCII-anchored semantic edits; failed patch made no source change. |
| First WFI run reported a bubble assertion. | The old assertion assumed every trap requires a live instruction. | Distinguish instruction retirement from WFI wake trap entry. |
| First timer-owner test changed a valid stalled request. | Testbench violated the stable-request protocol. | Fix stimulus; never weaken a correct protocol assertion to accommodate an invalid test. |
| WSL test builder failed at `bash\r` and `pipefail\r`. | Windows CRLF checkout made the Linux script non-executable. | Normalize the WSL script to LF and preserve that executable format. |
| Initial timer file patch could not create a missing directory. | The new real peripheral category did not yet exist. | Create `src/periph` only when the phase supplies a real implemented interface. |

## 7. Verification evidence

| Verification | Result |
|---|---|
| Pre-change smoke baseline | 22/22 PASS |
| Focused retirement contract | PASS |
| Focused CSR post-retirement ordering | PASS |
| Focused timer target protocol/register behavior | PASS |
| Focused three-owner fabric routing | PASS |
| Precise SoC timer/WFI firmware | PASS |
| Repeated timer interrupt/MRET/WFI stress | 10,000 interrupts PASS |
| Final directed smoke regression | 22/22 PASS |
| Phase 2 SoC access-fault regression | 4/4 PASS |
| ELF/import Python utilities | 4/4 PASS |
| Vivado 2019.2 OOC SoC synthesis | PASS; 0 errors, 0 critical warnings, 32 `RAMB36E1`, timer and retirement hierarchy retained |

Key commands:

```powershell
Set-Location D:\Rsicv-soc-worktrees\phase2-act4-cleanup\sim
vsim -c -do run_retire_stage.do
vsim -c -do run_csr_retire_order.do
vsim -c -do run_mtime_timer.do
vsim -c -do run_soc_data_fabric.do

Set-Location .\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run_regression.ps1 -Tag smoke
.\run_regression.ps1 -Manifest .\soc_red_tests.json -Tag soc
.\run_regression.ps1 -Manifest .\phase3_tests.json -Test soc_timer_wfi
.\run_regression.ps1 -Manifest .\phase3_tests.json -Test soc_timer_10k
python -m unittest test_elf_to_mem.py test_import_act4.py

Set-Location ..\synth
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\check_riscv_soc_ar003.tcl
```

## 8. Long-term guiding principles

1. **Retirement is an architectural boundary, not a collection of WB wires.**
2. **A post-instruction interrupt preserves that instruction's normal effects.**
3. **Preview must not be decision-gated.** Otherwise enabling/disabling CSR
   writes cannot influence the decision without a loop.
4. **State-owner policy stays with the state owner.** WARL rules are not copied
   into retirement logic.
5. **Events and levels are different contracts.** MTIP is a persistent level;
   trap entry is a one-cycle event.
6. **WFI is retired state plus a wait record, not a stalled instruction.**
7. **A protocol test must obey the protocol it is testing.** Never fix a valid
   assertion by weakening it around invalid stimulus.
8. **Full addresses belong to the fabric; local offsets belong to targets.**
9. **Registered owner identity is part of the response transaction.**
10. **Clock gating is an implementation layer.** Prove logical sleep/wake first.
