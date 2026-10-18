# CV2 Verification Strategy and Module Exit Gates

**Phase:** CV2 / core-v2-foundation

**Status:** Accepted strategy; all new DUT verification NOT RUN

**Owner:** Project owner and verification support

**Last updated:** 2026-10-16

**Depends on:** [requirements](requirements.md), [architecture](architecture.md)

**Related evidence:** [results](results.md), [AR-026](../../ar/AR026_SCALABLE_UVM_VERIFICATION_ARCHITECTURE.md)

## Verification scope and strategy

验证从规格同时展开 RTL 和独立 oracle。旧代码、旧 directed tests、ACT4、固件是
可复用资产，但不足以独立定义新版行为。按五层验证：module、cluster、core、shell/
interconnect、SoC/FPGA。core 虽然从内部重写，架构 observation 必须在开始集成前
设计好，而不是 core 写完后才补。

## Requirement traceability

| Requirements | Planned checks | Actual status |
| --- | --- | --- |
| REQ-CV2-001/002/003 | 分支、显式 manifest、模块规格/作者解释审查 | Foundation documentation only |
| REQ-CV2-004, VER-CV2-004 | oracle known-answer、mismatch injection、mutation、native exit | NOT RUN |
| REQ-CV2-005 | request/response conservation、ordering、error/reset/kill agent tests | NOT RUN |
| REQ-CV2-006 | RF/CSR/store exclusion、precise trap/IRQ、MRET/WFI/debug、RVFI mapping | NOT RUN |
| REQ-CV2-007 | manifest/seed/hash/tool/exit/first-failure capture and rerun | NOT RUN |
| VER-CV2-001/002/003 | traceability、lint waiver、coverage/assumption review | NOT RUN for RTL |
| PERF-CV2-001/002 | per-module latency/throughput、timing/resources、controlled PPA experiment | NOT RUN |

## Verification layers

| Layer | Oracle and stimulus | What it must catch |
| --- | --- | --- |
| Module | math model、truth table、independent state machine、directed/random/formal | 局部功能、边界、reset、握手、非法输入 |
| Cluster | frontend+bus、decode+regfile、LSU+memory、CSR+retire | 两三个模块之间的状态归属、stall/flush/kill 竞争 |
| Core | passive architectural monitor、ISS adapter、directed/ACT4/generated programs | ISA、CSR、precise traps/IRQs、寄存器/内存效果 |
| Shell/interconnect | independent host/device BFMs、latency/error/ID scoreboard | deadlock、duplicate/lost response、错误归属、背压/复位/仲裁 |
| SoC/physical | firmware、register model、DMA/debug contention、board observations | 软件 ABI、端到端行为、deadline/wake/fault、真实时序 |

## Per-module specification checklist

每个模块在写 RTL 前填完这些字段：

1. stable requirement IDs、版本化参考规范与支持范围；
2. port 表：方向、宽度、signedness、有效条件、握手/保持要求；
3. 每个输入组合的定义，reserved/illegal 与未知值策略；
4. 组合/时序边界、延迟、吞吐、busy/ready 与允许 outstanding；
5. reset/kill/flush 与 request/response 同周期的优先级；
6. architectural 与 external side effects 的所有者；
7. oracle、directed cases、覆盖 bin、断言、formal assumptions；
8. 失败日志、超时和 module exit gate。

首个填写实例见 [ALU specification](modules/alu.md)。有 MMIO 时再增加唯一 RDL 源、
SW/HW 同时更新、reserved bits、byte lane、W1C、read side effect、shadow update。

## Test categories

### Positive/nominal and boundaries

ALU：模 2^32 运算、符号边界、全部 shift amount、忽略的高 shift bits。
Decoder：每个支持编码、合法/非法 funct3/funct7、立即数符号扩展；不能只由 DUT
decode 的 enum 选择 oracle 而跳过独立指令解码。
Regfile：x0、写后读、读写同地址、enable、reset/powerup 与旁路策略。
MDU：signed variants、high product、division by zero、signed overflow、握手和 kill。

### Negative and protocol-error cases

请求被阻塞时 payload 保持；无请求不得有完成；每次接受恰好一次完成。
非法地址/对齐/mask 必须按规格报错且无未授权副作用。
fetch response 与 PC/fault/epoch 配对，错误路径和重定向路径都进入 scoreboard。

### Fault injection and recovery

注入 fetch/data access error、invalid source/response、target 停止响应，检查
error/trap/timeout 与恢复。元数据 corruption 仅在合同中定义了检测行为时要求硬件
检测。checker 必须能发现被故意改坏的计算/事件；不能靠关闭检查得到绿色。

### Reset, kill and race matrix

对时序模块覆盖 reset/kill 出现在 idle、request stalled、request accepted、
response pending、completion 同周期。按规格检查取消、排空与状态恢复。
cluster 覆盖 branch redirect、较老 trap、IRQ、MRET/WFI/debug request 与 LSU/MDU
等待的交叉；调度要能复现，并防止年轻 store/MMIO 读引起副作用。

### Performance/timing/area/power

先证明功能，再测协议开销、吞吐、最坏等待、中断延迟/抖动、总线争用。
产品和研究 profile 分别冻结；不穷举未支持的参数笛卡尔积。
PPA 记录库/器件、时钟约束、seed、软件及编译参数、活动窗口、分析对象哈希。
OOC、routed FPGA、ASIC mapped、板级实测分别报告。

## Architectural checking

