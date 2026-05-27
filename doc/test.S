/*
 * ============================================================
 * File: rv32im_test.S
 * Description:
 *   RV32IM self-check assembly program for the reconstructed CPU.
 *
 * Usage:
 *   - Assemble with -march=rv32im -mabi=ilp32.
 *   - Convert to prog.hex and load by prog_ram.
 *
 * Result convention:
 *   PASS:
 *     x10 = 1
 *     x11 = 0
 *
 *   FAIL:
 *     x10 = 0
 *     x11 = failure code
 *
 * Notes:
 *   - No CSR is used.
 *   - No compressed instruction is used.
 *   - Program ends with ebreak.
 *   - Data memory is assumed to be a separate RAM starting at
 *     byte address 0.
 * ============================================================
 */
.option norvc
.section .text
.globl _start
_start:
  /*
   * ------------------------------------------------------------
   * Initial status
   * ------------------------------------------------------------
   */
  addi x10, x0, 0        /* x10 = pass flag, initially 0 */
  addi x11, x0, 0        /* x11 = failure code */
  /*
   * ============================================================
   * 1. I-Type ALU
   * ============================================================
   */
  /* ADDI */
  addi x1, x0, 10
  addi x2, x0, 10
  addi x11, x0, 1
  bne  x1, x2, fail
  /* SLTI: 5 < 6 signed => 1 */
  addi x1, x0, 5
  slti x3, x1, 6
  addi x4, x0, 1
  addi x11, x0, 2
  bne  x3, x4, fail
  /* SLTI: 7 < 6 signed => 0 */
  addi x1, x0, 7
  slti x3, x1, 6
  addi x4, x0, 0
  addi x11, x0, 3
  bne  x3, x4, fail
  /* SLTIU: 5 < 6 unsigned => 1 */
  addi  x1, x0, 5
  sltiu x3, x1, 6
  addi  x4, x0, 1
  addi  x11, x0, 4
  bne   x3, x4, fail
  /* SLTIU: -1 < 1 unsigned => 0 */
  addi  x1, x0, -1
  sltiu x3, x1, 1
  addi  x4, x0, 0
  addi  x11, x0, 5
  bne   x3, x4, fail
  /* XORI */
  addi x1, x0, 0x55
  xori x3, x1, 0x0f
  addi x4, x0, 0x5a
  addi x11, x0, 6
  bne  x3, x4, fail
  /* ORI */
  addi x1, x0, 0x50
  ori  x3, x1, 0x0f
  addi x4, x0, 0x5f
  addi x11, x0, 7
  bne  x3, x4, fail
  /* ANDI */
  addi x1, x0, 0x5f
  andi x3, x1, 0x0f
  addi x4, x0, 0x0f
  addi x11, x0, 8
  bne  x3, x4, fail
  /* SLLI */
  addi x1, x0, 1
  slli x3, x1, 5
  addi x4, x0, 32
  addi x11, x0, 9
  bne  x3, x4, fail
  /* SRLI */
  addi x1, x0, 32
  srli x3, x1, 5
  addi x4, x0, 1
  addi x11, x0, 10
  bne  x3, x4, fail
  /* SRAI: -8 >> 1 = -4 */
  addi x1, x0, -8
  srai x3, x1, 1
  addi x4, x0, -4
  addi x11, x0, 11
  bne  x3, x4, fail
  /*
   * ============================================================
   * 2. R-Type ALU
   * ============================================================
   */
  addi x1, x0, 10
  addi x2, x0, 3
  /* ADD */
  add x3, x1, x2
  addi x4, x0, 13
  addi x11, x0, 20
  bne x3, x4, fail
  /* SUB */
  sub x3, x1, x2
  addi x4, x0, 7
  addi x11, x0, 21
  bne x3, x4, fail
  /* AND */
  and x3, x1, x2       /* 10 & 3 = 2 */
  addi x4, x0, 2
  addi x11, x0, 22
  bne x3, x4, fail
  /* OR */
  or x3, x1, x2        /* 10 | 3 = 11 */
  addi x4, x0, 11
  addi x11, x0, 23
  bne x3, x4, fail
  /* XOR */
  xor x3, x1, x2       /* 10 ^ 3 = 9 */
  addi x4, x0, 9
  addi x11, x0, 24
  bne x3, x4, fail
  /* SLL */
  sll x3, x1, x2       /* 10 << 3 = 80 */
  addi x4, x0, 80
  addi x11, x0, 25
  bne x3, x4, fail
  /* SRL */
  srl x3, x1, x2       /* 10 >> 3 = 1 */
  addi x4, x0, 1
  addi x11, x0, 26
  bne x3, x4, fail
  /* SRA */
  addi x1, x0, -8
  addi x2, x0, 1
  sra x3, x1, x2       /* -8 >>> 1 = -4 */
  addi x4, x0, -4
  addi x11, x0, 27
  bne x3, x4, fail
  /* SLT signed: -1 < 1 => 1 */
  addi x1, x0, -1
  addi x2, x0, 1
  slt x3, x1, x2
  addi x4, x0, 1
  addi x11, x0, 28
  bne x3, x4, fail
  /* SLTU unsigned: -1 < 1 => 0 */
  sltu x3, x1, x2
  addi x4, x0, 0
  addi x11, x0, 29
  bne x3, x4, fail
  /*
   * ============================================================
   * 3. LUI / AUIPC / JAL / JALR
   * ============================================================
   */
  /* LUI */
  lui  x3, 0x12345
  lui  x4, 0x12345
  addi x11, x0, 30
  bne  x3, x4, fail
  /*
   * AUIPC test:
   *   auipc x5,0 at PC=P gives x5=P.
   *   jal x6,1f at PC=P+4 gives x6=P+8.
   *   x6 - 8 should equal x5.
   */
  auipc x5, 0
  jal   x6, 1f
