/*
 * AR-004 precise load-access-fault regression.
 *
 * The data target returns rsp_error for address 0x00002000. The faulting load
 * must trap with mcause=5 and mtval=0x00002000, must not write x20, and must
 * squash the adjacent younger GPR write.
 *
 * tohost:
 *   1 = PASS
 *   2 = wrong mcause
 *   3 = wrong mepc
 *   4 = wrong mtval
 *   5 = faulting load or younger instruction changed x20
 *   6 = execution continued after the faulting load
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
    nop
    nop
    li      x6, FAULT_ADDR

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
