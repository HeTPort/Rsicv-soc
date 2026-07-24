# TODO.md — FreeRTOS on the Custom RV32IM Core in Zynq-7010 PL

## Primary target

Boot **FreeRTOS on this repository's custom RV32IM CPU**, synthesized into the
programmable logic (PL) of a Zynq XC7Z010 device. Demonstrate:

- preemptive task switching from a machine-timer interrupt;
- UART console output;
- an LED controlled through memory-mapped GPIO;
- repeatable ModelSim regression and Vivado bitstream generation;
- stable execution on the physical FPGA board.

FreeRTOS must execute on the custom RISC-V core, not on the Zynq ARM processing
system. The ARM processing system may be used only to provide a PL clock/reset
if the selected board does not expose a suitable oscillator directly to the PL.

Linux is intentionally deferred. This target does **not** require S-mode, an
MMU, OpenSBI, U-Boot, DDR, caches, RV64GC, AXI, or a PLIC.

The detailed architecture findings, remediation steps, verification cases, and
recommended Phase 0A gate are recorded in
[`doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md`](doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md).

> **Board information still required:** `XC7Z010` identifies the FPGA/SoC
> device, not the board model. Before board-specific work, record the board
> manufacturer/model, complete FPGA part (package and speed grade), oscillator
> frequency and pin, reset polarity, UART pins, LED pins, schematic, and any
> vendor XDC file.

## Development and learning rules

1. Preserve a green regression before and after every architectural change.
2. Use focused tests while debugging, then run the complete smoke suite.
3. A checkbox is complete only when its implementation and verification
   evidence both exist.
4. Before completing a phase, be able to explain why the interface or mechanism
   is needed, not only how it was coded.
5. Prefer the smallest design that meets the FreeRTOS target. Add AXI, PLIC,
   DDR, and advanced debug only when a later requirement justifies them.

---

## ACT4 policy: parallel verification, not a starting barrier

The complete official ACT4 suite does **not** have to pass before SoC and
FreeRTOS work starts. ACT4 checks ISA behavior; it does not implement or verify
the timer, UART, GPIO, linker script, FreeRTOS port, or FPGA constraints.

Development therefore proceeds in two parallel tracks:

```text
Track A: official ACT4 RV32I/RV32M coverage and CPU bug fixing
Track B: SoC bus -> timer interrupt -> UART/GPIO -> FreeRTOS -> FPGA
```

The tracks join at release gates:

- **Before timer/FreeRTOS debugging:** the existing directed smoke regression
  must remain green.
- **Before declaring FreeRTOS simulation complete:** CSR, trap, `mret`, timer
  interrupt, LSU, and context-switch-directed tests must pass.
- **Before declaring the CPU/FPGA target complete:** all applicable official
  RV32I/RV32M ACT4 tests should pass. Any unexecuted or unsupported test must be
  documented; a synthetic ACT4 harness smoke test is not ISA compliance.

This ordering prevents ACT4 integration work from blocking useful SoC progress
while still preventing FreeRTOS from hiding CPU correctness defects.

---

## Current project state

Implemented:

- [x] RV32IM in-order core with packed pipeline packets.
- [x] Explicit architectural commit/retirement interface.
- [x] M-mode CSR instructions and synchronous trap entry/return support.
- [x] Lightweight JSON/PowerShell ModelSim regression runner; UVM is not
  required for this target.
- [x] Separate instruction/data image support and commit-based `tohost`
  completion checking.
- [x] ELF-to-memory converter and ACT4 import/runner adapters.
- [x] Synthetic ACT4 harness smoke test.
- [x] Existing directed regression last verified at 9/9 passing, with converter
  tests at 4/4 passing.

Still missing:

- [ ] Imported and passing official ACT4 RV32I/RV32M test corpus.
- [ ] External CPU data bus and SoC address decoder.
- [ ] Hardware interrupt input and precise interrupt entry.
- [ ] `mtime`/`mtimecmp` machine timer.
- [ ] Implemented UART and GPIO peripherals; current files are empty
  placeholders.
- [ ] Firmware startup code, linker script, drivers, and FreeRTOS application.
- [ ] FPGA top, XDC constraints, Vivado build script, and physical-board result.

---

## Phase 0 — Freeze the present green baseline

**Purpose:** make failures introduced by the SoC work easy to identify.

- [x] Review and checkpoint the current uncommitted regression, ACT4 adapter,
  CSR, testbench, and test-image changes.
- [x] Run and archive the complete directed regression summary.
- [x] Run the ELF/importer unit tests and archive their summary.
- [x] Record the tool versions used: ModelSim/Questa, Python, WSL Ubuntu,
  RISC-V GNU toolchain, Spike, and Vivado.
