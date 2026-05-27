/*
 * ============================================================
 * File: ebreak_test.S
 * Description:
 *   Test EBREAK handling.
 *
 * Expected CPU behavior:
 *   - decode should recognize EBREAK.
 *   - EBREAK should not be treated as NOP.
 *   - ebreak internal flag should be set.
 *   - exception_o should pulse high.
 *   - halt_o should become high.
 *   - illegal_instr_o should normally remain low if EBREAK is
 *     treated as a recognized system event.
 *
 * Register markers:
 *   x10 = 106
 *   x11 = 6
 *
 * EBREAK encoding:
 *   0x00100073
 *
 * Notes:
 *   - This is also useful as the normal simulation stop instruction.
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * Mark this test case.
   */
  addi x10, x0, 106
  addi x11, x0, 6
  /*
   * Breakpoint.
   * Current simple CPU has no full debug/trap system, so this
   * should trigger halt/exception.
   */
  ebreak
  /*
   * If CPU reaches here, EBREAK was incorrectly ignored.
   * This should not execute.
   */
  addi x11, x, 0x7ff
  ebreak