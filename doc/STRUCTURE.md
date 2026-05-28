# 2. 目前顶层的整体结构

 顶层大体可以看成下面这个结构：

```text
外部指令存储器
    ↑       ↓
    │       instr_rdata_i
    │
instr_addr_o
instr_ren_o

┌──────────────────────────────────────────────────────────────────────┐
│                              riscv top                               │
│                                                                      │
│  ┌────────────┐    ┌────────────┐    ┌────────────┐                  │
│  │ pc_counter │ -> │   if2id    │ -> │   decode   │                  │
│  └────────────┘    └────────────┘    └─────┬──────┘                  │
│                                            │                         │
│                                            │ read addr/data           │
│                                            v                         │
│                                      ┌────────────┐                  │
│                                      │  regfile   │<────── WB write  │
│                                      └────────────┘                  │
│                                            │                         │
│                                            v                         │
│                                      ┌────────────┐                  │
│                                      │   id2ex    │                  │
│                                      └─────┬──────┘                  │
│                                            v                         │
│                                      ┌────────────┐                  │
│                                      │  execute   │                  │
│                                      └─────┬──────┘                  │
│                                            │                         │
│                      branch redirect/flush │                         │
│                                            │                         │
│                                            v                         │
│                                      ┌────────────┐                  │
│                                      │ data_ram   │                  │
│                                      └─────┬──────┘                  │
│                                            │ dmem_rdata              │
│                                            v                         │
│                                      ┌────────────┐                  │
│                         ex metadata │   ex2wb    │                  │
│                            ────────>│            │                  │
│                                      └─────┬──────┘                  │
│                                            v                         │
│                                      ┌────────────┐                  │
│                                      │ wb_stage   │                  │
│                                      └─────┬──────┘                  │
│                                            │                         │
│                                            └────> regfile write      │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

# 3. 按 5 级流水理解目前结构

经典 5 级流水是：

```text
IF -> ID -> EX -> MEM -> WB
```

 代码可以对应成：

| 流水级 | 当前模块/逻辑 |
|---|---|
| IF | `pc_counter`，指令接口 `instr_addr_o/instr_rdata_i`，`if_resp_pc_q` |
| IF/ID | `if2id` |
| ID | `decode` + `regfile` 读 + hazard detection |
| ID/EX | `id2ex` |
| EX | `execute` |
| MEM | `data_ram` |
| EX/WB 或 MEM/WB | `ex2wb` |
| WB | `wb_stage` + `regfile` 写回 |

但要注意一点：

 现在没有单独的 `ex2mem` 模块，也没有明确命名的 `mem2wb` 模块。

 现在的结构更像：

```text
IF -> IF/ID -> ID -> ID/EX -> EX -> EX/WB -> WB
                         │
                         └──── data_ram
```

也就是说：

- `execute` 直接产生 data RAM 的访问控制；
- `data_ram` 的读数据 `dmem_rdata` 直接进入 `wb_stage`；
- `ex2wb` 负责把写回相关控制信号打一拍，与 `dmem_rdata` 对齐。

如果 `data_ram` 是同步读 RAM，这种结构可能是有意设计的。  
如果 `data_ram` 是组合读 RAM，那么时序理解又不一样。

所以严格来说， 代码注释里的：

```text
IF -> IF/ID -> ID/decode -> ID/EX -> EX/MEM -> EX/WB -> WB
```

和实际模块不完全一致。实际没有显式 `EX/MEM` 流水寄存器。

---

# 4. 顶层外部接口关系

顶层模块：

```systemverilog
module riscv #(
  parameter int AW = riscv_pkg::AW,
  parameter int DW = riscv_pkg::DW,
  parameter int DATA_RAM_DEPTH = 4096
)(
  input  logic          clk_i,
  input  logic          rst_ni,
  output logic          instr_ren_o,
  output logic [AW-1:0] instr_addr_o,
  input  logic [DW-1:0] instr_rdata_i,
  output logic [DW-1:0] dbg_x3_o,
  output logic [DW-1:0] dbg_x10_o,
  output logic [DW-1:0] dbg_x11_o,
  output logic          halt_o,
  output logic          illegal_instr_o,
  output logic          exception_o
);
```

## 外部接口图

```text
                 ┌────────────────────────┐
clk_i        --->│                        │
rst_ni       --->│                        │
                 │                        │
instr_ren_o  <---│                        │---> dbg_x3_o
instr_addr_o <---│       riscv top        │---> dbg_x10_o
instr_rdata_i--->│                        │---> dbg_x11_o
                 │                        │
halt_o       <---│                        │
illegal_instr_o<-│                        │
exception_o  <---│                        │
                 └────────────────────────┘
