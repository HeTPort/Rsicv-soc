# TODO.md — Roadmap to Linux on This RISC-V CPU

> **Reality check**: The current core is a simple **RV32IM** educational CPU with no privilege modes, no CSRs, no MMU, no bus, and no peripherals. Running Linux requires a **RV64GC** application-class processor with M/S/U privilege modes, SV39 MMU, interrupt controllers, timers, UART, and a DDR controller. This is a large, multi-phase project. The steps below break the gap into practical milestones.

## Learning Rule

**Before checking off any TODO item, you must be able to explain the underlying knowledge to me.** Each phase lists the concepts you need to understand. Use the notes, ask questions, or request drills. Only mark an item complete after you can teach it back.

---

## Phase 0 — Stabilize the Current Core

**Goal**: Make the existing RV32IM core correct, clean, and well-verified before adding major features.

**Current deficiencies**:
- `sim/filelist.f` references non-existent `register.sv` and is missing new `lsu.sv`/`core_ctrl.sv`.
- Testbench uses a hard-coded Windows hex path.
- No forwarding: RAW hazards always stall, even when the result is already computed.
- Hazard detection only covers ID-vs-EX, missing load-use and WB-stage dependencies.
- RV32M multiply/divide is combinational, creating a long critical path.
- Verification is one manual test; no regression or ISA reference.
- LSU is new and needs directed tests for byte/halfword aligned stores and loads, plus misaligned exceptions.

**What industry does**:
- Maintains clean, portable build scripts and filelists.
- Uses forwarding/bypass networks (EX→EX, MEM→EX, WB→EX) to minimize stalls.
- Uses multi-cycle or pipelined divider/multipliers.
- Runs nightly regression against architectural tests (riscv-tests) and a golden ISS (Spike, QEMU, Imperas).

**Knowledge you need before doing this phase**:
1. How packed SystemVerilog structs reduce wiring and improve bubble injection (`fetch_pkt_t`, `id_ex_pkt_t`, `ex_wb_pkt_t`).
2. How RAW hazards are detected and why forwarding eliminates most stalls.
3. Why combinational MULDIV is bad for timing/area and how multi-cycle state machines fix it.
4. How to run ModelSim/QuestaSim and read waveforms.
5. How the LSU isolates memory access: address generation, store strobe alignment, load alignment/sign-extension, and misalignment detection.

- [x] Fix `sim/filelist.f`: replace `register.sv` with `regfile.sv`, and add `./../src/core/core_ctrl.sv` and `./../src/core/lsu.sv`.
- [x] Fix `tb_riscv_core.sv` hex file path to be portable (relative path).
- [ ] Add directed LSU tests for byte/halfword stores/loads at all alignments and misaligned exception reporting.
- [ ] Add forwarding/bypass network to eliminate unnecessary RAW stalls.
- [ ] Extend hazard detection to cover load-use and multi-stage hazards.
- [ ] Convert combinational RV32M multiply/divide to multi-cycle unit and assert `ex_stall` correctly.
- [ ] Add a directed-test runner that automatically builds and runs all `testdata/*.S` files.
- [ ] Add basic formal checks or ISA co-simulation against Spike for RV32IM.
- [ ] Clean up empty placeholder files or fill them with stubs that compile.

---

## Phase 1 — Privileged Architecture (M-mode)

**Goal**: Implement the machine-mode privileged ISA so the core can take traps, handle interrupts, and expose CSRs.

**Current deficiencies**:
- No privilege modes: everything runs in a flat, single mode.
- No CSRs at all.
- `ecall`/`ebreak` simply halt the CPU instead of entering a trap handler.
- No timer, no software interrupt, no external interrupt controller connection.

**What industry does**:
- Even the smallest embedded RISC-V has M-mode with a full CSR set (`mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`, `mtval`, etc.).
- Real CPUs implement precise exception handling: save PC, set cause, jump to vector, allow `mret` to resume.
- CLINT provides `mtime`/`mtimecmp` for timer interrupts; PLIC handles external interrupts.

