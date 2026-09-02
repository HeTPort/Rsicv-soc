# CPU Verification Framework and Debug Methodology

## 1. Overview

本项目为 RV32 流水线 CPU 建立了一套由 **裸机定向测试（bare-metal directed test）**、**memory-mapped `tohost` 结果上报**、**SystemVerilog Assertion（SVA）** 和 **波形调试** 组成的验证框架。

该框架用于形成从软件测试到 RTL 根因定位的完整闭环，主要验证目标包括：

- RV32 指令的功能正确性；
- Trap/Exception 行为是否符合 RISC-V 特权架构要求；
- 流水线 flush、kill 和 precise exception 是否正确；
- 异常发生时，年轻指令的 CSR、GPR 和 Memory 副作用是否被可靠屏蔽；
- 仿真失败后能否快速定位到具体周期、流水级和控制信号；
- RTL 修改后能否通过自动回归确认修复未引入新的功能退化。

整体验证流程如下：

```text
Assembly Test
      |
      v
RISC-V Toolchain
      |
      v
ELF / HEX / Disassembly
      |
      v
RTL Simulation
      |
      +-------------------+-------------------+
      |                   |                   |
      v                   v                   v
tohost Result         Assertions          Waveform
      |                   |                   |
      +-------------------+-------------------+
                          |
                          v
                  PASS / FAIL / Root Cause
```

`tohost` 用于报告软件可见的最终结果，Assertion 用于在非法微架构状态发生的第一时间停止仿真，波形则用于解释错误发生的时序和传播路径。

---

## 2. Test Framework

### 2.1 Test Artifact Organization

每个裸机测试通常包含以下产物：

```text
testdata/
├── <test_name>_test.S      # 定向汇编测试源码
├── <test_name>_test.elf    # 带符号信息的可执行文件
├── <test_name>_test.hex    # 仿真器加载的存储器镜像
└── <test_name>_test.dis    # 用于波形和 PC 对照的反汇编文件
```

以 precise trap CSR squash 测试为例：

```text
testdata/
├── precise_trap_csr_squash_test.S
├── precise_trap_csr_squash_test.elf
├── precise_trap_csr_squash_test.hex
└── precise_trap_csr_squash_test.dis
```

推荐保留 ELF 和反汇编文件。HEX 用于加载指令或数据存储器，而 ELF 符号及反汇编可以把波形中的 PC 快速映射回测试源码。

### 2.2 Build and Simulation Flow

测试构建与执行过程如下：

```text
Assembly Source
      |
      | riscv*-unknown-elf-gcc / as
      v
ELF Image
      |
      +----> objdump ----> Disassembly
      |
      +----> objcopy ----> HEX/Binary Image
                              |
                              v
                       RTL Testbench
                              |
                              v
                    tohost / Assertion Result
```

回归脚本应自动完成以下工作：

1. 解析测试清单并选择目标测试；
2. 构建或定位对应的 HEX 镜像；
3. 将镜像加载到仿真存储器；
4. 配置入口地址、`tohost` 地址和超时周期；
5. 启动 RTL 仿真并按需生成波形；
6. 监控 Assertion、`tohost` 和 timeout；
7. 汇总 PASS、FAIL、TIMEOUT 及日志路径。

### 2.3 Test Manifest

建议使用统一的测试清单，例如 `sim/regress/tests.json`，集中维护镜像、超时和标签等配置：

```json
{
  "default": {
    "tohost_addr": 4096,
    "timeout_cycles": 1000
  },
  "tests": [
    {
      "name": "precise_trap_csr_squash",
      "image": "testdata/precise_trap_csr_squash_test.hex",
      "timeout_cycles": 1000,
      "tags": [
        "trap",
        "csr",
        "precise"
      ]
    }
  ]
}
```

其中：