```

---

## `clk_i`

系统时钟。

连接到所有时序模块：

```text
pc_counter
if2id
regfile
id2ex
data_ram
ex2wb
halt_q logic
```

---

## `rst_ni`

低有效复位。

连接到几乎所有时序模块：

```text
pc_counter
if2id
regfile
id2ex
data_ram
ex2wb
halt_q logic
```

---

## `instr_ren_o`

```systemverilog
assign instr_ren_o = !halt_q;
```

指令读取使能。

连接到外部 instruction memory 或 instruction bus。

当前逻辑表示：

```text
CPU 没有 halt 时持续取指
```

注意：它没有受 `pc_stall` 控制。  
也就是说，即使流水线因为 hazard stall，`instr_ren_o` 仍然为 1，只是 PC 地址不变。

这通常也可以接受，前提是外部指令存储器允许重复读取同一个地址。

---

## `instr_addr_o`

```systemverilog
assign instr_addr_o = if_pc;
```

指令地址。

来自：

```text
pc_counter.pc_o
```

连接到外部指令存储器地址端口。

---

## `instr_rdata_i`

外部指令存储器返回的指令数据。

连接到：

```systemverilog
if2id.instr_i
```

也就是：

```text
外部 imem -> riscv.instr_rdata_i -> if2id -> decode
```

---

## `dbg_x3_o/dbg_x10_o/dbg_x11_o`

来自 regfile 的调试输出：

```systemverilog
.dbg_x3_o    (dbg_x3_o),
.dbg_x10_o   (dbg_x10_o),
.dbg_x11_o   (dbg_x11_o)
```

通常用于仿真观察：

```text
x3
x10/a0
x11/a1
```

---

## `halt_o`

```systemverilog
assign halt_o = halt_q;
```

表示 CPU 已经停止。

触发条件：

```systemverilog
exception_event =
    wb_valid &&
    (wb_illegal_instr || wb_ecall || wb_ebreak || wb_mem_misaligned);
```

也就是说以下情况会 halt：

```text
非法指令
ecall
ebreak
访存未对齐
```

---

## `illegal_instr_o`

```systemverilog
assign illegal_instr_o = wb_valid && wb_illegal_instr;
```

表示 WB 阶段发现非法指令。

注意它是 WB 阶段输出，不是 decode 阶段立刻输出。

---

## `exception_o`

```systemverilog
assign exception_o = exception_event;
```

表示发生异常事件。

---

# 5. IF 阶段接口关系

相关信号：

```systemverilog
logic [AW-1:0] if_pc;
logic [AW-1:0] if_resp_pc_q;
logic          if_resp_valid_q;
logic          fetch_kill_q;
```

模块：

```systemverilog
pc_counter u_pc_counter
```

连接：

```systemverilog
pc_counter (
  .clk_i        (clk_i),
  .rst_ni       (rst_ni),
  .stall_i      (pc_stall),
  .redirect_en_i(ex_redirect_en),
  .redirect_pc_i(ex_redirect_pc),
  .pc_o         (if_pc)
);
```

## IF 阶段图

```text
                    ex_redirect_en
                    ex_redirect_pc
                         │
                         v
                  ┌─────────────┐
pc_stall -------> │ pc_counter  │
clk/rst --------> │             │
                  └──────┬──────┘
                         │ if_pc
                         v
                  instr_addr_o
                         │
                         v
              external instruction memory
                         │
                         v
                  instr_rdata_i
```

## `pc_counter` 输入输出

| 信号 | 方向 | 作用 |
|---|---|---|
| `clk_i` | input | 时钟 |
| `rst_ni` | input | 低有效复位 |
| `stall_i` | input | 暂停 PC 更新 |
| `redirect_en_i` | input | 分支/跳转重定向有效 |
| `redirect_pc_i` | input | 重定向目标 PC |
| `pc_o` | output | 当前取指 PC |

---

# 6. IF/ID 流水寄存器接口关系

模块：

```systemverilog
if2id u_if2id
```

连接：

```systemverilog
if2id (
  .clk_i   (clk_i),
  .rst_ni  (rst_ni),
  .flush_i (ifid_flush),
  .stall_i (ifid_stall),
  .valid_i (if_resp_valid_q),
  .pc_i    (if_resp_pc_q),
  .instr_i (instr_rdata_i),
  .valid_o (id_valid),
  .pc_o    (id_pc),
  .instr_o (id_instr)
);
```

## IF/ID 图

```text
     if_resp_valid_q
     if_resp_pc_q
     instr_rdata_i
           │
           v
     ┌──────────┐
     │  if2id   │ <--- ifid_flush
     │ pipeline │ <--- ifid_stall
     └────┬─────┘
          │
          v
     id_valid
     id_pc
     id_instr
```

## `if2id` 作用

保存 IF 阶段取到的：

```text
valid
pc
instr
```

送给 ID 阶段 decode。

---

# 7. ID 阶段：decode 和 regfile 关系

ID 阶段主要包括：

```text
decode
regfile read
hazard detection
```

---

## 7.1 decode 接口关系

模块：

```systemverilog
decode u_decode
```

输入：

```text
id_pc
id_instr
id_rs1_rdata
id_rs2_rdata
```

输出：

```text
id_rs1_raddr
id_rs2_raddr
id_op1
id_op2
id_store_data
id_use_rs1
id_use_rs2
id_rd
id_rf_we
id_imm
id_alu_op
id_branch_op
id_jump_op
id_mem_req
id_mem_we
id_mem_size
id_mem_unsigned
id_wb_sel
id_muldiv_valid
id_muldiv_op
id_illegal_instr
id_ecall
id_ebreak
```

## decode 和 regfile 的读接口图

```text
                         ┌────────────┐
id_pc -----------------> │            │
id_instr --------------> │   decode   │
                         │            │
