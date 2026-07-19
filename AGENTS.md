# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project overview

This is a small RV32IM RISC-V CPU + SoC written in SystemVerilog.

- `src/core/riscv.sv` — top of the pipelined CPU.
- `src/core/core_ctrl.sv` — centralized pipeline control: hazard detection, stall/flush generation, halt/pipe_kill state machine.
- `src/core/lsu.sv` — Load/Store Unit: address generation, store strobe/data alignment, load data alignment/sign-extension, and the only interface to `data_ram`.
- `src/riscv_soc.sv` — SoC wrapper that connects the CPU to a program RAM.
- `src/mem/prog_ram.sv` — synchronous instruction/program RAM.
- `src/mem/data_ram.sv` — synchronous data RAM, now written as a pure BRAM template.
- `sim/tb/tb_riscv_core.sv` — main testbench that loads `testdata/prog.hex` and checks the CPU.
- `testdata/*.S` and `testdata/*.hex` — hand-written assembly tests.
- `doc/*.md` — architecture notes in Chinese; `doc/STRUCTURE.md` has the most detailed pipeline diagram.
- `doc/some_points.md` — note about removing the `seen_illegal` latch to avoid glitch capture after struct packing.

The project is meant to be simulated with ModelSim/QuestaSim and synthesized with Vivado.

### Recent refactor

The pipeline data flow was refactored from flat signals into packed SystemVerilog structs (`fetch_pkt_t`, `id_ex_pkt_t`, `ex_wb_pkt_t` defined in `src/core/riscv_pkg.sv`). Most pipeline modules now accept/return a single struct instead of dozens of individual signals. A few placeholder directories/files were added (`src/common/`, `src/bus/`, `src/periph/`, `webServerApiSettings.json`) but they are currently empty or unrelated to the core CPU.

### LSU / control split

A later refactor extracted the load/store logic out of `execute.sv` into `src/core/lsu.sv` and the hazard/flush/halt control out of `riscv.sv` into `src/core/core_ctrl.sv`:

- `execute.sv` now only does ALU, branch/jump, and MULDIV; it receives `mem_misaligned_i` from the LSU for exception reporting.
- `lsu.sv` owns the data-memory request interface, byte/halfword store alignment, and load alignment/sign/zero-extension.
- `wb_stage.sv` no longer performs load alignment; it receives pre-aligned `load_data_i` from the LSU and muxes it into the register write port.
- `core_ctrl.sv` centralizes `hazard_stall`, `pc_stall`/`ifid_stall`/`idex_stall`, `ifid_flush`/`idex_flush`, `pipe_kill`, and `halt_q`.

## Build / simulation commands

All source files are listed in `sim/filelist.f` and compiled with the main testbench.

### Run the main CPU testbench

```bash
cd sim
vsim -do run.do
```

`run.do` does the following:

1. Deletes/recreates the `work` library.
2. Compiles all files from `filelist.f` with `vlog -sv -f filelist.f`.
3. Runs `vsim -voptargs=+acc work.tb_riscv_core`.
4. Adds all signals to the wave window and runs to completion.

### What the simulation checks

The testbench loads `testdata/prog.hex` into `prog_ram` and runs until the CPU halts. The pass/fail convention is:

- **PASS:** `x10 == 1` and `x11 == 0`
- **FAIL:** `x10 == 0` and `x11` contains a failure code

The program in `testdata/prog.hex` ends with `ebreak`, which the core treats as a halt/exception event.

### Known filelist issues

- `sim/filelist.f` references `./../src/core/register.sv`, which does not exist; replace it with `./../src/core/regfile.sv`.
- `sim/filelist.f` is also missing the new `src/core/lsu.sv` and `src/core/core_ctrl.sv` files; add them after `execute.sv`.
- `tb_riscv_core.sv` hard-codes a Windows path for the program hex file:
  ```systemverilog
  .FILE("D:/Rsicv-soc/testdata/prog.hex")
  ```
  Change it to a relative or Linux path (e.g., `../testdata/prog.hex`) for local simulation.
- `tb_riscv_soc.sv` is currently empty/unused.

### Assembling tests

No build script is provided for the assembly tests. To regenerate a `.hex` from one of the `.S` files, use a RISC-V toolchain:

```bash
riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 -o test.o testdata/ebreak_test.S
riscv64-unknown-elf-objcopy -O ihex test.o test.hex
```

Then convert the Intel HEX to the plain `$readmemh` format used by `prog_ram`.

## High-level architecture

### Pipeline

The CPU is organized as a simple in-order pipeline:

```text
IF -> IF/ID -> ID -> ID/EX -> EX -> LSU -> data RAM -> EX/WB -> WB
```

| Stage | Modules / logic |
|-------|-----------------|
| IF    | `pc_counter` outputs `instr_addr_o`; instruction RAM returns data one cycle later |
| IF/ID | `if2id` receives `fetch_pkt_t` and registers the fetched instruction and its PC |
| ID    | `decode` decodes the instruction into an `id_ex_pkt_t`; `regfile` reads operands |
| ID/EX | `id2ex` registers the `id_ex_pkt_t` from decode |
| EX    | `execute` runs the ALU, evaluates branches, computes jumps, runs MULDIV, and produces an `ex_wb_pkt_t` |
| MEM   | `lsu.sv` generates address, byte/halfword strobes, and misalignment detection; `data_ram` is a synchronous RAM; loads return one cycle later |
| EX/WB | `ex2wb` registers the `ex_wb_pkt_t` writeback metadata from EX/LSU |
| WB    | `wb_stage` selects the final writeback value (using pre-aligned load data from LSU) and writes to `regfile` |

