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
- [x] Explicit M-mode CSR legality, no-write rules, WARL filtering, and
      same-address dependency bypass.
- [x] Lightweight JSON/PowerShell ModelSim regression runner with native
  simulator-exit and transcript result gates; UVM is not required for this
  target.
- [x] Separate instruction/data image support and commit-based `tohost`
  completion checking.
- [x] ELF-to-memory converter and ACT4 import/runner adapters.
- [x] Synthetic ACT4 harness smoke test.
- [x] Official ACT4 RV32IM baseline: 39/39 RV32I and 8/8 RV32M tests passed
  on unchanged RTL on 2026-08-03, with no failures or DUT candidates.
- [x] Synchronous instruction BRAM with PC/response alignment across stalls and
      redirects, verified as four `RAMB36E1` primitives in Vivado 2019.2.
- [x] Single-outstanding wait-state-capable CPU data bus and LSU transaction
      state machine, with data RAM outside the CPU.
- [x] Registered EX/WB memory results with precise load/store access-fault
      completion and packet-owned WB/commit data.
- [x] Centralized full-address SoC data decoder and one-cycle registered default
  error target, plus registered instruction-access-fault reporting.
- [x] Existing directed regression last verified at 22/22 passing, with
  converter tests at 4/4 and the regression-result negative test passing.

Still missing:

- [ ] Hardware interrupt input and precise interrupt entry.
- [ ] `mtime`/`mtimecmp` machine timer.
- [ ] Implemented UART and GPIO peripherals; empty placeholder RTL was removed
  and real modules will be added in Phase 4.
- [ ] Firmware startup code, linker script, drivers, and FreeRTOS application.
- [ ] FPGA top, XDC constraints, Vivado build script, and physical-board result.

Current planning position:

- Phase 0A is complete; this closes its correctness gate, not the whole
  architecture review or FreeRTOS roadmap.
- Phase 1 is complete: AR-009 and the generated
  `freertos_split_64k_v1` hardware/software ABI are accepted.
- Phase 2 is complete: AR-003/AR-004 close transaction/result ownership,
  AR-019 supplies centralized data decode and the registered default target,
  and AR-018 verifies precise data and instruction access faults.
- AR-008 belongs to Phase 3; AR-010 is continuous verification; AR-011 is an
  early FPGA feasibility gate; and AR-012 is cross-stage cleanup.
- AR-014 accepted-map generation infrastructure is complete. AR-019 uses its
  SystemVerilog constants in the implemented data decoder/default target;
  remaining software/tool consumers continue in their owning later phases.
- AR-015 records the paired 16 KiB/64 KiB baseline and its failing
  combinational MULDIV path. AR-017 replaces that divider with a verified
  Radix-2 iterative implementation; both profiles now pass the 25/50 MHz OOC
  post-synthesis checks. Exact-board timing closure remains open.
- AR identifiers are stable finding numbers, not phase numbers. Detailed
  ownership and status are maintained in
  [`doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md`](doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md).

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
- [x] Require a zero native simulator exit in addition to the PASS/fatal/error
  transcript gates, with RED/GREEN evidence in
  [`doc/AR013_REGRESSION_EXIT_STATUS_GATE.md`](doc/AR013_REGRESSION_EXIT_STATUS_GATE.md).

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

## Phase 0A — Make retirement and pipeline side effects precise

**Status:** complete. This does not close the overall architecture review or any
later phase.

**Purpose:** close the correctness gap identified by the architecture review
before a wait-state bus or asynchronous interrupts make the same failures more
difficult to isolate.

- [x] Reproduce AR-001 with a trap immediately followed by a younger CSR write.
- [x] Require packet validity for CSR writes and clear the complete younger
  EX/WB packet on `pipe_kill`.
- [x] Promote the precise CSR squash regression into the smoke suite.
- [x] Record the RED/GREEN evidence in
  [`doc/AR001_PRECISE_CSR_SQUASH_FIX.md`](doc/AR001_PRECISE_CSR_SQUASH_FIX.md).
- [x] Test a trap followed by a younger GPR write and a younger store.
- [x] Make every reset and flush produce a completely initialized packet bubble.
- [x] Record the AR-002 implementation problems, handling decisions, and
  reusable principles in
  [`doc/AR002_CANONICAL_PIPELINE_BUBBLES.md`](doc/AR002_CANONICAL_PIPELINE_BUBBLES.md).
