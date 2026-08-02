# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Living documentation requirement

Architecture-changing work is incomplete until the living documents are
updated in the same change:

- Update `doc/PROJECT_KNOWLEDGE_BASE.md` when behavior, timing, module
  boundaries, packets, build steps, or current status change.
- Update `doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md` when a design decision is
  proposed, accepted, implemented, verified, deferred, or superseded.
- Record the problem, root cause, options considered, decision, consequences,
  and verification evidence for problem-resolution work.
- Update diagrams and open-risk tables when the data/control path changes.
- Keep detailed focused evidence in a dedicated `doc/AR*.md` file and link it
  from the consolidated documents.
- Update `TODO.md` when phase ordering, exit gates, or milestone scope changes.

## Project overview

This is a small RV32IM RISC-V CPU + SoC written in SystemVerilog.

The active core also includes `src/core/radix2_divider.sv`, a kill-safe
32-iteration restoring divider for DIV/DIVU/REM/REMU.

- `src/core/riscv.sv` — top of the pipelined CPU.
- `src/core/core_ctrl.sv` — centralized pipeline control: hazard detection, stall/flush generation, delayed fetch kill, and `pipe_kill`.
- `src/core/lsu.sv` — Load/Store Unit: address/alignment, store lanes, load extension, and the single-outstanding data-bus transaction FSM.
- `src/bus/core_bus_data_ram.sv` — adapter from the CPU-local request/response bus to synchronous data RAM, with verification wait-state parameters.
- `src/bus/soc_data_fabric.sv` — centralized full-address data decoder, local-address translator, and registered response-owner mux.
- `src/bus/core_bus_default_target.sv` — one-cycle registered, side-effect-free error target for every non-RAM data address.
- `src/riscv_soc.sv` — SoC wrapper that connects the CPU to program RAM and routes its data bus through the fabric to RAM/default targets.
- `src/mem/prog_ram.sv` — synchronous instruction/program RAM.
- `src/mem/data_ram.sv` — synchronous data RAM, now written as a pure BRAM template.
- `sim/tb/tb_riscv_core.sv` — main testbench that loads `testdata/prog.hex` and checks the CPU.
- `testdata/*.S` and `testdata/*.hex` — hand-written assembly tests.
- `doc/PROJECT_KNOWLEDGE_BASE.md` — living beginner-oriented study guide.
- `doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md` — living architecture and decision record.
- `doc/AR*.md` — focused problem reports with RED/GREEN evidence.

The project is meant to be simulated with ModelSim/QuestaSim and synthesized with Vivado.

### Recent refactor

The pipeline data flow was refactored from flat signals into packed SystemVerilog structs (`fetch_pkt_t`, `id_ex_pkt_t`, `ex_wb_pkt_t` defined in `src/core/riscv_pkg.sv`). Most pipeline modules now accept/return a single struct instead of dozens of individual signals. A few placeholder directories/files were added (`src/common/`, `src/bus/`, `src/periph/`, `webServerApiSettings.json`) but they are currently empty or unrelated to the core CPU.

### LSU / control split

A later refactor extracted the load/store logic out of `execute.sv` into `src/core/lsu.sv` and the hazard/flush control out of `riscv.sv` into `src/core/core_ctrl.sv`:

- `execute.sv` does ALU, branch/jump, combinational multiply, and
  completed-divider result selection; it receives `mem_misaligned_i` from the
  LSU for exception reporting.
- `lsu.sv` owns request payload registers, the
  `IDLE -> REQUEST -> RESPONSE -> COMPLETE` state machine, byte/halfword store
  alignment, and load alignment/sign/zero-extension.
- `riscv.sv` exposes the single-outstanding data bus; RAM and future
  peripherals are targets outside the CPU.
- `wb_stage.sv` no longer performs load alignment; it receives pre-aligned `load_data_i` from the LSU and muxes it into the register write port.
- `core_ctrl.sv` centralizes `hazard_stall`, `pc_stall`/`ifid_stall`/`idex_stall`, `ifid_flush`/`idex_flush`, delayed fetch kill, and `pipe_kill`.
- `radix2_divider.sv` produces one quotient bit per run cycle. `riscv.sv` holds
  ID/EX and bubbles EX/WB until `div_complete`, combines `div_wait` with
  `lsu_busy` at `ex_wait_i`, and cancels the unit through `ex_kill`.

## Build / simulation commands

All source files are listed in `sim/filelist.f` and compiled with the main testbench.

### Run the main CPU testbench

```bash
cd sim
vsim -do run.do
```

### Run the focused divider protocol test

```bash
cd sim
vsim -c -do run_divider_protocol.do
```

### Run the focused SoC data-fabric test

```bash
cd sim
vsim -c -do run_soc_data_fabric.do
```

`run.do` does the following:

1. Deletes/recreates the `work` library.
2. Compiles all files from `filelist.f` with `vlog -sv -f filelist.f`.
3. Runs `vsim -voptargs=+acc work.tb_riscv_core`.
4. Adds all signals to the wave window and runs to completion.

### What the simulation checks

The testbench loads `testdata/prog.hex` into `prog_ram` and monitors the
architectural commit interface. Completion is a committed store to the
configured `tohost` address:

- **PASS:** `tohost == 1`
- **FAIL:** another nonzero `tohost` value contains a test-specific failure code

`halt_o` is retained only as an obsolete compatibility output and is fixed low.

