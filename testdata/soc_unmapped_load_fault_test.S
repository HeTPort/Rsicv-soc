/*
 * Phase 2 RED: an unmapped data read must complete as a load access fault.
 * Current riscv_soc routes every address directly to data RAM, so the load
 * succeeds and reports failure code 6 until the decoder/default target exists.
 */
.option norvc
.section .text
.globl _start

.equ TOHOST,      0x8000fffc
.equ FAULT_ADDR,  0x40000000
.equ SENTINEL,    17

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    li      x20, SENTINEL
    li      x6, FAULT_ADDR
    nop
    nop

_faulting_load:
    lw      x20, 0(x6)
    addi    x20, x0, 42

    li      x10, 6
    j       _report

.balign 4
_trap_handler:
    csrr    x8, mcause
    li      x9, 5
    bne     x8, x9, _fail_cause

    csrr    x8, mepc
    la      x9, _faulting_load
    bne     x8, x9, _fail_mepc

    csrr    x8, mtval
    li      x9, FAULT_ADDR
    bne     x8, x9, _fail_mtval

    li      x9, SENTINEL
    bne     x20, x9, _fail_squash

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

_report:
    li      x5, TOHOST
    nop
    nop
    sw      x10, 0(x5)
_stop:
    j       _stop
