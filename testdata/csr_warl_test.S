/*
 * AR-007 CSR WARL regression for the minimal M-mode FreeRTOS contract.
 *
 * Implemented state:
 *   mstatus: MIE, MPIE, and MPP; MPP is fixed to M-mode
 *   mie:     MTIE only
 *   mip:     no software-writable bits; future MTIP is hardware-owned
 *   mtvec:   direct mode, 4-byte-aligned base
 *   mepc:    IALIGN=32, therefore 4-byte aligned
 *   misa:    fixed RV32IM value
 *   medeleg/mideleg: fixed zero because no lower privilege mode exists
 *
 * tohost:
 *   1 = PASS
 *   2 = mstatus WARL behavior wrong
 *   3 = mie WARL behavior wrong
 *   4 = mip software-write filtering wrong
 *   5 = mtvec WARL behavior wrong
 *   6 = mepc WARL behavior wrong
 *   7 = misa fixed-value behavior wrong
 *   8 = delegation CSR fixed-zero behavior wrong
 */
.option norvc
.section .text
.globl _start

.equ TOHOST,        0x1000
.equ MSTATUS_MASK,  0x00001888
.equ MSTATUS_MPP_M, 0x00001800
.equ MIE_MTIE,      0x00000080
.equ MISA_RV32IM,   0x40001100

_start:
    /* Unsupported mstatus fields are discarded; MPP is fixed at M-mode. */
    li      x5, -1
    csrw    mstatus, x5
    csrr    x6, mstatus
    li      x7, MSTATUS_MASK
    bne     x6, x7, _fail_mstatus

    csrw    mstatus, x0
    csrr    x6, mstatus
    li      x7, MSTATUS_MPP_M
    bne     x6, x7, _fail_mstatus

    /* Only machine-timer interrupt enable is retained for this milestone. */
    li      x5, -1
    csrw    mie, x5
    csrr    x6, mie
    li      x7, MIE_MTIE
    bne     x6, x7, _fail_mie

    /* mip has no software-writable state; MTIP will come from hardware. */
    csrw    mip, x5
    csrr    x6, mip
    bne     x6, x0, _fail_mip

    /* Direct-only mtvec retains the aligned BASE and forces MODE=0. */
    la      x5, _aligned_address
    addi    x6, x5, 3
    csrw    mtvec, x6
    csrr    x7, mtvec
    bne     x7, x5, _fail_mtvec

    /* IALIGN=32 forces mepc[1:0] to zero. */
    addi    x6, x5, 3
    csrw    mepc, x6
    csrr    x7, mepc
    bne     x7, x5, _fail_mepc

    /* misa is implemented as a fixed legal RV32IM WARL value. */
    csrw    misa, x0
    csrr    x6, misa
    li      x7, MISA_RV32IM
    bne     x6, x7, _fail_misa

    /* No S/U mode means delegation fields legally retain zero. */
    li      x5, -1
    csrw    medeleg, x5
    csrr    x6, medeleg
    bne     x6, x0, _fail_deleg
    csrw    mideleg, x5
    csrr    x6, mideleg
    bne     x6, x0, _fail_deleg

_aligned_address:
    nop

_pass:
    li      x10, 1
    j       _report
_fail_mstatus:
    li      x10, 2
    j       _report
_fail_mie:
    li      x10, 3
    j       _report
_fail_mip:
    li      x10, 4
    j       _report
_fail_mtvec:
    li      x10, 5
    j       _report
_fail_mepc:
    li      x10, 6
    j       _report
_fail_misa:
    li      x10, 7
    j       _report
_fail_deleg:
    li      x10, 8

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)
_stop:
    j       _stop
