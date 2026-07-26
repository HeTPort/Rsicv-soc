/*
 * Precise instruction-address-misalignment test for JALR.
 *
 * JALR clears target bit zero, but target bit one remains set. The resulting
 * address is invalid for this IALIGN=32 core and must trap without writing rd.
 *
 * tohost results:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = wrong mtval
 *   5 = destination register was written
 *   6 = execution continued after the misaligned JALR
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
    la      x6, _misaligned_jalr
    addi    x6, x6, 2
    nop
    nop

_misaligned_jalr:
    jalr    x20, 0(x6)

    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    bne     x8, x0, _fail_cause

    csrr    x8, mepc
    la      x9, _misaligned_jalr
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    la      x9, _misaligned_jalr
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
