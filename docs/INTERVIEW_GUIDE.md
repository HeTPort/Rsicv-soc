# RV32IM SoC interview guide

This guide is a speaking aid for explaining the project from requirements to
RTL, firmware, verification, synthesis, and FPGA bring-up. Use it to tell a
coherent engineering story; do not try to recite every signal name.

## 1. Thirty-second project summary

> I designed and verified a small in-order RV32IM SoC in SystemVerilog. It has
> synchronous instruction and data BRAM, a wait-state-safe one-outstanding LSU,
> precise machine-mode traps and timer interrupts, polling UART TX/RX, GPIO,
> a split-image C runtime, and the official FreeRTOS RISC-V port. I used packed
> pipeline packets and a central retirement stage to make side effects precise.
> Verification combines focused protocol testbenches, directed assembly and C
> firmware, assertions, 47 applicable ACT4 cases, Vivado timing/DRC checks, and
> physical LED/JTAG tests on a Zynq-7010 board.

## 2. Requirement-to-evidence workflow

For any feature, explain the same loop:

1. State the externally visible requirement.
2. Define the owner and interface before writing behavior.
3. Identify timing, back-pressure, reset, error, and cancellation cases.
4. Write a focused test that can fail for the intended reason.
5. Implement the smallest design that satisfies the contract.
6. Run the focused test, then cross-module and full regressions.
7. Check synthesis or board behavior when simulation cannot prove the claim.
8. Record the decision, rejected alternatives, consequences, and evidence.

Example: “A peripheral response may arrive after the CPU address changes.” The
fabric therefore registers the target that accepted the request. The focused
test changes the live address while GPIO is outstanding, proves UART is held
under back-pressure, then proves UART becomes eligible and is accepted exactly
once after the GPIO response.

## 3. System architecture

```text
program BRAM -> IF -> IF/ID -> decode -> ID/EX -> execute
                                                    |
                         +--------------------------+
                         |
                         +-> iterative divider
                         +-> LSU -> data fabric -> timer/UART/GPIO/data BRAM/error
                         |
                         +-> EX/WB -> retire_stage -> RF/CSR/redirect/commit
```

Key architectural choices:

- RV32IM, one hart, machine mode, no MMU/cache/PLIC/AXI.
- In-order issue and retirement.
- Packed `fetch_pkt_t`, `id_ex_pkt_t`, and `ex_wb_pkt_t` payloads.
- Synchronous program RAM with a one-cycle response.
- One outstanding data transaction and no cache.
- RAW stalls rather than a full forwarding network.
- A single retirement owner for final architectural effects.
- Split 64 KiB instruction and data address regions.
- Native request/response MMIO rather than APB or AXI.

## 4. Core-module concepts

### Fetch and synchronous program memory

Program BRAM returns data one cycle after a read request. The core carries a
delayed PC and valid bit beside that response. A taken branch or trap can leave
one stale request in flight, so `fetch_kill_q` discards the delayed wrong-path
response.

Interview points:

- A synchronous memory changes pipeline timing even if the ISA does not change.
- The response must stay associated with the request PC.
- A same-cycle flush is insufficient when an older request returns later.

### Decode and packed packets

Decode produces operands, destination metadata, ALU/branch/memory/mul-div
controls, CSR commands, exception flags, and operand-use bits in one packet.
Flush/reset assigns the canonical all-zero bubble rather than clearing only
`valid` and leaving stale controls visible.

Benefits:

- Fewer top-level wires and fewer connection mistakes.
- Easier module-boundary evolution.
- Whole-packet bubble injection.
- Clear ownership of instruction metadata as it moves through the pipeline.

### Hazard and pipeline control

`core_ctrl` detects a RAW dependency between decode and execute. It holds the
PC and IF/ID register and injects an ID/EX bubble. There is no full bypass
network; register-file write-first behavior handles the same-cycle read/write
case.

