# AR-006 Precise Control-Flow Misalignment Fix

**Implemented:** 2026-07-26

**Branch:** `codex/architecture-review-roadmap`

**RED regression commit:** `f10cf31`

## Architectural requirement

This core implements RV32IM without the compressed-instruction extension, so
`IALIGN=32`: every instruction address must be four-byte aligned.

For conditional branches, the target is checked only when the branch is taken.
For JAL and JALR, the resolved target is always checked. JALR first clears
target bit zero as required by the ISA; bit one must still be zero for this
core.

A misaligned control transfer must:

- report instruction-address-misaligned cause `0`;
- write the faulting branch/jump PC to `mepc`;
- write the resolved misaligned target to `mtval`;
- suppress the redirect;
- suppress JAL/JALR destination-register writeback;
- squash younger instructions when the trap reaches WB.

## RED evidence

Three directed tests were added:

- [`inst_misaligned_branch_test.S`](../testdata/inst_misaligned_branch_test.S)
  covers both a not-taken branch with a misaligned encoded target and a taken
  branch to `PC+2`;
- [`inst_misaligned_jal_test.S`](../testdata/inst_misaligned_jal_test.S)
  executes `jal x20,+2` and verifies that `x20` keeps its sentinel;
- [`inst_misaligned_jalr_test.S`](../testdata/inst_misaligned_jalr_test.S)
  first proves that a raw bit-zero-only target is masked and executes normally,
  then resolves a target with bit one set and verifies that `x20` is unchanged.

Before the RTL fix, all three failed. The trace showed:

- the branch/JAL/JALR committed with `trap=0`;
- JAL and JALR wrote their link register;
- the core redirected to a `PC+2` address;
- the testbench then reported PC/instruction mismatch errors because the word
  memory silently discarded the low address bits.

The architectural defect was failure to trap before redirect. The subsequent
memory aliasing errors were only a symptom.

## Problems found and handling decisions

### 1. The trap cause existed but had no producer

`MCAUSE_INST_MISALIGNED` was already defined in
[`riscv_pkg.sv`](../src/core/riscv_pkg.sv), but execute never generated it.

**Handling:** execute now produces an explicit `instr_misaligned` result and
carries it in the EX/WB packet.

### 2. Target calculation was mixed into redirect side effects

Branch, JAL, and JALR each calculated and drove their target inside redirect
logic. That made it difficult to inspect the target before the redirect became
effective.

**Handling:** [`execute.sv`](../src/core/execute.sv) now has one resolved
control-transfer path:

```text
compute candidate target
        |
check whether transfer occurs
        |
validate target against IALIGN
        |
trap OR redirect
```

The same `control_target` is used for redirect and `mtval`, preventing those
values from diverging.

### 3. A conditional branch target is not always architecturally observed

The immediate encoding can describe a misaligned address even when the branch
condition is false. That must not trap.

**Handling:** `control_transfer` is asserted for a branch only when
`branch_taken` is true. The not-taken directed case proves normal sequential
execution.

### 4. JALR has a two-step target rule

JALR computes `rs1 + imm` and then clears bit zero. Checking the raw sum would
incorrectly trap a target whose only set low bit was bit zero.

**Handling:** the alignment check uses the post-mask JALR target
`{eff_addr[AW-1:1], 1'b0}`. With `IALIGN=32`, bit one must still be zero.

### 5. The instruction must trap without becoming a bubble

The faulting instruction is architecturally observed as a trap and therefore
travels to WB with `valid=1`. Clearing the complete packet in EX would lose
`mepc`, `mcause`, and `mtval`.

**Handling:** execute suppresses redirect and RF writeback but retains a valid
trap packet. WB performs precise trap entry and kills only younger packets.

### 6. Alignment was initially a literal bit slice

A direct `[1:0]` test works today but hides the implemented ISA contract.

**Handling:** `riscv_pkg.sv` defines `IALIGN_BITS=32` and derives
`IALIGN_LSB`. Target checks and assertions use that named configuration.

## Assertions

Simulation checks verify that an instruction-misaligned EX result:

- does not redirect;
- does not request a redirect flush;
- does not write a GPR;
- carries cause `MCAUSE_INST_MISALIGNED`;
- carries a genuinely misaligned `mtval`.

The existing precise-trap and canonical-bubble assertions continue to check
younger side-effect suppression.

## GREEN evidence

Focused regression:

```text
inst_misaligned_branch PASS
inst_misaligned_jal    PASS
inst_misaligned_jalr   PASS
```

The commit trace reports each faulting instruction with `trap=1`, cause `0`,
and `rd_we=0`. Each handler independently verifies `mcause`, `mepc`, `mtval`,
and the relevant architectural sentinel.

Complete directed regression:

```text
All 15 selected tests passed.
```

Regression utility tests:

```text
Ran 4 tests
OK
```

There were no assertion failures and no new warning class.

## Reusable design principles

1. Compute a candidate result before enabling its side effect.
2. Validate the exact architecturally resolved value, not an intermediate.
3. Conditional operations raise conditional faults only when they occur.
4. Carry trap metadata with the faulting transaction to the retirement owner.
5. A faulting instruction is valid but side-effect-suppressed; it is not the
   same thing as a bubble.
6. Name architectural assumptions such as `IALIGN` instead of hiding them in
   bit slices.
7. Verify the architectural record (`mepc`, `mcause`, `mtval`, registers), not
   only internal redirect signals.