Important: there is **no explicit `ex2mem` or `mem2wb` register**. `lsu.sv` directly drives `data_ram`, and `ram_rdata` bypasses `ex2wb` and goes straight to `wb_stage` via the LSU's load-alignment logic. `ex2wb` only holds the writeback control/metadata so it lines up with the delayed load data.

### Pipeline packets (structs)

`src/core/riscv_pkg.sv` defines the packed structs that flow through the pipeline:

- `fetch_pkt_t` — `{ valid, pc, instr }` used by `if2id`.
- `id_ex_pkt_t` — used by `id2ex`, containing:
  - `valid`, `pc`, `instr`
  - `rf_pkt_t rf` — `{ we, addr }`
  - `ex_data_pkt_t ex_data` — `{ op1, op2, imm, store_data }`
  - `ex_ctrl_pkt_t ex_ctrl` — `{ alu_op, branch_op, jump_op, mem_req, mem_we, mem_size, mem_unsigned, wb_sel, muldiv_valid, muldiv_op }`
  - `exc_pkt_t exc` — `{ illegal_instr, ecall, ebreak }`
  - `use_rs1`, `use_rs2`
- `ex_wb_pkt_t` — used by `ex2wb`, containing:
  - `valid`
  - `rf_pkt_t rf`
  - `wb_sel`
  - `alu_data`, `pc4_data`
  - `mem_pkt_t mem_info` — `{ mem_size, mem_unsigned, load_offset }`
  - `mem_misaligned`
  - `exc_pkt_t exc`

These structs reduce top-level wiring and make bubble injection safer because reset/flush can clear the whole packet at once.

### Instruction fetch timing

`prog_ram` is synchronous read with one-cycle latency. The top-level `riscv.sv` keeps a delayed PC/valid pair (`if_resp_pc_q` / `if_resp_valid_q`) so the instruction coming back from memory can be matched with the PC that requested it. `if2id` captures this delayed response in a `fetch_pkt_t`.

### Branch / jump handling

Branches and jumps are resolved in EX. When taken:

- `ex_redirect_en` / `ex_redirect_pc` update `pc_counter`.
- `ex_flush_req` flushes `if2id` and `id2ex`.
- Because the instruction memory has one-cycle latency, the fetch started before the redirect will return on the next cycle. `fetch_kill_q` (a delayed version of `ex_flush_req`) is OR'd into `ifid_flush` to discard that stale fetch result.

### Hazard handling

The only hazard logic is a simple RAW stall in `core_ctrl.sv`:

```systemverilog
assign hazard_stall =
    id_valid && ex_valid && ex_rf_we && (ex_rd_addr != 5'd0) &&
    (
      (id_use_rs1 && id_rs1_addr == ex_rd_addr) ||
      (id_use_rs2 && id_rs2_addr == ex_rd_addr)
    );
```

`core_ctrl.sv` also generates `pc_stall`, `ifid_stall`, `idex_stall`, `ifid_flush`, `idex_flush`, `pipe_kill`, and `halt_q`. When a hazard is detected:

- `pc_stall` and `ifid_stall` are asserted.
- `idex_flush` is asserted to insert a bubble.

There is **no forwarding network** beyond the write-first behavior in `regfile.sv` (a write in the same cycle as a read returns the new value for the same address). Hazards that span more than one stage may require extra stalls or forwarding. `ex_stall` is currently tied to `0` and is reserved for a future multi-cycle MULDIV or memory interface.

### Trap / halt handling

`riscv.sv` sets `halt_q` when the EX/WB packet (`ex2wb_pkt_out`) indicates any of:

- `illegal_instr`
- `ecall`
- `ebreak`
- memory misaligned access

After halt is asserted, `pipe_kill` is used to suppress further fetch, memory access, and writeback. Before entering `ex2wb`, `ex2wb_pkt_in_safe` masks off the valid bit, register write enable, and exception flags when `pipe_kill` is active, preventing stale instructions from propagating.

`exception_o` and `illegal_instr_o` are reported at the WB stage.

### Control/data conventions

- `riscv_pkg.sv` defines opcodes, funct3/funct7 constants, enum control types (`alu_op_e`, `branch_op_e`, `jump_op_e`, `mem_size_e`, `wb_sel_e`, `muldiv_op_e`), and the pipeline packet structs. It replaces the old `define.sv`.
- `riscv_pkg.sv` also contains compile-time hooks for future RV64 support (`+define+RISCV_XLEN_64`) and additional ALU ops (`ALU_ADDW`, `ALU_SUBW`, etc.).
- RV32M multiply/divide is implemented **combinationally** in `execute.sv`. `ex_stall` in `core_ctrl.sv` is reserved for a future multi-cycle implementation.
- Data memory is little-endian; `lsu.sv` handles store strobe alignment and load byte/halfword extraction and sign/zero extension before forwarding the data to `wb_stage.sv`.
- `data_ram.sv` is now a pure BRAM template (no reset branch, no range checks) so Vivado infers Block RAM. It accepts an `INIT_FILE` parameter for loading firmware images in simulation.

### Testbench note

`tb_riscv_core.sv` previously used a sticky `seen_illegal` latch that could capture a glitch caused by packed-struct unpacking delays. That latch was removed; pass/fail now checks `illegal_instr` directly after halt is stable. See `doc/some_points.md` for the rationale.
