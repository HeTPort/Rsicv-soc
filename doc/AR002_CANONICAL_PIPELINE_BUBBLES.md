# AR-002 Canonical Pipeline Bubble Fix

**Implemented:** 2026-07-26

**Branch:** `codex/architecture-review-roadmap`

## Why this change was required

A pipeline bubble is an invalid instruction slot. The old ID/EX reset and flush
code cleared selected fields one by one. That list predated the CSR, `mret`, and
`wfi` fields, so those fields were omitted.

The current design usually used the packet's top-level `valid` bit to suppress
the stale controls. AR-001 demonstrated why that is too fragile: one consumer
that forgets to qualify a side effect can turn stale metadata into an
architectural update.

The required invariant is stronger:

> Every registered invalid pipeline packet has one complete, known, safe
> representation.

## Problems found while implementing the fix

### 1. Field-by-field clearing did not evolve with the packet

[`id2ex.sv`](../src/core/id2ex.sv) cleared the original RF, ALU, memory, and
exception fields, but not:

- `csr`;
- `is_mret`;
- `is_wfi`.

Adding another packet field would require finding and updating every reset and
flush list. A missed edit would recreate the same defect class.

**Handling:** typed, all-zero bubble constants are defined next to the packet
types in [`riscv_pkg.sv`](../src/core/riscv_pkg.sv). Pipeline registers assign
the complete packet from one constant.

### 2. Fixing only reset and flush was not sufficient

An invalid IF/ID packet still passes through combinational decode. The
instruction bits can produce raw control values even though the decoded
packet's `valid` bit is zero. For example, a NOP is encoded as `addi x0,x0,0`;
decode can therefore produce a raw GPR-write control that is harmless only
because later logic checks `valid`.

If a pipeline register copied that invalid decoded packet verbatim, there would
again be multiple physical representations of a bubble.

**Handling:** IF/ID, ID/EX, and EX/WB normalize every incoming packet with
`valid=0` to their canonical bubble. Reset and flush use the same constants.

### 3. NOP readability conflicted with zero-control invariants

The old flush path wrote `INST_NOP` into the instruction field for easier wave
reading. A NOP is architecturally harmless when valid, but its binary encoding
is not an all-zero packet and it still decodes as an ALU instruction.

**Handling:** the canonical packet is entirely zero. Safety comes from
`valid=0` plus zero side-effect controls, not from choosing a benign
instruction encoding. Waveform readability is less important than having one
unambiguous invalid representation.

### 4. Same-edge assertions would observe the old packet

Pipeline registers use nonblocking assignments at the rising clock edge. An
immediate assertion in another rising-edge process normally samples before
those assignments update the registered packet. Such an assertion can report a
false failure by checking the instruction that was present before the flush.

**Handling:** bubble and effective-side-effect assertions sample on the falling
edge. This is a simple ModelSim-compatible way to inspect the stable result of
the preceding rising-edge update without relying on simulator scheduling
tricks.

### 5. Raw controls and effective side effects are different

A valid instruction is allowed to carry RF, CSR, memory, redirect, or exception
controls. The architectural safety question is whether an invalid instruction
can make any of those controls effective outside its stage.

**Handling:** local assertions prove that invalid registered packets equal the
canonical bubble. Top-level assertions separately prove that:

- an invalid ID/EX packet cannot issue an LSU request or redirect;
- an invalid EX/WB packet cannot write a GPR or CSR, report memory activity,
  enter a trap, or execute `mret`.

This checks both representation and externally visible behavior.

## Implemented changes

[`riscv_pkg.sv`](../src/core/riscv_pkg.sv) defines:

```systemverilog
localparam fetch_pkt_t FETCH_PKT_BUBBLE = '0;
localparam id_ex_pkt_t ID_EX_PKT_BUBBLE = '0;
localparam ex_wb_pkt_t EX_WB_PKT_BUBBLE = '0;
```

[`if2id.sv`](../src/core/if2id.sv),
[`id2ex.sv`](../src/core/id2ex.sv), and
[`ex2wb.sv`](../src/core/ex2wb.sv) use those constants for reset, flush where
applicable, and invalid-input normalization.

[`riscv.sv`](../src/core/riscv.sv) uses `EX_WB_PKT_BUBBLE` for `pipe_kill` and
contains assertions for effective EX and retirement side effects.

## Verification evidence

Focused precise-exception regressions:

```text
precise_trap_csr_squash   PASS
precise_trap_gpr_squash   PASS
precise_trap_store_squash PASS
```

Complete directed regression:

```text
All 12 selected tests passed.
```

Regression utility tests:

```text
Ran 4 tests
OK
```

There were no assertion failures. ModelSim continued to report the known
`vopt-13314` packed-input-port warnings already present in the baseline; this
change introduced no new warning class.

## Reusable principles for future designs

### Make invalid state canonical

Use one representation for an invalid transaction or packet. Normalize invalid
inputs at storage boundaries instead of allowing stale payloads to circulate.
This reduces the number of states every consumer must understand.

### Clear aggregates as aggregates

When a structure is the unit of transfer, reset, flush, and cancellation should
assign the complete structure. Field-by-field safety lists become obsolete as
the structure evolves.

### Gate effects at the final owner

Safe packet contents are defense in depth, not a substitute for valid-qualified
side effects. GPR writes, CSR writes, memory requests, redirects, traps, and
commit records should each have a final enable that includes the instruction's
architectural validity.

### Verify representation and behavior separately

One assertion should check that an invalid packet has the canonical contents.
Another should check that no externally visible effect occurs. Either assertion
alone can miss bugs that the other exposes.

### Sample sequential properties at the correct time

Assertions must reflect clock and simulator scheduling. When using immediate
assertions around nonblocking assignments, sample after the update has settled
or use an equivalent correctly delayed concurrent property.

### Test cancellation at architectural boundaries

Precise-exception tests should distinguish older, trapping, and younger
instructions. Check architectural state—not only internal flush signals—because
the user-visible result is the real contract.

### Establish invariants before adding backpressure

Canonical bubbles and valid-qualified effects should be proven before adding a
wait-state bus, multi-cycle unit, or interrupt deferral. Stalls greatly increase
how long stale controls can remain visible and how often an instruction might
otherwise be repeated.
