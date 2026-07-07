/*
 * ============================================================
 * File: illegal_opcode_test.S
 * Description:
 *   Test illegal-instruction trap handling.
 *
 * Expected CPU behavior:
 *   - decode detects unknown opcode (0xffffffff).
 *   - Illegal instruction enters M-mode trap (mcause = 2).
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

    /* Illegal opcode: opcode = 7'b1111111, unsupported. */
    .word 0xffffffff

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