For LSU or divider work, ID/EX must remain stable until completion. EX/WB sees
bubbles during the wait. Redirect, WFI, and trap controls have explicit flush,
kill, and delayed-fetch-kill behavior.

Tradeoff: the implementation is easy to reason about but has a higher CPI than
a forwarding pipeline.

### Execute stage

Execute owns:

- ALU operations and signed/unsigned comparisons;
- branch/JAL/JALR targets and IALIGN=32 checks;
- combinational multiply and high-half variants;
- CSR read-modify-write data formation and legality checks;
- synchronous exception metadata;
- completed divider result selection.

It does not own the memory transaction or final architectural writeback. Those
responsibilities belong to the LSU and retirement stage.

### Iterative divider

The first combinational divider failed timing badly. It was replaced with a
kill-safe restoring Radix-2 divider that emits one quotient bit per cycle.

Important details:

- `IDLE -> RUN -> COMPLETE` protocol;
- signed operations use magnitude conversion and result-sign correction;
- divide-by-zero returns an all-ones quotient and the dividend as remainder;
- redirects/traps can cancel work safely;
- the pipeline reuses the existing multi-cycle wait path.

This is a good area-versus-latency story: about 32 run cycles were accepted to
remove a critical combinational path and close timing.

### LSU and ready/valid correctness

The LSU follows `IDLE -> REQUEST -> RESPONSE -> COMPLETE`.

- In `IDLE`, it computes effective address, alignment, byte lanes, and payload.
- In `REQUEST`, it holds valid and the registered payload until ready.
- In `RESPONSE`, it waits for exactly one response.
- In `COMPLETE`, it presents one packet-owned result and releases ID/EX.

Loads perform byte/halfword extraction and sign or zero extension. Stores
generate little-endian strobes and shifted data. Misaligned accesses trap
without issuing a bus request. Response errors become precise load/store access
faults.

Ready/valid rule to say clearly: once valid is asserted under back-pressure,
the producer must keep valid and payload stable until the accepting edge.

### Retirement and precise effects

`retire_stage` is the sole final decision point for:

- GPR writes;
- CSR writes and `minstret`;
- synchronous trap entry;
- post-retirement timer interrupts;
- MRET and WFI;
- redirects;
- the ordered `commit_pkt_t` observation.

A synchronous trap suppresses normal effects. An interrupt is taken between
instructions after the current instruction’s normal effects are selected. MRET
cannot share a boundary with an interrupt. Incomplete LSU/divider ownership
defers the interrupt.

WFI retires once, saves `next_pc`, and enters logical wait. An eligible timer
interrupt later wakes directly into trap entry without committing WFI twice.

### CSR file

The CSR file implements machine-mode state, legality, read-only behavior, and
WARL filtering. It owns `mstatus`, `mie`, composed `mip.MTIP`, `mtvec`, `mepc`,
`mcause`, `mtval`, `mcycle`, and `minstret`.

An effective CSR-write preview feeds interrupt selection so a retiring write to
interrupt control or `mtvec` is observed consistently at that same boundary.
Storage and WARL policy remain centralized in the CSR module.

## 5. SoC bus and peripheral integration

### Data-fabric contract

The CPU presents a full architectural address. The fabric:

1. decodes timer, UART, GPIO, data RAM, or default target;
2. subtracts the selected base address;
3. forwards valid only to one target;
4. registers which target accepted the request;
5. routes the later response from that registered owner.

The live CPU address must never select a response. Unmapped accesses go to a
registered, side-effect-free error target so the core cannot deadlock.

### Machine timer

The timer provides 64-bit `mtime` and `mtimecmp` through aligned 32-bit words.
`irq_mti` is a level: `mtime >= mtimecmp`. On RV32, software updates the compare
safely by writing low all-ones, then high, then the final low word to avoid a
transient early interrupt.

### UART

The UART is deliberately layered:

- `uart_tx` and `uart_rx`: serial timing and 8N1 framing;
- `core_bus_uart`: MMIO, one-byte TX holding stage, 16-byte RX FIFO, sticky
  overrun/framing errors, and exactly-once side effects;
