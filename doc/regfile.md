顶层riscv.sv对外提供：

|信号	|方向	|含义|
| ------ | ------ |-----|
|instr_ren_o	|output	|指令读使能。当前恒为 1|
|instr_addr_o	|output	|指令读取地址||
|instr_rdata_i	|input	|同步指令 RAM 返回的指令数据，延迟一拍有效|

同步指令RAM的行为：
```
cycle N:
  CPU 输出 instr_addr_o = PC

posedge cycle N:
  prog_ram 锁存地址并读取

cycle N+1:
  instr_rdata_i 输出上一拍地址对应的指令

```

因此 CPU 内部必须保存“上一拍请求的 PC”，使返回指令和 PC 对齐