/*
 * ============================================================
 * File: misaligned_sw_test.S
 * Description:
 *   Test misaligned SW trap handling.
 *
 * Expected CPU behavior:
 *   - SW at address 0x00000002 is word-misaligned.
 *   - Trap enters M-mode handler (mcause = 6).
 *   - No data RAM write occurs at the misaligned address.
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

    lui  x1, 0x12345
    addi x1, x1, 0x678      /* x1 = 0x12345678 */

    /* Misaligned store: effective address = 0x00000002. */
    sw   x1, 2(x0)

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
