/*
 * Precise exception test:
 *
 * The CSR write immediately after ECALL is younger than ECALL.
 * It must be squashed and must not change mscratch.
 *
 * tohost results:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = younger CSR write was not squashed
 *   5 = mtval was incorrect
 *   6 = execution incorrectly continued after ECALL
 */

.option norvc
.section .text
.globl _start

.equ TOHOST,         0x1000
.equ SENTINEL,       0x13579bdf
.equ SQUASHED_VALUE, 0x2468ace0

_start:
    /* Install the exception handler. */
    la      x5, _trap_handler
    csrw    mtvec, x5

    /*
     * Put a known value in mscratch.
     * This is an older instruction and must complete before ECALL.
     */
    li      x6, SENTINEL
    csrw    mscratch, x6

    /*
     * Give the setup CSR writes time to retire.
     * These NOPs make this test focus specifically on exception squashing.
     */
    nop
    nop

    /* Value the younger instruction will try to write. */
    li      x7, SQUASHED_VALUE

_ecall_instruction:
    /*
     * ECALL is the synchronous exception.
     * Expected mcause = 11.
     * Expected mepc   = address of this ECALL.
     */
    ecall

    /*
     * This instruction is younger than ECALL.
     * It may enter the pipeline, but it must never modify mscratch.
     */
    csrw    mscratch, x7

    /*
     * Reaching this code architecturally would also be incorrect.
     */
    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    /* Check mcause: ECALL from M-mode is cause 11. */
    csrr    x8, mcause
    li      x9, 11
    bne     x8, x9, _fail_cause

    /* Check mepc points to the ECALL instruction. */
    csrr    x8, mepc
    la      x9, _ecall_instruction
    bne     x8, x9, _fail_mepc

    /* ECALL must write zero into mtval. */
    csrr    x8, mtval
    bne     x8, x0, _fail_mtval

    /*
     * This is the important AR-001 check.
     * The younger csrw must not have replaced SENTINEL.
     */
    csrr    x8, mscratch
    li      x9, SENTINEL
    bne     x8, x9, _fail_csr_squash

_pass:
    li      x10, 1
    j       _report

_fail_cause:
    li      x10, 2
    j       _report

_fail_mepc:
    li      x10, 3
    j       _report

_fail_csr_squash:
    li      x10, 4
    j       _report

_fail_mtval:
    li      x10, 5

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)

_stop:
    j       _stop