- `name`：测试的唯一名称；
- `image`：仿真加载的存储器镜像；
- `timeout_cycles`：防止 CPU 跑飞或测试未结束；
- `tohost_addr`：测试结果上报地址，可由单个测试覆盖默认值；
- `tags`：用于按功能域筛选回归测试。

测试地址、目录及命令行参数应以项目实际实现为准。测试清单应作为 testbench 和回归脚本的单一配置来源，避免相同参数分散在多个脚本中。

### 2.4 Testbench Termination Rules

建议 testbench 明确定义以下结束状态：

| 状态 | 触发条件 | 结果 |
| --- | --- | --- |
| PASS | `tohost == 1` | 测试通过 |
| FAIL | `tohost != 0 && tohost != 1` | 测试失败，并报告错误码 |
| ASSERTION FAIL | SVA 失败或 `$fatal` | RTL 约束被破坏 |
| TIMEOUT | 达到 `timeout_cycles`，且 `tohost == 0` | 测试未正常结束 |

终止日志至少应包含测试名、仿真周期、PC、`tohost` 值和波形文件路径。

---

## 3. `tohost` Result Reporting Mechanism

### 3.1 Motivation

裸机 CPU 通常没有操作系统、标准输出、UART 驱动或 `printf` 环境。测试程序需要一种简单、确定且不依赖复杂外设的方法向 testbench 报告执行结果。

本项目采用 memory-mapped `tohost` 协议：

```text
Test Program
      |
      | store
      v
Configured Memory Address
      |
      v
Testbench Monitor
      |
      v
PASS / Failure Code
```

从 CPU 的角度看，写入 `tohost` 与普通 store 没有区别；“该地址代表测试结果”是测试软件与 testbench 之间的协议，不属于 RISC-V ISA，也不是标准 CSR。

### 3.2 Address Configuration

典型默认地址可以在测试清单中配置为：

```json
{
  "tohost_addr": 4096
}
```

十六进制表示为 `0x00001000`。某些存储器布局不同的测试可以单独覆盖该值。软件、链接脚本、testbench 和回归配置必须对该地址保持一致。

### 3.3 Software Interface

汇编测试可使用统一宏上报结果：

```assembly
.equ TOHOST, 0x1000

.macro TEST_PASS
    li  t0, TOHOST
    li  t1, 1
    sw  t1, 0(t0)
.endm

.macro TEST_FAIL code
    li  t0, TOHOST
    li  t1, \code
    sw  t1, 0(t0)
.endm
```

结果编码约定：

```text
tohost = 0    Test is still running
tohost = 1    PASS
tohost > 1    FAIL; value is the test-defined failure code
```

失败码应在测试源码附近定义，并在文档或日志中映射到明确原因。例如：

| Failure code | Meaning |
| ---: | --- |
| 2 | Trap handler was not entered |
| 3 | `mcause` did not match the expected cause |
| 4 | A younger CSR instruction produced a side effect |
| 5 | `mepc` did not point to the trapping instruction |

具体编码由各测试定义，回归报告不应把错误码误解为地址。

### 3.4 Testbench Monitor Example

下面的代码展示一种概念性监控方式。实际信号名应与项目总线或存储器接口保持一致：

```systemverilog
always_ff @(posedge clk_i) begin
  if (rst_ni && data_req_i && data_we_i &&
      (data_addr_i == tohost_addr)) begin
    if (data_wdata_i == 32'd1) begin
      $display("[TB] RESULT: PASS");
      $finish;
    end
    else if (data_wdata_i != 32'd0) begin
      $display("[TB] RESULT: FAIL, tohost = 0x%08x",
               data_wdata_i);
      $fatal(1);
    end
  end
end
```

若设计支持 byte enable，监控器还应根据写掩码重建最终 word，避免 partial store 被错误识别。

### 3.5 Example: Precise Trap CSR Squash

测试目标是验证 trap 发生后，所有比异常指令更年轻的指令均被取消，且不能修改架构状态。

