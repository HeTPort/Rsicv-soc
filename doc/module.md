|模块	|作用|
|--|--|
|riscv_pkg.sv	|全局参数、opcode、funct3、funct7 常量|
|pc_counter.sv	|PC 寄存器|
|if2id.sv	|IF/ID 流水寄存器|
|decode.sv	|指令译码，产生寄存器读地址和 EX 操作数|
|id2ex.sv	|ID/EX 流水寄存器|
|execute.sv	|ALU、branch、jump、load/store 请求生成|
|ex2wb.sv	|EX/WB 流水寄存器|
|wb_stage.sv	|写回阶段，处理 load 数据格式扩展|
|regfile.sv	|通用寄存器堆|
|data_ram.sv|	同步数据 RAM|
|prog_ram.sv|	同步指令 RAM|
|riscv.sv	|CPU 顶层|