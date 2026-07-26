# AR-001 Precise CSR Squash Fix

**Implemented:** 2026-07-26

**Branch:** `codex/architecture-review-roadmap`

**RED regression commit:** `fb6bf18`

## Why this change was required

A synchronous exception must be precise: instructions older than the trapping
instruction may complete, while younger instructions must have no architectural
side effects.

The directed test places these two instructions next to each other:

```asm
ecall
csrw mscratch, x7
```

The `csrw` is younger than the `ecall`. It may already be in EX when the trap is
recognized in WB, but it must never change `mscratch`.

Before this fix, `pipe_kill` cleared the younger EX/WB packet's top-level
`valid` bit without clearing `csr.valid`. One cycle later, the top-level CSR
write enable used `csr.valid` by itself, so the invalid packet wrote
`mscratch`.

## RED evidence

The permanent regression consists of:

- [`precise_trap_csr_squash_test.S`](../testdata/precise_trap_csr_squash_test.S)
- [`precise_trap_csr_squash_test.hex`](../testdata/precise_trap_csr_squash_test.hex)
- the `precise_trap_csr_squash` entry in
  [`tests.json`](../sim/regress/tests.json)

The test first writes `0x13579bdf` to `mscratch`, then prepares
`0x2468ace0` for the younger write. Its trap handler checks:

1. `mcause == 11` for an M-mode `ecall`;
2. `mepc` points to the `ecall`;
3. `mtval == 0`;
4. `mscratch` still contains `0x13579bdf`.

Before the RTL change, the simulation completed with `tohost=4`. The failure
code means that the younger CSR write incorrectly replaced the sentinel.

## Root-cause sequence

1. The `ecall` reaches WB and asserts `wb_trap_event`.
2. The adjacent `csrw` is the younger instruction in EX.
3. `core_ctrl` correctly asserts `pipe_kill`.
4. The old safety logic clears only selected fields, leaving `csr.valid=1`.
5. The killed packet enters EX/WB with `valid=0` and stale CSR controls.
6. On the following cycle, the trap event is no longer asserted.
7. The old `wb_csr_we` expression sees `csr.valid=1` and writes `mscratch`.

The trap timing and `pipe_kill` generation were therefore correct. The defect
was incomplete packet invalidation plus a CSR write enable that was not
qualified by the packet's architectural validity.

## Implemented RTL handling

[`riscv.sv`](../src/core/riscv.sv) now applies two independent protections:

```systemverilog
assign wb_csr_we = ex2wb_pkt_out.valid &&
                   ex2wb_pkt_out.csr.valid &&
                   !wb_trap_event;
```

This makes an invalid packet incapable of writing a CSR.

```systemverilog
if (pipe_kill)
  ex2wb_pkt_in_safe = '0;
```

This converts the complete younger packet into a bubble instead of maintaining
a field-by-field kill list that can become incomplete when the packet grows.

Simulation-only immediate assertions also check that:

- an invalid EX/WB packet cannot enable a CSR write;
- `pipe_kill` clears the younger packet's RF, CSR, and memory side-effect
  controls;
- `pipe_kill` suppresses the LSU request.

No change was made to `core_ctrl`, trap timing, `csr_regfile`, or the pipeline
stage count.

## GREEN evidence

Focused regression:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Test precise_trap_csr_squash -Trace
```

Result:

```text
precise_trap_csr_squash PASS
tohost = 0x00000001
Errors: 0, Warnings: 0
```

Full directed smoke regression:

```powershell
./run_regression.ps1 -Tag smoke
```

Result after adding the GPR/store squash coverage: **12/12 passed**, including:

- `precise_trap_csr_squash`;
- `precise_trap_gpr_squash`;
- `precise_trap_store_squash`.

Regression utility unit tests:

```powershell
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Result: **4/4 passed**.

## What this result proves

For the reproduced AR-001 sequences, trap-killed younger instructions cannot
update CSR state, a GPR, or data memory. All three focused tests will run in
every future smoke regression.

This result does not yet prove every Phase 0A side-effect case. Consolidation of
retirement-side-effect ownership and a common invalid-packet assertion remain
open in
[`ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md`](ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md).