### Current filelist notes

- `sim/filelist.f` includes `regfile.sv`, `lsu.sv`, and `core_ctrl.sv`.
- `tb_riscv_core.sv` uses parameterized relative test-image paths.
- `tb_riscv_soc.sv` is the Phase 2 SoC integration environment. The
  separate `sim/regress/soc_red_tests.json` manifest selects it for unmapped
  load/store and invalid-fetch cases. The data cases now pass through the
  centralized fabric; invalid fetch remains intentionally RED until explicit
  instruction-error signaling is added.

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
IF -> IF/ID -> ID -> ID/EX -> EX -> LSU -> SoC fabric -> RAM/default -> EX/WB -> WB
```

| Stage | Modules / logic |
|-------|-----------------|
| IF    | `pc_counter` outputs `instr_addr_o`; instruction RAM returns data one cycle later |
| IF/ID | `if2id` receives `fetch_pkt_t` and registers the fetched instruction and its PC |
| ID    | `decode` decodes the instruction into an `id_ex_pkt_t`; `regfile` reads operands |
| ID/EX | `id2ex` registers the `id_ex_pkt_t` from decode |
| EX    | `execute` runs ALU/branch/jump/multiply; `radix2_divider` runs multi-cycle DIV/REM; completed results form an `ex_wb_pkt_t` |
| MEM   | `lsu.sv` captures one request, holds it until accepted, waits for one response, and emits one completion; `core_bus_data_ram.sv` translates it to synchronous RAM |
| EX/WB | `ex2wb` registers the `ex_wb_pkt_t` writeback metadata from EX/LSU |
| WB    | `wb_stage` selects the final writeback value (using pre-aligned load data from LSU) and writes to `regfile` |

Important: there is **no explicit `ex2mem` or `mem2wb` register**. The LSU
holds ID/EX during REQUEST/RESPONSE and allows the memory instruction into
EX/WB only during COMPLETE. Response data is registered in the LSU and still
feeds `wb_stage`/commit outside `ex2wb`; AR-004 remains open until the response
data/error are carried by the registered EX/WB packet.

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

`core_ctrl.sv` also generates `pc_stall`, `ifid_stall`, `idex_stall`,
`exwb_stall`, `ifid_flush`, `idex_flush`, delayed fetch kill, and `pipe_kill`.
When a hazard is detected:

- `pc_stall` and `ifid_stall` are asserted.
- `idex_flush` is asserted to insert a bubble.

There is **no forwarding network** beyond the write-first behavior in
`regfile.sv` (a write in the same cycle as a read returns the new value for the
same address). Hazards that span more than one stage may require extra stalls
or forwarding. `ex_stall` follows the combined LSU/divider `ex_wait_i`; the
owning ID/EX packet is held and EX/WB receives bubbles until completion.

### Trap handling

A valid EX/WB packet causes a synchronous trap for illegal instruction, ECALL,
EBREAK, instruction-address misalignment, or load/store misalignment.

- The faulting instruction remains valid so it can provide `mepc`, `mcause`,
  and `mtval`, but its normal register/CSR/memory/redirect effects are
  suppressed.
- WB trap entry updates the machine CSRs and redirects the PC to `mtvec`.
- `pipe_kill` converts the complete younger EX/WB input packet to the canonical
  bubble and suppresses younger LSU activity.
- `halt_o` is fixed low; tests and software use `tohost` completion.
- `exception_o` and `illegal_instr_o` are WB-stage observations.

### Control/data conventions

- `riscv_pkg.sv` defines opcodes, funct3/funct7 constants, enum control types (`alu_op_e`, `branch_op_e`, `jump_op_e`, `mem_size_e`, `wb_sel_e`, `muldiv_op_e`), and the pipeline packet structs. It replaces the old `define.sv`.
- `riscv_pkg.sv` also contains compile-time hooks for future RV64 support (`+define+RISCV_XLEN_64`) and additional ALU ops (`ALU_ADDW`, `ALU_SUBW`, etc.).
- RV32M multiplication remains combinational in `execute.sv`. DIV/DIVU/REM/REMU
  use `radix2_divider.sv`; `riscv.sv` selects quotient/remainder, asserts the
  generic EX wait path, and suppresses incomplete EX/WB packets.
- Data memory is little-endian; `lsu.sv` handles store strobe alignment and load byte/halfword extraction and sign/zero extension before forwarding the data to `wb_stage.sv`.
- `data_ram.sv` is a pure BRAM template (no reset branch, no range checks) and
  is instantiated outside the CPU through `core_bus_data_ram.sv`. It accepts
  an `INIT_FILE` parameter for loading firmware images in simulation.

### Testbench note

`tb_riscv_core.sv` validates ordered architectural commits, x0 protection,
trap/write exclusion, memory masks, data-bus single-outstanding/exactly-once
behavior, fetch request/response timing, and final IF/ID PC/instruction pairing.
Test programs report PASS or a failure code through a committed store to
`tohost`.

### Check the AR-003 SoC synthesis boundary

```powershell
Set-Location D:\Rsicv-soc\sim\synth
& 'D:\vivado\Vivado\2019.2\bin\vivado.bat' `
  -mode batch -source .\check_riscv_soc_ar003.tcl
```

This out-of-context check proves that the external data-bus/adapter hierarchy
synthesizes and retains both program/data Block RAM. It does not prove board
timing closure because no board clock or XDC constraints are applied.
