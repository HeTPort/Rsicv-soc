/*
 * AR-007 CSR legality and zero-source no-write regression.
 *
 * Machine identity CSRs are implemented read-only. CSRRS/CSRRC and their
 * immediate forms with a zero architectural source are reads, not writes, so
 * they are legal. An actual write to a read-only CSR and any access to an
 * unimplemented CSR must raise an illegal-instruction exception.
 *
 * tohost:
 *   1 = PASS
 *   2 = a zero-source read-only access trapped
 *   3 = read-only write did not trap
 *   4 = unimplemented CSR access did not trap
 *   5 = wrong mcause
 *   6 = wrong mepc
 *   7 = trapping CSR instruction wrote its destination GPR
 */
.option norvc
.section .text
.globl _start

.equ TOHOST,          0x1000
.equ CSR_UNIMPLEMENTED, 0x7c0
.equ DEST_SENTINEL,   0x13579bdf

_start:
    la      x5, _trap_handler
    csrw    mtvec, x5
    nop
    nop

    li      x20, 0

    /*
     * These four instructions address a read-only CSR but have no write
     * intent. None may raise an illegal-instruction exception.
     */
    csrrs   x0, mvendorid, x0
    csrrc   x0, mvendorid, x0
    csrrsi  x0, mvendorid, 0
    csrrci  x0, mvendorid, 0
    bne     x20, x0, _fail_no_write

    /* This is a real write attempt to a read-only CSR and must trap. */
    li      x6, 1
_readonly_write:
    csrw    mvendorid, x6
_after_readonly_write:
    li      x7, 1
    bne     x20, x7, _fail_readonly_write

    /*
     * Even a read/no-write form is illegal when the CSR address does not
     * exist. Its destination register must remain unchanged.
     */
    li      x8, DEST_SENTINEL
_unknown_read:
    csrrs   x8, CSR_UNIMPLEMENTED, x0
_after_unknown_read:
    li      x7, 2
    bne     x20, x7, _fail_unknown
    li      x9, DEST_SENTINEL
    bne     x8, x9, _fail_gpr_write

_pass:
    li      x10, 1
    j       _report

.balign 4
_trap_handler:
    csrr    x11, mcause
    li      x12, 2
    bne     x11, x12, _fail_cause

    csrr    x11, mepc
    beq     x20, x0, _check_readonly_pc
    li      x12, 1
    beq     x20, x12, _check_unknown_pc
    j       _fail_mepc

_check_readonly_pc:
    la      x12, _readonly_write
    bne     x11, x12, _fail_mepc
    j       _resume

_check_unknown_pc:
    la      x12, _unknown_read
    bne     x11, x12, _fail_mepc

_resume:
    addi    x20, x20, 1
    addi    x11, x11, 4
    csrw    mepc, x11
    mret

_fail_no_write:
    li      x10, 2
    j       _report
_fail_readonly_write:
    li      x10, 3
    j       _report
_fail_unknown:
    li      x10, 4
    j       _report
_fail_cause:
    li      x10, 5
    j       _report
_fail_mepc:
    li      x10, 6
    j       _report
_fail_gpr_write:
    li      x10, 7

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)
_stop:
    j       _stop