在 v2 core 接第一条程序前定义 lossless `retire_event` 与独立 `trap_entry_event`，
包括 order/hart、instruction/length、PC/next-PC、privilege、operand 与 GPR 写效果、
memory mask/data/address 和 trap 信息。是否进入 retired count 按所选 ISA 语义，
不能让 faulting instruction 递增 minstret。

通过 adapter 映射 RVFI/ISS；只导出实际需要的观察信息，不以 trace 控制 core。
先测试 monitor/scoreboard 的已知事件序列与 deliberate mismatch，再接 ISS。
core 全部支持指令逐次比对，重点检查无 rd 写的 store/branch/CSR/trap；最终
`tohost=PASS` 只是一个 oracle，不能掩盖较早错误后又恢复的状态。

ISS 的 ISA/CSR/WARL、misalignment 和 privilege 配置必须匹配。采用一份权威
memory/MMIO 模型，读结果和副作用只发生一次，DUT 与 reference 用记录重放同步。
timer/IRQ/volatile counters 需要显式采样/调度规则，异步 IRQ 按允许的架构边界对齐；
不能用每次 mismatch 后改 reference PC/寄存器或 blanket skip 来“修复”比对。

旧 v1 与 v2 可比较共同配置下的架构结果；其时序不同，不要求逐周期相同。
ISA 模型和独立局部模型仍提供另外的真值依据。ACT4、random ISA、formal 相互补充；
任何一个通过都不自动意味着完整 ISA/SoC 合规。

## Assertions and formal assumptions

按模块证明：计算关系、valid/stable、no loss/duplicate、one owner、no killed side
effects、redirect priority、reset recovery、FIFO bounds。组合 ALU 可检查完整输入域；
core 采用分解与可解释假设，先做可收敛属性。
区分 unbounded proof、bounded pass、cover witness、timeout 和 unsupported。
环境有界响应/公平性等假设必须列出，并用 cover 检查可达性，防止过约束/vacuity。
CDC/RDC/模拟失效不能用普通 RTL 仿真或一个两态 proof 完全证明。

## Coverage and checker quality

- requirement coverage：每项 required requirement 至少一个实际检查结果；
- functional coverage：操作/operand/状态/竞争和交叉 bin，依据规格定义；
- code coverage：statement/branch/toggle/FSM 辅助发现未触及逻辑，不规定万能百分比；
- assertion coverage：触发、cover witness、assumption review；
- mutation：ALU 错 signed/shift、duplicate/drop completion、错误 trap PC、kill 泄漏等
  定向变异应被已有 checker 捕获；不能只证明“好实现通过”。

required bins 必须命中或逐项 waiver；随机样本数量/seed 集合是配置化预算，不代表
穷举保证。每个历史 bug 增加永久、可快速运行的 regression。

## Tools and reuse boundaries

Verilator/cocotb 用于快速 module/cluster tests；现有 ModelSim/Questa 与 UVM 用于
passive/domain/VIP/system 场景；SBY/riscv-formal 用于明确支持的断言/ISA 子集。
独立 ISS（例如 Sail/Spike）通过统一 adapter 接入，riscv-dv 在比对可信后引入。
GTKWave/Surfer 是诊断工具；coverage 和 native exit 才进入 gate。
版本/编译特性需实测后 pin，不假定现有 Verilator 能运行最新版 cocotb 或完整 UVM/SVA。

沿用 AR-026 的 semantic/domain 与 protocol 分离；v1 U0/U1/U2/U3 状态不因此变绿。
CV2 可先做 module models/tests；自身的 core gate 同样先通过被动事件检查和负向
验证，再接 ISS，再运行生成指令。无需将 Python 组合模块测试阻塞到完整 UVM 完成。

Primary references: [RVFI](https://github.com/YosysHQ/riscv-formal/blob/main/docs/source/rvfi.rst),
[riscv-dv](https://github.com/chipsalliance/riscv-dv),
[cocotb simulator support](https://docs.cocotb.org/en/stable/simulator_support.html).
No third-party code is imported by this phase.

## Regression and reproducibility

计划中的层级：每次修改运行 touched module、相关 cluster 和 checker negative；
集成变更运行 core directed/differential；定期扩大 seeds、ISA coverage 和 formal；
release 时加入 ACT4、固件、synthesis/route、板级门槛。明确清单与 skip 原因。

每次结果记录 DUT/model/tool revision、source manifest/hash、profile、seed、
stimulus/program/ELF hash、命令、native exit、test/assert/coverage summary、首个
mismatch、waveform window 和 reproduction command；generated/output 放 ignored build。
失败缩减为最短输入/指令/事件序列，再保存为 regression。

## Pass/fail oracle and exit gates

| Gate | Required evidence |
| --- | --- |
| G0 specification | 功能/端口/时序/错误/reset 必需项完整；用户能解释机制；无 blocking TBD |
| G1 module | 独立 oracle、directed/boundary/negative、lint、适用断言/formal、required bins、checker mutation |
| G2 cluster | 随机 latency/backpressure、reset/kill race、错误归属及 no-side-effect 检查 |
| G3 core | 被动事件及 negative checker、匹配 ISS、directed/ACT4/随机 ISA、精确 trap/debug/IRQ |
| G4 system | memory/MMIO 单一权威、DMA/debug 争用、fault/wake/firmware、协议与寄存器覆盖 |
| G5 physical | 明确约束下 routed timing/DRC、软件工作负载、板级复现；独立 PPA 证据 |

不可用工具/未收敛 proof 标为 NOT RUN/INCONCLUSIVE 并记录剩余风险，不能静默 PASS。
每个 profile 独立有 gate 身份；“一种配置通过”不推导全部配置通过。