```text
I0: ecall
I1: csrw mscratch, x7    # younger instruction; must be killed
```

期望行为：

```text
ECALL detected
      |
      v
Trap accepted
      |
      v
Pipeline redirect and kill
      |
      v
I1 becomes invalid
      |
      v
No CSR side effect
```

若 flush 只清除了流水包的 `valid` 位，但 CSR write enable 未与 `valid` 联合门控，I1 仍可能错误修改 `mscratch`。Trap handler 检测到该问题后写入失败码：

```text
[TB] tohost = 0x00000004
[TB] RESULT: FAIL
```

此时 `4` 表示软件定义的“年轻 CSR 指令未被正确 squash”，而不是地址 `0x4`。

---

## 4. Assertion Strategy

### 4.1 Purpose

`tohost` 能说明软件最终观察到了错误，但错误可能在几十个周期之前已经发生。Assertion 应把关键微架构约束编码到 RTL 附近，在非法状态首次出现时立即报告。

本项目的核心原则是：

> 无效、被 kill 或产生 trap 的指令不得产生任何架构可见副作用。

需要统一受指令有效位控制的副作用包括：

- GPR writeback；
- CSR write；
- Memory write；
- MMIO transaction；
- 分支预测器或其他需要精确提交的状态更新。

推荐在副作用的最终发起点进行安全门控：

```systemverilog
assign wb_rf_we_safe = wb_pkt.valid && wb_pkt.rf_we && !wb_trap_event;
assign wb_csr_we     = wb_pkt.valid && wb_pkt.csr.valid &&
                       wb_pkt.csr.we && !wb_trap_event;
assign mem_we_safe   = mem_pkt.valid && mem_pkt.mem_we &&
                       !mem_pkt.killed;
```

清空整个流水包可以降低残留控制字段的风险，但最终副作用仍应显式依赖 `valid`。

### 4.2 Assertion Placement

Assertion 可按职责分为三层：

| Layer | Purpose | Example |
| --- | --- | --- |
| Protocol | 检查总线握手和请求稳定性 | request held until ready |
| Pipeline | 检查 stall、kill、redirect 和 valid 传播 | kill creates a bubble |
| Commit | 检查架构状态更新是否合法 | invalid packet cannot write CSR |

优先把 Assertion 放在最接近被保护状态的位置。例如，CSR 写约束应靠近最终 CSR write enable，而不是只检查译码阶段控制信号。

### 4.3 Invalid Packet Cannot Modify CSR

```systemverilog
property p_invalid_packet_no_csr_write;
  @(posedge clk_i) disable iff (!rst_ni)
    !ex2wb_pkt_out.valid |-> !wb_csr_we;
endproperty

a_invalid_packet_no_csr_write:
  assert property (p_invalid_packet_no_csr_write)
  else $error("Invalid EX/WB packet attempted a CSR write");
```

### 4.4 Trap Cannot Commit Normal Side Effects

```systemverilog
property p_trap_no_normal_side_effect;
  @(posedge clk_i) disable iff (!rst_ni)
    wb_trap_event |-> (!wb_rf_we_safe && !wb_csr_we && !wb_mem_we);
endproperty

a_trap_no_normal_side_effect:
  assert property (p_trap_no_normal_side_effect)
  else $error("Trapping instruction committed a normal side effect");
```

如果某类 trap 与 store 的检测和提交位于不同阶段，应根据实际时序拆分属性，避免使用错误的同周期假设。

### 4.5 Pipeline Kill Must Create a Bubble

```systemverilog
property p_kill_creates_bubble;
  @(posedge clk_i) disable iff (!rst_ni)
    pipe_kill |=> (!ex2wb_pkt_out.valid &&
                   !ex2wb_pkt_out.csr.valid &&
                   !ex2wb_pkt_out.mem_valid);
endproperty

a_kill_creates_bubble:
  assert property (p_kill_creates_bubble)
  else $error("Pipeline kill did not clear the EX/WB packet");
```

