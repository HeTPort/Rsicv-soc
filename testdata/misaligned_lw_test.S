/*
 * ============================================================
 * File: misaligned_lw_test.S
 * Description:
 *   Test misaligned LW access.
 *
 * Expected CPU behavior:
 *   - LW requires 4-byte alignment.
 *   - Address 0x00000002 is not word-aligned.
 *   - execute should detect memory misalignment.
 *   - exception_o should pulse high.
 *   - halt_o should become high.
 *   - illegal_instr_o should normally remain low because the
 *     instruction encoding itself is legal.
 *
 * Register markers:
 *   x10 = 103
 *   x11 = 3
 *
 * Notes:
 *   - This tests access alignment, not illegal instruction decode.
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * Mark this test case.
   */
  addi x10, x0, 103
  addi x11, x0, 3
  /*
   * Optional: initialize aligned data at address 0.
   */
  addi x1, x0, 0x55
  sw   x1, 0(x0)
  /*
   * Misaligned load:
   *   effective address = x0 + 2 = 0x00000002
   *   LW requires addr[1:0] == 2'b00.
   */
  lw   x2, 2(x0)
  /*
   * If CPU reaches here, misaligned LW was not handled.
   * This should not execute.
   */
  addi x11, x0, 0x7ff
  ebreak