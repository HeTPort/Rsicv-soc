/*
 * Phase 2 RED: an unmapped write must return a store access fault and must not
 * modify the data-RAM word that shares its truncated low address bits.
 */
.option norvc
.section .text
.globl _start

.equ TOHOST,        0x8000fffc
.equ DATA_BASE,     0x80000000
.equ FAULT_ADDR,    0x40000000
.equ SENTINEL_DATA, 0x11223344
.equ BAD_DATA,      0x55667788
.equ GPR_SENTINEL,  17

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    li      x5, DATA_BASE
    li      x8, SENTINEL_DATA
    nop
    nop
    sw      x8, 0(x5)

    li      x20, GPR_SENTINEL
    li      x6, FAULT_ADDR
    li      x7, BAD_DATA
    nop
    nop

_faulting_store:
    sw      x7, 0(x6)
    addi    x20, x0, 42

    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    li      x9, 7
    bne     x8, x9, _fail_cause

    csrr    x8, mepc
    la      x9, _faulting_store
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    li      x9, FAULT_ADDR
    bne     x8, x9, _fail_mtval

    li      x9, GPR_SENTINEL
    bne     x20, x9, _fail_squash

    li      x5, DATA_BASE
    lw      x8, 0(x5)
    nop
    nop
    li      x9, SENTINEL_DATA
    bne     x8, x9, _fail_side_effect

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
_fail_squash:
    li      x10, 5
    j       _report
_fail_side_effect:
    li      x10, 7

_report:
    li      x5, TOHOST
    nop
    nop
    sw      x10, 0(x5)
_stop:
    j       _stop
