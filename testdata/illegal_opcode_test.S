/*
 * ============================================================
 * File: illegal_opcode_test.S
 * Description:
 *   Test illegal opcode detection.
 *
 * Expected CPU behavior:
 *   - decode detects unknown/illegal opcode.
 *   - illegal_instr_o should pulse high.
 *   - exception_o should pulse high.
 *   - halt_o should become high.
 *
 * Register markers:
 *   x10 = 101
 *   x11 = 1
 *
 * Notes:
 *   - 0xffffffff is not a valid RV32I/RV32M instruction.
 *   - The CPU should not silently execute it as NOP.
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * Mark this test case.
   */
  addi x10, x0, 101
  addi x11, x0, 1
  /*
   * Illegal instruction.
   *
   * opcode = 7'b1111111, unsupported.
   */
  .word 0xffffffff
  /*
   * If CPU reaches here, illegal instruction was not handled.
   * This should not execute.
   */
  addi x11, x0, 0x7ff
  ebreak