# CV2 — Independent Core Rewrite Foundation

**Phase:** CV2 / core-v2-foundation

**Status:** Accepted; documentation and verification-design foundation active

**Owner:** Project owner (RTL/specification); assistant (review/verification support)

**Last updated:** 2026-10-18

**Depends on:** current RV32 baseline, AR-016 ownership, AR-026 verification layers

**Related evidence:** [results](results.md), [AR-034](../../ar/AR034_SPEC_FIRST_CORE_V2_REWRITE.md)

## Scope and user/system outcome

用户按照规格自行重写 core 各模块；本阶段建立独立分支、目标目录、
规格/参考模型/测试/断言的验收规则，并提供首个 ALU 规格试点。
目标以产品和研究价值判断，不以改动行数或实现难度限制架构。
当前交付不包含新版 RTL、仿真环境、ISS 集成或任何新版 PPA 结论。

## Decision contract

| Field | Value |
| --- | --- |
| Decision question | 能否在不依赖旧 RTL 作为唯一真值的前提下逐模块重写，并提供独立可复现的正确性证据？ |
| Linked research claims | none; no W0/M0 claim is established here |
| Linked product hypotheses | none; this is a computing-platform learning/engineering track |
| Current baseline / alternative | 保留 src/ 的 v1；可选原地改造、平行重写或重新使用成熟 core |
| GO condition | 分支/目录归属明确；首模块规格无阻塞歧义；oracle、负向验证和验收项可落实 |
| PIVOT condition | 原生总线或工具配置无法满足已声明吞吐/正确性条件，先修契约再写 RTL |
| DEFER condition and re-entry | 某模块的 ISA/时序/错误语义不完整时推迟该模块编码，完成规格后恢复 |
| NO-GO condition | 验证只能复述 DUT 实现，或结果不能复现；该模块不得接入新版 core |

## Information classification before work

| Field | Value |
| --- | --- |
| Anticipated data class | DATA-PUBLIC for this generic specification/verification documentation; owner authorized GitHub publication on 2026-10-18 |
| Potential confidential/restricted fields | No customer data, plant parameters, credentials or unpublished PPA inputs |
| Repository-safe content | Generic directory, interface, verification and learning contracts |
| Approved external storage | Not required for this documentation slice |
| Classification owner and review trigger | Project owner; explicit request to commit/push this branch on 2026-10-18; future new payloads require their own review |

## Preconditions and assumptions

- Branch: `codex/core-v2-spec-first`, from `e88bb3b62efa7074390bb948b96dfb1c3837a1de`.
- v1 remains in `src/`; existing source lists/runners continue to select v1.
- v2 remains RV32, single-hart, single-issue in-order as an initial architectural
  scope; exact ISA profile/CSR set and interrupt/debug behavior must be recorded
  before core integration. RV32C, U/PMP and predictors remain explicit decisions.
- Core functional ownership and pipeline-register placement are separate decisions.
- Existing 23-test smoke/47-test ACT4 counts describe v1 historical evidence,
  not a new run and not sufficient sign-off for v2.

## Functional requirements

| ID | Requirement | Rationale | Verification method | Priority |
| --- | --- | --- | --- | --- |
| REQ-CV2-001 | v2 在独立分支和独立显式 source manifest 下演进 | 隔离实现/编译身份 | 分支、清单和 build identity 审查 | Required |
| REQ-CV2-002 | 每个模块在编码前规定功能、端口语义、时序、错误、reset/kill 和参数范围 | 避免 AI/RTL 反向定义需求 | 模块规格审查 | Required |
| REQ-CV2-003 | RTL 由用户自主编写；辅助工作可提供模型、测试和审查 | 支持重新理解与学习 | 变更归属与解释记录 | Required |
| REQ-CV2-004 | 每个模块有独立于其实现结构的 oracle | 避免共同错误 | 数学/ISA/独立状态机模型及负向 checker 测试 | Required |
| REQ-CV2-005 | core 与平台经 memory/IRQ/debug/power/trace 契约交互 | 外部 IP 与 core 独立演进 | contract tests、接口与所有权审查 | Required |
| REQ-CV2-006 | 精确退休决策留在 hart；观察事件可经 adapter 输出 | 精确架构状态和可复用验证 | RF/CSR/store/trap/redirect 断言与事件检查 | Required |
| REQ-CV2-007 | 所有失败保留 seed、配置、程序/输入哈希和复现命令 | 可审查、可缩减 | 从干净 build 复跑 | Required |

## Non-functional requirements

| ID | Target |
| --- | --- |
| VER-CV2-001 | 每项 required requirement 映射到检查与实际结果；未执行为 NOT RUN |
| VER-CV2-002 | lint/elaboration 不保留未审查 warning；waiver 要含原因、范围和有效配置 |
| VER-CV2-003 | required 功能覆盖 bin 全部命中或有逐项批准的 waiver；不以统一代码覆盖率数字替代 |
| VER-CV2-004 | checker 的 deliberate mismatch、assert failure、timeout 必须产生 native nonzero exit |
| PERF-CV2-001 | 每个时序模块在集成前给出周期延迟、吞吐、阻塞上限及环境前提；数值不能留空 |
| PERF-CV2-002 | 系统频率/面积/能量预算由目标平台和 workload 冻结；基础阶段不虚构数字 |

## Safety and failure consequences

主要风险是验证遗漏导致错误架构状态、被 kill 指令的外部副作用、错误睡眠/唤醒、
失去事务归属，以及把计划误报为能力。检测采用独立模型、断言、错误注入和结果分类。
v2 未经过 core/SoC/板级 gate 前不承担控制输出；此阶段不授权任何物理执行器实验。

## Non-goals

本阶段不实现 RTL，不复制第三方源码，不安装/升级工具；不改变 v1 的时序、ISA、
总线、固件和板级构建。最初的本地准备不含提交/推送；项目所有者已于 2026-10-18
明确授权将本次文档分支提交并发布到 GitHub。产品需求不因目录图自动成立。

## Acceptance and exit gate

本次 foundation 文档 gate：分支建立、目录/规格/验证文档和 living links 完整，
文档治理及 diff 检查通过。模块编码 gate：选定模块规格无未解决必需项，
模型和测试计划已定义。模块完成 gate 与 core/SoC sign-off 见
[verification plan](verification_plan.md)，当前均不视为通过。

## Open questions

- 原生 memory interface 采用哪个精确 OBI profile 或本地协议版本？
- 首个完整 core 的 ISA/CSR/特权配置与 instruction alignment 是什么？
- pipeline latency、bypass、预测、fetch outstanding 和 local memory 的目标预算？
- 采用哪个固定版本的仿真器、ISS、formal frontend，以及实际支持哪些特性？

这些问题不妨碍纯组合 ALU 试点，但会阻塞相关 core 集成规格的接受。
