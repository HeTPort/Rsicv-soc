-core/:纯CPU核
-mem/:存储模块
-periph/:外设
-soc/:地址映射与互联
-top/:板级封装
-sim/:仿真
-vivado/:工程和约束


step1.
1. testbench 先往 prog_ram 里预装一段小程序
2. CPU 复位释放
3. CPU 从地址 0 取指
4. 执行若干条 RV32I 指令
5. 最后停在自旋 jal x0, 0

point:
CPU 取指
看：
- u_riscv.pc_pointer
- instr_addr
- instr_rdata

确认 PC 是：0x0 -> 0x4 -> 0x8 -> ... -> 0x28 -> 0x30 -> 0x30 -> 0x30 ...
最后在 jal x0, 0 处自旋

写回寄存器
看：
- u_riscv.wr_reg_en
- u_riscv.wr_reg_addr
- u_riscv.wr_reg_data

预期关键写回：

- x1 = 5
- x2 = 7
- x3 = 12
- x4 = 7
- x5 = 16
- x6 = 12
- x7 = 7
- x8 = 7

x9 不应被写成 99，因为 branch 应跳过那条 addi。

数据存储器
看：
- u_riscv.mem_wr_en
- u_riscv.mem_wr_strb
- u_riscv.mem_addr
- u_riscv.mem_wdata
- u_riscv.mem_rdata

关键行为：

sw x3, 0(x5)
- mem_addr = 16
- mem_wr_strb = 4'b1111
- mem_wdata = 12

sb x4, 4(x5)
- mem_addr = 20
- mem_wr_strb = 4'b0001
- mem_wdata[7:0] = 7

lb/lbu
- 从地址 20 读
- 返回 byte 7
- 分别做符号/零扩展

按经验优先查：

 define.sv 是否统一
最容易出错的是：
- 宏名大小写不一致
- INST_TYPE_JALR / INST_TYPE_JAL
- INST_LB/LBU/LH/LHU/SB/SH/SW 是否齐全

 include 路径
如果 vlog 提示找不到 define.sv，说明你的相对路径或当前目录不对。
你可以：
- 保持在 sim/ 下运行
- 或在 filelist.f 里改成绝对/正确相对路径

 execute/store 行为
如果 sw/sb 不对，优先看：
- mem_wr_strb
- mem_wdata
- byte_offset

 branch 行为
如果 x9 被写成 99，说明 branch 没跳过。
优先看：
- jump_en
- jump_addr
- if2id/id2ex 是否在跳转时注入了 NOP