/*
 * Minimal program using the same termination sequence as rvmodel_macros.h.
 * It verifies that an ACT4 image can signal PASS at simulation-only tohost
 * address 0x0000_3ffc through the architectural commit interface.
 */
.option norvc
.section .text
.globl _start

_start:
    li x1, 1
    li x5, 0x3ffc
    sw x1, 0(x5)
1:  j 1b