id_rs1_rdata ----------> │            │
id_rs2_rdata ----------> │            │
                         │            │
id_rs1_raddr <---------- │            │
id_rs2_raddr <---------- │            │
                         └────────────┘


                         ┌────────────┐
id_rs1_raddr ----------> │            │
id_rs2_raddr ----------> │  regfile   │
                         │            │
id_rs1_rdata <---------- │            │
id_rs2_rdata <---------- │            │
                         └────────────┘
```

从 decode 视角：

```text
decode 输出寄存器读地址
regfile 返回寄存器读数据
```

所以：

```systemverilog
rf_rs1_raddr_o   是 decode output
rf_rs1_rdata_i   是 decode input
```

---

## 7.2 regfile 接口关系

模块：

```systemverilog
regfile u_regfile
```

连接：

```systemverilog
regfile (
  .clk_i       (clk_i),
  .rst_ni      (rst_ni),

  .rs1_raddr_i (id_rs1_raddr),
  .rs1_rdata_o (id_rs1_rdata),

  .rs2_raddr_i (id_rs2_raddr),
  .rs2_rdata_o (id_rs2_rdata),

  .rd_wen_i    (wb_rf_wen),
  .rd_waddr_i  (wb_rf_waddr),
  .rd_wdata_i  (wb_rf_wdata),

  .dbg_x3_o    (dbg_x3_o),
  .dbg_x10_o   (dbg_x10_o),
  .dbg_x11_o   (dbg_x11_o)
);
```

## regfile 图

```text
                  ID read side
             ┌─────────────────┐
id_rs1_raddr │                 │ id_rs1_rdata
────────────>│                 ├────────────>
id_rs2_raddr │     regfile     │ id_rs2_rdata
────────────>│                 ├────────────>
             │                 │
             │                 │ dbg_x3_o
             │                 ├────────────>
             │                 │ dbg_x10_o
             │                 ├────────────>
             │                 │ dbg_x11_o
             │                 ├────────────>
             │                 │
             │                 │
             │                 │
             │                 │
             └───────▲─────────┘
                     │
                  WB write side

wb_rf_wen  ──────────┐
wb_rf_waddr──────────┼──> write port
wb_rf_wdata──────────┘
```

---

# 8. Hazard Detection 关系

  hazard detection 在顶层直接写组合逻辑：

```systemverilog
assign hazard_stall =
    id_valid &&
    ex_valid &&
    ex_rf_we &&
    ex_rd != 5'd0 &&
    (
      (id_use_rs1 && id_rs1_raddr == ex_rd) ||
      (id_use_rs2 && id_rs2_raddr == ex_rd)
    );
```

## 当前检测内容

它检测：

```text
ID 阶段指令是否读取 EX 阶段即将写回的 rd
```

也就是：

```text
ID.rs1 == EX.rd
ID.rs2 == EX.rd
```

## Hazard 图

```text
          ID stage                       EX stage
 ┌────────────────────┐          ┌────────────────────┐
 │ id_valid           │          │ ex_valid           │
 │ id_use_rs1         │          │ ex_rf_we           │
 │ id_use_rs2         │          │ ex_rd              │
 │ id_rs1_raddr       │          └─────────┬──────────┘
 │ id_rs2_raddr       │                    │
 └─────────┬──────────┘                    │
           │                               │
           v                               v
        ┌─────────────────────────────────────┐
        │          hazard detection            │
        └──────────────────┬──────────────────┘
                           │
                           v
                    hazard_stall
```

## 当前 hazard_stall 影响

```systemverilog
assign pc_stall   = hazard_stall | ex_stall | halt_q;
assign ifid_stall = hazard_stall | ex_stall | halt_q;
assign idex_flush = ex_flush_req | hazard_stall;
```

也就是说发生 hazard 时：

```text
PC 停住
IF/ID 停住
ID/EX 插入 bubble
```

这是典型 load-use 或 RAW hazard 的处理方式。

但是这里有个重要问题。

---

# 9. 当前 hazard 处理可能不够

 设计里目前没有看到 forwarding/bypass 逻辑。

而 hazard detection 只检查了：

```text
ID 阶段 vs EX 阶段
```

没有检查：

```text
ID 阶段 vs WB 阶段
```

如果没有 forwarding，这通常是不够的。

例如：

```assembly
add x5, x1, x2
add x6, x5, x3
```

时间大概是：

```text
cycle N:
  第一条 add 在 EX
  第二条 add 在 ID
  检测到 hazard，stall 1 拍

cycle N+1:
  第一条 add 进入 WB 相关路径
  第二条 add 仍在 ID
  此时 hazard_stall 可能消失，因为 ex_valid 是 bubble

cycle N+2:
  第二条 add 进入 EX
```

问题是：  
如果第一条指令的写回还没真正写入 regfile，而第二条指令在 ID 阶段已经读取了旧值，就会算错。

解决方法一般有三种：

## 方法 1：增加 forwarding

从 EX/WB 或 WB 阶段把结果旁路到 EX 阶段。

例如：

```text
EX result -> next EX operand
WB result -> next EX operand
```

这是经典流水线做法。

## 方法 2：增加更多 stall

如果不做 forwarding，就需要 hazard detection 检查更多阶段，例如：

```text
ID vs EX
ID vs WB pending
```

甚至根据 写回时序，可能需要 stall 两拍。

## 方法 3：regfile 支持 write-first 或 WB->ID bypass

有些设计会让 regfile 在同一周期写入并读出新值，或者在 decode 处做：

```systemverilog
if (wb_rf_wen && wb_rf_waddr == id_rs1_raddr)
  id_rs1_rdata_effective = wb_rf_wdata;