该属性中的延迟操作符应与设计的寄存器边界保持一致。若 `pipe_kill` 在同一时钟沿直接覆盖目标寄存器，则检查下一采样周期；若目标信号为组合输出，则可能需要同周期检查。

### 4.6 Additional Recommended Properties

建议逐步补充以下约束：

- stall 时流水寄存器内容保持稳定；
- redirect 后错误路径指令不能到达 commit；
- `mepc` 保存产生同步异常的指令地址；
- `mcause` 与 trap 类型一致；
- `mret` 重定向到 `mepc`；
- 未对齐或非法访存不能产生 memory write；
- reset 期间没有架构状态写入；
- 同一指令最多提交一次；
- timeout 前 testbench 只能接受一次终止结果。

Assertion 名称、失败信息和波形信号应稳定，便于回归系统对失败进行分类。

---

## 5. Waveform Debug Methodology

### 5.1 Role of Waveform Debug

三种验证手段的职责不同：

```text
tohost     -> 哪个软件检查失败
Assertion  -> 哪条 RTL 约束、在哪个周期被破坏
Waveform   -> 错误如何沿流水线传播，以及为什么发生
```

波形调试应从失败点向前追溯，而不是从 reset 后第一个周期开始逐拍浏览。

### 5.2 Recommended Signal Groups

#### Pipeline state

```text
if_valid
id_valid
ex_valid
mem_valid
wb_valid
if_pc
id_pc
ex_pc
mem_pc
wb_pc
```

#### Trap and redirect

```text
trap_valid
trap_cause
trap_pc
trap_target
redirect_valid
redirect_pc
pipe_kill
```

#### Machine-mode CSRs

```text
mstatus
mtvec
mepc
mcause
mtval
mscratch
```

#### CSR operation

```text
csr_valid
csr_addr
csr_cmd
csr_we
csr_wdata
csr_rdata
```

#### Architectural side effects

```text
wb_rf_we
wb_rf_waddr
wb_rf_wdata
wb_csr_we
mem_write
mem_addr
mem_wdata
```

#### Flow control

```text
stall
flush
kill
ready
valid
```

实际工程中应按模块层级保存一组稳定的波形配置，以减少重复添加信号的时间。

### 5.3 Debug Procedure

发生失败时，推荐按以下顺序定位：

1. 从回归日志取得测试名、失败码、失败周期和 Assertion 信息；
2. 在测试源码中查找失败码，确定失败的架构检查；
3. 使用反汇编将相关 PC 映射到具体指令；
4. 在波形中定位 Assertion 或 `tohost` 写入周期；
5. 向前追踪对应指令的 PC、valid 和流水包；
6. 检查 trap、redirect、stall 和 kill 的先后关系；
7. 检查副作用控制信号是否由有效位正确门控；
8. 形成最小根因假设，并用新增 Assertion 或定向测试验证；
9. 修复后先运行失败测试，再运行相关标签及全量回归。

### 5.4 Precise Trap Debug Example

已知软件结果：

```text
tohost = 4
```

结合失败码定义可知，trap 后的年轻 CSR 指令产生了副作用。典型波形可能表现为：

```text
Cycle N:
  ex_pc       = address of ECALL
  trap_valid  = 1

Cycle N+1:
  pipe_kill   = 1
  redirect_pc = mtvec

Cycle N+2:
  wb_valid    = 0
  csr_valid   = 1
  wb_csr_we   = 1    <-- illegal side effect
```

由此可缩小根因范围：

```text
Pipeline flush
      |
      v
valid bit cleared
      |
      v
CSR control remains asserted
      |
      v
wb_csr_we is not gated by packet validity
      |
      v
mscratch is corrupted
```

修复方向通常包括：

1. kill 时清空完整流水包；
2. 在最终 CSR 写入口使用 `packet.valid && csr.valid && csr.we`；
3. 保留 Assertion，防止同类问题回归。

