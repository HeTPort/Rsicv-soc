    .option norvc
    .section .text, "ax", @progbits
    .align  2
    .globl  context_sentinel_queue_send
    .type   context_sentinel_queue_send, @function

/*
 * xQueueGenericSend wakes the higher-priority receiver and yields through the
 * official ECALL/context-switch path. Verify the ABI callee-saved register set
 * survives that forced task switch before returning to C.
 */
context_sentinel_queue_send:
    addi    sp, sp, -48
    sw      s2,  0(sp)
    sw      s3,  4(sp)
    sw      s4,  8(sp)
    sw      s5, 12(sp)
    sw      s6, 16(sp)
    sw      s7, 20(sp)
    sw      s8, 24(sp)
    sw      s9, 28(sp)
    sw      s10,32(sp)
    sw      s11,36(sp)
    sw      ra, 44(sp)

    li      s2,  0x22334452
    li      s3,  0x23344563
    li      s4,  0x24455674
    li      s5,  0x25566785
    li      s6,  0x26677896
    li      s7,  0x277889a7
    li      s8,  0x28899ab8
    li      s9,  0x299aabc9
    li      s10, 0x2aabbcda
    li      s11, 0x2bbccdeb

    li      a2, 0
    li      a3, 0
    call    xQueueGenericSend
    sw      a0, 40(sp)

    li      t0, 0x22334452
    bne     s2, t0, .Lsentinel_fail
    li      t0, 0x23344563
    bne     s3, t0, .Lsentinel_fail
    li      t0, 0x24455674
    bne     s4, t0, .Lsentinel_fail
    li      t0, 0x25566785
    bne     s5, t0, .Lsentinel_fail
    li      t0, 0x26677896
    bne     s6, t0, .Lsentinel_fail
    li      t0, 0x277889a7
    bne     s7, t0, .Lsentinel_fail
    li      t0, 0x28899ab8
    bne     s8, t0, .Lsentinel_fail
    li      t0, 0x299aabc9
    bne     s9, t0, .Lsentinel_fail
    li      t0, 0x2aabbcda
    bne     s10,t0, .Lsentinel_fail
    li      t0, 0x2bbccdeb
    bne     s11,t0, .Lsentinel_fail
    lw      a0, 40(sp)
    j       .Lsentinel_restore

.Lsentinel_fail:
    li      a0, 0

.Lsentinel_restore:
    lw      s2,  0(sp)
    lw      s3,  4(sp)
    lw      s4,  8(sp)
    lw      s5, 12(sp)
    lw      s6, 16(sp)
    lw      s7, 20(sp)
    lw      s8, 24(sp)
    lw      s9, 28(sp)
    lw      s10,32(sp)
    lw      s11,36(sp)
    lw      ra, 44(sp)
    addi    sp, sp, 48
    ret

    .size context_sentinel_queue_send, . - context_sentinel_queue_send