else
  id_rs1_rdata_effective = id_rs1_rdata;
```

但 目前顶层没有看到这种 bypass。

所以如果 后续跑程序发现相关指令结果错误，优先检查这个问题。

---

# 10. Pipeline Control 关系

相关逻辑：

```systemverilog
assign pc_stall   = hazard_stall | ex_stall | halt_q;
assign ifid_stall = hazard_stall | ex_stall | halt_q;
assign idex_stall = ex_stall | halt_q;
assign ifid_flush = ex_flush_req | fetch_kill_q;
assign idex_flush = ex_flush_req | hazard_stall;
```

## 控制信号来源

```text
hazard_stall : 数据冒险
ex_stall     : EX 多周期运算预留，目前恒为 0
halt_q       : CPU halt
ex_flush_req : 分支/跳转冲刷请求
fetch_kill_q : 延迟一拍的 fetch kill
```

## 控制关系图

```text
hazard_stall ─┬─> pc_stall
ex_stall     ─┤
halt_q       ─┘

hazard_stall ─┬─> ifid_stall
ex_stall     ─┤
halt_q       ─┘

ex_stall ─────┬─> idex_stall
halt_q   ─────┘

ex_flush_req ─┬─> ifid_flush
fetch_kill_q ─┘

ex_flush_req ─┬─> idex_flush
hazard_stall ─┘
```

---

# 11. ID/EX 流水寄存器接口关系

模块：

```systemverilog
id2ex u_id2ex
```

输入来自 decode：

```text
id_valid
id_pc
id_instr
id_op1
id_op2
id_store_data
id_rd
id_rf_we
id_imm
id_alu_op
id_branch_op
id_jump_op
id_mem_req
id_mem_we
id_mem_size
id_mem_unsigned
id_wb_sel
id_muldiv_valid
id_muldiv_op
id_illegal_instr
id_ecall
id_ebreak
```

输出到 execute：

```text
ex_valid
ex_pc
ex_instr
ex_op1
ex_op2
ex_store_data
ex_rd
ex_rf_we
ex_imm
ex_alu_op
ex_branch_op
ex_jump_op
ex_mem_req
ex_mem_we
ex_mem_size
ex_mem_unsigned
ex_wb_sel
ex_muldiv_valid
ex_muldiv_op
ex_illegal_instr
ex_ecall
ex_ebreak
```

## ID/EX 图

```text
        ID/decode outputs
              │
              v
        ┌──────────┐
        │  id2ex   │ <--- idex_flush
        │ pipeline │ <--- idex_stall
        └────┬─────┘
             │
             v
        EX/execute inputs
```

---

# 12. EX 阶段 execute 接口关系

模块：

```systemverilog
execute u_execute
```

## 输入

来自 `id2ex`：

```text
ex_valid
ex_pc
ex_instr
ex_op1
ex_op2
ex_store_data
ex_rd
ex_rf_we
ex_imm
ex_alu_op
ex_branch_op
ex_jump_op
ex_mem_req
ex_mem_we
ex_mem_size
ex_mem_unsigned
ex_wb_sel
ex_muldiv_valid
ex_muldiv_op
ex_illegal_instr
ex_ecall
ex_ebreak
```

## 输出分三类

### 1. 输出到 data_ram

```text
dmem_ren
dmem_wen
dmem_wstrb
dmem_addr
dmem_wdata
```

### 2. 输出到 ex2wb

```text
ex_wb_valid
ex_wb_rf_wen
ex_wb_rf_waddr
ex_wb_sel_out
ex_wb_alu_data
ex_wb_pc4_data
ex_wb_mem_size
ex_wb_mem_unsigned
ex_wb_load_offset
ex_wb_illegal_instr
ex_wb_ecall
ex_wb_ebreak
ex_wb_mem_misaligned
```

### 3. 输出到 PC / flush 控制

```text
ex_redirect_en
ex_redirect_pc
ex_flush_req
```

## EX 阶段图

```text
                  from ID/EX
                     │
                     v
              ┌────────────┐
              │  execute   │
              └─────┬──────┘
                    │
      ┌─────────────┼────────────────┬───────────────────┐
      │             │                │                   │
      v             v                v                   v
 data_ram       ex2wb          pc_counter           pipeline flush
 interface      metadata       redirect             ex_flush_req

dmem_ren        wb_valid       ex_redirect_en       ifid_flush
dmem_wen        wb controls    ex_redirect_pc       idex_flush
dmem_wstrb
dmem_addr
dmem_wdata
```

---

# 13. MEM 阶段 data_ram 接口关系

模块：

```systemverilog
data_ram u_data_ram
```

连接：

```systemverilog
data_ram (
  .clk_i   (clk_i),
  .rst_ni  (rst_ni),
  .ren_i   (dmem_ren),
  .wen_i   (dmem_wen),
  .wstrb_i (dmem_wstrb),
  .addr_i  (dmem_addr),
  .wdata_i (dmem_wdata),
  .rdata_o (dmem_rdata)
);
```

## data_ram 图

```text
                from execute
                    │
                    v
              ┌────────────┐
