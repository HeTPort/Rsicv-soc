/*
 * ============================================================
 * File: misaligned_sw_test.S
 * Description:
 *   Test misaligned SW access.
 *
 * Expected CPU behavior:
 *   - SW requires 4-byte alignment.
 *   - Address 0x00000002 is not word-aligned.
 *   - execute should detect memory misalignment.
 *   - No data RAM write should occur.
 *   - exception_o should pulse high.
 *   - halt_o should become high.
 *   - illegal_instr_o should normally remain low because the
 *     instruction encoding itself is legal.
 *
 * Register markers:
 *   x10 = 104
 *   x11 = 4
 *
 * Notes:
 *   - This tests store alignment check.
 *   - Store must not be silently ignored without exception.
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * Mark this test case.
   */
  addi x10, x0, 104
  addi x11, x0, 4
  /*
   * Prepare store data.
   */
  lui  x1, 0x12345
  addi x1, x1, 0x678      /* x1 = 0x12345678 */
  /*
   * Misaligned store:
   *   effective address = x0 + 2 = 0x00000002
   *   SW requires addr[1:0] == 2'b00.
   */
  sw   x1, 2(x0)
  /*
   * If CPU reaches here, misaligned SW was not handled.
   * This should not execute.
   */
  addi x11, x0, 0x7ff
  ebreak