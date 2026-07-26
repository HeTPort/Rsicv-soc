/*
 * Precise exception test:
 *
 * The store immediately after ECALL is younger than ECALL.
 * It must be squashed and must not change memory.
 *
 * tohost results:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = younger store was not squashed
 *   5 = mtval was incorrect
 *   6 = execution incorrectly continued after ECALL
 */

.option norvc
.section .text
.globl _start

.equ TOHOST,          0x1000
.equ TEST_ADDRESS,    0x0100
.equ SENTINEL,        0x13579bdf
.equ SQUASHED_VALUE,  0x2468ace0

_start:
    /* Install the exception handler. */
    la      x5, _trap_handler
    csrw    mtvec, x5

    /* Establish a known data-memory value before the exception. */
    li      x6, TEST_ADDRESS
    li      x7, SENTINEL
    sw      x7, 0(x6)
    nop
    nop

    /* Prepare the value for the younger store before taking the trap. */
    li      x8, SQUASHED_VALUE

_ecall_instruction:
    ecall

    /*
     * This single 32-bit instruction is adjacent to and younger than ECALL.
     * It may reach EX/LSU, but it must never issue a memory write.
     */
    sw      x8, 0(x6)

    /* Reaching this code architecturally would also be incorrect. */
    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    /* ECALL from M-mode has cause 11. */
    csrr    x8, mcause
    li      x9, 11
    bne     x8, x9, _fail_cause

    /* The saved PC must identify the ECALL. */
    csrr    x8, mepc
    la      x9, _ecall_instruction
    bne     x8, x9, _fail_mepc

    /* ECALL writes zero to mtval. */
    csrr    x8, mtval
    bne     x8, x0, _fail_mtval

    /*
     * Give the synchronous load enough separation from its comparison so this
     * test isolates store squashing rather than load-use timing.
     */
    lw      x8, 0(x6)
    nop
    nop
    li      x9, SENTINEL
    bne     x8, x9, _fail_store_squash

_pass:
    li      x10, 1
    j       _report

_fail_cause:
    li      x10, 2
    j       _report

_fail_mepc:
    li      x10, 3
    j       _report

_fail_store_squash:
    li      x10, 4
    j       _report

_fail_mtval:
    li      x10, 5

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)

_stop:
    j       _stop