dmem_ren  --->│            │
dmem_wen  --->│            │
dmem_wstrb--->│ data_ram   │
dmem_addr --->│            │
dmem_wdata--->│            │
              └─────┬──────┘
                    │
                    v
              dmem_rdata
                    │
                    v
                wb_stage
```

## 信号含义

| 信号 | 作用 |
|---|---|
| `dmem_ren` | 数据 RAM 读使能 |
| `dmem_wen` | 数据 RAM 写使能 |
| `dmem_wstrb` | 字节写使能 |
| `dmem_addr` | 访存地址 |
| `dmem_wdata` | store 写入数据 |
| `dmem_rdata` | load 读出数据 |

---

# 14. EX/WB 流水寄存器接口关系

模块：

```systemverilog
ex2wb u_ex2wb
```

它保存 execute 产生的写回控制和部分数据。

## 输入来自 execute

```text
ex_wb_valid
ex_wb_rf_wen
ex_wb_rf_waddr
ex_wb_sel_out
ex_wb_alu_data
ex_wb_pc4_data
ex_wb_mem_size
ex_wb_mem_unsigned
ex_wb_load_offset
ex_wb_illegal_instr
ex_wb_ecall
ex_wb_ebreak
ex_wb_mem_misaligned
```

## 输出到 wb_stage

```text
wb_valid
wb_rf_wen_pre
wb_rf_waddr_pre
wb_sel
wb_alu_data
wb_pc4_data
wb_mem_size
wb_mem_unsigned
wb_load_offset
wb_illegal_instr
wb_ecall
wb_ebreak
wb_mem_misaligned
```

## EX/WB 图

```text
        execute WB metadata
                │
                v
          ┌──────────┐
          │  ex2wb   │
          │ pipeline │
          └────┬─────┘
               │
               v
          wb_stage controls
```

注意：

```text
dmem_rdata 没有经过 ex2wb
```

而是直接：

```text
data_ram.dmem_rdata -> wb_stage.dmem_rdata_i
```

所以 `ex2wb` 里的 load 控制信号必须和 `dmem_rdata` 时序对齐。

---

# 15. WB 阶段接口关系

模块：

```systemverilog
wb_stage u_wb_stage
```

输入来自：

1. `ex2wb` 的控制和 ALU/PC4 数据；
2. `data_ram` 的 `dmem_rdata`。

输出到：

```text
regfile write port
```

## 连接

```systemverilog
wb_stage (
  .valid_i          (wb_valid),
  .rf_wen_i         (wb_rf_wen_pre),
  .rf_waddr_i       (wb_rf_waddr_pre),
  .wb_sel_i         (wb_sel),
  .alu_data_i       (wb_alu_data),
  .pc4_data_i       (wb_pc4_data),
  .mem_size_i       (wb_mem_size),
  .mem_unsigned_i   (wb_mem_unsigned),
  .load_offset_i    (wb_load_offset),
  .dmem_rdata_i     (dmem_rdata),
  .illegal_instr_i  (wb_illegal_instr),
  .ecall_i          (wb_ecall),
  .ebreak_i         (wb_ebreak),
  .mem_misaligned_i (wb_mem_misaligned),
  .rf_wen_o         (wb_rf_wen),
  .rf_waddr_o       (wb_rf_waddr),
  .rf_wdata_o       (wb_rf_wdata)
);
```

## WB 图

```text
        from ex2wb                      from data_ram
            │                                │
            v                                v
      wb_valid                         dmem_rdata
      wb_rf_wen_pre                         │
      wb_rf_waddr_pre                       │
      wb_sel                                │
      wb_alu_data                           │
      wb_pc4_data                           │
      wb_mem_size                           │
      wb_mem_unsigned                       │
      wb_load_offset                        │
            │                               │
            └──────────────┬────────────────┘
                           v
                    ┌────────────┐
                    │  wb_stage  │
                    └─────┬──────┘
                          │
                          v
                    wb_rf_wen
                    wb_rf_waddr
                    wb_rf_wdata
                          │
                          v
                       regfile