**Knowledge you need before doing this phase**:
1. RISC-V privilege architecture: what M-mode is and why U/S/M separation matters.
2. CSR instructions (`csrrw`, `csrrs`, `csrrc`) and the CSR address encoding.
3. Trap flow: what `mtvec`, `mepc`, `mcause`, `mtval` do on entry and how `mret` restores state.
4. Difference between exceptions (synchronous) and interrupts (asynchronous).
5. How `mtime`/`mtimecmp` work and why timer interrupts are essential for preemptive OS.

- [x] Add CSR register file (`mstatus`, `mie`, `mip`, `mtvec`, `mepc`, `mcause`, `mtval`, `mscratch`, `mideleg`, `medeleg`, etc.).
- [x] Implement `csr*`, `mret`, `wfi` instructions.
- [x] Replace the simple `halt_q` mechanism with proper trap entry/exit:
  - Save PC to `mepc`.
  - Write cause to `mcause`.
  - Write badaddr/inst to `mtval`.
  - Jump to `mtvec`.
- [ ] Implement M-mode timer interrupt (`mtime`/`mtimecmp` via CLINT).
- [ ] Implement M-mode software interrupt.
- [ ] Implement external interrupt path from PLIC (wire through SoC).
- [x] Update exception detection to set `mcause` correctly (illegal inst, ecall, ebreak, misaligned, etc.).

---

## Phase 2 — Supervisor Mode & MMU

**Goal**: Allow an OS to run in S-mode with virtual memory.

**Current deficiencies**:
- No S-mode, so no OS can run in a protected environment.
- No virtual memory; all addresses are physical.
- No page faults, no memory protection.

**What industry does**:
- Linux runs in S-mode and uses U-mode for user processes.
- SV39 MMU translates 39-bit virtual addresses to physical addresses via a three-level page table.
- TLBs cache translations; page faults trigger S-mode handlers.

**Knowledge you need before doing this phase**:
1. Purpose of S-mode vs M-mode vs U-mode.
2. SV39 page-table format: PTE layout, valid/dirty/accessed bits, RWX permissions, U/S bit.
3. Page-table walk algorithm: how the hardware traverses the three-level tree.
4. TLB purpose and basic direct-mapped vs set-associative trade-offs.
5. What `satp` controls and what `sfence.vma` does.
6. How page-fault exceptions (`scause`/`mcause`) are reported.

- [ ] Add S-mode CSRs (`sstatus`, `sie`, `sip`, `stvec`, `sepc`, `scause`, `stval`, `sscratch`, `satp`).
- [ ] Implement `sret`, `sfence.vma`.
- [ ] Implement SV39 page-table walker (or SV32 if staying RV32).
- [ ] Add TLB (even a direct-mapped one helps performance).
- [ ] Implement page-fault exceptions with correct `scause`/`mcause`.
- [ ] Add privilege checks for CSR access, memory access, and instruction execution.

---

## Phase 3 — Expand ISA to RV64GC

**Goal**: Meet the Linux user-space ABI requirements.

**Current deficiencies**:
- 32-bit datapath only; Linux typically targets RV64.
- No compressed instructions (`C`), so code size is larger.
- No atomic instructions (`A`), so multi-core synchronization impossible.
- No floating point (`F`/`D`), so many userspace programs fail.

**What industry does**:
- Application processors use RV64GC (IMAFDC) as the baseline Linux ABI.
- Atomics are required for SMP Linux, thread libraries, and kernel locking.
- Compressed instructions reduce static code size ~25–30%.
- Floating point can be hardware or emulated via kernel traps, but hardware is expected for performance.

**Knowledge you need before doing this phase**:
1. RV64I differences from RV32I: `lwu`, `ld`, `sd`, `addiw`, `addw/subw/sllw/srlw/sraw`.
2. RISC-V `C` extension: 16-bit instruction formats and how they map to 32-bit instructions.
3. RISC-V `A` extension: `lr`/`sc` semantics, AMO operations, memory ordering (`aq`/`rl`).
4. IEEE-754 basics for `F`/`D`: rounding modes, NaN boxing in RV64, exception flags in `fcsr`.
5. Why `XLEN=64` changes register file, ALU, memory, and immediate handling.

