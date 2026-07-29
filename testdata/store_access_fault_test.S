/*
 * AR-004 precise store-access-fault regression.
 *
 * The data target returns rsp_error and suppresses the write at 0x00002000.
 * The store must trap with mcause=7 and mtval=0x00002000, and the adjacent
 * younger GPR write must be squashed.
 *
 * tohost:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = wrong mtval
 *   5 = younger instruction changed x20
 *   6 = execution continued after the faulting store
 */
.option norvc
.section .text
.globl _start

.equ TOHOST,      0x1000
.equ FAULT_ADDR,  0x2000
.equ SENTINEL,    17

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5

    li      x20, SENTINEL
    li      x7, 0x12345678
    li      x6, FAULT_ADDR
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

    li      x9, SENTINEL
    bne     x20, x9, _fail_squash

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
_fail_squash:
    li      x10, 5

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)
_stop:
    j       _stop
