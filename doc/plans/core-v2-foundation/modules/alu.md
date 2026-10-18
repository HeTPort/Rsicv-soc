# CV2 Module Pilot — RV32 Integer ALU

**Phase:** CV2 / core-v2-foundation

**Status:** Draft module contract; RTL/model/test implementation NOT RUN

**Owner:** Project owner implements RTL

**Last updated:** 2026-10-16

**Depends on:** [verification gates](../verification_plan.md)

**Related evidence:** [foundation results](../results.md)

## Outcome and scope

用一个可独立证明的纯组合模块演练“读规格→数学模型→自己写 RTL→模型/断言检查”。
此规格不引用旧 ALU 实现，不预先固定流水级。采用前将端口/编码确认为 Accepted；
任何修改先更新规格和独立测试向量，再修改实现。

## Ports and encoding

| Port | Direction | Meaning |
| --- | --- | --- |
| a_i | input [31:0] | 第一个 32-bit operand |
| b_i | input [31:0] | 第二个 operand；shift 仅使用 [4:0] |
| op_i | input [3:0] | 下表定义的内部运算选择，不是 ISA opcode |
| result_o | output [31:0] | 组合结果 |
| op_error_o | output | 非法内部选择为 1；上层不能据此替代 ISA decode legality |

| op_i | Operation | Mathematical result |
| --- | --- | --- |
| 0 | ADD | (a+b) mod 2^32 |
| 1 | SUB | (a-b) mod 2^32 |
| 2 | SLL | (a << b[4:0]) mod 2^32 |
| 3 | SLT | signed32(a) < signed32(b) ? 1 : 0 |
| 4 | SLTU | unsigned(a) < unsigned(b) ? 1 : 0 |
| 5 | XOR | a xor b |
| 6 | SRL | unsigned(a) >> b[4:0] |
| 7 | SRA | signed32(a) arithmetic-right-shift b[4:0], encoded as 32 bits |
| 8 | OR | a or b |
| 9 | AND | a and b |
| 10..15 | invalid | result=0, op_error=1 |

Legal selections have op_error=0. Addition/subtraction overflow does not trap.
Comparison results have bits [31:1]=0. The reference signed32 conversion uses
`x` when x<2^31, otherwise `x-2^32`; this definition is independent of HDL casts.

## Timing, state, reset and side effects

Combinational, no clock/reset, no storage, no ready/valid, no architectural writes.
Inputs determine outputs in the same combinational evaluation; the caller owns
sampling and any valid/kill qualification. Complete assignment and no latch are
required. No cycle/Fmax claim follows until synthesized in a specified context.
Functional tests use fully known 0/1 inputs. X/Z are not legal operands; an
event-driven environment must detect unexpected unknown inputs when valid,
rather than silently converting them to zeros in a Python model.

## Stable requirements and test obligations

| ID | Obligation | Planned check |
| --- | --- | --- |
| REQ-CV2-ALU-001 | 全部 10 种合法操作符合数学定义 | 每 op 的 known-answer 与独立 Python/formal oracle |
| REQ-CV2-ALU-002 | signed/unsigned 比较和算术移位正确 | 0x7fffffff/0x80000000/0xffffffff 等边界 |
| REQ-CV2-ALU-003 | shift 使用且仅使用低 5 位 | 0..31 全覆盖；改变 b[31:5] 结果不变 |
| REQ-CV2-ALU-004 | ADD/SUB/SLL 截断至 32 位 | wrap/overflow/underflow 边界 |
| REQ-CV2-ALU-005 | 6 种非法 op 确定返回 0/error | 每种 op 独立 directed case |
| REQ-CV2-ALU-006 | 无状态/锁存，无架构副作用 | lint/elaboration，组合属性，切换 op/input sequence |

## Independent model and test design

- 数学模型直接由上表推导；不得调用 DUT 的 helper 或读取 result 生成 expected。
- directed operand set 包含 0、1、2、0x7fffffff、0x80000000、0xffffffff、
  0xaaaaaaaa、0x55555555、单 bit 与其补码；覆盖关键两两组合和相等情形。
- 每个 shift amount 都覆盖正、负、零和单 bit operand；高 shift bits 变化作为
  metamorphic test。SLT 与 SLTU 使用相同 bit pattern 验证相反结果的情况。
- seeded random 按 manifest 预算运行，每个 op 单独计数/覆盖；报告 sample count、
  seed 和输入 hash，不把随机测试称作全域证明。
- 形式化目标是全部已知输入下的数学关系和 invalid default；记录 proved/BMC/
  timeout 与假设，不能只报告“formal ran”。
- checker mutation 至少能发现：SLT 误用 unsigned、SRA 误用 logical、shift 用 6 位、
  ADD/SUB 互换、invalid 无 error。mutation 发生在测试 mutant/adapter，不修改用户
  正常 DUT 来制造历史混淆。

## Module exit and implementation placement

G0: 端口与 op 编码已接受且无必需 TBD。G1: requirements trace 完整，全部 required
bins 命中，directed/random、negative checker、lint 与适用 formal 有实际证据。
若 formal 不可用，记录 gap/替代检查，不能声明完成了全域证明。

首份实际源码建议为 `rtl/core/execute/rv32_alu.sv`；第一次实现时再创建它。
配套模型/test/formal 分别在 `verif/v2/` 的实际工作目录创建，显式列入 v2 manifest。
本次未创建这些源码或测试空壳。
