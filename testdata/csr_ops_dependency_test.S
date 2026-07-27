/*
 * AR-007 CSR operation and dependency regression.
 *
 * Covers all six Zicsr operation forms and same-address, back-to-back CSR
 * dependencies. The second instruction in each adjacent pair must observe the
 * value produced by the older instruction.
 *
 * tohost:
 *   1  = PASS
 *   2  = CSRRW returned the wrong old value
 *   3  = CSRRS read/write behavior was wrong
 *   4  = CSRRC did not observe the preceding CSRRS result
 *   5  = CSRRSI read/write behavior was wrong
 *   6  = CSRRCI did not observe the preceding CSRRSI result
 *   7  = CSRRWI returned/wrote the wrong values
 *   8  = CSRRW with rs1=x0 did not write zero
 *   9  = back-to-back write/read returned stale data
 */
.option norvc
.section .text
.globl _start

.equ TOHOST, 0x1000

_start:
    /* CSRRW must return the old value and install the new value. */
    li      x5, 0x12345678
    csrrw   x6, mscratch, x5
    bne     x6, x0, _fail_csrrw
    csrr    x7, mscratch
    bne     x7, x5, _fail_csrrw

    /*
     * Register set/clear forms. CSRRC is intentionally adjacent to CSRRS:
     * its read-modify-write must use the CSRRS result, not stale CSR state.
     */
    li      x5, 0x10
    csrw    mscratch, x5
    li      x6, 0x1
    csrrs   x7, mscratch, x6
    li      x8, 0x10
    bne     x7, x8, _fail_csrrs
    csrrc   x9, mscratch, x6
    li      x8, 0x11
    bne     x9, x8, _fail_csrrc_dependency
    csrr    x7, mscratch
    li      x8, 0x10
    bne     x7, x8, _fail_csrrc_dependency

    /*
     * Immediate set/clear forms, again adjacent so the clear depends on the
     * value written by the immediately preceding set.
     */
    csrrsi  x7, mscratch, 1
    li      x8, 0x10
    bne     x7, x8, _fail_csrrsi
    csrrci  x9, mscratch, 1
    li      x8, 0x11
    bne     x9, x8, _fail_csrrci_dependency
    csrr    x7, mscratch
    li      x8, 0x10
    bne     x7, x8, _fail_csrrci_dependency

    /* Immediate swap writes zimm and returns the old value. */
    csrrwi  x7, mscratch, 5
    li      x8, 0x10
    bne     x7, x8, _fail_csrrwi
    csrr    x7, mscratch
    li      x8, 5
    bne     x7, x8, _fail_csrrwi

    /* CSRRW with rs1=x0 is still a write: it installs zero. */
    csrrw   x7, mscratch, x0
    li      x8, 5
    bne     x7, x8, _fail_zero_write
    csrr    x7, mscratch
    bne     x7, x0, _fail_zero_write

    /* A direct adjacent write/read pair must not return the old zero. */
    li      x5, 0x2468ace0
    csrw    mscratch, x5
    csrr    x6, mscratch
    bne     x6, x5, _fail_write_read_dependency

_pass:
    li      x10, 1
    j       _report

_fail_csrrw:
    li      x10, 2
    j       _report
_fail_csrrs:
    li      x10, 3
    j       _report
_fail_csrrc_dependency:
    li      x10, 4
    j       _report
_fail_csrrsi:
    li      x10, 5
    j       _report
_fail_csrrci_dependency:
    li      x10, 6
    j       _report
_fail_csrrwi:
    li      x10, 7
    j       _report
_fail_zero_write:
    li      x10, 8
    j       _report
_fail_write_read_dependency:
    li      x10, 9

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)
_stop:
    j       _stop