- [ ] Switch to 64-bit datapath (`+define+RISCV_XLEN_64`).
- [ ] Implement RV64I base integer instructions (`lwu`, `ld`, `sd`, `addiw`, `*w` ops).
- [ ] Implement compressed instruction extension (`C`) to reduce code size.
- [ ] Implement atomic extension (`A`): `lr.w/d`, `sc.w/d`, `amoswap`, `amoadd`, etc.
- [ ] Implement single/double-precision floating point (`F`, `D`) — can initially trap and emulate in M-mode if hardware is too complex.
- [ ] Update decode, execute, regfile width, memory interface to 64-bit.

---

## Phase 4 — SoC Interconnect & Peripherals

**Goal**: Build a minimal SoC around the CPU.

**Current deficiencies**:
- No system bus; CPU talks directly to a single data RAM.
- No memory map, no boot ROM.
- No CLINT, PLIC, UART, GPIO, timer, or DDR interface.

**What industry does**:
- CPUs connect via AXI4/AHB-lite to an interconnect that routes to memory and peripherals.
- Address decode is centralized; each peripheral has a base address and IRQ line.
- DRAM is managed by a DDR controller (e.g., Xilinx MIG for FPGA).

**Knowledge you need before doing this phase**:
1. AXI4 or AHB-lite protocol basics: address, data, response channels; valid/ready handshake.
2. Memory-mapped I/O: how writes to an address control a peripheral.
3. CLINT registers (`mtime`, `mtimecmp`, `msip`) and their addresses.
4. PLIC architecture: interrupt source → gateway → priority → claim/complete.
5. 16550 UART registers (THR/RBR, IER, IIR, LCR, LSR) and baud-rate generation.
6. DDR controller basics: row/column/bank addressing, refresh, calibration.

- [ ] Design/choose a system bus: AXI4, AHB-lite, or a simple internal crossbar.
- [ ] Implement address map: DRAM region, boot ROM, CLINT, PLIC, UART, GPIO, Timer.
- [ ] Implement CLINT (`mtime`, `mtimecmp`, MSIP).
- [ ] Implement PLIC with enough IRQ lines for UART and timers.
- [ ] Implement a 16550-compatible UART for console output.
- [ ] Implement basic GPIO and Timer peripherals.
- [ ] Add boot ROM that loads OpenSBI or jumps to DDR.
- [ ] Integrate a DDR controller (Xilinx MIG for FPGA, or simple SRAM for simulation).

---

## Phase 5 — Bootloader Stack

**Goal**: Boot a real operating system.

**Current deficiencies**:
- No firmware, no bootloader, no device tree.

**What industry does**:
- Typical RISC-V boot flow: Boot ROM → OpenSBI → U-Boot → Linux.
- OpenSBI provides the SBI interface that Linux calls for M-mode services.
- Device tree describes hardware to the OS.

**Knowledge you need before doing this phase**:
1. What OpenSBI is and what SBI calls it provides (console, timer, IPI, reset).
2. Boot flow from reset vector to Linux `start_kernel`.
3. Device tree syntax and how Linux parses it.
4. How to cross-compile OpenSBI and U-Boot for a custom platform.
5. Linux kernel `defconfig` and command-line options for embedded RISC-V.

- [ ] Port or build **OpenSBI** (RISC-V SBI firmware) for the platform.
- [ ] Add device-tree source (DTS) describing the SoC.
- [ ] Port **U-Boot** as second-stage bootloader (optional but useful).
- [ ] Build a Linux kernel with the correct `defconfig` for the platform.
- [ ] Create a root filesystem (initramfs or external storage).

---

## Phase 6 — Linux Bring-Up

**Goal**: Get Linux actually running.

**Current deficiencies**:
- Linux has never booted; many integration bugs are guaranteed.

