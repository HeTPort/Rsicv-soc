/*
 * ============================================================
 * File: ecall_test.S
 * Description:
 *   Test ECALL handling.
 *
 * Expected CPU behavior:
 *   - decode should recognize ECALL.
 *   - ECALL should not be treated as NOP.
 *   - ecall internal flag should be set.
 *   - exception_o should pulse high.
 *   - halt_o should become high.
 *   - illegal_instr_o should normally remain low if ECALL is
 *     treated as a recognized system event.
 *
 * Register markers:
 *   x10 = 105
 *   x11 = 5
 *
 * ECALL encoding:
 *   0x00000073
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * Mark this test case.
   */
  addi x10, x0, 105
  addi x11, x0, 5
  /*
   * Environment call.
   * Current simple CPU has no full trap system, so this should
   * trigger halt/exception instead of executing silently.
   */
  ecall
  /*
   * If CPU reaches here, ECALL was incorrectly ignored.
   * This should not execute.
   */
  addi x11, x0, 0x7ff
  ebreak