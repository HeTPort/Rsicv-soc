/*
 * Directed architectural-capability and data-image test.
 *
 * The expected misa value is read from data RAM at 0x200. Keeping the
 * expected value outside the instruction image proves that the regression
 * harness initializes the Harvard instruction and data memories separately.
 */
.option norvc
.section .text
.globl _start

#define EXPECTED_MISA_ADDR 0x200
#define TOHOST             0x1000

_start:
    csrr x5, misa
    li   x6, EXPECTED_MISA_ADDR
    lw   x6, 0(x6)
    bne  x5, x6, fail

pass:
    li   x10, 1
    li   x6, TOHOST
    sw   x10, 0(x6)
1:  j    1b

fail:
    li   x10, 2
    li   x6, TOHOST
    sw   x10, 0(x6)
1:  j    1b
