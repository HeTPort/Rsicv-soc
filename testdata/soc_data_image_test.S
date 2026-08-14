    .section .text
    .globl _start

    .equ DATA_RAM_BASE, 0x80000000
    .equ TOHOST,       0x8000FFFC

_start:
    li      t0, DATA_RAM_BASE
    lw      t1, 0(t0)
    li      t2, 0x12345678
    bne     t1, t2, fail

    li      a0, 1
    j       report

fail:
    li      a0, 2

report:
    li      t0, TOHOST
    sw      a0, 0(t0)
1:  j       1b