- data fabric: address translation and response ownership;
- board top/XDC: physical pins and clock configuration.

The empty RXDATA read returns zero instead of stalling the only data transaction
forever. Correct software still checks RX-valid because zero is also legal data.

### GPIO

GPIO is a persistent output register with readback. Byte, halfword, and word
writes must have matching alignment and strobes. Legal writes merge selected
lanes; malformed writes return an error and cannot change the pins.

The SoC-level test observes both firmware readback and `gpio_out_o`, preventing
a disconnected pin path from falsely passing.

## 6. Hardware/software contract

### Generated memory map

`config/soc_map.json` is the editable source for RTL, C headers, linker
fragments, simulation, Vivado Tcl, and ACT4-facing data. Generation plus a
`--check` mode prevents address drift across layers.

### Reset-to-C startup

Hardware resets the PC to `0x0000_0000`; the ELF entry alone does not control
that. Startup therefore ensures `_start` is the first loaded instruction, masks
interrupts, creates an aligned stack, initializes `gp` with relaxation disabled,
installs direct `mtvec`, clears `.bss`, and calls `main`.

If `main` returns or an unexpected trap occurs, firmware reports a failure and
loops instead of executing adjacent memory.

### Why split images matter

The Harvard data path cannot load constants from program BRAM. Therefore:

- `.text` goes to instruction BRAM;
- `.rodata`, `.data`, `.bss`, heap, and stacks go to data BRAM;
- initialized `.data` is preloaded directly into a separate data image;
- startup clears `.bss`, including a test where RAM is deliberately poisoned.

The converter validates ELF regions, entry address, overlaps, boundaries, and
little-endian word output. Linker assertions catch RAM, heap, stack, and
`tohost` overlap.

### FreeRTOS integration

The project vendors a pinned, byte-identical subset of FreeRTOS Kernel V11.3.0
and uses the official GCC RISC-V machine-mode port. Platform adaptation stays
outside the upstream directory.

Configuration: one hart, RV32IM/Zicsr, ILP32, 1 kHz tick, preemption, four
priorities, `heap_4`, a 24 KiB heap, stack-overflow checking, malloc/assert/trap
failure hooks, and polling UART.

The demo has LED, heartbeat, queue producer, and higher-priority receiver tasks.
A wrapper loads sentinels into `s2` through `s11`, forces an ECALL/context
switch through the queue, and verifies the official port restores them.

The production image uses a 25 MHz clock. Simulation uses a distinct time-scaled
profile but keeps the kernel tick at 1 kHz. An earlier 500-cycle tick starved
lower priorities because interrupt catch-up exceeded the interval; measuring
live counters led to a 5,000-cycle simulation tick.

## 7. FPGA workflow

The board flow adds responsibilities simulation cannot prove:

- exact part/package and conservative speed grade;
- clock generation and reset synchronization;
- pin locations, I/O voltage, polarity, and UART crossover;
- synthesis, placement, routing, DRC, timing, utilization, power estimate;
- BRAM initialization in the actual bitstream;
- JTAG discovery and physical observation.

The ZYNQ MINI REVB uses a 50 MHz PL oscillator and an MMCM/BUFG to produce a
25 MHz core clock. A retained PS7 hard block satisfies Zynq configuration but
does not run the application.

A routed build exposed a combinational feedback loop between interrupt
selection, kill, and LSU/divider wait. The fix separated “operation is visibly
pending” from “new work may start when not killed.” Focused simulation stayed
green and route completed with zero blocking DRC errors and positive slack.

Physical evidence currently covers JTAG, GPIO/timer LEDs, and ten timer
interrupts. External UART, repeated reset, device speed grade, and FreeRTOS FPGA
execution remain open; say so plainly in an interview.

## 8. Verification strategy and test types