- [x] Implement precise IALIGN=32 traps for taken branch, JAL, and JALR targets.
- [x] Record AR-006 implementation and verification evidence in
  [`doc/AR006_CONTROL_FLOW_MISALIGNMENT.md`](doc/AR006_CONTROL_FLOW_MISALIGNMENT.md).
- [x] Implement AR-007 CSR legality, no-write semantics, WARL behavior, and
      back-to-back dependency handling.
- [x] Record the AR-007 contract, RED/GREEN evidence, implementation decisions,
      and learning notes in
  [`doc/AR007_CSR_LEGALITY_WARL_AND_HAZARDS.md`](doc/AR007_CSR_LEGALITY_WARL_AND_HAZARDS.md).
- [x] Implement and verify AR-005 synchronous instruction BRAM timing across
      sequential fetch, RAW stalls, and redirects.
- [x] Record the AR-005 timing contract, Vivado inference evidence, problems,
      handling decisions, and reusable principles in
  [`doc/AR005_SYNCHRONOUS_INSTRUCTION_BRAM.md`](doc/AR005_SYNCHRONOUS_INSTRUCTION_BRAM.md).
- [x] Complete the remaining Phase 0A exit criteria in
  [`doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md`](doc/ARCHITECTURE_REVIEW_AND_ACTION_PLAN.md).

AR-003 and AR-004 are Phase 2 sub-gates completed early to satisfy the
cross-cutting wait-state and registered-result criteria. AR-019 now implements
the centralized data decoder and default error target. AR-018's cause-1 path
and SoC regression complete the Phase 2 exit gate; real peripherals belong to
Phases 3 and 4.

Current verification after the AR-013 regression-gate fix:
directed smoke **22/22 passed**
and regression utility tests **4/4 passed**. The AR-013 negative result
classifier test also passes.

---

## Continuous Track A — Maintain official ACT4 RV32IM coverage

**Status:** baseline complete. On 2026-08-03, all 39 applicable RV32I tests and
all 8 applicable RV32M tests passed on unchanged RTL. This is a verified
project baseline, not a formal RISC-V compliance certification.

**Purpose:** prove instruction semantics independently of FreeRTOS behavior.

- [x] Provide an address-aware ELF converter for separate instruction/data RAM.
- [x] Provide an ACT4 ELF importer and generated JSON manifest.
- [x] Provide a PowerShell wrapper that imports and runs ACT4 ELFs.
- [x] Build and import 39 official RV32I machine-mode self-checking ELFs.
- [x] Run all 39 RV32I tests through ModelSim: 39 PASS, 0 FAIL/TIMEOUT.
- [x] Extend the ACT4 configuration and import flow for the applicable RV32M
  corpus.
- [x] Build, import, and run all 8 RV32M tests: combined manifest 47/47 PASS.
- [x] Classify the complete baseline: no environment, adapter, harness,
  unsupported, or DUT/RTL failures remained.
- [x] Re-run the directed smoke regression and importer/converter unit tests.
- [x] Record counts, commands, scope, and classification evidence in
  `doc/ACT4_RV32I_INTEGRATION_HANDOFF_2026-07-27.md`.

