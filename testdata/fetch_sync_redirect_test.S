/*
 * AR-005 synchronous instruction-fetch regression.
 *
 * Covers:
 *   - a back-to-back RAW dependency that stalls fetch;
 *   - aligned taken branch, JAL, and JALR redirects;
 *   - squashing the sequential poison instruction behind each redirect;
 *   - executing each redirect target exactly once.
 *
 * tohost:
 *   1 = PASS
 *   2 = RAW-stall result was paired with the wrong instruction
 *   3 = taken branch did not squash the sequential instruction
 *   4 = JAL did not squash the sequential instruction
 *   5 = dependency-fed JALR did not squash the sequential instruction
 *   6 = a redirect target was skipped or executed more than once
 */
.option norvc
.section .text
.globl _start

.equ TOHOST, 0x1000

_start:
    li      x20, 0

    /* The consumer must stall until x1 is available. */
    li      x1, 1
    addi    x2, x1, 2
    li      x3, 3
    bne     x2, x3, _fail_raw

    /* Signature bit 0: sequential path before the redirects. */
    addi    x20, x20, 1

    beq     x2, x3, _branch_target
    j       _fail_branch

_branch_target:
    /* Signature bit 1: aligned taken-branch target. */
    addi    x20, x20, 2
    jal     x4, _jal_target
    j       _fail_jal

_jal_target:
    /* Signature bit 2: aligned JAL target. */
    addi    x20, x20, 4

    /*
     * `la` produces x5 immediately before JALR, so this also checks that a
     * fetch stall and a redirect cannot separate the response PC from data.
     */
    la      x5, _jalr_target
    jalr    x6, 0(x5)
    j       _fail_jalr

_jalr_target:
    /* Signature bit 3: aligned JALR target. */
    addi    x20, x20, 8
    li      x7, 15
    bne     x20, x7, _fail_signature

_pass:
    li      x10, 1
    j       _report
_fail_raw:
    li      x10, 2
    j       _report
_fail_branch:
    li      x10, 3
    j       _report
_fail_jal:
    li      x10, 4
    j       _report
_fail_jalr:
    li      x10, 5
    j       _report
_fail_signature:
    li      x10, 6

_report:
    li      x5, TOHOST
    sw      x10, 0(x5)
_stop:
    j       _stop
