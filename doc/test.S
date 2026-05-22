addi x1, x0, 5        ; x1 = 5
addi x2, x0, 7        ; x2 = 7
add  x3, x1, x2       ; x3 = 12
sub  x4, x3, x1       ; x4 = 7
addi x5, x0, 16       ; x5 = 16 (data addr base)
sw   x3, 0(x5)        ; MEM[16] = 12
lw   x6, 0(x5)        ; x6 = 12
sb   x4, 4(x5)        ; MEM[20] low byte = 7
lb   x7, 4(x5)        ; x7 = 7 (sign extended)
lbu  x8, 4(x5)        ; x8 = 7 (zero extended)
beq  x6, x3, pass     ; should branch
addi x9, x0, 99       ; should be skipped
pass:
jal  x0, 0            ; self loop