| Test type | Best use | Project examples |
|---|---|---|
| Compile/elaboration | Interface and parameter consistency | complete SoC file list |
| Focused module test | Pure local behavior and corner cases | divider, UART TX/RX, GPIO, timer |
| Protocol test | Cycle-level handshake and ownership | LSU and data fabric |
| Directed assembly | Precise architectural corner case | CSR legality, trap squash, misalignment |
| SoC firmware test | Hardware/software end-to-end behavior | UART text, GPIO, timer/WFI |
| Negative/RED test | Prove a missing feature or gate fails correctly | unmapped access/fetch fault cases |
| SystemVerilog assertion | Continuously enforce invariants | stable stalled request, no ghost side effect |
| ACT4 | Broad applicable ISA behavior | 39 RV32I + 8 RV32M |
| Python/PowerShell unit test | Tool and result-classifier correctness | ELF converter, importer, map generator |
| Synthesis/OOC check | Inference, hierarchy, capacity, timing estimate | BRAM and divider comparisons |
| Routed FPGA build | Real placement, DRC, timing, initialized bitstream | Zynq board profiles |
| Physical test | Clock/reset/pins/electrical reality | LEDs, JTAG, UART |

### How to write a focused RTL test

1. Reset to a known state.
2. Drive one legal transaction and check normal behavior.
3. Add back-pressure or delayed response.
4. Change unrelated live inputs to prove registered ownership.
5. Exercise invalid size/alignment/strobes and prove no side effect.
6. Count accepts/responses to prove exactly-once behavior.
7. End with an unambiguous PASS and zero simulator errors.

### How to write a directed CPU test

1. Use a short assembly sequence that isolates one architectural rule.
2. Seed observable registers or memory with sentinel values.
3. Trigger the instruction, hazard, fault, or redirect.
4. Check architectural results in software.
5. Write 1 or a distinct failure code to `tohost` through a committed store.
6. Use the disassembly and commit trace to map a failure PC back to source.

### Why ACT4 does not replace directed tests

ACT4 checks applicable ISA behavior across many encodings and operand cases. It
does not verify this project’s UART, GPIO, timer integration, wait-state
protocol, WFI timing policy, linker, FreeRTOS tasks, FPGA pins, or a specific
microarchitectural invariant. Both layers are required.

### Regression result integrity

A test is PASS only when the architectural PASS marker is present, the native
simulator exits zero, there is no fatal marker, and ModelSim reports zero
errors. The classifier itself has a negative test so a PASS-looking transcript
cannot hide a failed simulator process.

## 9. Debugging method

Work from architecture inward:

1. Read the test name, failure code, timeout, and native simulator exit.
2. Find the last valid commit and the expected instruction in disassembly.
3. Decide whether the failure is architectural, protocol, firmware, harness,
   toolchain, timing, or board-specific.
4. Inspect the owning module and the smallest relevant waveform window.
5. Turn the failure into a focused reproducible test.
6. Fix the owner, rerun focused coverage, then the full preservation gates.
7. Record root cause and why the selected fix is correct.

Useful waveform groups: packet valid/PC, stall/flush/kill, request/ready and
response-valid/error, RF/CSR write commands, trap/redirect, commit order, and
timer/UART/GPIO state.

## 10. Interview questions and concise answers

### Architecture and requirements

**Q: Why did you choose an in-order core?**
A: The goal was precise, explainable behavior for FreeRTOS and FPGA bring-up.
In-order issue/retirement reduces ownership and recovery complexity while still
exercising real hazards, stalls, traps, and multi-cycle units.

**Q: What are the deliberate limitations?**
A: No cache, MMU, S-mode, PLIC, AXI, atomics, or full forwarding. Those features
were not required for a one-hart machine-mode FreeRTOS demonstration.

**Q: How did requirements shape module boundaries?**
A: Each stateful contract has one owner: LSU for a data transaction, fabric for
response routing, retirement for architectural effects, CSR file for WARL and
state, UART engines for serial timing, and the MMIO wrapper for buffering.

**Q: Why use packed pipeline structs?**
A: They keep instruction metadata together, reduce wiring errors, make bubbles
canonical, and let interfaces evolve by adding a field in one type.