- [x] Remove generated build/log files from source control while retaining
  reproducible scripts and manifests.

Baseline evidence is archived in
[`doc/PHASE0_BASELINE_2026-07-24.md`](doc/PHASE0_BASELINE_2026-07-24.md).

Baseline commands on Windows:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Tag smoke
python -m unittest test_elf_to_mem.py test_import_act4.py
```

**Exit gate:** all checked-in directed tests and Python tests pass from a clean
build directory.

---

## Continuous Track A — Finish official ACT4 RV32IM coverage

**Purpose:** prove instruction semantics independently of FreeRTOS behavior.

- [x] Provide an address-aware ELF converter for separate instruction/data RAM.
- [x] Provide an ACT4 ELF importer and generated JSON manifest.
- [x] Provide a PowerShell wrapper that imports and runs ACT4 ELFs.
- [ ] Build or obtain the official ACT4 RV32I machine-mode ELFs in WSL.
- [ ] Import and run the official RV32I tests through ModelSim.
- [ ] Extend the ACT configuration/import tags for applicable RV32M tests.
- [ ] Run the official RV32M tests.
- [ ] Classify every failure as RTL, harness, linker/signature, unsupported
  feature, or toolchain issue.
- [ ] Add a small permanent directed regression for every RTL bug found by
  ACT4 before fixing it.
- [ ] Re-run the full applicable ACT4 set after changes to decode, ALU, LSU,
  CSR, trap, or pipeline control.
- [ ] Add Spike comparison later for bugs that cannot be isolated from ACT4
  signatures and the commit trace.

Example Windows invocation after ACT4 ELFs exist:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
./run_act4.ps1 -ElfDir D:\Rsicv-soc\build\act4\work\rsicv-soc-rv32im\elfs
```

ACT4 remains active throughout all later phases; it is not a one-time task.

---

## Phase 1 — Define the minimal FreeRTOS SoC contract

**Purpose:** freeze the memory map and bus behavior before writing peripherals
or software.

Provisional memory map:

| Region | Address | Initial size / registers |
|---|---:|---|
| Instruction BRAM | `0x0000_0000` | 64 KiB |
| CLINT-compatible timer | `0x0200_0000` | `mtimecmp=+0x4000`, `mtime=+0xBFF8` |
| UART | `0x1000_0000` | 4 KiB decode window |
| GPIO | `0x1000_1000` | 4 KiB decode window |
| Data BRAM | `0x8000_0000` | 64 KiB |

The linker will place `.text` in instruction BRAM and `.rodata`, `.data`,
`.bss`, heap, and stacks in data BRAM. Memory sizes remain parameters and must
be adjusted using the final ELF size report rather than guesswork.

- [ ] Document byte addressing, little-endian lanes, alignment rules, response
  latency, unmapped access behavior, and reset behavior.
- [ ] Define a small single-outstanding-transaction core bus:
  `req_valid`, `req_ready`, `req_addr`, `req_write`, `req_wdata`, `req_wstrb`,
  `rsp_valid`, `rsp_rdata`, and `rsp_error`.
- [ ] Define how pipeline back-pressure uses `ex_stall` without duplicating or
  dropping a load/store.
- [ ] Decide and document access-fault causes for unmapped or failed accesses.
- [ ] Add the memory map and peripheral register definitions to both
  SystemVerilog and C-visible headers without duplicating unexplained constants.

**Knowledge checkpoint:** explain request/response handshaking, why synchronous
BRAM reads need a response phase, and why memory-mapped peripherals must be
outside the CPU core.

---

## Phase 2 — Externalize the data bus

**Purpose:** allow load/store instructions to reach RAM or peripherals.

- [ ] Correct the LSU interface direction: `ram_req_ready_i` must be supplied by
  the target rather than driven by the LSU.
- [ ] Replace RAM-specific LSU names with the Phase 1 bus contract.
- [ ] Move `data_ram` from `src/core/riscv.sv` into `src/riscv_soc.sv`.
- [ ] Add centralized address decode and return-path multiplexing.
- [ ] Preserve byte/halfword store strobes, load sign extension, and
  misalignment behavior.
- [ ] Connect `rsp_error` to load/store access-fault trap generation.
- [ ] Keep the commit interface accurate for stalled, completed, and faulting
  memory instructions.
- [ ] Add assertions for stable requests during stalls, one response per
  accepted request, and no memory operation after a pipeline kill.
- [ ] Add directed RAM, unmapped-address, wait-state, and back-to-back-access
  tests.

**Exit gate:** all old LSU tests pass through the new bus, plus the new bus
tests pass with zero-delay and inserted-wait-state targets.

---

## Phase 3 — Implement precise machine timer interrupts

**Purpose:** provide the periodic scheduler tick required by preemptive
FreeRTOS.

