/*
 * ============================================================
 * File: illegal_jalr_funct3_test.S
 * Description:
 *   Test illegal JALR funct3 detection.
 *
 * Expected CPU behavior:
 *   - JALR is only legal when funct3 == 3'b000.
 *   - This program uses JALR opcode with funct3 == 3'b001.
 *   - decode should report illegal_instr_o.
 *   - exception_o should pulse high.
 *   - halt_o should become high.
 *
 * Register markers:
 *   x10 = 102
 *   x11 = 2
 *
 * Illegal instruction encoding:
 *
 *   imm[11:0] = 0
 *   rs1       = x0
 *   funct3    = 001    illegal for JALR
 *   rd        = x1
 *   opcode    = 1100111
 *
 *   binary fields:
 *     000000000000 00000 001 00001 1100111
 *
 *   hex:
 *     0x000010e7
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * Mark this test case.
   */
  addi x10, x0, 102
  addi x11, x0, 2
  /*
   * Illegal JALR:
   *   jalr-like encoding, but funct3 = 001 instead of 000.
   */
  .word 0x000010e7
  /*
   * If CPU reaches here, illegal JALR funct3 was not handled.
   * This should not execute.
   */
  addi x11, x0, 0x7ff
  ebreak