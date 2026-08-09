# Phase 3 Guide — Precise Machine Timer Interrupts

**Status:** Implemented and verified on 2026-08-09.

This guide is the short implementation map. Detailed rationale, rejected
options, problems, consequences, and evidence are recorded in
[`../doc/AR008_PRECISE_MACHINE_TIMER_INTERRUPTS.md`](../doc/AR008_PRECISE_MACHINE_TIMER_INTERRUPTS.md).
Normative signal meanings and future interface rules are in
[`../doc/SEMANTIC_SIGNAL_SPEC.md`](../doc/SEMANTIC_SIGNAL_SPEC.md).

## Implemented ownership

| Concern | Owner |
|---|---|
| Architectural retirement, IRQ choice, WFI state, final RF/CSR commands, commit | `src/core/retire_stage.sv` |
| CSR storage, WARL preview, MTIP composition, ordered state update | `src/core/csr_regfile.sv` |
| Hazard/stall/flush/kill and redirect movement | `src/core/core_ctrl.sv` |
| Timer registers and MTIP comparison | `src/periph/mtime_timer.sv` |
| Full-address decode, local translation, registered response owner | `src/bus/soc_data_fabric.sv` |
| CPU/timer/fabric/RAM composition | `src/riscv_soc.sv` |

## Architectural flow

```text
ex_wb_pkt_t
    |
    v
retire_stage -- csr_write_req_t --> csr_regfile preview/WARL
    ^                                  |
    |--------- csr_irq_context_t -------|
    |
    +-- rf_write_cmd_t ----------> regfile
    +-- csr_retire_cmd_t --------> csr_regfile state update
    +-- redirect_t --------------> core_ctrl
    +-- commit_pkt_t ------------> verification
    +-- trap_entry_t ------------> verification
```

Interrupt eligibility uses the effective post-retirement context:

```text
mstatus.MIE && mie.MTIE && mip.MTIP
```

A synchronous exception wins over an interrupt. MRET excludes an interrupt on
the same retirement boundary. An incomplete LSU/divider operation asserts
interrupt deferral.

## WFI

WFI retires once and saves `next_pc`. The younger pipeline is killed and the
core enters a logical wait state. A later eligible interrupt creates trap entry
without another commit or `minstret` increment. Physical clock gating is not
part of Phase 3 and remains a later FPGA/power task.

## Timer register target

The fabric decodes `0x0200_0000..0x0200_FFFF` and subtracts the base before
forwarding the request.

| Full address | Timer-local offset | Meaning |
|---:|---:|---|
| `0x0200_4000` | `0x4000` | `mtimecmp[31:0]` |
| `0x0200_4004` | `0x4004` | `mtimecmp[63:32]` |
| `0x0200_BFF8` | `0xBFF8` | `mtime[31:0]` |
| `0x0200_BFFC` | `0xBFFC` | `mtime[63:32]` |

The target uses `req_valid`, `req_ready`, `core_bus_req_t`, `rsp_valid`, and
`core_bus_rsp_t`. It returns one registered response. Only aligned word accesses
are supported in this milestone.

`irq_mti` is the level `mtime >= mtimecmp`. It is not cleared by writing `mip`.
RV32 software safely replaces `mtimecmp` by writing low=`0xFFFF_FFFF`, then the
new high word, then the final low word.

## Verification

```powershell
Set-Location D:\Rsicv-soc-worktrees\phase2-act4-cleanup\sim
vsim -c -do run_retire_stage.do
vsim -c -do run_csr_retire_order.do
vsim -c -do run_mtime_timer.do
vsim -c -do run_soc_data_fabric.do

Set-Location .\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run_regression.ps1 -Manifest .\phase3_tests.json -Test soc_timer_wfi
.\run_regression.ps1 -Manifest .\phase3_tests.json -Test soc_timer_10k
.\run_regression.ps1 -Tag smoke
```

Verified results:

- precise timer/WFI case: PASS;
- repeated timer/WFI/MRET case: 10,000 interrupts PASS;
- legacy smoke: 22/22 PASS;
- Phase 2 SoC fault cases: 4/4 PASS.
- Vivado 2019.2 OOC synthesis: PASS with 0 errors, 0 critical warnings, and
  32 retained `RAMB36E1` cells.

## Next phases

- Phase 4: polling UART TX and GPIO targets using the same bus contract.
- Phase 5: startup, linker, and bare-metal driver stack.
- Phase 6: official FreeRTOS RISC-V port and periodic scheduler tick.
- Phase 7: exact-board clock/reset/XDC work; consider safe FPGA clock gating
  only after the physical clocking design is known.
