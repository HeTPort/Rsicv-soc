/*
 * Precise exception test:
 *
 * The GPR write immediately after ECALL is younger than ECALL.
 * It must be squashed and must not change x20.
 *
 * tohost results:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = younger GPR write was not squashed
 *   5 = mtval was incorrect
 *   6 = execution incorrectly continued after ECALL
 */

.option norvc
.section .text
.globl _start

.equ TOHOST,         0x1000
.equ SENTINEL,       17
.equ SQUASHED_VALUE, 42

_start:
    /* Install the exception handler. */
    la      x5, _trap_handler
    csrw    mtvec, x5

    /*
     * Establish the architectural value that must survive the trap.
     * The handler deliberately does not use x20 for any other purpose.
     */
    li      x20, SENTINEL
    nop
    nop

_ecall_instruction:
    ecall

    /*
     * This single 32-bit instruction is adjacent to and younger than ECALL.
     * It may reach EX, but it must never write x20.
     */
    addi    x20, x0, SQUASHED_VALUE

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

    /* The killed ADDI must not have replaced the sentinel in x20. */
    li      x9, SENTINEL
    bne     x20, x9, _fail_gpr_squash

_pass:
    li      x10, 1
    j       _report

_fail_cause:
    li      x10, 2
    j       _report

_fail_mepc:
    li      x10, 3
    j       _report

_fail_gpr_squash:
    li      x10, 4
    j       _report

_fail_mtval:
    li      x10, 5

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)

_stop:
    j       _stop
