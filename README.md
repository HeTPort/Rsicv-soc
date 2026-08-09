# RV32IM RISC-V SoC

A small 32-bit RISC-V processor and SoC, written in SystemVerilog as a learning
project.

> "I am not trying to build the fastest RISC-V core. I am trying to understand
> why every instruction retires exactly once, even when memory stalls, a branch
> redirects the pipeline, or a trap interrupts the normal path."

I started this project because CPU block diagrams make everything look tidy.
The interesting lessons begin when the implementation is not tidy: a response
returns late, a younger instruction must be killed, or two parts of the design
disagree about which instruction owns a result.

The first practical goal is to run preemptive FreeRTOS on this custom RV32IM
core in the programmable logic of a Zynq XC7Z010. Linux is still an interesting
long-term direction, but it is not the current milestone. There is plenty to
learn before adding an MMU, caches, S-mode, and the rest of a Linux-capable
system.

If this is your first visit, start with the
[project knowledge base](doc/PROJECT_KNOWLEDGE_BASE.md). It explains the design
gradually and links the code to the bugs and tests that shaped it.

## Where the project is today

The processor can execute RV32I instructions and the RV32M multiply/divide
extension. It has M-mode CSR instructions, synchronous traps, `mret`, a
synchronous instruction RAM, and a wait-state-safe load/store path.

The latest recorded verification result is:

```text
Directed ModelSim tests       22/22 passed
Python converter tests         4/4 passed
Regression false-pass test     passed
```

That result is a useful baseline, not a claim that the SoC is finished or that
every corner of the ISA has been proven.

| Area | Current state |
|---|---|
| CPU | RV32IM in-order core using packed pipeline packets |
| Pipeline control | RAW stalls, redirect flushing, delayed fetch kill, and complete bubbles |
| Traps and CSRs | M-mode CSR operations, legality checks, WARL behavior, precise synchronous traps, and `mret` |
| Instruction path | One-cycle synchronous program RAM with paired fetch-error status and precise cause-1 traps |
| Data path | One outstanding request, inserted wait-state support, registered results, and precise access faults |
| Verification | Architectural commit checking, `tohost`, ModelSim regression, ELF conversion, and a 47/47 ACT4 RV32I/RV32M baseline |
| Memory map | AR-009 split 64 KiB map accepted; timer/UART/RAM/default decode is implemented |
| Peripherals | Machine timer and polling UART TX are implemented; GPIO and UART RX/IRQ remain open |
| Software | Startup code, final linker layout, drivers, and FreeRTOS are still to come |
| FPGA | Block RAM inference has been checked; board timing and hardware testing have not been completed |

## A short tour of the design

```text
                         +----------------------+
                         | synchronous prog_ram |
                         +----------+-----------+
                                    |
                                    v
IF -> IF/ID -> ID -> ID/EX -> EX / LSU -> EX/WB -> WB
 |                ^            |                  |
 |                |            |                  +-> GPR / CSR / trap entry
 +---- core_ctrl -+            |
                              request/response bus
                                    |
                                    v
               +---------- SoC fabric -----------+
               | timer | UART TX | data RAM | error |
               +---------------------------------+
```

Instruction memory takes one cycle to return a word. The front end therefore
keeps the request PC beside the delayed response and discards stale responses
after a redirect.

Loads and stores use a small request/response interface. The LSU accepts one
transaction, keeps its payload stable while the target stalls, waits for one
response, and moves the completed result into the EX/WB packet. RAM and future
peripherals sit outside the CPU core.

The design is deliberately modest. It has no cache, MMU, S-mode, PLIC, AXI
fabric, or general forwarding network. RV32M multiplication remains
combinational, while DIV/DIVU/REM/REMU use a 32-iteration Radix-2 divider and
the existing EX backpressure mechanism.

## What you can study here

The repository is intended to be readable as well as runnable. Some useful
starting points are:

- follow one instruction from fetch to architectural commit;
- see why a pipeline bubble must clear the complete packet;
- trace a stalled load through request, response, and writeback;
- compare misalignment traps with bus access faults;
- inspect RED and GREEN evidence for bugs that once produced wrong behavior;
- see how a testbench, regression runner, linker plan, and RTL memory map must
  agree.