1:
  addi x6, x6, -8
  addi x11, x0, 31
  bne  x5, x6, fail
  /*
   * JAL test:
   *   auipc x6,0 at PC=P gives x6=P.
   *   jal x5,2f at PC=P+4 gives link x5=P+8.
   */
  auipc x6, 0
  jal   x5, 2f
  addi  x11, x0, 32
  jal   x0, fail
2:
  addi x6, x6, 8
  addi x11, x0, 33
  bne  x5, x6, fail
  /*
   * JALR test with bit0 clearing:
   *   x6 = target + 1.
   *   jalr must clear bit0 and jump to target.
   */
  auipc x6, 0
  addi  x6, x6, 21       /* target address + 1 */
  jalr  x5, 0(x6)
  addi  x11, x0, 34
  jal   x0, fail
3:
  addi x6, x6, -9        /* x6 was P+21, expected link is P+12 */
  addi x11, x0, 35
  bne  x5, x6, fail
  /*
   * ============================================================
   * 4. Branch instructions
   * ============================================================
   */
  addi x1, x0, 5
  addi x2, x0, 5
  addi x7, x0, 7
  /* BEQ taken */
  addi x11, x0, 40
  beq  x1, x2, 4f
  jal  x0, fail
4:
  /* BEQ not taken */
  addi x11, x0, 41
  beq  x1, x7, fail
  /* BNE taken */
  addi x11, x0, 42
  bne  x1, x7, 5f
  jal  x0, fail
5:
  /* BNE not taken */
  addi x11, x0, 43
  bne  x1, x2, fail
  /* BLT signed taken: -1 < 1 */
  addi x1, x0, -1
  addi x2, x0, 1
  addi x11, x0, 44
  blt  x1, x2, 6f
  jal  x0, fail
6:
  /* BGE signed taken: 1 >= -1 */
  addi x11, x0, 45
  bge  x2, x1, 7f
  jal  x0, fail
7:
  /* BLTU unsigned not taken: -1 < 1 is false */
  addi x11, x0, 46
  bltu x1, x2, fail
  /* BGEU unsigned taken: -1 >= 1 */
  addi x11, x0, 47
  bgeu x1, x2, 8f
  jal  x0, fail