---

## 6. Layered Debug Model

本项目采用从架构结果逐层下钻到 RTL 根因的调试方法：

```text
Software Check
      |
      v
tohost Failure Code
      |
      v
Architectural Failure Category
      |
      v
Assertion Failure
      |
      v
Waveform and PC Trace
      |
      v
RTL Root Cause
      |
      v
Fix + Directed Test + Regression
```

以 CSR squash 问题为例：

```text
tohost = 4
      |
      v
Younger CSR instruction was not squashed
      |
      v
Assertion: invalid packet attempted CSR write
      |
      v
Waveform: wb_valid = 0, wb_csr_we = 1
      |
      v
Root cause: CSR side effect was not gated by packet validity
```

这种分层方式能把“软件结果错误”快速转换为可修复的 RTL 问题，并把一次性调试经验沉淀为可持续运行的 Assertion 和回归测试。

---

## 7. Verification Coverage

### 7.1 Directed Test Coverage

建议维护功能特性到测试用例的可追踪矩阵。以下表格可作为初始覆盖计划：

| Feature | Representative test | Key checks |
| --- | --- | --- |
| RV32I arithmetic/logic | `rv32i_*` | GPR result and flags/control |
| RV32M operations | `rv32m_*` | MUL/DIV result and corner cases |
| Branch and jump | `branch_*`, `jal_*` | target PC, link register, squash |
| Load/store | `load_store_*` | address, byte enable, sign extension |
| ECALL | `ecall` | `mcause`, `mepc`, handler entry |
| EBREAK | `ebreak` | breakpoint trap semantics |
| Illegal instruction | `illegal_opcode` | illegal-instruction cause and `mtval` |
| Misaligned load | `misaligned_lw` | trap with no GPR side effect |
| Misaligned store | `misaligned_sw` | trap with no memory side effect |
| CSR access | `csr_*` | CSR read-modify-write behavior |
| MRET | `mret` | privilege state restoration and redirect |
| Precise trap squash | `precise_trap_csr_squash` | no younger CSR/GPR/Memory side effect |

表中的名称是推荐约定，最终应与测试清单中的真实测试名保持一致。

### 7.2 Coverage Dimensions

除测试数量外，还应关注以下覆盖维度：

- 不同 trap cause 是否被触发；
- trap 出现在不同流水级和流控组合时是否被验证；
- trap 与 stall、branch redirect、memory wait-state 的交叉场景；
- 各类 CSR 地址与 CSR 指令操作是否被覆盖；
- 被 kill 的指令类型是否包含 CSR、GPR writeback、load/store 和 branch；
- PASS、FAIL、ASSERTION FAIL 和 TIMEOUT 路径是否都经过 testbench 自检。

后续可加入 functional coverage：

```systemverilog
covergroup trap_cg @(posedge clk_i);
  cp_cause: coverpoint trap_cause;
  cp_stage: coverpoint trap_stage;
  cp_stall: coverpoint pipeline_stall;
  cx_cause_stage: cross cp_cause, cp_stage;
endgroup
```

Coverage 的目标不是单纯提高百分比，而是证明关键架构场景及其危险交叉组合已经被观察和检查。

---

## 8. Regression and Reporting

建议为每次 RTL 修改运行分层回归：

```text
Failing Directed Test
      |
      v
Feature-tag Regression
      |
      v
Full Regression
```

回归报告至少应包含：

- commit 或 RTL 版本；
- simulator 和主要编译参数；
- 测试总数及 PASS/FAIL/TIMEOUT 数量；
- 每个失败测试的 `tohost` 值或 Assertion 名称；
- 日志、波形和反汇编路径；
- 仿真周期及运行时间。

建议将测试配置、随机种子和工具版本写入日志，使失败能够稳定复现。

---

## 9. Engineering Lessons

### 9.1 Validity Must Guard Every Side Effect