### CPU interrupt work

- [ ] Add a machine-timer interrupt input to the CPU.
- [ ] Drive `mip.MTIP` from hardware and prevent ordinary CSR writes from
  falsely creating or clearing the hardware-pending state.
- [ ] Gate timer interrupts with `mie.MTIE` and `mstatus.MIE`.
- [ ] Give synchronous exceptions priority over an interrupt at the same
  retirement boundary.
- [ ] On interrupt entry, write `mcause = 0x8000_0007`, save the correct resume
  PC in `mepc`, update `MIE/MPIE`, flush younger instructions, and suppress
  younger stores/register writes.
- [ ] Verify `mret` restores interrupt-enable state and resumes exactly once.
- [ ] Define useful `wfi` behavior; a simple wait-until-interrupt implementation
  is sufficient.

### Timer peripheral work

- [ ] Implement 64-bit `mtime`, incrementing from the SoC clock.
- [ ] Implement 64-bit memory-mapped `mtimecmp`.
- [ ] Assert MTIP while `mtime >= mtimecmp`.
- [ ] Support safe RV32 high/low-word accesses without a transient early tick.
- [ ] Make timer frequency and reset values explicit parameters.

### Required verification

- [ ] Timer increments and compare crossing test.
- [ ] Masked-pending interrupt test.
- [ ] Enabled interrupt entry test.
- [ ] `mcause`, `mepc`, `mtval`, and `mstatus` value tests.
- [ ] Interrupt taken around load, store, branch, CSR, and pipeline-stall tests.
- [ ] Repeated tick and `mret` loop test to detect skipped or duplicated work.
- [ ] Commit-interface assertions proving precise retirement around interrupts.

**Exit gate:** a bare-metal handler services at least 10,000 simulated timer
interrupts and returns correctly, with the complete smoke regression green.

---

## Phase 4 — Add minimal peripherals

**Purpose:** provide observable hardware behavior and a FreeRTOS console.

### UART

- [ ] Implement parameterized UART TX with data register, busy/ready status,
  baud divider, start/data/stop bits, and polling operation.
- [ ] Add a loopback or serial decoder testbench that checks the transmitted
  byte stream and baud timing.
- [ ] Add UART RX later; it is not required for the first FreeRTOS milestone.
- [ ] Defer UART interrupts and PLIC until polling TX is working on hardware.

### GPIO

- [ ] Implement a memory-mapped output register for LEDs.
- [ ] Parameterize output width and define reset value.
- [ ] Add byte-strobe and readback tests.

### Integration

- [ ] Add UART/GPIO address decode to the SoC bus.
- [ ] Verify RAM and peripheral accesses cannot both accept one request.
- [ ] Add a SoC-level test that writes a UART message and toggles GPIO.

**Exit gate:** ModelSim decodes the expected UART text and observes the expected
GPIO waveform from a bare-metal program.

---

## Phase 5 — Establish bare-metal firmware and FPGA sanity tests

**Purpose:** separate CPU/peripheral/board failures from FreeRTOS port failures.

- [ ] Add `sw/common/startup.S`: initialize `sp`/`gp`, set `mtvec`, initialize
  memory as required, and call `main`.
- [ ] Add `sw/common/linker.ld` matching the final BRAM memory map.
- [ ] Add minimal UART, GPIO, timer, and CSR headers/drivers.
- [ ] Add a reproducible WSL build script using
  `riscv64-unknown-elf-gcc -march=rv32im_zicsr -mabi=ilp32`.
- [ ] Produce ELF, disassembly, size report, instruction image, and data image.
- [ ] Run three separate programs in simulation:
  1. UART `hello`;
  2. timer-polled LED toggle;
  3. timer-interrupt counter with `mret`.
- [ ] Run the same three programs on the FPGA before attempting FreeRTOS.

**Exit gate:** the bare-metal timer-interrupt program works both in ModelSim and
on the physical board.

---

## Phase 6 — Integrate the official FreeRTOS RISC-V port

**Purpose:** run an existing, reviewed kernel rather than inventing a scheduler
or context-switch ABI.

- [ ] Vendor or submodule a pinned FreeRTOS Kernel release.
- [ ] Use the official `portable/GCC/RISC-V` port and document any platform
  adaptation rather than rewriting its context switch.
- [ ] Add `FreeRTOSConfig.h` with explicit CPU clock and a 1 kHz tick.
- [ ] Start with one hart, M-mode only, preemption enabled, and no atomic `A`
  extension requirement.
- [ ] Choose and document `heap_4.c` or static allocation; keep heap and task
  stacks in data BRAM.
