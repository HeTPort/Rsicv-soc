# 除法器 lint 小实验：报警不是判决，清零也不是正确性证明

本实验使用本机已安装的 **Verilator 5.032 2025-01-01 rev (Debian 5.032-1)**，于 2026-09-09 实跑。没有安装新软件，没有改动 `src/core/radix2_divider.sv`。生成文件位于已忽略的 `build/divider_lab/lint/`。

## 1. 实际怎么运行

在仓库根目录打开 PowerShell：

```powershell
wsl -d Ubuntu --exec python3 /mnt/d/Rsicv-soc-worktrees/phase2-act4-cleanup/tools/divider_lab/lint_lab.py
```

它会运行八个静态检查，检查**预期报警集合和退出码**，然后写出 `build/divider_lab/lint/summary.json`。整体退出码 0 表示“这些教学实验的实际结果符合预期”，并不表示原始除法器没有报警。

也可以只跑原始除法器，观察原生输出：

```powershell
wsl -d Ubuntu --exec verilator --lint-only --sv --Wall -DSYNTHESIS --top-module radix2_divider /mnt/d/Rsicv-soc-worktrees/phase2-act4-cleanup/src/core/radix2_divider.sv
$LASTEXITCODE
```

参数的含义：

| 参数 | 此实验中做什么 |
|---|---|
| `--lint-only` | 只解析、展开并检查设计；不运行 testbench，不生成输入激励 |
| `--sv` | 按 SystemVerilog 处理输入 |
| `--Wall` | 启用额外 lint/风格报警；不等于覆盖所有可能的设计错误 |
| `-DSYNTHESIS` | 选择本模块的综合视图，排除 `ifndef SYNTHESIS` 内的仿真断言；这不是综合命令 |
| `--top-module radix2_divider` | 指定检查边界，没有把整个 SoC 加入检查 |
| `-GDW=8` | 覆盖顶层参数，按 8 位配置展开；静态通过不等于 8 位功能已验证 |

本机 WSL 启动时有代理配置提示。真实 Verilator 日志由 Python 在 WSL 内单独捕获，因此不会把该环境提示误计为 RTL 报警。

## 2. 原始 RTL 的两个真实报警

原始文件 SHA256：`033d5a55d55cdb25a1546a61a8e46b7dfb09cc0667d3e60d693f81b988997707`。

### WIDTHEXPAND：先弄清表达式宽度

位置：`src/core/radix2_divider.sv:115`。

```systemverilog
if (iteration_q == DW-1) begin
```

默认 `DW=32`，所以 `COUNT_W=$clog2(33)=6`，`iteration_q` 是 6 位。参数 `DW` 是 `int`，右边 `DW-1` 是 32 位表达式；相等比较要先统一宽度。Verilator 报 `WIDTHEXPAND`，提醒这里发生了隐式扩展。

**不要直接认定当前除法算错。** 这里计数范围是 0～31，默认参数下扩展不会把这些非负值变成别的数。报警的价值是让设计意图更明确，也避免将来改动位宽时不知不觉依赖隐式规则。

实验仅在 `build/divider_lab/lint/width_explicit/radix2_divider.sv` 的机械副本中改成：

```systemverilog
if (iteration_q == COUNT_W'(DW-1)) begin
```

`COUNT_W'(...)` 是定宽转换，不是字符串。它明确把比较常量转换成计数器宽度。对支持的 `DW >= 2`，`DW-1` 可由 `COUNT_W` 位表示；但一般代码中不能盲目加转换，转换本身也可能截断重要高位。

这个改动后实际只剩一个 `UNUSEDSIGNAL`。本实验还对该生成副本实际重跑了现有 42-case 功能/协议测试：

```powershell
python tools/divider_lab/run_lint_candidate_sim.py
```

结果为 `candidate_42_case_sim: PASS`。这提高了对小改动的信心，但定向回归仍不是形式等价性证明，也没有把副本代替生产设计。

### UNUSEDSIGNAL：未使用不一定是漏接

位置：`src/core/radix2_divider.sv:34`；默认配置提示 `remainder_work_q[32]` 未使用。

```systemverilog
logic [DW:0] remainder_work_q;
// 下一轮明确只取低 DW 位，再移入被除数的一位。
shifted_remainder = {remainder_work_q[DW-1:0], quotient_work_q[DW-1]};
```

需要分开看两件事：