The focused reports in [`doc/`](doc/) describe the problem, root cause, options,
decision, consequences, and verification evidence. They are written as a study
record, not only as a changelog.

## How it is tested

Tests finish by committing a store to a configured `tohost` address:

```text
tohost == 1       PASS
tohost != 0 or 1  FAIL with a test-specific code
```

The regression runner accepts PASS only when four signals agree:

1. the simulator process exits with status zero;
2. the architectural PASS marker appears;
3. no fatal marker appears; and
4. ModelSim reports zero errors.

The testbench also checks ordered commits, x0 protection, trap and write
exclusion, memory byte masks, single-outstanding data transactions, response
pairing, and instruction-fetch timing.

The repository's current applicable ACT4 baseline passes all 39 RV32I and all
8 RV32M tests. That is strong regression evidence for the implemented I/M
subset, but it is not a claim of complete ISA or privileged-architecture
compliance.

## Try it

### Requirements

- ModelSim or QuestaSim, with `vlog` and `vsim` on `PATH`
- Windows PowerShell for the regression scripts
- Python 3 for the converter and importer tests
- Vivado for the optional synthesis checks
- a RISC-V GNU toolchain when rebuilding assembly programs

### Run one simulation

From the repository root:

```powershell
Set-Location .\sim
vsim -do run.do
```

This rebuilds the ModelSim work library, compiles the files in
[`sim/filelist.f`](sim/filelist.f), starts `tb_riscv_core`, and runs until the
test reports completion.

### Run the regression

```powershell
Set-Location .\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\run_regression.ps1 -Tag smoke
.\test_regression_result.ps1
python -m unittest test_elf_to_mem.py test_import_act4.py
```

A few useful selections:

```powershell
# Show the manifest without compiling.
.\run_regression.ps1 -List

# Run tests from selected areas.
.\run_regression.ps1 -Tag lsu
.\run_regression.ps1 -Tag csr,mret

# Trace one test and request waveform output.
.\run_regression.ps1 -Test ebreak -Trace -DumpWaves
```

The [regression guide](sim/regress/README.md) explains the manifest, generated
files, ACT4 import flow, and result checks.

### Generate and check the accepted SoC map

```powershell
python .\tools\gen_soc_map.py
python .\tools\gen_soc_map.py --check
python -m unittest tools/test_gen_soc_map.py
```

[`config/soc_map.json`](config/soc_map.json) is the sole editable source for the
accepted split 64 KiB map. It generates SystemVerilog, C, linker, simulation,
Vivado Tcl, and ACT4-facing artifacts. The lifecycle status is preserved in
every artifact: `accepted` freezes the ABI but does not mean the decoder or
software map is implemented.
See the [configuration guide](config/README.md).

### Check FPGA resource inference and early internal timing

The synthesis scripts use the provisional `xc7z010clg400-1` part unless you
override it with the documented environment variable.

```powershell
Set-Location .\sim\synth
vivado -mode batch -source .\check_prog_ram_bram.tcl
vivado -mode batch -source .\check_riscv_soc_ar003.tcl
vivado -mode batch -source .\check_riscv_soc_configured_ram.tcl
vivado -mode batch -source .\compare_riscv_soc_ram_utilization.tcl -tclargs ram_16k
vivado -mode batch -source .\compare_riscv_soc_ram_utilization.tcl -tclargs ram_64k
vivado -mode batch -source .\report_riscv_soc_ram_timing.tcl -tclargs ram_16k
vivado -mode batch -source .\report_riscv_soc_ram_timing.tcl -tclargs ram_64k
```