```

---

# 16. 完整 5 级流水信号关系图

下面是把 当前顶层按 5 级流水展开后的接口关系图：

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                                   IF                                         │
│                                                                              │
│  ┌────────────┐                                                              │
│  │ pc_counter │                                                              │
│  └─────┬──────┘                                                              │
│        │ if_pc                                                               │
│        v                                                                     │
│  instr_addr_o ───────────────> external instruction memory                   │
│  instr_ren_o  ───────────────> external instruction memory                   │
│                                      │                                       │
│                                      v                                       │
│                                instr_rdata_i                                 │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  IF/ID                                       │
│                                                                              │
│  if_resp_valid_q                                                             │
│  if_resp_pc_q                                                                │
│  instr_rdata_i                                                               │
│        │                                                                     │
│        v                                                                     │
│  ┌──────────┐                                                                │
│  │  if2id   │  flush = ifid_flush, stall = ifid_stall                        │
│  └────┬─────┘                                                                │
│       │                                                                      │
│       v                                                                      │
│  id_valid, id_pc, id_instr                                                   │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                   ID                                         │
│                                                                              │
│                         ┌────────────┐                                       │
│  id_pc, id_instr -----> │   decode   │                                       │
│                         └─────┬──────┘                                       │
│                               │                                              │
│        ┌──────────────────────┼──────────────────────┐                       │
│        │                      │                      │                       │
│        v                      v                      v                       │
│  regfile read addr       control signals        operands/immediate           │
│        │                                             │                       │
│        v                                             │                       │
│  ┌────────────┐                                      │                       │
│  │  regfile   │                                      │                       │
│  └─────┬──────┘                                      │                       │
│        │ read data                                   │                       │
│        └──────────────> decode                       │                       │
│                                                                              │
│  hazard detection:                                                           │
│    uses id_use_rs1/id_use_rs2/id_rs*_raddr and ex_rd/ex_rf_we/ex_valid       │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  ID/EX                                       │
│                                                                              │
│  ┌──────────┐                                                                │
│  │  id2ex   │ flush = idex_flush, stall = idex_stall                         │
│  └────┬─────┘                                                                │
│       │                                                                      │
│       v                                                                      │
│  ex_valid                                                                    │
│  ex_pc                                                                       │
│  ex_instr                                                                    │
│  ex_op1                                                                      │
│  ex_op2                                                                      │
│  ex_store_data                                                               │
│  ex_rd                                                                       │
│  ex_rf_we                                                                    │
│  ex_imm                                                                      │
│  ex_alu_op                                                                   │
│  ex_branch_op                                                                │
│  ex_jump_op                                                                  │
│  ex_mem_req                                                                  │
│  ex_mem_we                                                                   │
│  ex_mem_size                                                                 │
│  ex_mem_unsigned                                                             │
│  ex_wb_sel                                                                   │
│  ex_muldiv_valid                                                             │
│  ex_muldiv_op                                                                │
│  ex_illegal_instr                                                            │
│  ex_ecall                                                                    │
│  ex_ebreak                                                                   │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                   EX                                         │
│                                                                              │
│  ┌────────────┐                                                              │
│  │  execute   │                                                              │
│  └─────┬──────┘                                                              │
│        │                                                                     │
│        ├────> branch/jump redirect:                                          │
│        │        ex_redirect_en                                               │
│        │        ex_redirect_pc                                               │
│        │        ex_flush_req                                                 │
│        │                                                                     │
│        ├────> data RAM interface:                                            │
│        │        dmem_ren                                                     │
│        │        dmem_wen                                                     │
│        │        dmem_wstrb                                                   │
│        │        dmem_addr                                                    │
│        │        dmem_wdata                                                   │
│        │                                                                     │
│        └────> WB metadata:                                                   │
│                 ex_wb_valid                                                  │
│                 ex_wb_rf_wen                                                 │
│                 ex_wb_rf_waddr                                               │
│                 ex_wb_sel_out                                                │
│                 ex_wb_alu_data                                               │
│                 ex_wb_pc4_data                                               │
│                 ex_wb_mem_size                                               │
│                 ex_wb_mem_unsigned                                           │
│                 ex_wb_load_offset                                            │
│                 ex_wb_illegal_instr                                          │
│                 ex_wb_ecall                                                  │
│                 ex_wb_ebreak                                                 │
│                 ex_wb_mem_misaligned                                         │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  MEM                                         │
│                                                                              │
│  ┌────────────┐                                                              │
│  │  data_ram  │                                                              │
│  └─────┬──────┘                                                              │
│        │                                                                     │
│        v                                                                     │
│  dmem_rdata                                                                  │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                  EX/WB                                       │
│                                                                              │
│  ┌──────────┐                                                                │
│  │  ex2wb   │ receives EX WB metadata                                        │
│  └────┬─────┘                                                                │
│       │                                                                      │
│       v                                                                      │
│  wb_valid                                                                    │
│  wb_rf_wen_pre                                                               │
│  wb_rf_waddr_pre                                                             │
│  wb_sel                                                                      │
│  wb_alu_data                                                                 │
│  wb_pc4_data                                                                 │
│  wb_mem_size                                                                 │
│  wb_mem_unsigned                                                             │
│  wb_load_offset                                                              │
│  wb_illegal_instr                                                            │
│  wb_ecall                                                                    │
│  wb_ebreak                                                                   │
│  wb_mem_misaligned                                                           │
│                                                                              │
└───────────────┬──────────────────────────────────────────────────────────────┘
                │
                v
┌──────────────────────────────────────────────────────────────────────────────┐
│                                   WB                                         │
│                                                                              │
│  ┌────────────┐                                                              │
│  │  wb_stage  │ <------ dmem_rdata                                           │
│  └─────┬──────┘                                                              │
│        │                                                                     │
│        v                                                                     │
│  wb_rf_wen                                                                   │
│  wb_rf_waddr                                                                 │
│  wb_rf_wdata                                                                 │
│        │                                                                     │
│        v                                                                     │
│  regfile write port                                                          │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

# 17. 各模块之间的关键信号连接表

## 17.1 `pc_counter` 连接关系

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| pipeline control | `pc_stall` | `pc_counter.stall_i` | 暂停 PC |
| execute | `ex_redirect_en` | `pc_counter.redirect_en_i` | 跳转/分支重定向 |
| execute | `ex_redirect_pc` | `pc_counter.redirect_pc_i` | 新 PC |
| pc_counter | `if_pc` | `instr_addr_o` | 取指地址 |

---

## 17.2 指令接口连接关系

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| riscv top | `instr_ren_o` | 外部指令存储器 | 取指使能 |
| riscv top | `instr_addr_o` | 外部指令存储器 | 取指地址 |
| 外部指令存储器 | `instr_rdata_i` | `if2id.instr_i` | 指令数据 |

---

## 17.3 `if2id` 连接关系

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| IF response logic | `if_resp_valid_q` | `if2id.valid_i` | 指令有效 |
| IF response logic | `if_resp_pc_q` | `if2id.pc_i` | 当前指令 PC |
| 外部 imem | `instr_rdata_i` | `if2id.instr_i` | 当前指令 |
| pipeline control | `ifid_flush` | `if2id.flush_i` | 冲刷流水级 |
| pipeline control | `ifid_stall` | `if2id.stall_i` | 暂停 IF/ID |
| if2id | `id_valid` | decode/hazard/id2ex | ID 指令有效 |
| if2id | `id_pc` | decode/id2ex | ID 指令 PC |
| if2id | `id_instr` | decode/id2ex | ID 指令 |

---

## 17.4 `decode` 和 `regfile` 连接关系

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| if2id | `id_pc` | decode | 当前指令 PC |
| if2id | `id_instr` | decode | 当前指令 |
| decode | `id_rs1_raddr` | regfile | rs1 读地址 |
| decode | `id_rs2_raddr` | regfile | rs2 读地址 |
| regfile | `id_rs1_rdata` | decode | rs1 数据 |
| regfile | `id_rs2_rdata` | decode | rs2 数据 |
| wb_stage | `wb_rf_wen` | regfile | 写回使能 |
| wb_stage | `wb_rf_waddr` | regfile | 写回地址 |
| wb_stage | `wb_rf_wdata` | regfile | 写回数据 |

---

## 17.5 `decode` 到 `id2ex`

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| decode | `id_op1` | id2ex | EX 操作数 1 |
| decode | `id_op2` | id2ex | EX 操作数 2 |
| decode | `id_store_data` | id2ex | store 写数据 |
| decode | `id_rd` | id2ex | 目的寄存器 |
| decode | `id_rf_we` | id2ex | 寄存器写使能 |
| decode | `id_imm` | id2ex | 立即数 |
| decode | `id_alu_op` | id2ex | ALU 控制 |
| decode | `id_branch_op` | id2ex | 分支控制 |
| decode | `id_jump_op` | id2ex | 跳转控制 |
| decode | `id_mem_req` | id2ex | 访存请求 |
| decode | `id_mem_we` | id2ex | 访存写使能 |
| decode | `id_mem_size` | id2ex | 访存大小 |
| decode | `id_mem_unsigned` | id2ex | load 是否无符号扩展 |
| decode | `id_wb_sel` | id2ex | 写回来源选择 |
| decode | `id_muldiv_valid` | id2ex | 乘除法有效 |
| decode | `id_muldiv_op` | id2ex | 乘除法操作 |
| decode | `id_illegal_instr` | id2ex | 非法指令 |
| decode | `id_ecall` | id2ex | ecall |
| decode | `id_ebreak` | id2ex | ebreak |

---

## 17.6 `id2ex` 到 `execute`

基本是把上一节 `id_*` 信号打一拍，变成 `ex_*` 信号：

```text
id_op1            -> ex_op1
id_op2            -> ex_op2
id_store_data     -> ex_store_data
id_rd             -> ex_rd
id_rf_we          -> ex_rf_we
id_imm            -> ex_imm
id_alu_op         -> ex_alu_op
id_branch_op      -> ex_branch_op
id_jump_op        -> ex_jump_op
id_mem_req        -> ex_mem_req
id_mem_we         -> ex_mem_we
id_mem_size       -> ex_mem_size
id_mem_unsigned   -> ex_mem_unsigned
id_wb_sel         -> ex_wb_sel
id_muldiv_valid   -> ex_muldiv_valid
id_muldiv_op      -> ex_muldiv_op
id_illegal_instr  -> ex_illegal_instr
id_ecall          -> ex_ecall
id_ebreak         -> ex_ebreak
```

---

## 17.7 `execute` 到 `data_ram`

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| execute | `dmem_ren` | data_ram | 读使能 |
| execute | `dmem_wen` | data_ram | 写使能 |
| execute | `dmem_wstrb` | data_ram | 字节写掩码 |
| execute | `dmem_addr` | data_ram | 数据地址 |
| execute | `dmem_wdata` | data_ram | store 数据 |
| data_ram | `dmem_rdata` | wb_stage | load 数据 |

---

## 17.8 `execute` 到 `pc_counter` 和 flush

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| execute | `ex_redirect_en` | pc_counter | 分支/跳转重定向 |
| execute | `ex_redirect_pc` | pc_counter | 新 PC |
| execute | `ex_flush_req` | pipeline control | 冲刷流水线 |

---

## 17.9 `execute` 到 `ex2wb`

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| execute | `ex_wb_valid` | ex2wb | 写回级有效 |
| execute | `ex_wb_rf_wen` | ex2wb | RF 写使能 |
| execute | `ex_wb_rf_waddr` | ex2wb | RF 写地址 |
| execute | `ex_wb_sel_out` | ex2wb | WB 数据来源选择 |
| execute | `ex_wb_alu_data` | ex2wb | ALU 结果 |
| execute | `ex_wb_pc4_data` | ex2wb | PC+4 |
| execute | `ex_wb_mem_size` | ex2wb | load 大小 |
| execute | `ex_wb_mem_unsigned` | ex2wb | load 是否无符号 |
| execute | `ex_wb_load_offset` | ex2wb | load 地址低位 offset |
| execute | `ex_wb_illegal_instr` | ex2wb | 非法指令 |
| execute | `ex_wb_ecall` | ex2wb | ecall |
| execute | `ex_wb_ebreak` | ex2wb | ebreak |
| execute | `ex_wb_mem_misaligned` | ex2wb | 访存未对齐 |

---

## 17.10 `ex2wb` 到 `wb_stage`

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| ex2wb | `wb_valid` | wb_stage | WB 有效 |
| ex2wb | `wb_rf_wen_pre` | wb_stage | 写使能预处理 |
| ex2wb | `wb_rf_waddr_pre` | wb_stage | 写地址 |
| ex2wb | `wb_sel` | wb_stage | 写回选择 |
| ex2wb | `wb_alu_data` | wb_stage | ALU 结果 |
| ex2wb | `wb_pc4_data` | wb_stage | PC+4 |
| ex2wb | `wb_mem_size` | wb_stage | load 大小 |
| ex2wb | `wb_mem_unsigned` | wb_stage | load 是否无符号 |
| ex2wb | `wb_load_offset` | wb_stage | load offset |
| ex2wb | `wb_illegal_instr` | wb_stage / exception | 非法指令 |
| ex2wb | `wb_ecall` | wb_stage / exception | ecall |
| ex2wb | `wb_ebreak` | wb_stage / exception | ebreak |
| ex2wb | `wb_mem_misaligned` | wb_stage / exception | 访存未对齐 |

---

## 17.11 `wb_stage` 到 `regfile`

| 来源 | 信号 | 去向 | 作用 |
|---|---|---|---|
| wb_stage | `wb_rf_wen` | regfile | 最终写使能 |
| wb_stage | `wb_rf_waddr` | regfile | 最终写地址 |
| wb_stage | `wb_rf_wdata` | regfile | 最终写数据 |

---

# 18. 当前顶层还建议重点检查的地方

## 18.1 `id_store_data` 未声明

这个必须修。

```systemverilog
logic [DW-1:0] id_store_data;
```

---

## 18.2 hazard detection 可能不完整

目前只有：

```text
ID vs EX
```

如果没有 forwarding，建议至少检查：

```text
ID vs EX
ID vs WB
```

或者加入 forwarding。

---

## 18.3 没有显式 EX/MEM 流水寄存器

如果 目标是标准 5 级流水，建议结构更清晰地写成：

```text
IF
IF/ID
ID
ID/EX
EX
EX/MEM
MEM
MEM/WB
WB
```

目前  `ex2wb` 更像把 EX 结果直接送 WB 控制，对初学调试来说容易混淆。

---

## 18.4 指令存储器时序需要确认

 取指逻辑里有：

```systemverilog
if_resp_pc_q    <= if_pc;
if_resp_valid_q <= !halt_q;
```

然后：

```systemverilog
if2id.instr_i = instr_rdata_i;
```

这隐含了某种 instruction memory 时序假设。

如果外部指令存储器是同步读，需要确认：

```text
if_resp_pc_q 和 instr_rdata_i 是否对应同一条指令
```

否则 PC 和指令可能错位。

---

## 18.5 `instr_ren_o` 没有受 stall 控制

现在：

```systemverilog
assign instr_ren_o = !halt_q;
```

如果外部 imem 简单组合读，问题不大。

如果是总线接口、握手接口或同步 RAM，可能希望：

```systemverilog
assign instr_ren_o = !halt_q && !pc_stall;
```

但这要看  instruction memory 设计。

---

# 19. 总结

 当前顶层的模块关系可以总结成：

```text
pc_counter
  -> external instruction memory
  -> if2id
  -> decode
  <-> regfile read
  -> id2ex
  -> execute
     -> pc redirect / pipeline flush
     -> data_ram
     -> ex2wb
  -> wb_stage
  -> regfile write
```

按 5 级流水理解是：

```text
IF  : pc_counter + instruction fetch
ID  : if2id output + decode + regfile read + hazard detection
EX  : id2ex output + execute
MEM : data_ram
WB  : ex2wb + wb_stage + regfile write
```

但当前实现不是非常标准的显式五级寄存器结构，因为：

```text
没有单独 ex2mem/mem2wb
而是 execute 直接访问 data_ram，ex2wb 保存写回控制
```

最需要立刻修的是：

```systemverilog
id_store_data 没声明，id_data 没用
```

建议改成：

```systemverilog
logic [DW-1:0] id_op1;
logic [DW-1:0] id_op2;
logic [DW-1:0] id_store_data;
```

然后删除：

```systemverilog
logic [DW-1:0] id_data;
```
