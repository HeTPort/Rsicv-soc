/*
 * Illegal-JALR-funct3 precise-trap regression.
 *
 * JALR is legal only with funct3=000. This test executes the JALR opcode with
 * funct3=001 and proves that the core reports a precise illegal-instruction
 * trap without writing the encoded destination register.
 *
 * tohost results:
 *   1 = PASS
 *   2 = execution continued after the illegal instruction
 *   3 = wrong mcause
 *   4 = wrong mepc
 *   5 = wrong mtval
 *   6 = destination register was written
 */

.option norvc
.section .text
.globl _start

.equ TOHOST,          0x1000
.equ DEST_SENTINEL,   0x13579bdf
.equ ILLEGAL_JALR,    0x000010e7

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    li      x1, DEST_SENTINEL

_illegal_jalr:
    /* imm=0, rs1=x0, funct3=001, rd=x1, opcode=JALR. */
    .word   ILLEGAL_JALR

    li      x10, 2
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    li      x9, 2
    bne     x8, x9, _fail_cause

    csrr    x8, mepc
    la      x9, _illegal_jalr
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    li      x9, ILLEGAL_JALR
    bne     x8, x9, _fail_mtval

    li      x9, DEST_SENTINEL
    bne     x1, x9, _fail_rd

    li      x10, 1
    j       _report

_fail_cause:
    li      x10, 3
    j       _report

_fail_mepc:
    li      x10, 4
    j       _report

_fail_mtval:
    li      x10, 5
    j       _report

_fail_rd:
    li      x10, 6

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)

_stop:
    j       _stop