流水包中的 `valid` 不是仅供调试观察的状态位，而是所有架构副作用的资格条件。任何未与 `valid` 联合门控的控制字段都可能形成 ghost side effect。

```text
Invalid instruction
      |
      +----> No GPR write
      +----> No CSR write
      +----> No memory/MMIO write
```

### 9.2 Clear the Packet and Guard the Commit Point

只清除 `valid` 位容易让控制字段在波形中残留并增加误用风险。推荐同时采用两层保护：

- kill/flush 时将流水包恢复为定义明确的 bubble；
- 在最终 commit 或请求发起点再次使用 `valid` 门控。

### 9.3 Preserve Every Useful Failure as a Regression Asset

每个定位完成的 bug 最好留下三类资产：

1. 一个能够稳定复现问题的最小定向测试；
2. 一条描述设计不变量的 Assertion；
3. 一段记录症状、根因和修复方式的 bug note。

这样，同类错误会从“需要人工重新调试的问题”转变为“回归中自动阻止的问题”。

---

## 10. Accepted Scalable UVM Expansion

UVM 作为增量验证层加入现有框架，不替代定向测试、ACT4、`tohost`、
SVA/formal、固件测试、综合时序和板级验证。详细决策、来源项目、风险和
阶段门槛见
[`AR026_SCALABLE_UVM_VERIFICATION_ARCHITECTURE.md`](../doc/AR026_SCALABLE_UVM_VERIFICATION_ARCHITECTURE.md)。

### 10.1 Stable abstraction boundary

稳定边界不是当前 CoreBus 或 DUT 引脚，而是少量具有明确语义的事务：

| Domain | Transaction | Meaning |
| --- | --- | --- |
| Retirement | `retire_event`, `trap_entry_event` | 已完成指令及同步 trap；独立的同步/异步 trap-entry 观察 |
| Memory | `mem_access` | 与 CoreBus/AXI 引脚无关的读写请求和完成 |
| Translation | `translation_event` | 地址翻译、权限、特权级和 fault |
| Coherence | `coherence_event` | cache-line 状态、probe、响应和数据传输 |
| Accelerator | `accel_job`, `accel_completion` | GPU/NPU 命令、上下文、完成和异常 |

SystemVerilog `interface` 负责信号分组、clocking block、modport 和协议
Assertion；UVM sequence item / analysis transaction 负责组件间的语义数据。
协议 agent 只处理引脚时序，adapter 显式完成 protocol/domain/model 之间的
转换，scoreboard 和 reference model 不依赖当前物理接口。

```text
test / workload / virtual sequence
                 |
                 v
       domain transaction + coverage
                 |
       +---------+----------+
       |                    |
       v                    v
scoreboard/model       explicit adapter
                            |
                            v
                    protocol VIP/interface
                            |
                            v
                           DUT
```

### 10.2 Planned ownership and directories

```text
verif/
├── act4/                existing architecture-test integration
├── uvm/
│   ├── common/          base config, reset/clock, reporting
│   ├── domains/         retirement, memory, translation, coherence, accelerator
│   ├── vip/             pin-level agents, monitors, local protocol coverage
│   ├── adapters/        protocol/domain/reference-model conversion
│   ├── models/          authoritative memory, ISS, cache, accelerator models
│   ├── ral/             generated UVM register models
│   ├── envs/            block, core, and SoC environments
│   ├── sequences/       protocol and multi-agent virtual sequences
│   ├── coverage/        cross-domain functional coverage
│   ├── tests/           small configuration/policy selections
│   └── tb/              interfaces, wrappers, assertions, static top
├── generators/          riscv-dv and later workload generators
├── workloads/           assembly, C, kernels, tensors, signatures
├── testplans/           requirement-to-test/coverage traceability
├── sim/                 UVM filelists, scripts, manifests, CI entry
└── generated/           disposable generated tests/RAL/results
```