- [ ] Enable `configASSERT`, stack-overflow checking, and malloc-failure hooks.
- [ ] Avoid full `printf`; use a small polling UART writer.
- [ ] Add build-time RAM/ROM overflow checks using the ELF size and linker map.
- [ ] Add three demonstration tasks:
  1. toggle an LED every 500 ms;
  2. print a UART heartbeat every second;
  3. send and receive values through a FreeRTOS queue.
- [ ] Verify register/context preservation using sentinel register values across
  forced context switches.
- [ ] Run long simulation with assertions for illegal traps, duplicate commits,
  stack corruption, and unexpected writes.

**Exit gate:** FreeRTOS starts in ModelSim, the tick count advances, at least two
tasks preempt each other, queue communication succeeds, and UART/GPIO output
matches the scoreboard.

---

## Phase 7 — Zynq XC7Z010 FPGA integration

**Purpose:** prove the custom RISC-V SoC in silicon.

This phase is blocked only on the exact board identity and schematic/XDC, not on
ACT4 completion.

- [ ] Record the exact board model and full XC7Z010 part/package/speed grade.
- [ ] Create `fpga/<board>/top.sv` with explicit clock, reset, UART, and LED
  ports.
- [ ] Create and review `fpga/<board>/constraints.xdc` from the board schematic
  or vendor reference file.
- [ ] Add synchronizers and reset deassertion logic for asynchronous board
  inputs.
- [ ] If necessary, instantiate the Zynq processing system only to generate PL
  FCLK/reset; keep FreeRTOS on the custom RISC-V core.
- [ ] Add a non-interactive Vivado Tcl flow for project creation, synthesis,
  implementation, reports, and bitstream generation.
- [ ] Initialize instruction/data BRAM images reproducibly in the bitstream.
- [ ] Run an early synthesis checkpoint and inspect the combinational RV32M
  divider critical path. Convert MULDIV to multi-cycle if timing requires it.
- [ ] Begin with a conservative 25 MHz core clock; attempt 50 MHz only after
  timing closes with margin.
- [ ] Capture utilization, WNS/TNS, clock, BRAM, LUT, FF, and power estimates.
- [ ] Program and verify bare-metal UART, LED, and timer interrupt tests.
- [ ] Program and verify the FreeRTOS demonstration.
- [ ] Add an ILA for bus requests, interrupt entry, `mepc`, and task heartbeat
  only if external UART/LED evidence is insufficient.

**Exit gate:** after programming or power-up, the custom RISC-V core boots the
BRAM firmware, prints the FreeRTOS banner and task heartbeats, switches tasks at
1 kHz, and controls the LED without ARM software executing the application.

---

## Phase 8 — Release verification and definition of done

- [ ] All applicable official RV32I and RV32M ACT4 tests pass.
- [ ] All directed, CSR/trap, LSU, bus, timer, UART, GPIO, and FreeRTOS tests
  pass from one documented regression command.
- [ ] ModelSim logs contain no fatal errors or unexpected assertions.
- [ ] Vivado synthesis and implementation complete with non-negative timing
  slack at the selected clock.
- [ ] BRAM, LUT, FF, clock, and estimated power usage fit the XC7Z010 target.
- [ ] FPGA UART output demonstrates task scheduling and queue communication.
- [ ] FPGA LED output demonstrates timed task execution.
- [ ] Stack-overflow, malloc-failure, and unexpected-trap indicators remain
  clear during an extended hardware run.
- [ ] A reproducible README documents Windows 11, ModelSim, Vivado, WSL Ubuntu,
  GNU RISC-V toolchain, firmware build, simulation, bitstream build, and board
  programming commands.

---

## Deferred work after the FreeRTOS milestone

These may improve performance or broaden the SoC, but they are not prerequisites
for the first FreeRTOS FPGA demonstration:

- [ ] EX/MEM/WB forwarding and reduced RAW stalls.
- [ ] Multi-cycle or pipelined RV32M implementation, unless required for FPGA
  timing closure.
- [ ] UART RX FIFO and external UART interrupt.
- [ ] Machine software interrupt (`msip`).
- [ ] PLIC or a small external interrupt controller.
- [ ] AXI bridge and access to Zynq PS DDR.
- [ ] JTAG RISC-V Debug Module and GDB integration.
- [ ] Random instruction generation and continuous Spike differential testing.
- [ ] Performance counters and profiling.
- [ ] Linux research: S/U modes, MMU, atomics, OpenSBI, DDR, and a larger ISA.

## Immediate next action

1. Checkpoint the current green baseline.
2. Start official ACT4 RV32I tests as continuous Track A.
3. In parallel, implement Phase 1 and Phase 2: freeze the bus/memory map, then
   move data RAM out of the CPU.
4. Make the first new functional milestone the CLINT-style timer and precise
   machine-timer-interrupt regression—not UART or FreeRTOS itself.
