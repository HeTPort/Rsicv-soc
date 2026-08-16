    .option norvc
    .section .text.trap, "ax", @progbits
    .align  2
    .globl  trap_entry
    .type   trap_entry, @function

/* Startup keeps one common symbol; this app forwards it to the official port. */
trap_entry:
    j       freertos_risc_v_trap_handler

    .size   trap_entry, . - trap_entry
