    .section .text
    .globl _start

    .equ GPIO_OUT, 0x10001000
    .equ TOHOST,   0x8000FFFC

_start:
    li      t0, GPIO_OUT

    li      t1, 0x01
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t1, t2, fail_1

    li      t1, 0x02
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t1, t2, fail_2

    li      t1, 0x04
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t1, t2, fail_3

    li      t1, 0x08
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t1, t2, fail_4

    li      t1, 0xa5
    sw      t1, 0(t0)
    lw      t2, 0(t0)
    bne     t1, t2, fail_5

    li      a0, 1
    j       report

fail_1: li a0, 2; j report
fail_2: li a0, 3; j report
fail_3: li a0, 4; j report
fail_4: li a0, 5; j report
fail_5: li a0, 6

report:
    li      t0, TOHOST
    sw      a0, 0(t0)
1:  j       1b