**Q: What is a canonical bubble?**
A: A completely zeroed invalid packet. It removes stale control fields and is
paired with final valid gating so invalid work cannot cause a side effect.

### Pipeline and execution

**Q: How do you handle RAW hazards?**
A: Decode compares used source registers with the executing destination. On a
match, PC and IF/ID hold while ID/EX receives a bubble. There is no full bypass
network, so the tradeoff is simplicity versus CPI.

**Q: Why is delayed fetch kill needed?**
A: Instruction BRAM is synchronous. A request launched before redirect returns
one cycle later, after the immediate flush, so a delayed kill discards it.

**Q: How does branch recovery work?**
A: Execute resolves the target and alignment, redirects the PC, flushes younger
packets, and kills the outstanding stale fetch response.

**Q: Why replace the combinational divider?**
A: Synthesis measured it as the critical path and it failed 25/50 MHz targets.
The iterative divider reused the wait protocol and traded 32 cycles for timing.

**Q: How do you make a multi-cycle unit kill-safe?**
A: Start only for a valid, un-killed owner; keep ownership visible for stall and
interrupt deferral; clear internal state on kill; emit completion for one cycle.

### Memory and buses

**Q: Why a one-outstanding LSU?**
A: It is the smallest protocol that tolerates target wait states and delayed
responses while making ordering and precise faults straightforward.

**Q: What must remain stable under back-pressure?**
A: Request valid and the entire payload—address, direction, size, write data,
and strobes—until the ready edge accepts it.

**Q: Why register the fabric response owner?**
A: The CPU address can change after request acceptance. Routing from live decode
could return a later response from the wrong target.

**Q: Why include a default error target?**
A: Every address must complete. Returning a registered error converts an
unmapped access into a precise fault instead of a permanent bus hang.

**Q: How are misalignment and access faults different?**
A: Misalignment is detected before issuing the request. An access fault comes
from a completed target response error. Both trap precisely with normal effects
suppressed.

### Traps, interrupts, and retirement

**Q: What makes an exception precise?**
A: Older instructions have completed, the faulting instruction reports the
correct PC/cause/value, its forbidden normal effects are suppressed, and younger
instructions cannot modify architectural state.

**Q: Why centralize retirement?**
A: Distributed RF, CSR, trap, and redirect decisions create conflicting owners.
A single boundary makes priority and exclusion rules explicit and testable.

**Q: When is the timer interrupt taken?**
A: Between instructions using effective post-retirement CSR state. Synchronous
exceptions win, MRET is excluded on the same boundary, and multi-cycle owners
defer the interrupt.

**Q: How is WFI modeled?**
A: It retires once and enters logical wait with a saved next PC. An eligible
interrupt wakes into trap entry without retiring WFI again.

**Q: What is WARL?**
A: Write Any, Read Legal. Software may write a wider value, but the CSR stores
only supported legal bits or aligned values, such as direct aligned `mtvec`.

### Peripherals and firmware

**Q: Why polling UART before interrupts?**
A: Polling established serial timing, FIFO, MMIO, firmware, and board pins
without first requiring a PLIC. Interrupts can be added after that baseline.

**Q: Why separate UART engines from the MMIO block?**
A: Bit timing/framing and software-visible buffering/error policy are different
concerns. The split permits focused tests and cleaner reuse.

**Q: Why can’t `.rodata` live beside code?**
A: The LSU cannot read program BRAM. C constants must be in data BRAM or loads
fault even though instruction fetch can see the code region.

**Q: How is `.data` initialized without flash copy?**
A: The ELF converter creates a separate initialized data-BRAM image loaded by
simulation and bitstream generation. Startup still clears `.bss` itself.

**Q: Why initialize `gp` carefully?**
A: Linker relaxation can generate GP-relative accesses. The startup sequence
uses the psABI pattern with relaxation locally disabled so it does not assume
`gp` was already valid.

