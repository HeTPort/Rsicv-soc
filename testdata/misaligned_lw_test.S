/*
 * ============================================================
 * File: misaligned_lw_test.S
 * Description:
 *   Test misaligned LW trap handling.
 *
 * Expected CPU behavior:
 *   - LW at address 0x00000002 is word-misaligned.
 *   - Trap enters M-mode handler (mcause = 4).
 *   - Handler writes PASS (1) to tohost at 0x0000_1000.
 *
 * Register markers:
 *   x10 = 1
 *   x11 = 0
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
    la   x5, _trap_handler
    csrw mtvec, x5

    li   x10, 1
    li   x11, 0

    addi x1, x0, 0x55
    sw   x1, 0(x0)

    /* Misaligned load: effective address = 0x00000002. */
    lw   x2, 2(x0)

    /* Should not reach here. */
    li   x10, 2
    li   x6, TOHOST
    sw   x10, 0(x6)
1:  j    1b

    .align 8
_trap_handler:
    li   x10, 1
    li   x6, TOHOST
    sw   x10, 0(x6)
1:  j    1b
