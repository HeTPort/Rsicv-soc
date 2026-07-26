/*
 * Precise instruction-address-misalignment test for JAL.
 *
 * JAL targets PC+2, which is invalid for this IALIGN=32 core. The instruction
 * must trap without redirecting and without writing its destination register.
 *
 * tohost results:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = wrong mtval
 *   5 = destination register was written
 *   6 = execution continued after the misaligned JAL
 */

.option norvc
.section .text
.globl _start

.equ TOHOST,   0x1000
.equ SENTINEL, 0x13579bdf

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    li      x20, SENTINEL
    nop
    nop

_misaligned_jal:
    /*
     * jal x20,+2. Encoding fields:
     *   imm = 2, rd = x20, opcode = 1101111
     */
    .word   0x00200a6f

    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    bne     x8, x0, _fail_cause

    csrr    x8, mepc
    la      x9, _misaligned_jal
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    la      x9, _misaligned_jal
    addi    x9, x9, 2
    bne     x8, x9, _fail_mtval

    li      x9, SENTINEL
    bne     x20, x9, _fail_rd

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

_fail_rd:
    li      x10, 5

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)

_stop:
    j       _stop
