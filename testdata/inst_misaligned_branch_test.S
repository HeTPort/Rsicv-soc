/*
 * Precise instruction-address-misalignment test for conditional branches.
 *
 * A not-taken branch with a misaligned encoded target must not trap.
 * A taken branch to PC+2 must trap because this core implements IALIGN=32.
 *
 * tohost results:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = wrong mtval
 *   5 = not-taken branch did not execute normally
 *   6 = execution continued after the taken misaligned branch
 */

.option norvc
.section .text
.globl _start

.equ TOHOST, 0x1000

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    /* Records that the not-taken case completed normally. */
    li      x20, 0
    nop
    nop

_not_taken_branch:
    /*
     * bne x0,x0,+2: the encoded target is misaligned, but the branch is not
     * taken and therefore must not raise an exception.
     */
    .word   0x00001163
    li      x20, 1

_taken_branch:
    /*
     * beq x0,x0,+2: this branch is taken. Target = _taken_branch + 2, which
     * violates IALIGN=32 and must trap on this instruction.
     */
    .word   0x00000163

    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    bne     x8, x0, _fail_cause

    csrr    x8, mepc
    la      x9, _taken_branch
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    la      x9, _taken_branch
    addi    x9, x9, 2
    bne     x8, x9, _fail_mtval

    li      x9, 1
    bne     x20, x9, _fail_not_taken

_pass:
    li      x10, 1
    j       _report

_fail_cause:
    li      x10, 2
    j       _report

_fail_mepc:
    li      x10, 3
    j       _report

_fail_mtval:
    li      x10, 4
    j       _report

_fail_not_taken:
    li      x10, 5

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)

_stop:
    j       _stop
