    .section .text
    .globl _start

    .equ MTIMECMP, 0x02004000
    .equ MTIME,    0x0200BFF8
    .equ TOHOST,   0x8000FFFC

_start:
    la      t0, timer_handler
    csrw    mtvec, t0
    li      s0, 0
    li      s1, 10000

    # Initial compare; low=-1 prevents a transient early tick.
    li      t0, MTIMECMP
    li      t1, -1
    sw      t1, 0(t0)
    sw      zero, 4(t0)
    li      t2, MTIME
    lw      t3, 0(t2)
    addi    t3, t3, 100
    sw      t3, 0(t0)

    li      t0, 0x80
    csrw    mie, t0
    li      t0, 0x8
    csrs    mstatus, t0

wait_tick:
    wfi
after_tick:
    bne     s0, s1, wait_tick

    # Disable new timer entries before reporting completion.
    li      t0, 0x8
    csrc    mstatus, t0
    li      t0, MTIMECMP
    li      t1, -1
    sw      t1, 0(t0)
    sw      t1, 4(t0)
    li      a0, 1
    li      t0, TOHOST
    sw      a0, 0(t0)
1:  j       1b

timer_handler:
    csrr    t0, mcause
    li      t1, 0x80000007
    bne     t0, t1, fail
    addi    s0, s0, 1

    # Schedule the next level transition from the current time. The selected
    # interval is long enough for the handler and MRET to complete.
    li      t0, MTIMECMP
    li      t1, -1
    sw      t1, 0(t0)
    li      t2, MTIME
    lw      t3, 0(t2)
    addi    t3, t3, 100
    sw      zero, 4(t0)
    sw      t3, 0(t0)
    mret

fail:
    li      a0, 2
    li      t0, TOHOST
    sw      a0, 0(t0)
2:  j       2b
