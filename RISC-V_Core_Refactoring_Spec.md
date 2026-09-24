| 序号 | 分类 | 当前状态/痛点 | 建议状态/改动 | 原因/收益 | 涉及文件/目录 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **1** | **命名规范统一** | `pc_counter`, `AW`, `redirect_en_i` 等 | `pc_reg`, `ADDR_WIDTH`, `redirect_i` | 名副其实，符合RISC-V业界标准 | `pc_counter.sv` -> `pc_reg.sv` |
| | | `pktd_i`, `op1_o` 等内部信号 | `fetch_pkt_i`, `op1` 等 | 明确数据流方向，避免内部信号误用 `_o` 后缀 | `decode.sv` |
| **2** | **参数化设计** | 步长硬编码 `AW'(4)` | 增加 `PC_STEP` 参数 | 提高复用性，未来可支持RVC | `pc_reg.sv` |
| **3** | **流水线寄存器解耦 (核心)** | `if2id`, `id2ex`, `ex2wb` 三个文件高度重复 | **提取通用模块 `pipe_reg.sv`**，使用 `parameter type T` | 消除重复代码，实现真正的IP级复用 | 新建 `src/common/pipe_reg.sv` |
| | | 寄存器内部处理 `valid` 逻辑 | 移至 `core_ctrl.sv`，通过 `flush_i` 控制 | 遵守单一职责，保持数据通路纯净 | `pipe_reg.sv`, `core_ctrl.sv` |
| **4** | **目录层次重构** | 所有模块混在 `src/core/` 下 | 新建 `src/common/` 存放与架构无关的通用IP | 建立基础IP库，区分架构特定逻辑与通用积木 | 目录树调整 |
| **5** | **实例化方案** | 保留 `if2id.sv` 等作为独立文件 | **删除这3个文件**，在 `riscv.sv` 中内联例化 `pipe_reg` | 扁平化设计，减少不必要封装，集中管控 | 删除3个文件，修改 `riscv.sv` |
| **6** | **验证机制保留** | `if2id` 等内部有断言 | 断言移至 `pipe_reg.sv` 内部，检查输出是否等于 `RESET_VAL` | 在通用层面保障基础IP安全性 | `pipe_reg.sv` 内 `ifndef SYNTHESIS` |
| **7** | **寄存器堆时序优化** | `always_comb` 中包含复位判断 `if (!rst_ni)` | **移除组合逻辑中的复位** | 消除复位信号对读数据路径的污染，减少MUX层级，**提升频率** | `regfile.sv` |
| **8** | **译码器模块化** | 立即数生成逻辑混在 `decode.sv` 中 | **抽离为独立模块 `imm_gen.sv`** | 职责分离，使译码器专注于控制信号查表，代码量减少近30% | `decode.sv`, 新建 `imm_gen.sv` |
| **9** | **译码错误处理风格** | `decode.sv` 中处理取指错误时，直接用结构体覆盖再补回 | 保持逻辑或改为通过 `clear` 信号控制；添加注释说明 | 功能正确且安全，但风格略显粗暴。记录在案以便未来风格优化 | `decode.sv` 末尾 `always_comb` 块 |
| **10** | **语言选择定调** | 纠结是否需要纯Verilog目录控制时序 | 统一使用清晰风格的SystemVerilog | SV是超集，时序由编码风格和综合工具决定，非语言本身 | 全局编码风格 |
| **11** | **Verilog/SV混用界限** | 无明确界限 | `src/common/` 存放通用IP，`src/core/` 存放架构特定逻辑 | 即使未来引入硬核IP，也放入 `src/hard_ip/` 区分 | 目录结构规划 |
| **12** | **执行单元 ALU 抽离** | `execute.sv` 内部硬编码了 ALU 运算逻辑 | **抽离为独立模块 `alu.sv`** | 提高复用性，隔离关键路径时序，减少 execute 代码量 | `execute.sv`, 新建 `src/core/alu.sv` |
| **13** | **CSR 原子运算下沉** | `execute.sv` 中计算 CSR 的 Read-Modify-Write 最终写入数据 | 将 RMW 逻辑移至 `csr_regfile.sv` | 职责分离，减少 EX 级组合逻辑层级，优化时序 | `execute.sv`, `csr_regfile.sv` |
| **14** | **异常/陷阱控制抽离** | `execute.sv` 中包含大量 `mcause` 优先级仲裁和打包逻辑 | 考虑抽离至 `exception_ctrl.sv` 或 `core_ctrl.sv` | 数据通路与控制逻辑分离，使 EX 级专注於计算与跳转 | `execute.sv`, 新建/修改控制模块 |
| **15** | **输入输出结构体冗余** | 开头 40 行解包，结尾 30 行打包，包含大量 `mem_xxx = '0` | 逻辑中直接引用结构体字段；输出端使用 `pkt_exe_o = '0;` 批量置默认值 | 消除冗余赋值，代码更精炼，避免遗漏新增字段 | `execute.sv` |
| **16** | **除法器接口标准化** | `execute.sv` 直接耦合特定 Radix-2 除法器 | 定义通用 MDU 接口，将此算法作为底层可替换实现 | 便于未来替换为 Radix-4 或单周期除法器，实现即插即用 | 新建 `src/core/mdu/` 或 `src/common/mdu/` |
| **17** | **迭代周期深度参数化** | 迭代次数硬编码为 `DW`，每周期仅1bit | 增加 `BITS_PER_CYCLE` 参数，支持 Radix-4 等配置 | 极大提高复用性，灵活权衡面积与性能 (PPA) | `radix2_divider.sv` |
| **18** | **除法器数据与控制解耦** | FSM 与恢复余数法计算逻辑混杂在同一个 `always` 块 | 将无符号核心运算抽离为纯组合逻辑模块/函数 | 便于综合工具针对数据通路优化，结构更清晰 | `radix2_divider.sv` |
| **19** | **符号处理逻辑下沉** | 符号判断与结果修正混在除法器顶层 | 外层包装处理符号转换，底层为纯无符号除法核心 | 底层 IP 越纯粹越易验证和复用 | `radix2_divider.sv`, MDU 包装层 |
| **20** | **通用IP参数命名** | `DW`, `ONE` 等局部参数 | `DATA_WIDTH`, 删除 `ONE` 使用字面量 | 避免缩写歧义，符合通用IP命名规范，减少冗余定义 | `radix2_divider.sv` |
| **21** | **控制信号术语统一 [高优]** | `kill_i`, `signed_i`, `complete_o`, `flush_req_o` | `flush_i`, `is_signed_i`, `done_o`, `flush_o` | 避免口语化，避开SV保留字，与全局控制流(`flush`)术语对齐 | `radix2_divider.sv`, `execute.sv` 等 |
| **22** | **内部寄存器语义化** | `quotient_work_q`, `quotient_negative_q` | `quot_shift_q` (或 `q_shift_q`), `q_neg_q` | 精确描述物理行为(移位)，避免过长命名导致排版换行 | `radix2_divider.sv` |
| **23** | **函数命名表达意图** | `magnitude(value)` | `to_unsigned(value)` | 明确表示将数据转为无符号表示送入核心计算单元，而非纯数学概念 | `radix2_divider.sv` |
| **24** | **EX模块内部信号去后缀** | 解包/打包信号带 `_i` / `_o` (如 `valid_i`, `wb_valid_o`) | 移除后缀，如 `valid`, `wb_valid` | 严格区分端口与内部线网，消除视觉噪音 | `execute.sv` |
| **25** | **EX模块数据信号语义化** | `pc4_data`, `muldiv_result`, `exception_like` | `pc_plus4`, `mdu_result`, `exc_detected` | 摒弃口语化，向标准微架构术语靠拢 | `execute.sv` |
| **26** | **EX模块端口缩写统一** | `pkt_exe_i` 等 | `ex_pkt_i` 等 | 统一使用流水线级缩写 (`IF`, `ID`, `EX`, `WB`) | `execute.sv` |
| **27** | **MDU术语与命名统一** | `rv32m_unit`, `rv32m_req_t` 等 | `mdu_top`, `mdu_req_t`, `mdu_mul_core` 等 | 指代微架构单元而非指令集扩展，语法更简短，适应未来RV64M | `rv32m_unit.sv`, `rv32m_mul_comb.sv` |
| **28** | **控制信号规范化 [高优]** | 保留 `kill_i`，使用 `wait_o` | `kill_i` -> `flush_i`，`wait_o` -> `stall_o` | 贯彻控制流术语统一，避开SV保留字 | `rv32m_unit.sv` |
| **29** | **虚假参数化清理 (Mul)** | `rv32m_mul_comb` 有 `DW` 参数但硬编码限制为 32 | 移除 `DW` 参数，直接硬编码支持 RV32 | 避免上层例化误传参数导致综合报错，代码更诚实 | `rv32m_mul_comb.sv` |
| **30** | **乘法器时序预留** | 乘法为纯组合逻辑，无打拍参数 | 重命名为 `mdu_mul_core`，预留 `MUL_LATENCY` 参数 | 32x32乘法易成关键路径，预留参数方便未来转流水线乘法器提升主频 | `rv32m_mul_comb.sv` -> `mdu_mul_core.sv` |
| **31** | **SV端口声明精简** | `input wire logic`, `input wire xxx_t` | 移除 `wire` 关键字 | 纯 SV 风格精简，消除冗余声明 | 全局涉及端口声明处 |
| **32** | **LSU控制信号统一 [高优]** | `ex_kill_i`, `complete_o` | `ex_flush_i` (或 `flush_i`), `done_o` | 贯彻全局控制流术语，避免口语化命名 | `lsu.sv` |
| **33** | **LSU数据通路抽离** | Store/Load 字节对齐与符号扩展混在 FSM 内 | **抽离为 `lsu_align.sv`**（或独立函数） | 控制与数据分离，FSM大幅瘦身，时序约束更清晰 | `lsu.sv`, 新建 `lsu_align.sv` |
| **34** | **虚假参数化清理 (LSU)** | 带有 `DW` 参数，但内部硬编码 32 位切片 | **移除 `DW` 参数，明确标注 RV32 only** | 避免 `DW=64` 时综合报错或数据截断，代码更诚实安全 | `lsu.sv` |
| **35** | **LSU输出握手缺失** | `LSU_COMPLETE` 单周期脉冲，不看下游是否反压 | 增加 `wb_ready_i` (或 `stall_i`)，在 COMPLETE 状态保持 | 防止下游流水线停顿时丢失 Load 数据 | `lsu.sv` |
| **36** | **CSR单体架构拆分** | 所有CSR混在一个模块的5个不同代码块中 | **按功能簇拆分** (如 `csr_counters.sv`, `csr_trap.sv`) | 将“散弹枪式修改”变为“局部修改”，极大提升自定义CSR的扩展性 | `csr_regfile.sv`, 新建 `src/core/csr/` 目录 |
| **37** | **CSR地址译码抽离** | `csr_implemented`, `csr_read_only` 等判定函数混在内部 | 抽离为独立的 `csr_decode.sv` | 纯组合查表逻辑独立，便于EX级提前快速判定非法指令 | `csr_regfile.sv`, 新建 `csr_decode.sv` |
| **38** | **计数器参数化** | `mcycle` 等硬编码 64 位并手动分割高低位 | 增加 `MCYCLE_WIDTH` 参数 | 便于未来裁剪或扩展为 RV32E 极简核 | `csr_regfile.sv` (或拆分后的 `csr_counters.sv`) |
| **39** | **CSR端口语法精简** | `input wire logic`, `input wire xxx_t` | 移除 `wire` 关键字 | 统一为纯 SV 风格，消除冗余声明 | `csr_regfile.sv` 及全局所有模块 |
| **40** | **特权级切换通路打通** | `MPP` 硬编码为 M，Trap/MRET 未处理特权级保存与恢复 | Trap时存入 `current_priv_i`，MRET时输出 `priv_mode_o` | 保持 M-mode 功能不变，但打通特权级切换的数据通路，为 S-mode 铺路 | `csr_regfile.sv` |
| **41** | **架构特性参数化** | 无 U/S 模式开关 | 增加 `SUPPORT_S_MODE`, `SUPPORT_U_MODE` 参数 | 通过参数控制 CSR 地址译码，实现一套代码编译不同特权级核 | `riscv_pkg.sv`, `csr_regfile.sv` |
| **42** | **委派寄存器真实化** | `medeleg`/`mideleg` 硬编码返回 0 | 建立真实可读写寄存器(复位为0) | 为未来的异常/中断委派 机制预留状态存储 | `csr_regfile.sv` |
| **43** | **PMP 空间预留** | 无物理内存保护结构 | 新建 `csr_pmp.sv` 空壳，预留配置接口 | 跑 Linux 等 OS 的刚需，提前留坑避免事后重构顶层 | 新建 `src/core/csr/csr_pmp.sv` |
| **44** | **冒险检测与前递抽离** | 所有 RAW 冒险均停顿一拍，无前递逻辑 | **抽离 `forward_unit.sv`**，ALU结果前递，仅 Load-Use 停顿 | 消除不必要的流水线气泡，大幅降低 CPI，提升核的基础性能 | `core_ctrl.sv`, 新建 `src/core/forward_unit.sv` |
| **45** | **控制信号统筹集中** | EX/WB 模块直接生成 `flush_req`，控制源零散 | 数据通路只输出原始事件(如 `branch_taken`)，由 `core_ctrl` 集中仲裁冲刷向量 | 让数据通路无状态化，控制逻辑成为唯一大脑，消除多源冲刷毛刺 | `execute.sv`, `core_ctrl.sv` |
| **46** | **控制信号打包传递** | `ifid_stall`, `idex_flush` 等零散走线穿越顶层 | 打包为 `pipe_ctrl_t` 结构体，直连 `pipe_reg.sv` | 扁平化顶层连线，减少布线拥堵和人工连线错误 | `riscv.sv`, `pipe_reg.sv` |
| **47** | **WFI 控制路径分离** | WFI 与 Trap/Redirect 共用 `pipe_kill` 冲刷逻辑 | WFI 仅停顿 PC 和 IF 级，不参与流水线冲刷 | 避免 WFI 唤醒后引入不必要的气泡，降低中断响应延迟 | `core_ctrl.sv` |
| **48** | **通用握手缓冲抽离** | MDU 等模块手写 `rsp_hold` 反压逻辑 | **新建 `skid_buffer.sv`**，封装标准 valid/ready 缓冲 | 屏蔽底层反压时序，MDU 逻辑瘦身30%，全局复用 | `src/common/skid_buffer.sv` |
| **49** | **总线数据对齐器抽离** | LSU 内混杂字节移位、符号扩展、写选通生成 | **新建 `bus_align.sv`** 纯组合逻辑模块 | 与指令集解耦，LSU 的 FSM 极度精简，对齐逻辑可复用于其他总线接口 | `src/common/bus_align.sv` |
| **50** | **MDU 算法核心下沉** | 乘法器和除法器带有部分架构特定逻辑 | 去除符号处理，下沉为 `mul_core.sv`, `div_core.sv` | 彻底成为与架构无关的算术积木，可供加速器/DSP复用 | 移入 `src/common/mdu/` |
| **51** | **Common/Core 界限定型** | 通用逻辑与架构逻辑混杂，目录界限模糊 | **明确二分法则**：无 `riscv_pkg` 依赖的放 `common/`，流水线/译码/控制放 `core/` | 建立清晰的 IP 层次，为未来引入新架构(如 RV64)提供干净的积木库 | 全局目录结构重构 |
| **52** | **Commit追踪路径隔离** | `commit_o` 拼装逻辑(近30行)混在核心控制块中 | 抽离至 `commit_trace.sv` 或用宏隔离 | 避免干扰核心写回控制逻辑阅读，综合时不占面积 | `retire_stage.sv` |
| **53** | **写回数据通路抽离** | `rf_write_data` 多路选择混在退休模块中 | 抽离为 `wb_mux.sv` 纯组合逻辑 | 职责分离，退休级专注控制流与异常仲裁，不碰数据选择 | `retire_stage.sv`, 新建 `wb_mux.sv` |
| **54** | **异常优先级仲裁抽离** | Trap/IRQ/MRET 优先级判定散落在多个 if 块 | 抽离为 `exception_arbiter.sv` | 未来支持 S-mode 异常委派时，复杂的优先级逻辑不会污染主状态机 | `retire_stage.sv`, 新建 `exception_arbiter.sv` |
| **55** | **中断Eligibility参数化** | `irq_eligible` 硬编码 M-mode 寄存器位 | 预留 `SUPPORT_S_MODE` 参数分支 | 落实架构拓展预留，为引入 S-mode 中断(SIE/SIP)做准备 | `retire_stage.sv` |
| **56** | **顶层胶水逻辑下沉** | 顶层有近30行 `always_comb` 拼装 EX/WB 安全气泡数据 | **将 LSU/MDU 状态仲裁逻辑下沉至 `execute` 或独立仲裁器** | 顶层应只做纯连线，剥离微架构控制逻辑后顶层代码锐减，可读性极高 | `riscv.sv`, `execute.sv` |
| **57** | **CSR 旁路逻辑越界** | 顶层手写 `csr_rdata_for_ex` 等旁路多路选择 | 将旁路逻辑移至 `csr_regfile.sv` 内部，增加 preview 端口 | CSR 模块自管 architectural forwarding，顶层不需要感知 CSR 地址语义 | `riscv.sv`, `csr_regfile.sv` |
| **58** | **验证断言剥离** | 顶层散布大量 `ifndef SYNTHESIS` 的 assert/info | 抽离至独立的 `riscv_sva.sv`，使用 `bind` 绑定 | 物理隔离设计代码与验证代码，回归纯粹的硬件连线图风格 | `riscv.sv`, 新建 `riscv_sva.sv` |
| **59** | **控制信号打包传递** | 冒险检测单元拉出近10根零散的 stall/flush 线 | 定义 `pipe_ctrl_t` 结构体，控制单元输出结构体，顶层单线传递 | 扁平化顶层连线，极大降低连错风险，便于扩展 | `riscv_pkg.sv`, `riscv.sv`, `core_ctrl.sv` |
| **60** | **通用类型解耦** | `riscv_pkg` 中混有 `core_bus_req_t` 等总线类型 | **抽离至 `common_pkg.sv`** | `src/common/` 下的 IP 无需导入 RISC-V 架构包，实现真正解耦 | 新建 `src/common/common_pkg.sv` |
| **61** | **Mcause 位宽动态化** | `{1'b0, 31'd0}` 硬编码 31 位 | 改为 `DW'(0)` 或动态拼接 | 确保切换 RV64 宏时，package 一键无错编译通过 | `riscv_pkg.sv` |
| **62** | **流水线控制结构体** | 顶层有近10根零散的 stall/flush 连线 | 在 pkg 中定义 `pipe_ctrl_t` 结构体 | 扁平化顶层连线，`core_ctrl` 输出单结构体，降低连线错误率 | `riscv_pkg.sv`, `core_ctrl.sv` |
| **63** | **Commit Order 参数化** | `commit_pkt_t` 中 order 硬编码 64 位 | 增加 `ORDER_W` 全局参数 | 允许在低功耗场景下裁剪退休计数器位宽，节省面积 | `riscv_pkg.sv` |