**Q: Why use the official FreeRTOS port?**
A: Context switching is ABI-sensitive. Reusing a reviewed upstream port reduces
custom assembly risk and lets platform work focus on timer, linker, and trap
adaptation.

**Q: How did you verify context preservation?**
A: Load distinct values into `s2`–`s11`, force a higher-priority queue receiver
to switch through ECALL, then check every sentinel after the producer resumes.

### Verification and debug

**Q: What is the difference between `tohost` and the commit interface?**
A: `tohost` is a software/testbench completion convention. `commit_pkt_t` is an
ordered architectural observation of every retiring instruction and its effects.

**Q: Why not rely only on waveform inspection?**
A: Waveforms explain a known failure but do not provide scalable automatic
checking. Tests and assertions detect regressions; waveforms locate causality.

**Q: How do you avoid false PASS results?**
A: Require PASS marker, native simulator exit zero, no fatal marker, and zero
ModelSim errors; test the classifier with deliberately contradictory inputs.

**Q: What did ACT4 prove?**
A: All 39 applicable RV32I and 8 RV32M self-checking cases passed. It is strong
ISA regression evidence, not full compliance certification or SoC validation.

**Q: Give an example of a testbench bug you found.**
A: A new fabric scenario expected UART valid while driving CPU valid low, then
tried to withdraw a stalled request before acceptance. Enforcing ready/valid
semantics led to a correct exactly-once request/response test.

**Q: Give an example simulation did not catch.**
A: Vivado route found a combinational loop through interrupt selection, kill,
and busy/wait. Separating observed ownership from start permission removed it.

**Q: How do you decide whether to change RTL after a failure?**
A: First classify environment, adapter, test, firmware, and RTL possibilities.
Change RTL only after a minimal test and architectural evidence isolate the DUT.

### FPGA and tradeoffs

**Q: What does synthesis prove that simulation does not?**
A: Synthesizability, inferred resources, retained hierarchy/initialization, and
estimated timing. Placement/routing adds real interconnect, DRC, and slack.

**Q: What does a physical board test add?**
A: Actual clock/reset behavior, JTAG, I/O voltage, pin mapping, polarity, baud,
signal crossover, and observable execution.

**Q: Why target the `-1` speed grade?**
A: The physical suffix is unreadable. Using the conservative part avoids
claiming an unverified faster device while still allowing reproducible builds.

**Q: What would you improve next?**
A: Close external UART/reset/FreeRTOS hardware gates, expand redirect/stall
fault tests, then measure before adding forwarding, UART
interrupts/PLIC, or performance optimizations.

## 11. Stories worth preparing in STAR format

1. **Precise retirement:** side-effect leakage risk → central owner and canonical
   bubbles → directed squash tests and assertions → clean trap semantics.
2. **Wait-state-safe LSU:** fixed-latency assumption → registered request/FSM →
   delayed/back-pressure tests → exactly-once memory behavior.
3. **Divider timing:** measured failed critical path → iterative alternatives →
   Radix-2 implementation → ACT4 plus positive synthesis timing.
4. **Data fabric:** multi-target requirement → registered owner → adversarial
   live-address test → correct response routing.
5. **FreeRTOS tick starvation:** tasks did not progress → inspect live counters
   and interrupt catch-up → separate simulation timing profile → green queue,
   UART, GPIO, and context-sentinel test.
6. **Routed combinational loop:** Vivado DRC failure → trace feedback across
   retirement/kill/wait → split observation from permission → zero blocking DRC.
7. **JTAG bring-up:** hardware manager saw no cable → separate USB transport,
   runtime, server, and target layers → install Digilent runtime → program LEDs.

## 12. Honest closing statement

This is a learning-oriented, verified baseline rather than a production CPU.
Its strongest qualities are explicit ownership, precise side-effect control,
reproducible cross-layer tests, and documented refinement from measured
failures. Its open limits—performance, randomized verification, UART/reset
hardware evidence, and production robustness—are known and recorded.