Rebuild either extension with the consolidated Windows launcher:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
.\run_act4_build.ps1 -Extension I
.\run_act4_build.ps1 -Extension M
```

Maintenance policy: keep the 47/47 baseline green after changes to decode,
ALU, LSU, CSR, trap, or pipeline control. If a future ACT4 test exposes an RTL
bug, first add a small directed regression that reproduces it. Use Spike only
when the ACT4 signature and commit trace cannot isolate the mismatch. These are
ongoing regression rules, not open Track A completion items.

---

## Phase 1 — Define the minimal FreeRTOS SoC contract

**Status:** complete. AR-009 and the 64 KiB split-memory ABI were accepted on
2026-08-01. Behavioral RTL adoption remains Phase 2 work.

**Purpose:** freeze the memory map and bus behavior before writing peripherals
or software.

The accepted design rules, transaction invariants, topology decision, and
freeze evidence are recorded in
[`doc/MEMORY_MAP_CONTRACT_DESIGN_GUIDE.md`](doc/MEMORY_MAP_CONTRACT_DESIGN_GUIDE.md).
The detailed accepted split-memory decision, consequences, verification plan,
and review answers are recorded in
[`doc/AR009_ARCHITECTURAL_MEMORY_MAP.md`](doc/AR009_ARCHITECTURAL_MEMORY_MAP.md).
It is accepted but must not be treated as implemented until Phase 2 is
verified. The accepted constants have one validated machine-readable source and
generated consumers, as recorded in
[`doc/AR014_MACHINE_READABLE_SOC_MAP.md`](doc/AR014_MACHINE_READABLE_SOC_MAP.md).
The complete core-to-SoC ownership and integration boundary is recorded in
[`doc/AR016_CORE_TO_SOC_ENVIRONMENT_CONTRACT.md`](doc/AR016_CORE_TO_SOC_ENVIRONMENT_CONTRACT.md).
The paired resource measurement is recorded in
[`doc/AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md`](doc/AR015_RAM_CAPACITY_UTILIZATION_COMPARISON.md):
the 16 KiB pair uses 8/60 RAMB36 tiles and the selected 64 KiB pair uses 32/60
on the provisional `xc7z010clg400-1`. Exact-board resource and timing closure
remain mandatory implementation gates.

Accepted first-milestone memory map:

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

- [x] Document byte addressing, little-endian lanes, alignment rules, response
  latency, unmapped access behavior, and reset behavior.
- [x] Review and accept the AR-009 split-memory contract,
      including topology, `tohost`, instruction access faults, and default
      target behavior.
- [x] Select 64 KiB for each instruction/data RAM bank, informed by the AR-015
      provisional utilization and timing comparison.
- [x] Define a small single-outstanding-transaction core bus:
  `req_valid`, `req_ready`, `req_addr`, `req_write`, `req_wdata`, `req_wstrb`,
  `req_size`, `rsp_valid`, `rsp_rdata`, and `rsp_error`.
- [x] Define how pipeline back-pressure uses `ex_stall` without duplicating or
  dropping a load/store.
- [x] Decide and document access-fault causes for unmapped or failed accesses.
- [x] Add a dependency-free generator and stale-file check for accepted
      SystemVerilog, C, linker, simulation, Vivado Tcl, and ACT4-facing map
      artifacts without changing current implemented addresses.
- [x] Generate named 16 KiB/64 KiB RAM profiles and preserve paired Vivado
      LUT/FF/BRAM/DSP utilization reports for the provisional XC7Z010 part.
- [x] Apply identical 25/50 MHz post-synthesis clock constraints to both RAM
      profiles and preserve WNS/TNS and critical-path reports; both identify
      the same failing 87.102 ns combinational MULDIV baseline. AR-017 records
      the later iterative-divider GREEN comparison.
- [x] Generate accepted memory-map and peripheral-register definitions for
      SystemVerilog, C, GNU linker, simulation, Vivado Tcl, and ACT4-facing
      consumers. Behavioral RTL/test adoption remains a Phase 2 gate.

**Exit gate:** satisfied. A review can answer the owner, address, access width,
latency, response, and fault behavior for every first-milestone region without
claiming that Phase 2 RTL has implemented it.

**Knowledge checkpoint:** explain request/response handshaking, why synchronous
BRAM reads need a response phase, and why memory-mapped peripherals must be
outside the CPU core.

---

## Phase 2 — Externalize the data bus

**Status:** complete (2026-08-03).

**Purpose:** allow load/store instructions to reach RAM or peripherals.

- [x] Correct the LSU interface direction: `ram_req_ready_i` must be supplied by
  the target rather than driven by the LSU.
- [x] Replace RAM-specific LSU names with the Phase 1 bus contract.
- [x] Move `data_ram` from `src/core/riscv.sv` into `src/riscv_soc.sv`.
- [x] Add centralized full-address decode, local RAM address subtraction, and
  registered return-path ownership. See
  [`doc/AR019_CENTRALIZED_DATA_FABRIC.md`](doc/AR019_CENTRALIZED_DATA_FABRIC.md).
- [x] Add a one-cycle registered, zero-data, side-effect-free default error
  target for every non-RAM data address.
- [x] Preserve byte/halfword store strobes, load sign extension, and
  misalignment behavior.
- [x] Connect `rsp_error` to load/store access-fault trap generation.
- [x] Keep the commit interface accurate for stalled, completed, and faulting
  memory instructions.
- [x] Add assertions for stable requests during stalls, one response per
  accepted request, and no memory operation after a pipeline kill.
- [x] Add isolated SoC-level RED tests for unmapped load/store access faults,
  side-effect-free invalid stores, and instruction access fault cause 1. See
  [`doc/AR018_SOC_FABRIC_RED_TESTS.md`](doc/AR018_SOC_FABRIC_RED_TESTS.md).
- [x] Add initial RAM-boundary, unmapped-address, request-wait, owner-stability,
  and back-to-back cross-target GREEN tests through the implemented decoder.
- [x] Add explicit instruction-fetch error signaling and turn the AR-018
  cause-1 case GREEN.

SoC-level target coverage expands in Phases 3 and 4 as timer/UART/GPIO targets
are implemented; that future expansion is not part of the Phase 2 exit gate.

**Exit gate:** all old LSU tests pass through the new bus, plus the new bus
tests pass with zero-delay and inserted-wait-state targets.

AR-003 transaction-control details and RED/GREEN evidence are recorded in
[`doc/AR003_WAIT_STATE_SAFE_LSU.md`](doc/AR003_WAIT_STATE_SAFE_LSU.md).
AR-004 registered-result ownership and access-fault evidence are recorded in
[`doc/AR004_REGISTERED_MEMORY_RESULT.md`](doc/AR004_REGISTERED_MEMORY_RESULT.md).
The AR-003/AR-004 sub-gates are satisfied. AR-019 closes centralized data
decode/default-target ownership with focused protocol coverage, 3/3 SoC data
fault runs (including inserted RAM waits), 22/22 smoke, and accepted-map OOC
synthesis. AR-018 is GREEN for all four selected SoC runs: three data cases
and one instruction-access-fault case.

### Non-blocking Phase 2 / ACT4 hardening

These maintenance items do not reopen Phase 2 and are not prerequisites for
Phase 3. Schedule them when the related fetch or verification interface is
next changed, or earlier only if a regression exposes a real failure.

- [ ] Make a fetch-error decode packet canonical by clearing normal RF, CSR,
  memory, redirect, operand-use, and mul/div controls; verify with deliberately
  side-effectful replacement instruction data.
- [ ] Turn the AR-018 consecutive-invalid, redirect/stale-response, and
  fault-during-stall scenarios into executable directed tests.
- [ ] If instruction wait states or multiple fetch targets are introduced,
  separate response-valid from response-error and move range ownership into a
  SoC-level instruction decoder.
- [ ] Before extension-specific ACT4 automation is needed, tag RV32I and RV32M
  entries distinctly and preserve a compact baseline report under
  `doc/evidence/act4/`.

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
- [x] Run the early post-synthesis timing checkpoint and inspect the
      combinational RV32M divider critical path; AR-015 confirms it fails both
      25 MHz and 50 MHz for both RAM capacities.
- [x] Replace DIV/DIVU/REM/REMU with the AR-017 Radix-2 iterative divider and
      rerun the paired internal timing comparison. Both profiles pass 50 MHz
      with WNS +7.373 ns; the worst path is now multiply-high.
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
- [ ] Further RV32M throughput optimization only if measured software workload
  or routed timing justifies it; AR-017's required divider fix is verified.
- [ ] UART RX FIFO and external UART interrupt.
- [ ] Machine software interrupt (`msip`).
- [ ] PLIC or a small external interrupt controller.
- [ ] AXI bridge and access to Zynq PS DDR.
- [ ] JTAG RISC-V Debug Module and GDB integration.
- [ ] Random instruction generation and continuous Spike differential testing.
- [ ] Performance counters and profiling.
- [ ] Linux research: S/U modes, MMU, atomics, OpenSBI, DDR, and a larger ISA.

## Immediate next action

1. Keep all 47 official ACT4 RV32I/RV32M baseline tests active as continuous
   Track A.
2. Begin Phase 3 with the CLINT-style timer and precise machine-timer-interrupt
   regression.
3. Complete the accepted-map migration for linker, images, regression/ACT4
   consumers, and peripheral target integration; the SoC RTL defaults and data
   decoder already consume the accepted 64 KiB map.
4. Keep the verified AR-017 iterative-divider regression and timing checkpoint
   active while exact-board closure remains pending.
