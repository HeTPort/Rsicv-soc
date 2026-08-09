    .section .text
    .globl _start

    .equ MTIMECMP, 0x02004000
    .equ MTIME,    0x0200BFF8
    .equ TOHOST,   0x8000FFFC

_start:
    la      t0, trap_handler
    csrw    mtvec, t0

    # Program mtimecmp safely and far enough ahead to reach WFI first.
    li      t0, MTIMECMP
    li      t1, -1
    sw      t1, 0(t0)
    sw      zero, 4(t0)
    li      t2, MTIME
    lw      t3, 0(t2)
    addi    t3, t3, 200
    sw      t3, 0(t0)

    li      s1, 0
    li      t0, 0x80
    csrw    mie, t0
    li      t0, 0x8
    csrs    mstatus, t0

    wfi
after_wfi:
    li      t0, 1
    bne     s1, t0, fail_1
    csrr    t1, mstatus
    andi    t1, t1, 0x8
    beqz    t1, fail_2
    j       pass

trap_handler:
    csrr    t0, mcause
    li      t1, 0x80000007
    bne     t0, t1, fail_3
    csrr    t0, mepc
    la      t1, after_wfi
    bne     t0, t1, fail_4
    csrr    t0, mtval
    bnez    t0, fail_5
    csrr    t0, mstatus
    andi    t1, t0, 0x8
    bnez    t1, fail_6
    andi    t1, t0, 0x80
    beqz    t1, fail_7

    # Move compare to its reset-like maximum so MTIP becomes inactive.
    li      t0, MTIMECMP
    li      t1, -1
    sw      t1, 0(t0)
    sw      t1, 4(t0)
    addi    s1, s1, 1
    mret

fail_1: li a0, 1; j fail
fail_2: li a0, 2; j fail
fail_3: li a0, 3; j fail
fail_4: li a0, 4; j fail
fail_5: li a0, 5; j fail
fail_6: li a0, 6; j fail
fail_7: li a0, 7; j fail

pass:
    li      a0, 1
    j       report
fail:
    addi    a0, a0, 1
report:
    li      t0, TOHOST
    sw      a0, 0(t0)
1:  j       1b
