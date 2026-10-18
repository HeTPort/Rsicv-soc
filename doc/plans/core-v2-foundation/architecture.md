# CV2 Architecture and Directory Ownership

**Phase:** CV2 / core-v2-foundation

**Status:** Accepted directory/ownership direction; detailed core contracts Draft

**Owner:** Project owner

**Last updated:** 2026-10-16

**Depends on:** [requirements](requirements.md), AR-016, AR-026

**Related evidence:** [results](results.md), [AR-034](../../ar/AR034_SPEC_FIRST_CORE_V2_REWRITE.md)

## Context and boundary

当前可综合实现继续位于 `src/`。新版计划放在独立 `rtl/` 中，让用户可按规格
逐块重写；两者不靠 wildcard 混编。此文件中的路径是目标布局，源码/模型开始时
才创建相应目录；本次只建立有实际内容的文档 phase。

```text
src/                            v1：现有生产参考与回归
rtl/                            v2 synthesizable source（按实际实现创建）
  common/                       FIFO、同步/CDC、通用原语
  core/                         ISA 与微架构，不含平台地址图
    frontend/                   fetch、buffer/align、redirect、predictor
    decode/                     decode、issue、imm、hazard/bypass
    execute/                    ALU、branch、MDU
    memory/                     LSU
    privileged/                 CSR、trap/IRQ、PMP、hart debug
    retire/                     精确副作用决策
  core_complex/                 core_shell、local-memory/cache 集成
  interconnect/                 router、arbiter、adapter、error target
  ip/                           CLINT、PLIC、GPIO、UART、SPI、PWM 等
  soc/                          系统实例与平台控制
  targets/                      FPGA/ASIC technology/pad/clock wrappers
verif/v2/                       v2 models/agents/unit/core/soc/formal
config/v2/                      named profiles、显式 source lists、test manifests
doc/plans/core-v2-foundation/    本阶段契约、验证方案、实际结果
```

`frontend/execute/...` 是所有权方向，不是固定流水级数。无状态小函数可以留在
package；有独立契约、状态、生命周期或验证价值才拆模块。AI 不替用户提交 RTL。

## Block/data-flow diagram

```text
specification ──> independent model ──> expected events
      │                                   │
      └─> user RTL ──> monitor/adapter ──> checker/coverage
                           │
                     protocol assertions

rv32_core <─ memory/IRQ/debug/power ─> core_shell <─> platform
     └─ retire/trap/perf events ──────────────────> observation
```

## Interfaces and protocols

Core 原生 I/D memory 接口独立于 AXI/APB/TL；精确选择见后续 accepted interface
contract。AXI4 共享数据面、APB4 寄存器控制面、TL-UL 接入是候选方向，不在这里
自动声明已接受或兼容。必须固定通道、顺序、mask/size、error、outstanding、
response backpressure、cancel/drain、FENCE/FENCE.I 和地址属性。

IRQ bundle、debug request/status、reset/sleep/wake 与 trace 保持独立语义。
PLIC/CLINT、存储器、pinmux 和地址图不属于流水线；精确 retire/trap 和 hart-side
Debug Mode 状态属于 core。外部 Debug Module 不能替代正常退休。

内部事务应区分 instruction、load/store、retire、trap entry；不创建一个囊括所有
未来字段的 universal packet。模块 contract 是编码依据；旧 RTL 只是被比较对象。

## Clock, reset, CDC/RDC, and safe-state strategy

每个时序模块明确时钟域、reset assertion/deassertion、初始有效位、kill、flush、
reset 与握手的竞争。组合 ALU 无时钟/复位，标记不适用。CDC/RDC 在跨域模块实际
开始前定义同步结构/恢复策略；通过单时钟仿真不能证明 metastability 已被解决。

## State machines and timing

先定义请求/响应/完成事件，再实现状态机。所有 `valid`、ready、fire、busy、
kill、commit 的语义写清楚。已接受外部事务不能因 flush 从环境中消失；迟到响应
必须保留归属。store/MMIO 副作用授权必须与较老异常和 kill 协调。

延迟和吞吐独立记录。允许多个 outstanding 不意味着允许改变 ISA 可见顺序。
停止时钟前要求无未处理工作、无未清 redirect/trap 并满足系统静止握手。

## Data representation

XLEN=32；little-endian；signed/unsigned、shift amount、地址/byte lane 分别定义。
64 位 timer/counter 保持显式宽度。模型的无限精度整数必须在规格规定位置 mask、
符号扩展或截断。不同 pipeline/config profile 使用命名 manifest，不使用隐含宏组合。

## Error and fault containment

区分 DUT mismatch、protocol violation、environment error、unsupported feature、
timeout 和 tool error。期望错误不能被 classifier 算作 PASS；负向测试验证的是
checker/runner 正确失败，再由外层测试确认该失败是预期的。

bus timeout 后必须定义隔离/排空/域复位，不能立即复用尚可能收到旧响应的归属。
测试模型拒绝 speculative device reads；faulting/killed instruction 不得产生普通
架构写效果。trace buffer 满时不得静默丢失验证事件。

## Alternatives and decision links

选用平行重写，见 [AR-034](../../ar/AR034_SPEC_FIRST_CORE_V2_REWRITE.md)。保留旧版
便于复现历史 bug 和板级成果，但不要求新微架构逐周期等价；只在共同 ISA、相同
外部事件调度下做架构比较。时序变化需要独立 latency/throughput 证明。

## Implementation partition

- 用户：规格理解、RTL 实现、关键状态机和时序说明。
- 辅助：独立模型、测试、断言建议、review、失败缩减；不能同时复制同一算法到
  DUT 和 oracle 后将一致当作证明。
- 当前实际首个模块规格：[RV32 ALU pilot](modules/alu.md)。
- 软件/FPGA 目录在第一项真实集成工作时沿用现有所有权或另记迁移决策；不先搬动。
- source manifest 必须显式列出 package/module/TB 与编译顺序；旧 runner 默认不变。
