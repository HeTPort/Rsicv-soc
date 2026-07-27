# AR-007 — CSR Legality, WARL, No-Write Semantics, and Dependencies

**Status:** implemented and verified for the current single-hart, M-mode RV32IM
milestone.

**RED checkpoint:** `b29d4c5` (`Add failing AR-007 CSR regressions`)

## Why this work is before the timer and FreeRTOS

FreeRTOS will use the machine trap CSRs to install a handler, enable timer
interrupts, save the interrupted PC, and return from the handler. A CSR bug can
therefore look like a timer, pipeline, context-switch, or kernel bug.

AR-007 closes that ambiguity while the machine still has:

- one privilege mode;
- no asynchronous interrupt input;
- no wait-state data bus;
- a small directed regression suite.

The implementation is deliberately a minimal M-mode contract. It does not add
S-mode, U-mode, delegation behavior, a PLIC, or a complete configurable
privileged architecture merely because those features exist in the RISC-V
specification.

The implementation follows the official RISC-V
[Zicsr instruction semantics](https://docs.riscv.org/reference/isa/v20260120/unpriv/zicsr.html),
[CSR address mapping rules](https://docs.riscv.org/reference/isa/v20260120/priv/priv-csrs.html),
and
[machine-level CSR definitions](https://docs.riscv.org/reference/isa/v20260120/priv/machine.html).

## Implemented CSR contract

The access checker recognizes only the following addresses. An instruction
accessing any other CSR traps as an illegal instruction.

| CSR | Address | Current behavior |
|---|---:|---|
| `mstatus` | `0x300` | MIE and MPIE writable; MPP fixed to M; all other fields read as zero |
| `misa` | `0x301` | legal fixed WARL value `0x4000_1100` (RV32IM) |
| `medeleg` | `0x302` | legal fixed-zero WARL value; no lower privilege mode exists |
| `mideleg` | `0x303` | legal fixed-zero WARL value; no lower privilege mode exists |
| `mie` | `0x304` | MTIE is the only retained bit |
| `mtvec` | `0x305` | direct mode only; BASE is four-byte aligned |
| `mscratch` | `0x340` | full 32-bit read/write state |
| `mepc` | `0x341` | full address except bits 1:0 are zero for IALIGN=32 |
| `mcause` | `0x342` | full 32-bit software write path; trap entry writes the implemented cause |
| `mtval` | `0x343` | full 32-bit read/write state |
| `mip` | `0x344` | no software-writable fields at this milestone; reads zero |
| `mcycle[h]` | `0xB00/0xB80` | writable 64-bit cycle counter split into RV32 low/high halves |
| `minstret[h]` | `0xB02/0xB82` | writable 64-bit retire counter split into RV32 low/high halves |
| `mvendorid` | `0xF11` | read-only zero |
| `marchid` | `0xF12` | read-only zero |
| `mimpid` | `0xF13` | read-only zero |
| `mhartid` | `0xF14` | read-only zero for the single hart |
| `mconfigptr` | `0xF15` | read-only zero |

`mip.MTIP` remains reserved for Phase 3. Ordinary CSR writes already cannot
create or clear pending state. When the timer input is added, the read value and
the same-address bypass value must both compose MTIP from that hardware input
rather than from CSR write data.

## The four concepts in plain language

### 1. CSR legality

A CSR instruction is legal only when:

1. its address is implemented;
2. the current privilege mode is high enough for the address;
3. if the instruction intends to write, the CSR address is not encoded
   read-only.

This core currently executes only in M-mode, so every implemented CSR's minimum
privilege check succeeds. The comparison is still explicit in the access
checker so a future current-privilege register has one clear integration point.

An unimplemented access is not a read of a convenient zero value. It is an
illegal-instruction exception. Similarly, a real write attempt to a read-only
machine identity CSR traps.

### 2. No-write semantics

The instruction encoding, not the numeric source value, determines write
intent:

| Instruction | Does it write the CSR? |
|---|---|
| `CSRRW` / `CSRRWI` | always |
| `CSRRS` / `CSRRC` | only when the encoded `rs1` is not `x0` |
| `CSRRSI` / `CSRRCI` | only when encoded `zimm` is not zero |

This means `CSRRS x5, mvendorid, x0` is a legal read of a read-only CSR, while
`CSRRS x5, mvendorid, x6` is a write attempt even if `x6` happens to contain
zero. `CSRRW x0, mscratch, x0` still writes zero to `mscratch`; `rd=x0`
suppresses the destination read result, not the CSR write.

The pipeline packet now carries an explicit `csr.write` bit so later stages do
not try to reconstruct this distinction from `wdata`.

### 3. WARL behavior

WARL means **Write Any Values, Reads Legal Values**. Software may present any
bit pattern, but the implementation retains and returns only a supported
pattern.

Examples in this core:

- writing all ones to `mstatus` reads back `0x0000_1888`, because only
  MIE/MPIE are stored and MPP is fixed to M;
- writing all ones to `mie` reads back only MTIE (`0x80`);
- writing an address ending in `...3` to `mtvec` or `mepc` reads back the
  address ending in `...0`;
- writing `misa`, `medeleg`, or `mideleg` is legal, but their fixed supported
  values remain visible.

A writable CSR containing read-only or WARL fields is not the same thing as a
read-only CSR address. Unsupported field writes are filtered; they do not
automatically make the instruction illegal.

### 4. Back-to-back CSR dependencies

CSR instructions are atomic read-modify-write operations. A younger operation
to the same address must observe the newest older value.

In this pipeline, the older CSR instruction is in WB while an adjacent younger
CSR instruction is in EX:

```text
cycle N:  older CSR -> WB writes at the clock edge
          younger CSR -> EX reads combinational CSR state before that edge
```

Without handling, EX sees the old register value. AR-007 adds a same-address
WB-to-EX bypass. It forwards the older write's **WARL-filtered effective
value**, because forwarding the raw operand could expose unsupported bits that
will never be stored.

The existing special `mepc`-to-`mret` forwarding now uses this same effective
value, so an adjacent `mret` cannot redirect to stale or unaligned state.

## Problems found and how they were handled

### Source register zero is not source value zero

Testing `wdata == 0` would be wrong. `CSRRS` with `rs1=x6` remains a write
attempt when x6 contains zero, while `rs1=x0` is architecturally no-write. The
decoder records intent directly from instruction bits 19:15.

### Address read-only and field read-only are different

The old regfile treated `misa`, delegation CSRs, and counters as a local
read-only list. That silently ignored writes and did not follow the CSR address
encoding. The new checker uses address bits 11:10 for read-only CSR addresses,
while WARL filtering handles unsupported fields in writable-address CSRs.

### A raw-data bypass would violate WARL

Forwarding an all-ones write to `mstatus` would let the adjacent instruction
observe unsupported bits even though the register stores only `0x1888`. The
regfile now exposes the effective write value, and both state update and bypass
consume that same value.

### RV32 counters need high halves

The pre-AR-007 implementation exposed only 32-bit `mcycle` and `minstret`.
Their state is now 64 bits with `mcycleh` and `minstreth`, while an explicit
write changes the addressed low or high half.

### MTIP must not become software state accidentally

The timer does not exist yet, so `mip` currently reads zero and ignores legal
writes. Phase 3 must source MTIP from the timer comparison signal and keep it
hardware-owned in the normal read path and the bypass path.

## RED evidence

The three regressions were first committed without the RTL fix. Against commit
`b29d4c5`'s parent behavior they produced:

| Test | RED result | Meaning |
|---|---|---|
| `csr_ops_dependency` | FAIL, code 9 | adjacent `csrw`/`csrr` returned stale state |
| `csr_legality_no_write` | FAIL, code 3 | a real `mvendorid` write did not trap |
| `csr_warl` | FAIL, code 2 | unsupported `mstatus` bits were stored |

## GREEN evidence

Focused command:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Test csr_ops_dependency,csr_legality_no_write,csr_warl
```

Result: **3/3 passed**.

Full verification:

```powershell
./run_regression.ps1 -Tag smoke
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Result:

- directed smoke regression: **18/18 passed**;
- regression utility tests: **4/4 passed**.

The permanent tests are:

- [`csr_ops_dependency_test.S`](../testdata/csr_ops_dependency_test.S);
- [`csr_legality_no_write_test.S`](../testdata/csr_legality_no_write_test.S);
- [`csr_warl_test.S`](../testdata/csr_warl_test.S).

## Reusable design principles

1. Carry architectural intent through the pipeline; do not infer it later from
   data values.
2. Make implemented-address legality an explicit allowlist.
3. Separate access legality from legal-value filtering.
4. Put WARL policy next to the state owner and reuse one effective-value
   function for storage and forwarding.
5. Forward the architectural result, not an intermediate operand.
6. Reserve hardware-owned status bits before the hardware source is connected.
7. Use one focused test per failure class, then run the complete regression
   after changing a packed packet type.
