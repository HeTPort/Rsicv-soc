    .option norvc
    .section .text.startup, "ax", @progbits
    .align  2
    .globl  _start
    .type   _start, @function

_start:
    /* No asynchronous interrupt may observe a partial runtime. */
    csrci   mstatus, 0x8
    csrw    mie, zero

    /* Establish the first 16-byte-aligned ILP32 procedure boundary. */
    lui     sp, %hi(__stack_top)
    addi    sp, sp, %lo(__stack_top)

    /* The psABI requires relaxation to be disabled around gp setup. */
    .option push
    .option norelax
.Lset_gp:
    auipc   gp, %pcrel_hi(__global_pointer$)
    addi    gp, gp, %pcrel_lo(.Lset_gp)
    .option pop

    /* One hart, and no TLS runtime in the Phase 5 environment. */
    mv      tp, zero

    la      t0, trap_entry
    csrw    mtvec, t0

    /* `.data` is preloaded; only `.bss` needs reset-time initialization. */
    lui     t0, %hi(__bss_start)
    addi    t0, t0, %lo(__bss_start)
    lui     t1, %hi(__bss_end)
    addi    t1, t1, %lo(__bss_end)
    bgeu    t0, t1, .Lbss_done

.Lbss_clear:
    sw      zero, 0(t0)
    addi    t0, t0, 4
    bltu    t0, t1, .Lbss_clear

.Lbss_done:
    call    main

    /* Falling out of main is a runtime error, not an implicit reset. */
    lui     t0, %hi(__soc_tohost)
    addi    t0, t0, %lo(__soc_tohost)
    li      t1, 0xBAD00002
    sw      t1, 0(t0)
.Lmain_returned:
    j       .Lmain_returned

    .size   _start, . - _start

    .section .text.trap, "ax", @progbits
    .align  2
    .weak   trap_entry
    .type   trap_entry, @function

trap_entry:
    /* Diagnostic-only fallback: it never calls C and never executes mret. */
    csrci   mstatus, 0x8
    csrw    mie, zero
    csrr    t0, mcause
    csrr    t1, mepc
    csrr    t2, mtval
    lui     t0, %hi(__soc_tohost)
    addi    t0, t0, %lo(__soc_tohost)
    li      t1, 0xBAD00001
    sw      t1, 0(t0)
.Lunexpected_trap:
    j       .Lunexpected_trap

    .size   trap_entry, . - trap_entry
