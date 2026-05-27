PC
 |
 | instr_addr_o
 v
同步指令 RAM
 |
 | instr_rdata_i，延迟一拍返回
 v
IF/ID
 |
 v
Decode + Regfile Read
 |
 v
ID/EX
 |
 v
Execute
 |        \
 |         \ branch/jump redirect
 |          \
 |           -> PC redirect + flush IF/ID、ID/EX
 |
 v
EX/WB
 |
 v
WB Stage
 |
 v
Regfile Write
