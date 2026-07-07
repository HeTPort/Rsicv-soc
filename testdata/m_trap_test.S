/*
 * ============================================================
 * File: m_trap_test.S
 * Description:
 *   Minimal M-mode trap-flow test.
 *
 * Tests:
 *   - csrrw / csrw mtvec
 *   - ECALL enters trap (mcause = 11)
 *   - mepc is saved and can be adjusted in handler
 *   - mret returns to the instruction after ECALL
 *   - Memory-mapped tohost exit at 0x0000_1000
 *
 * Register markers:
 *   On trap entry the handler preserves x10 = 1 (PASS).
 *   After mret the main code writes 1 to tohost.
 *
 * PASS:  tohost write == 1
 * FAIL:  tohost write != 1
 * ============================================================
 */
.option norvc
.section .text
.globl _start

#define TOHOST 0x1000

_start:
    /* Install trap handler at _trap_handler */
    la   x5, _trap_handler
    csrw mtvec, x5

    /* PASS marker */
    li   x10, 1
    li   x11, 0

    /* Environment call: should enter handler, then return here. */
    ecall

    /* Exit via tohost */
    li   x6, TOHOST
    sw   x10, 0(x6)
1:  j    1b

    .align 8
_trap_handler:
    /* Read saved PC, advance it past the ECALL, and return. */
    csrr x7, mepc
    addi x7, x7, 4
    csrw mepc, x7
    mret
