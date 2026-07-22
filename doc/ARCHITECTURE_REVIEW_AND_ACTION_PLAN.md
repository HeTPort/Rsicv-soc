# Architecture Review and Remediation Plan

**Review date:** 2026-07-22

**Target:** FreeRTOS on the custom RV32IM core in the PL of a Zynq XC7Z010

**Scope:** current CPU pipeline, LSU, CSR/trap implementation, memory system,
verification environment, and the execution order in `TODO.md`

## Purpose

This document records the architecture review of the current working tree and
turns each finding into an implementation and verification action. It is not a
claim that the listed defects are already fixed. The checkboxes below should be
closed only after both the RTL change and its regression evidence exist.

The FreeRTOS target in [`TODO.md`](../TODO.md) is appropriate for the present
core. The packed pipeline packets, separated LSU, centralized control module,
and architectural commit interface are useful foundations. The main change to
the roadmap is to insert a short correctness phase before introducing a
wait-state bus or asynchronous interrupts.

## Verified baseline

The live working tree was checked on 2026-07-22 with:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
./run_regression.ps1 -Tag smoke
python -m unittest test_elf_to_mem.py test_import_act4.py
```

Observed result:

- ModelSim directed smoke regression: **9/9 passed**.
- ELF/importer Python tests: **4/4 passed**.
- RTL compilation: **0 errors and 16 non-fatal packed-input-port warnings**.

This is a valuable change-detection baseline. It is not yet evidence of complete
RV32IM, Zicsr, precise-trap, or wait-state-bus correctness because the current
directed programs do not exercise all of those behaviors.

## Required Phase 0A gate

Add the following phase immediately after checkpointing the current green
baseline and before Phase 1/Phase 2 bus implementation:

> **Phase 0A — Make retirement and pipeline side effects precise.**

Exit criteria:

- [ ] A killed or invalid packet cannot write a GPR, CSR, or memory.
- [ ] Every pipeline reset/flush creates a completely initialized bubble.
- [ ] A memory instruction advances to WB exactly once, including with wait
      states.
- [ ] Load response data and fault status are registered with their instruction.
- [ ] Taken branch/JAL/JALR instruction-address misalignment traps correctly.
- [ ] Implemented CSR addresses and legal write/no-write behavior are explicit.
- [ ] Back-to-back CSR dependencies return the newest architectural value.
- [ ] Instruction fetch is verified against the memory latency that Vivado will
      actually synthesize.
- [ ] Directed tests exist for every item above and the complete smoke suite is
      green.

## Findings and handling plan

### AR-001 — A killed CSR packet can still write a CSR

**Evidence**

- [`wb_csr_we`](../src/core/riscv.sv#L148) uses `csr.valid` without also
  requiring `ex2wb_pkt_out.valid`.
- The trap safety block in [`riscv.sv`](../src/core/riscv.sv#L318) clears the
  packet's `valid` bit but does not clear its CSR sub-packet.
- [`wb_stage.sv`](../src/core/wb_stage.sv#L47) already calculates a
  valid-qualified CSR write enable, but that output is not used by the top
  level.

**Failure sequence**

1. An older instruction reaches WB with a synchronous exception.
2. A younger CSR instruction is in EX in the same cycle.
3. `pipe_kill` clears only the younger packet's main `valid` bit.
4. The invalid packet reaches EX/WB with `csr.valid` still set.
5. The top-level CSR write enable asserts and the squashed instruction modifies
   architectural state.

**Handling**

- [ ] Define `wb_csr_we` as `packet.valid && packet.csr.valid && !trap`.
- [ ] Prefer clearing the complete EX/WB packet on a kill rather than maintaining
      a growing list of individually masked fields.
- [ ] Route CSR write information through one owner, either `wb_stage` or a new
      retirement block; remove the duplicate top-level derivation.
- [ ] Audit every architectural side effect so it is qualified by one common
      `retire_fire`/valid condition.

**Required tests**

- [ ] Trap followed by younger `csrw`; confirm the CSR is unchanged.
- [ ] Trap followed by younger GPR write and store; confirm both are suppressed.
- [ ] Assertion: an invalid EX/WB packet never enables RF, CSR, or memory writes.

### AR-002 — Pipeline bubbles do not clear all packet fields

**Evidence**

The reset and flush branches in [`id2ex.sv`](../src/core/id2ex.sv#L36) clear
fields individually but omit newer fields such as `csr`, `is_mret`, and
`is_wfi`.

The main `valid` bit currently prevents most omitted fields from causing a
side effect, but stale values and unknowns weaken simulation checks and create a
maintenance hazard whenever a new field is added.

**Handling**

- [ ] Build a single safe bubble value for each packet type.
- [ ] On reset or flush, assign the entire packet to that bubble in one
      nonblocking assignment.
- [ ] Keep `instr = INST_NOP` only if it materially improves wave readability;
      safety must come from `valid = 0`, not from the instruction encoding.
- [ ] Add an assertion that a bubble has no RF, CSR, memory, redirect, or trap
      side effects.

### AR-003 — The current stall model cannot support a wait-state bus

**Evidence**

- [`lsu.sv`](../src/core/lsu.sv#L22) declares `ram_req_ready_i` in the wrong
  direction and drives both ready and response-valid internally.
- [`core_ctrl.sv`](../src/core/core_ctrl.sv#L60) ties `ex_stall` low.
- EX/WB is never stalled, while a future EX stall would hold the same ID/EX
  packet in place.

If EX is merely held without masking its output, the same valid instruction can
be copied into EX/WB and committed repeatedly.

**Handling**

Implement a single-outstanding LSU transaction state machine:

```text
IDLE -> REQUEST -> RESPONSE -> COMPLETE -> IDLE
```

- `IDLE`: accept a new EX memory operation.
- `REQUEST`: hold request address/control/data stable until
  `req_valid && req_ready`.
- `RESPONSE`: deassert the request and wait for exactly one `rsp_valid`.
- `COMPLETE`: present one valid result to EX/WB, then release ID/EX.

During REQUEST/RESPONSE:

- [ ] Stall PC, IF/ID, and ID/EX.
- [ ] Send a bubble to EX/WB after any older WB instruction has retired.
- [ ] Never reissue an accepted request.
- [ ] Never report a commit until the response completes.
- [ ] Do not accept another memory operation while one is outstanding.
- [ ] Defer an interrupt after a request has been accepted; do not attempt to
      cancel an externally visible store.

The existing pipeline does not require a new full MEM stage if an `ex_done` or
`ex_fire` signal controls when the held ID/EX instruction is allowed to enter
EX/WB.

**Required protocol assertions**

- [ ] Request fields remain stable while valid is asserted and ready is low.
- [ ] Every accepted request receives exactly one response.
- [ ] A response is impossible without one outstanding request.
- [ ] A memory instruction commits at most once.
- [ ] No new request is issued while `pipe_kill` is active.

### AR-004 — Load response data bypasses the pipeline packet

**Evidence**

- [`lsu.sv`](../src/core/lsu.sv#L129) aligns live `ram_rdata_i` using metadata
  from the WB packet.
- [`riscv.sv`](../src/core/riscv.sv#L394) sends that combinational value directly
  into WB.
- The commit interface reads the live RAM output in
  [`riscv.sv`](../src/core/riscv.sv#L423).

This is valid only while RAM latency is fixed and the output remains aligned
with EX/WB by construction. It is unsafe for a response-valid bus.

**Handling**

- [ ] Extend the memory result packet with raw response data, aligned load data,
      and response error/fault information.
- [ ] Capture the response and its instruction metadata together.
- [ ] Make WB and the commit interface consume only registered packet fields.
- [ ] Define whether a faulting transaction reports memory masks/data in the
      commit record; apply the definition consistently in RTL and tests.

### AR-005 — Instruction memory is not the synchronous BRAM assumed by the plan

**Evidence**

- [`prog_ram.sv`](../src/mem/prog_ram.sv#L237) implements a combinational read.
- [`riscv.sv`](../src/core/riscv.sv#L217) registers the returned instruction and
  current request PC.
- `TODO.md` and the intended FPGA target assume a synchronous instruction BRAM.

Changing only `prog_ram` to a clocked read would pair the previous response data
with the current request PC because of nonblocking clocked-update timing.

**Handling**

- [ ] State the instruction request/response latency explicitly.
- [ ] Convert program memory to a Vivado-recognized synchronous BRAM template.
- [ ] Delay the accepted request PC/valid so it is paired with the actual RAM
      response; do not register an unrelated current PC beside old data.
- [ ] Recalculate the number of stale responses that must be killed after a
      branch, jump, trap, or interrupt redirect.
- [ ] Add assertions that every valid IF/ID `{pc,instr}` pair matches the
      corresponding program-memory word after stalls and redirects.
- [ ] Inspect the Vivado synthesis report and confirm Block RAM inference.

### AR-006 — Taken control-flow targets do not check IALIGN=32

**Evidence**

The redirect paths in [`execute.sv`](../src/core/execute.sv#L298) generate branch,
JAL, and JALR targets, but the exception set in
[`execute.sv`](../src/core/execute.sv#L243) does not include instruction-address
misalignment.

For an RV32 core without the compressed extension, a taken target with
`target[1:0] != 0` must trap on the control-flow instruction. JALR still clears
bit zero, but bit one can remain set.

**Handling**

- [ ] Compute the resolved target before redirect arbitration.
- [ ] For a taken branch, JAL, or JALR, detect `target[1:0] != 0`.
- [ ] Suppress the redirect and RF writeback for the faulting instruction.
- [ ] Report instruction-address-misaligned cause, faulting instruction PC in
      `mepc`, and the target address in `mtval` according to the selected
      architectural policy.

**Required tests**

- [ ] Taken and not-taken branch with a misaligned encoded target.
- [ ] Misaligned JAL target.
- [ ] JALR target with bit one set.
- [ ] Confirm the destination register is not written on the exception.

### AR-007 — CSR legality, no-write semantics, and hazards are incomplete

**Evidence**

- Unknown CSR reads return zero in [`csr_regfile.sv`](../src/core/csr_regfile.sv#L79).
- Unsupported or read-only writes are ignored rather than trapping in
  [`csr_regfile.sv`](../src/core/csr_regfile.sv#L102).
- Every decoded CSRRS/CSRRC form creates a CSR operation in
  [`decode.sv`](../src/core/decode.sv#L392), even when the architectural source
  is zero and the instruction should perform no write.
- Only the special `mepc`-to-`mret` sequence has top-level forwarding.

**Handling**

- [ ] Define the exact implemented CSR set needed by the FreeRTOS milestone.
- [ ] Add an access checker for implemented address, minimum privilege, and
      read-only encoding.
- [ ] Trap writes to read-only CSRs and accesses to unimplemented CSRs.
- [ ] Suppress writes for CSRRS/CSRRC with `rs1=x0` and CSRRSI/CSRRCI with
      `zimm=0`.
- [ ] Implement a same-address WB-to-EX CSR bypass or stall dependent CSR
      operations for one cycle.
- [ ] Apply WARL masks to `mstatus`, `mie`, `mip`, `mtvec`, and `mepc`; do not
      allow unsupported state to be stored accidentally.
- [ ] When timer interrupts are added, compose `mip.MTIP` from hardware and make
      ordinary CSR writes unable to manufacture or clear that level-sensitive
      pending condition.

**Required tests**

- [ ] CSRRW/CSRRS/CSRRC and all immediate forms.
- [ ] Zero-source no-write cases.
- [ ] Back-to-back write/read and write/modify sequences to the same CSR.
- [ ] Unknown CSR and read-only write traps.
- [ ] `mstatus.MIE/MPIE/MPP`, `mepc`, and `mtvec` WARL behavior.

### AR-008 — Interrupt entry needs an explicit retirement boundary

Interrupts occur between architectural instructions. Reusing only the current
synchronous-exception packet does not identify the correct resume PC after a
retired branch or jump, and it does not naturally describe an interrupt that is
not caused by a faulting instruction.

**Handling**

- [ ] Add `next_pc` to the retiring packet. For sequential instructions it is
      `pc+4`; for a taken branch or jump it is the resolved target.
- [ ] Use `next_pc` as interrupt `mepc` after the current instruction retires.
- [ ] Give a synchronous exception on the current instruction priority over an
      eligible interrupt.
- [ ] Defer interrupt entry while an accepted data-bus transaction is
      outstanding.
- [ ] Suppress all younger RF, CSR, memory, and redirect effects.
- [ ] Keep asynchronous trap-entry information separate from a fabricated
      instruction commit, for example with a `trap_entry` record containing
      interrupt/cause/mepc/mtval.
- [ ] Define how WFI records its resume PC and waits for an eligible interrupt.

Timer interrupt eligibility should be equivalent to:

```text
mstatus.MIE && mie.MTIE && mip.MTIP
```

**Required tests**

- [ ] Masked but pending timer interrupt.
- [ ] Interrupt immediately after enabling `mstatus.MIE`/`mie.MTIE`.
- [ ] Interrupt around sequential ALU, branch, jump, CSR, load, store, and bus
      stall boundaries.
- [ ] Synchronous exception and interrupt pending in the same cycle.
- [ ] Repeated interrupt/`mret` loop with no duplicate or skipped work.
- [ ] At least 10,000 simulated timer interrupts before closing Phase 3.

### AR-009 — The proposed memory map conflicts with the current ACT4 flow

**Evidence**

- The provisional map in [`TODO.md`](../TODO.md#phase-1--define-the-minimal-freertos-soc-contract)
  places instruction BRAM at `0x0000_0000` and data BRAM at `0x8000_0000`.
- The current ACT4 linker uses one 16 KiB executable/readable/writable region at
  zero in [`link.ld`](../verif/act4/rv32im_core/link.ld#L4).
- The current converter copies every loadable segment into both Harvard images
  in [`elf_to_mem.py`](../sim/regress/elf_to_mem.py#L1).
- Current SoC defaults are 4096 words, or 16 KiB at 32 bits per word, in
  [`riscv_soc.sv`](../src/riscv_soc.sv#L3), while the TODO proposes 64 KiB banks.

**Decision required before Phase 1 closes**

Option A — one dual-port BRAM in a unified architectural address region:

- instruction fetch uses one read port;
- the data bus uses the second read/write port;
- linker and ACT4 integration remain simpler;
- physical memory capacity is not duplicated;
- self-modifying code remains unsupported or explicitly constrained.

Option B — physically and architecturally split instruction/data BRAM regions:

- preserves the existing two-array implementation style;
- requires a split linker script and address-aware image generation;
- requires updates to the ACT4 linker, Sail regions, UDB description, converter,
  manifests, and `tohost` placement;
- consumes the sum of the two BRAM capacities.

**Handling**

- [ ] Record the selected option in `TODO.md` and the architecture documentation.
- [ ] Express all memory sizes in bytes at the SoC contract boundary; translate
      to words only inside RAM modules.
- [ ] Update hardware parameters, linker scripts, firmware image generation,
      ACT4 configuration, and testbench ranges in the same change.
- [ ] Use an explicit default error target for unmapped data-bus addresses.
- [ ] Reserve a large enough timer decode window for standard offsets:
      `mtimecmp=0x4000` and `mtime=0xBFF8` require a window extending beyond
      4 KiB.

### AR-010 — Current tests are green but too shallow for the claimed features

Several trap programs enter a handler and write PASS without checking every
value named in their comments. For example, the handler in
[`ebreak_test.S`](../testdata/ebreak_test.S#L40) does not read `mcause`, `mepc`,
or `mtval`. The existing [`illegal_jalr_funct3_test.S`](../testdata/illegal_jalr_funct3_test.S)
is not in the manifest and still describes the obsolete halt behavior.

**Handling**

- [ ] Make each trap test check `mcause`, `mepc`, `mtval`, and relevant
      `mstatus` fields before reporting PASS.
- [ ] For misaligned stores, prove the addressed memory bytes did not change.
- [ ] Add lane tests for LB/LBU/LH/LHU/LW and SB/SH/SW at every legal offset.
- [ ] Add dependency tests for ALU/load/CSR producers feeding ALU, branch,
      address, and store-data consumers.
- [ ] Update and add the illegal-JALR test to `tests.json`, or remove it if it is
      intentionally superseded.
- [ ] Require every checked-in `.hex` to have a source, build recipe, or clear
      provenance record.
- [ ] Keep official ACT4 as continuous coverage, but regenerate its artifacts
      after any memory-map change.

### AR-011 — FPGA feasibility checks should move earlier

The current roadmap leaves the first divider critical-path and BRAM-inference
inspection until the FPGA integration phase. A combinational RV32M divider or
non-inferred instruction BRAM can force changes to pipeline control, exactly the
area being redesigned for the bus.

**Handling**

- [ ] After Phase 0A/Phase 2, run an early out-of-context Vivado synthesis using
      the intended XC7Z010 part.
- [ ] Confirm instruction and data memories infer the expected number of Block
      RAMs.
- [ ] Record LUT/FF/BRAM/DSP utilization and the MULDIV critical path.
- [ ] If the divider fails timing or consumes unreasonable area, reuse the new
      EX completion/backpressure mechanism for a multi-cycle divider before
      interrupt and FreeRTOS work depends on it.
- [ ] Keep full placement, routing, power, and board timing closure in the later
      FPGA phase.

### AR-012 — Documentation and interface cleanup

The repository README still describes the long-term Linux target and an older
five-stage/privilege status, while `TODO.md` now correctly targets FreeRTOS.
Several interfaces also retain obsolete or duplicate signals, including a
permanently low `halt_o`, unused `core_ctrl` inputs, and tied-off WB CSR/trap
outputs.

**Handling**

- [ ] Update `README.md` after the target architecture and memory map are frozen.
- [ ] Document the real pipeline stages and actual instruction/data memory
      latency rather than the conceptual five-stage labels.
- [ ] Remove or explicitly deprecate `halt_o` and obsolete halt-based tests.
- [ ] Make one module own retirement, CSR writes, trap entry, and commit record
      construction.
- [ ] Remove unused control ports after the bus/interrupt control contract is
      stable.
- [ ] Replace empty placeholder RTL files with implemented modules when their
      phase starts, or retain only clearly named placeholders that are excluded
      from the build.

## Proposed data-bus contract

The Phase 1 contract should state the following behavior, not just list signal
names:

```systemverilog
req_valid
req_ready
req_addr
req_write
req_wdata
req_wstrb