只在真实组件出现时创建对应目录，不预先提交空的 cache/MMU/GPU/NPU
占位实现。agent-local coverage 留在 `vip/`，只有跨 agent/domain 的 coverage
进入顶层 `coverage/`。

### 10.3 Concurrency rules

为避免未来多核、乱序、多退休端口和 GPU 并发导致接口重写：

- 基础事务保留 `source_id`、`hart_id`、`txn_id`、`epoch` 和 `order`；
- `retire_lane`、`context_id`、`warp_id`、`lane_id` 只进入需要它们的 domain；
- 只有协议保证严格顺序时才能使用 FIFO scoreboard；其他情况按 ID 和显式
  ordering rule 做 associative/partial-order matching；
- active memory responder、scoreboard 和 ISS 共享一个 authoritative memory
  service，不能各自维护会漂移的存储器副本；
- 配置对象描述 width、outstanding depth、ordering、coherence、ISA extension、
  hart/lane 数量，不把能力矩阵散落为测试中的 `ifdef`；
- RAL 和 address map 从已接受的 SoC map 生成，不手工复制常量。

### 10.4 First implementation slice

第一步只建立被动的 core-level retirement vertical slice：

```text
commit_pkt_t + trap_entry_t
    -> clocking-block commit interface
    -> passive UVM monitor
    -> lossless retire_event / trap_entry_event adapters
    -> ordered scoreboard / tohost subscriber / retirement coverage
```

该步骤首先复用现有定向程序，不驱动 DUT，也不改变 memory timing。它必须：

1. 固定并记录实际 ModelSim/Questa 支持的 UVM 版本；
2. 无损映射现有 `commit_pkt_t` 和 `trap_entry_t`，区分 instruction commit
   与 asynchronous trap entry，并从第一天保留 `hart_id=0`、
   `retire_lane=0` 和 64-bit `order`；
3. 重现 retirement 顺序、trap/write exclusion 和 committed-`tohost` 结果；
4. 证明一个故意注入的 scoreboard mismatch 会产生 native failing exit；
5. 保持 focused retirement、23-test smoke 和现有 release flow 通过；
6. 记录编译和运行开销。

完成该 slice 后，第二步才加入 Spike/Sail differential adapter；随后再按需求
加入 reactive memory agent、riscv-dv、generated RAL 和 SoC virtual sequence。

## 11. Future Improvements

在已接受的分层结构中逐步扩展：

- 使用 Spike、Sail 或其他参考模型进行差分验证；
- 集成 riscv-dv 随机指令生成和可复现 seed；
- 增加 trap、CSR、流水线 flush 的 functional coverage；
- 使用 formal property 验证“无效指令永不改变架构状态”；
- 在 CI 中归档日志、波形、seed 和覆盖率报告；
- 对失败进行自动聚类，区分软件失败码、Assertion、scoreboard mismatch 和 timeout。

长期目标是让验证流程同时具备：

```text
Directed tests       -> 精确验证已知功能和边界条件
Assertions           -> 持续检查微架构不变量
Functional coverage  -> 衡量验证空间是否完整
Reference comparison -> 发现未知的功能差异
Continuous regression-> 防止修复引入退化
```

---

## 12. Resume Highlight

### English

> Developed a verification framework for an RV32 pipelined CPU using bare-metal assembly tests, memory-mapped `tohost` result reporting, SystemVerilog assertions, and waveform-based debugging. Implemented directed precise-trap tests for ECALL pipeline flush behavior and identified CSR side-effect leakage caused by invalid pipeline packets.

### 中文

> 为 RV32 流水线 CPU 搭建了由裸机汇编测试、memory-mapped `tohost` 结果上报、SystemVerilog Assertion 和波形调试组成的验证框架；设计 precise trap 定向测试验证 ECALL 后的流水线清除行为，并定位无效流水包导致的 CSR 副作用泄漏问题。