8:
  /*
   * ============================================================
   * 5. Load / Store
   * Data RAM is separate from instruction RAM.
   * Test little-endian byte lanes and sign/zero extension.
   * ============================================================
   */
  /* SW / LW */
  lui  x1, 0x12345
  addi x1, x1, 0x678     /* x1 = 0x12345678 */
  sw   x1, 0(x0)
  lw   x3, 0(x0)
  addi x11, x0, 50
  bne  x3, x1, fail
  /*
   * SB at address 9, then LBU/LB.
   * Store 0xff, LBU should be 255, LB should be -1.
   */
  addi x1, x0, -1
  sb   x1, 9(x0)
  lbu  x3, 9(x0)
  addi x4, x0, 255
  addi x11, x0, 51
  bne  x3, x4, fail
  lb   x3, 9(x0)
  addi x4, x0, -1
  addi x11, x0, 52
  bne  x3, x4, fail
  /*
   * SH at address 14, then LHU/LH.
   * Store 0x8123.
   */
  lui  x1, 0x8
  addi x1, x1, 0x123     /* x1 = 0x00008123 */
  sh   x1, 14(x0)
  lhu  x3, 14(x0)
  addi x11, x0, 53
  bne  x3, x1, fail
  lh   x3, 14(x0)
  slli x4, x1, 16
  srai x4, x4, 16        /* sign-extended 0x8123 */
  addi x11, x0, 54
  bne  x3, x4, fail
  /*
   * ============================================================
   * 6. RV32M Multiply / Divide
   * ============================================================
   */
  /* MUL: -2 * 3 = -6 */
  addi x1, x0, -2
  addi x2, x0, 3
  mul  x3, x1, x2
  addi x4, x0, -6
  addi x11, x0, 60
  bne  x3, x4, fail
  /* MULH signed high: -2 * 3 = high 0xffffffff */
  mulh x3, x1, x2
  addi x4, x0, -1
  addi x11, x0, 61
  bne  x3, x4, fail
  /* MULHSU signed x unsigned high: -2 * 3 = high 0xffffffff */
  mulhsu x3, x1, x2
  addi   x4, x0, -1
  addi   x11, x0, 62
  bne    x3, x4, fail
  /* MULHU unsigned high: 0xffffffff * 2 = high 1 */
  addi  x1, x0, -1
  addi  x2, x0, 2
  mulhu x3, x1, x2
  addi  x4, x0, 1
  addi  x11, x0, 63
  bne   x3, x4, fail
  /* DIV signed: -7 / 3 = -2 */
  addi x1, x0, -7
  addi x2, x0, 3
  div  x3, x1, x2
  addi x4, x0, -2
  addi x11, x0, 64
  bne  x3, x4, fail
  /* REM signed: -7 % 3 = -1 */
  rem  x3, x1, x2
  addi x4, x0, -1
  addi x11, x0, 65
  bne  x3, x4, fail
  /* DIVU: 7 / 3 = 2 */
  addi x1, x0, 7
  addi x2, x0, 3
  divu x3, x1, x2
  addi x4, x0, 2
  addi x11, x0, 66
  bne  x3, x4, fail
  /* REMU: 7 % 3 = 1 */
  remu x3, x1, x2
  addi x4, x0, 1
  addi x11, x0, 67
  bne  x3, x4, fail
  /* DIV by zero => 0xffffffff */
  addi x1, x0, 123
  addi x2, x0, 0
  div  x3, x1, x2
  addi x4, x0, -1
  addi x11, x0, 68
  bne  x3, x4, fail
  /* DIVU by zero => 0xffffffff */
  divu x3, x1, x2
  addi x4, x0, -1
  addi x11, x0, 69
  bne  x3, x4, fail
  /* REM by zero => dividend */
  rem  x3, x1, x2
  addi x4, x0, 123
  addi x11, x0, 70
  bne  x3, x4, fail
  /* REMU by zero => dividend */
  remu x3, x1, x2
  addi x4, x0, 123
  addi x11, x0, 71
  bne  x3, x4, fail
  /*
   * Signed division overflow:
   *   0x80000000 / -1 => 0x80000000
   *   0x80000000 % -1 => 0
   */
  lui  x1, 0x80000
  addi x2, x0, -1
  div  x3, x1, x2
  addi x11, x0, 72
  bne  x3, x1, fail
  rem  x3, x1, x2
  addi x4, x0, 0
  addi x11, x0, 73
  bne  x3, x4, fail
  /*
   * ============================================================
   * PASS
   * ============================================================
   */
pass:
  addi x10, x0, 1
  addi x11, x0, 0
  ebreak
  /*
   * ============================================================
   * FAIL
   * x11 already contains failure code.
   * ============================================================
   */
fail:
  addi x10, x0, 0
  ebreak