rsp_valid
rsp_rdata
rsp_error
```

Protocol rules:

1. A request is accepted only on `req_valid && req_ready`.
2. Request fields remain stable until acceptance.
3. Exactly one transaction may be outstanding.
4. Every accepted load and store receives exactly one response.
5. The address decoder latches the selected target at request acceptance; the
   response is not selected using a later live address.
6. Only one target receives request-valid for a transaction.
7. Unmapped accesses go to a default target that accepts and returns an error
   without a side effect.
8. A load retires only with its response data or access-fault result.
9. A store retires only after its completion response. A target returning an
   error must not perform the failed write.
10. An accepted transaction is not cancelled by a later interrupt. Interrupt
    entry waits for architectural completion.

## Timer block requirements

For the initial single-hart FreeRTOS target:

- [ ] Reset `mtime` to zero.
- [ ] Reset `mtimecmp` to all ones so reset does not create an immediate tick.
- [ ] Increment `mtime` at an explicitly documented frequency.
- [ ] Assert MTIP as a level while `mtime >= mtimecmp`.
- [ ] Define RV32 high/low read and write sequencing.
- [ ] Either require and document the conventional safe software update
      sequence or add hardware shadowing that prevents a transient early
      compare while `mtimecmp` halves are updated.
- [ ] Keep MTIP hardware-owned even if other writable `mip` bits are added.

## Revised execution order

1. **Checkpoint the current working tree and archived 9/9 + 4/4 evidence.**
2. **Complete Phase 0A:** precise side-effect gating, complete bubbles, CSR
   legality/hazards, control-flow misalignment, and real instruction BRAM timing.
3. **Freeze the memory topology and map.** Update all hardware, linker, ACT4,
   and converter descriptions together.
4. **Externalize the data bus.** Implement the LSU transaction FSM, decoder,
   registered responses, access faults, and protocol assertions.
5. **Run early synthesis.** Confirm BRAM inference and decide whether MULDIV must
   become multi-cycle.
6. **Add the machine timer interrupt.** Implement retirement-boundary entry,
   hardware MTIP, timer MMIO, WFI, and long repeated-interrupt tests.
7. **Add startup/linker/driver infrastructure.** This should begin immediately
   after the memory map is frozen rather than waiting until every peripheral is
   complete.
8. **Implement GPIO and polling UART.** Verify each independently, then at SoC
   level.
9. **Run bare-metal simulation and FPGA sanity programs.** Prove UART, GPIO, and
   timer interrupts before adding the kernel.
10. **Integrate the pinned official FreeRTOS RISC-V port.** Add context sentinel,
    stack, heap, queue, preemption, and long-run checks.
11. **Complete FPGA timing and physical-board validation.**

Official RV32I/RV32M ACT4 execution remains a continuous parallel track. It is
not a substitute for the directed pipeline, CSR, bus, interrupt, or peripheral
tests listed here.

## Definition of completion for this review

This review document can be considered fully handled only when:

- [ ] Every AR item is either implemented and verified or explicitly deferred
      with a reason and risk statement.
- [ ] The full directed and Python regression is reproducible from a clean
      checkout.
- [ ] ACT4 configuration describes the implemented hardware and final memory
      map accurately.
- [ ] Vivado reports confirm BRAM inference and timing at the selected clock.
- [ ] A bare-metal timer handler survives at least 10,000 interrupts.
- [ ] FreeRTOS preempts tasks, preserves context, communicates through a queue,
      writes UART output, and controls GPIO in simulation and on the board.