**What industry does**:
- Bring-up teams use JTAG, logic analyzers, and ISS co-simulation to debug early boot.
- They run Linux `kselftest`, LTP, and application workloads to stabilize.

**Knowledge you need before doing this phase**:
1. Early RISC-V Linux boot assembly (`head.S`, page tables, trap vector).
2. How to interpret OpenSBI and kernel console output.
3. Common bring-up bugs: wrong `satp`, missing timer interrupt, incorrect `mcause`, stale TLB entries.
4. How to use QEMU/Spike to compare behavior against hardware.

- [ ] Boot OpenSBI and verify SBI calls work.
- [ ] Boot Linux kernel and capture first console output.
- [ ] Debug early boot hangs using a JTAG/debug module or simulation traces.
- [ ] Resolve MMU and trap-handling bugs exposed by Linux.
- [ ] Stabilize until shell prompt appears.

---

## Phase 7 — Verification & Debug Infrastructure

**Goal**: Make the platform robust enough for real use.

**Current deficiencies**:
- Verification is one directed test with waveform dumps.
- No reference model, no architectural tests, no coverage.
- No debug module for hardware bring-up.

**What industry does**:
- Continuous integration runs riscv-tests, random instruction streams, and OS boot tests.
- Differential testing against Spike/QEMU catches ISA bugs.
- RISC-V Debug Module (JTAG) allows GDB connection to hardware.

**Knowledge you need before doing this phase**:
1. RISC-V Architectural Tests (`riscv-tests`) structure and how to run them.
2. Differential testing: comparing CPU trace against golden ISS.
3. RISC-V Debug Module spec: abstract commands, program buffer, halt/resume.
4. Coverage metrics: instruction coverage, privilege-mode coverage, exception coverage.

- [ ] Integrate a reference ISS (Spike, QEMU, or Imperas) and run differential testing.
- [ ] Add RISC-V Architectural Tests (`riscv-tests`) for each extension.
- [ ] Add Linux `kselftest` or LTP runs.
- [ ] Implement a RISC-V debug module (JTAG DM) for hardware debugging.
- [ ] Add performance counters and basic profiling support.

---

## Summary of Gaps vs. Linux Requirements

| Requirement | Current State | What Linux Needs | Industry Typical |
|---|---|---|---|
| ISA | RV32IM | RV64GC (IMAFDC) | RV64GC in application cores; RV32IM only for tiny MCUs |
| Privilege modes | None (flat) | M-mode + S-mode + U-mode | All Linux-capable cores have M+S+U |
| CSRs | None | Full M-mode and S-mode CSR set | Hundreds of CSRs including performance counters |
| MMU | None | SV39 (or SV32) with TLB | Multi-level TLBs, hardware page-table walkers |
| Interrupts | Halt on ecall/ebreak | CLINT + PLIC + precise trap flow | CLINT + PLIC or AIA (Advanced Interrupt Architecture) |
| Timer | None | `mtime`/`mtimecmp` | CLINT timer |
| Console | None | 16550 UART | 16550 or custom UART |
| Memory | Single data RAM | DDR controller + address map | DDR4/LPDDR controller, cache hierarchy |
| Bus | None | AXI/AHB crossbar | AXI4 interconnect with QoS |
| Bootloader | None | OpenSBI + U-Boot | OpenSBI → U-Boot → Linux |
| Verification | Single directed test | ISS co-sim, riscv-tests, Linux boot | Nightly CI, random tests, formal verification |

---

## Suggested First Step

Start with **Phase 0** and **Phase 1**. Do not attempt MMU or Linux until the core can:
1. Run all RV32IM tests correctly.
2. Take and return from M-mode traps.
3. Handle timer interrupts.

Then move to RV64 + S-mode + MMU.

---

## Notes for Future Claude Code Instances

When the user wants to work on a TODO item, first ask them to explain the prerequisite knowledge listed above. Only proceed with implementation after they demonstrate understanding. Prefer teaching first, coding second.