These are out-of-context checks. They show that Vivado inferred Block RAM and
retained the expected CPU, LSU, and RAM hierarchy. They do not prove timing on
a physical board. The paired capacity result and preserved raw reports are in
[AR-015](doc/AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md): 16 KiB per bank uses
8/60 RAMB36 tiles, while 64 KiB per bank uses 32/60 on the provisional part.
Its historical baseline exposed an 87.102 ns combinational MULDIV path that
failed both 25 MHz and 50 MHz. [AR-017](doc/AR017_RADIX2_ITERATIVE_DIVIDER.md)
replaces that path with the verified iterative divider: both profiles now pass
50 MHz OOC post-synthesis STA with WNS +7.373 ns, and the new worst path is
12.605 ns multiply-high logic. These checks are not post-route board timing
closure.

## Repository map

```text
src/
  core/       CPU pipeline, control, LSU, CSR file, and packet definitions
  bus/        Active RAM adapter and future bus work
  generated/  Generated accepted SoC-map constants
  mem/        Synchronous program and data RAM
  periph/     Implemented machine timer and polling UART TX targets
  riscv_soc.sv

sim/
  generated/  Generated normalized map and Vivado Tcl constants
  tb/         Directed and protocol testbenches
  regress/    Regression runner, image tools, ACT4 adapters, and utility tests
  synth/      Vivado out-of-context checks
  filelist.f
  run.do

testdata/     Assembly sources and simulation memory images
config/       Authoritative accepted SoC map and generation contract
firmware/     Generated C/linker map consumers; implementation follows later
tools/        Dependency-free configuration generator and tests
verif/act4/   RISC-V Architecture Test integration configuration
doc/          Design decisions, focused problem reports, and study notes
```

The build scripts include files explicitly. Obsolete alternatives and empty
placeholder files are not kept in the source tree; planned modules are added
when their interface and owning phase are ready.

## Where it is going

Phase 0A repaired retirement and pipeline side-effect precision, Phase 1 froze
the core-to-SoC contract, Phase 2 implemented the external data fabric, Phase 3
implemented precise timer interrupts/WFI, and Phase 4 now has polling UART TX.
The next steps are:

1. keep the Phase 2 SoC-fault and ACT4 RV32I/RV32M baselines continuously green;
2. finish migrating linker, images, `tohost`, regression, and ACT4 consumers
   to the accepted split 64 KiB map as one verified change;
3. keep precise machine-timer/WFI and polling-UART regressions green;
4. add simple GPIO and complete the combined Phase 4 exit gate;
5. build startup code, drivers, and bare-metal tests;
6. integrate the official FreeRTOS RISC-V port;
7. add board constraints, close timing, and test the design on hardware.

[`TODO.md`](TODO.md) is the authoritative checklist. The roadmap is allowed to
change when simulation, synthesis, or software gives a good reason.

## Reading and design notes

- [Project knowledge base](doc/PROJECT_KNOWLEDGE_BASE.md): a gradual guide to
  the RTL, timing, traps, memory path, and verification flow
- [Architecture design and decisions](doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md):
  design history, tradeoffs, evidence, and open gates
- [Architecture review and action plan](doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md):
  review findings and their current status
- [AR-009 accepted memory map](doc/AR009_ARCHITECTURAL_MEMORY_MAP.md): the
  frozen Phase 1 hardware/software ABI
- [AR-016 core-to-SoC environment contract](doc/AR016_CORE_TO_SOC_ENVIRONMENT_CONTRACT.md):
  ownership, request routing, fault behavior, and the Phase 2 handoff
- [Memory-map contract guide](doc/MEMORY_MAP_CONTRACT_DESIGN_GUIDE.md): address
  decoding, bus behavior, faults, and hardware/software consistency

## A personal note

This repository is a learning record, not a production-ready processor. Mature
open-source RISC-V cores are far ahead in features, performance, and
verification. That is not a reason to hide the unfinished parts. Those parts
often contain the most useful lessons.

AI tools have helped with parts of the implementation and documentation. I do
not treat generated code or explanations as proof. The standard for accepting
a change is still the same: understand the behavior, reproduce the failure,
write a focused test, and keep the regression green.

> "If one waveform, failed test, or design note helps someone understand their
> own CPU, this repository has done something useful."

Bug reports and technical review are welcome. If the project helps you learn or
saves you time on your own design, starring it helps other learners find it.