- **组合运算的额外一位**：`shifted_remainder` 和 `next_remainder` 保留 `DW+1` 位，用于移位后的比较和减法，不能看到 unused 就一并删除。
- **寄存器的额外一位**：当前递推的下一轮没有消费 `remainder_work_q[DW]`。设计审查应确认这是算法意图，还是本应使用却遗漏。正常非零除数的余数每步小于除数；除零时余数逐步收集被除数位。这个解释支持当前意图，但静态报警消失本身没有证明该不变量。

教学选择是保留生产 RTL，并对**生成副本的这个信号报警**做有理由的局部豁免，配置在 `lint_fixtures/divider_reviewed.vlt`：

```systemverilog
`verilator_config
lint_off -rule UNUSEDSIGNAL -file "*/build/divider_lab/lint/width_explicit/radix2_divider.sv" -match "*Bits of signal are not used: 'remainder_work_q'*"
```

`.vlt` 文件作为源文件列表的第一项传给工具。它没有关闭其他文件或信号的未使用检查，也没有关闭 `LATCH`、位宽检查或整个 lint。实际应用中 waiver 还应带审查人、理由、适用配置和何时重新审查；这里仅作教学，不是项目正式豁免政策。[Verilator 配置文件说明](https://verilator.org/guide/latest/control.html)

## 3. 一个确实违反需求的例子：组合逻辑漏赋值

两个小 fixture 都**没有接入 SoC**。它们的需求相同：`enable_i=1` 时输出输入，`enable_i=0` 时输出 0。

错误版本 `lint_fixtures/latch_bad.sv:9`：

```systemverilog
always_comb begin
  if (enable_i)
    sample_o = data_i;
end
```

`enable_i=0` 时没有赋值，输出需要“记住上一次的值”，因此工具发现锁存器行为并报 `LATCH`。例如先输入 `enable=1, data=8'hA5`，再改为 `enable=0`：需求要求输出 0，错误版本却保留 A5。这个输入序列是解释错误的预期行为，**本 lint 实验没有运行该 fixture 的波形仿真**。

正确版本 `lint_fixtures/latch_good.sv`：

```systemverilog
always_comb begin
  sample_o = '0;
  if (enable_i)
    sample_o = data_i;
end
```

这里 `=` 是组合过程中的阻塞赋值，`'0` 按赋值目标宽度填 0。先默认再覆盖，使每一条控制路径都有输出值。不能简单把 `always_comb` 改成 `always_latch` 来让报警消失，因为需求根本没有要求存储功能。

## 4. 本次实际结果

| 实验 | 实际报警 | Verilator 退出码 | 如何解读 |
|---|---|---:|---|
| 原始除法器 | `WIDTHEXPAND`、`UNUSEDSIGNAL` | 1 | 基线 RED，有两个待审查项 |
| 生成副本，仅显式位宽 | `UNUSEDSIGNAL` | 1 | 位宽项消失，仍不能说已清零 |
| 副本 + 局部 unused 审查豁免 | 无 | 0 | 指定配置的 lint GREEN，不是功能证明 |
| 故意漏赋值 fixture | `LATCH` | 1 | 负向测试：规则确实能抓住这类错误 |
| 补全默认赋值 fixture | 无 | 0 | 该规则的修正示例 GREEN |
| 副本 `DW=2/8/64`，各一次 | 无 | 各 0 | 仅参数展开/lint 检查通过 |

脚本同时确认原始 RTL SHA256 没有变化。它还要求 RED 的唯一 `%Error` 是“报警导致退出”，避免将语法错误、工具崩溃或缺文件错误误当成预期 RED。

## 5. “推进 lint”到底每天做什么

1. 固定顶层、源文件、宏、参数和工具版本，留下原始报警清单。
2. 从一个报警定位到 RTL，写出“本来应当是什么电路/行为”。
3. 分类：确实违反需求的错误；意图正确但写法不清楚；有明确理由的合法例外。
4. 错误和表达不清楚的地方做小改动；需要豁免的地方缩小到具体文件/信号，并记录原因，不能全局关规则。
5. 重跑 lint，再跑受影响的功能/协议回归；涉及电路结构时还要看综合、资源和时序有没有意外变化。
6. 把命令变成可以失败的检查入口，至少保证新改动不会引入未审查报警。

这就是一项可以逐模块推进的数字设计工作。它无需先搭 UVM，但离不开 RTL 语义、位宽/符号、组合/时序电路和设计意图。ModelSim 编译通过、Vivado 综合通过与 dedicated lint 是不同的证据；此实验实际使用的是专门的静态检查模式。[Verilator 报警说明](https://verilator.org/guide/latest/warnings.html)

本实验边界：没有扫描整个 SoC，没有跑 CDC/RDC，没有替代仿真/形式验证，没有替代 STA，也没有建立 ASIC signoff 结论。
