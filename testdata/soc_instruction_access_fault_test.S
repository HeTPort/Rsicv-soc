/*
 * Phase 2 RED: an aligned fetch immediately above the 64 KiB instruction RAM
 * must trap with instruction access fault cause 1 and mtval equal to its PC.
 * Current prog_ram substitutes EBREAK because the core has no fetch-error path.
 */
.option norvc
.section .text
.globl _start

.equ TOHOST,    0x8000fffc
.equ FAULT_PC,  0x00010000

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    li      x6, FAULT_PC
    nop
    nop
    jalr    x0, 0(x6)

    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    li      x9, 1
    bne     x8, x9, _fail_cause

    csrr    x8, mepc
    li      x9, FAULT_PC
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    li      x9, FAULT_PC
    bne     x8, x9, _fail_mtval

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

_report:
    li      x5, TOHOST
    nop
    nop
    sw      x10, 0(x5)
_stop:
    j       _stop
