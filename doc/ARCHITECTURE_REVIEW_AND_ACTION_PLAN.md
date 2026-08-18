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

## How to read phase and AR status

Phase numbers and AR numbers describe different things:

- `Phase 0A`, `Phase 1`, and later phases are execution gates. Their authoritative
  checklists and ordering live in [`TODO.md`](../TODO.md).
- `AR-001`, `AR-002`, and later identifiers are stable architecture-review
  finding IDs. They are not a second phase sequence and should not be renumbered
  when work moves earlier or later.
- **Phase 0A is complete.** That statement means its explicit exit checklist
  below is satisfied; it does not mean every AR finding or the whole FreeRTOS
  roadmap is complete.

Current ownership and status:

| Finding | Owning stage | Status |
|---|---|---|
| AR-001, AR-002, AR-005, AR-006, AR-007 | Phase 0A | Implemented and verified |
| AR-003, AR-004 | Phase 2 transaction/result sub-gates | Implemented and verified |
| AR-008 | Phase 3 | Implemented and verified; precise timer IRQ/WFI and 10,000-interrupt gate complete |
| AR-009 | Phase 1 | Accepted; Phase 1 contract and Phase 2 RTL adoption complete, later software consumers pending |
| AR-010 | Continuous verification track | Ongoing |
| AR-011 | Early FPGA feasibility, then Phase 7 closure | AR-017 closes the MULDIV OOC blocker; exact-board closure remains open |
| AR-012 | Cross-stage cleanup | Implemented and verified: retirement owner, control ports, public halt removal, and release documentation complete |
| AR-013 | Regression infrastructure | Implemented and verified |
| AR-014 | Phase 1 contract tooling | Accepted contract generation implemented and verified |
| AR-015 | AR-011 evidence supporting Phase 1 | 16 KiB/64 KiB utilization and post-synthesis timing comparison verified |
| AR-016 | Phase 1 architecture boundary | Core-to-SoC ownership and environment contract accepted |
| AR-017 | AR-011 timing optimization | Radix-2 iterative divider implemented and verified; exact-board closure open |
| AR-018 | Phase 2 SoC contract | All data and instruction fault cases GREEN; closed |
| AR-019 | Phase 2 data fabric | Centralized decoder/default target implemented and verified |
| AR-025 | Phase 6 FreeRTOS | Official V11.3.0 port initial ModelSim slice and routed bitstream verified; extended run and physical execution open |

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

- [x] A killed or invalid packet cannot write a GPR, CSR, or memory in the
      current direct-RAM design.
- [x] Every pipeline reset/flush creates a completely initialized bubble.
- [x] A memory instruction advances to WB exactly once, including with wait
      states.
- [x] Load response data and fault status are registered with their instruction.
- [x] Taken branch/JAL/JALR instruction-address misalignment traps correctly.
- [x] Implemented CSR addresses and legal write/no-write behavior are explicit.
- [x] Back-to-back CSR dependencies return the newest architectural value.
- [x] Instruction fetch is verified against the memory latency that Vivado will
      actually synthesize.
- [x] Directed tests exist for every item above and the complete smoke suite is
      green.

AR-003 and AR-004 are Phase 2 data-bus sub-gates that were deliberately pulled
forward to satisfy the wait-state and registered-result criteria above. AR-019
now implements centralized data decode/default termination, and AR-018 closes
the instruction-access-error path. Phase 2 is complete; timer/UART/GPIO target
adoption and system integration were subsequently verified in Phases 3–5.

## Findings and handling plan

### AR-001 — A killed CSR packet can still write a CSR

**Progress:** fixed, verified, and superseded by the single retirement owner.
The reproduced CSR corruption is retained as a smoke regression. See
[`AR001_PRECISE_CSR_SQUASH_FIX.md`](AR001_PRECISE_CSR_SQUASH_FIX.md) for the
RED/GREEN evidence. Directed CSR, GPR, and store squash cases are now covered;
the broader retirement-ownership work below remains open.

**Historical evidence before the fix**

- [`wb_csr_we`](../src/core/riscv.sv#L148) uses `csr.valid` without also
  requiring `ex2wb_pkt_out.valid`.
- The trap safety block in [`riscv.sv`](../src/core/riscv.sv#L318) clears the
  packet's `valid` bit but does not clear its CSR sub-packet.
- The former `wb_stage.sv` calculated a valid-qualified CSR write enable, but
  that output was not used by the top level. Phase 3 removed this second owner.

**Failure sequence**

1. An older instruction reaches WB with a synchronous exception.
2. A younger CSR instruction is in EX in the same cycle.
3. `pipe_kill` clears only the younger packet's main `valid` bit.
4. The invalid packet reaches EX/WB with `csr.valid` still set.
5. The top-level CSR write enable asserts and the squashed instruction modifies
   architectural state.

**Handling**

- [x] Define `wb_csr_we` as `packet.valid && packet.csr.valid && !trap`.
- [x] Prefer clearing the complete EX/WB packet on a kill rather than maintaining
      a growing list of individually masked fields.
- [x] Route CSR write information through the new `retire_stage` owner and
      remove the duplicate top-level derivation and obsolete `wb_stage`.
- [x] Audit every architectural side effect so it is qualified by one common
      `retire_fire`/valid condition.

**Required tests**

- [x] Trap followed by younger `csrw`; confirm the CSR is unchanged.
- [x] Trap followed by younger GPR write and store; confirm both are suppressed.
- [x] Assertion: an invalid EX/WB packet never enables RF, CSR, or memory writes.

Focused assertions prevent an invalid packet from enabling a CSR write, check
that `pipe_kill` suppresses younger side effects, and check that trap/WFI wake
events cannot accidentally create normal retirement effects.

### AR-002 — Pipeline bubbles do not clear all packet fields

**Status:** fixed and verified. See
[`AR002_CANONICAL_PIPELINE_BUBBLES.md`](AR002_CANONICAL_PIPELINE_BUBBLES.md)
for the implementation decisions, encountered problems, regression evidence,
and reusable design principles.

**Evidence**

The reset and flush branches in [`id2ex.sv`](../src/core/id2ex.sv#L36) clear
fields individually but omit newer fields such as `csr`, `is_mret`, and
`is_wfi`.

The main `valid` bit currently prevents most omitted fields from causing a
side effect, but stale values and unknowns weaken simulation checks and create a
maintenance hazard whenever a new field is added.

**Handling**

- [x] Build a single safe bubble value for each packet type.
- [x] On reset or flush, assign the entire packet to that bubble in one
      nonblocking assignment.
- [x] Keep `instr = INST_NOP` only if it materially improves wave readability;
      safety must come from `valid = 0`, not from the instruction encoding.
- [x] Add an assertion that a bubble has no RF, CSR, memory, redirect, or trap
      side effects.

### AR-003 — The current stall model cannot support a wait-state bus

**Status:** fixed and verified. See
[`AR003_WAIT_STATE_SAFE_LSU.md`](AR003_WAIT_STATE_SAFE_LSU.md) for the accepted
contract, state-machine design, RED/GREEN evidence, performance consequences,
and reusable principles.

**Evidence**

- Before the fix, `lsu.sv` declared RAM handshake ownership incorrectly and
  had no clocked transaction state.
- Before the fix, `core_ctrl.sv` tied the EX wait path low.
- The retained RED protocol test failed elaboration on the nine missing
  transaction-owner ports.

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

- [x] Stall PC, IF/ID, and ID/EX.
- [x] Send a bubble to EX/WB after any older WB instruction has retired.
- [x] Never reissue an accepted request.
- [x] Never report a commit until the response completes.
- [x] Do not accept another memory operation while one is outstanding.
- [x] Defer an interrupt after a request has been accepted; do not attempt to
      cancel an externally visible store. AR-008 implements retirement-boundary
      interrupt selection and verifies interrupts around loads, stores, and
      pipeline stalls.

The existing pipeline does not require a new full MEM stage if an `ex_done` or
`ex_fire` signal controls when the held ID/EX instruction is allowed to enter
EX/WB.

**Required protocol assertions**

- [x] Request fields remain stable while valid is asserted and ready is low.
- [x] Every accepted request receives exactly one response.
- [x] A response is impossible without one outstanding request.
- [x] A memory instruction commits at most once.
- [x] No new request is issued while `pipe_kill` is active.

### AR-004 — Load response data bypasses the pipeline packet

**Status:** fixed and verified. See
[`AR004_REGISTERED_MEMORY_RESULT.md`](AR004_REGISTERED_MEMORY_RESULT.md) for the
packet and fault contracts, RED/GREEN evidence, implementation decisions,
problems encountered, and reusable principles.

**Original evidence**

- AR-003 captured bus response data/error in LSU registers.
- `riscv.sv` sent LSU-held aligned data directly to WB.
- The commit interface read LSU-held raw response data.
- EX/WB carried memory metadata but not raw/aligned response data or error.

**Handling**

- [x] Extend the memory result packet with raw response data, aligned load data,
      and response error/fault information.
- [x] Capture the response and its instruction metadata together.
- [x] Make WB and the commit interface consume only registered packet fields.
- [x] Define whether a faulting transaction reports memory masks/data in the
      commit record; apply the definition consistently in RTL and tests.

### AR-005 — Instruction memory is not the synchronous BRAM assumed by the plan

**Status:** fixed and verified. See
[`AR005_SYNCHRONOUS_INSTRUCTION_BRAM.md`](AR005_SYNCHRONOUS_INSTRUCTION_BRAM.md)
for the timing contract, RED/GREEN evidence, Vivado inference result, problems
encountered, and reusable principles.

**Original evidence**

- [`prog_ram.sv`](../src/mem/prog_ram.sv#L237) implements a combinational read.
- [`riscv.sv`](../src/core/riscv.sv#L217) registers the returned instruction and
  current request PC.
- `TODO.md` and the intended FPGA target assume a synchronous instruction BRAM.

Changing only `prog_ram` to a clocked read would pair the previous response data
with the current request PC because of nonblocking clocked-update timing.

**Handling**

- [x] State the instruction request/response latency explicitly.
- [x] Convert program memory to a Vivado-recognized synchronous BRAM template.
- [x] Delay the accepted request PC/valid so it is paired with the actual RAM
      response; do not register an unrelated current PC beside old data.
- [x] Recalculate the number of stale responses that must be killed after a
      branch, jump, trap, or interrupt redirect.
- [x] Add assertions that every valid IF/ID `{pc,instr}` pair matches the
      corresponding program-memory word after stalls and redirects.
- [x] Inspect the Vivado synthesis report and confirm Block RAM inference.

### AR-006 — Taken control-flow targets do not check IALIGN=32

**Status:** fixed and verified. See
[`AR006_CONTROL_FLOW_MISALIGNMENT.md`](AR006_CONTROL_FLOW_MISALIGNMENT.md) for
the RED/GREEN evidence, handling decisions, and reusable principles.

**Evidence**

The redirect paths in [`execute.sv`](../src/core/execute.sv#L298) generate branch,
JAL, and JALR targets, but the exception set in
[`execute.sv`](../src/core/execute.sv#L243) does not include instruction-address
misalignment.

For an RV32 core without the compressed extension, a taken target with
`target[1:0] != 0` must trap on the control-flow instruction. JALR still clears
bit zero, but bit one can remain set.

**Handling**

- [x] Compute the resolved target before redirect arbitration.
- [x] For a taken branch, JAL, or JALR, detect `target[1:0] != 0`.
- [x] Suppress the redirect and RF writeback for the faulting instruction.
- [x] Report instruction-address-misaligned cause, faulting instruction PC in
      `mepc`, and the target address in `mtval` according to the selected
      architectural policy.

**Required tests**

- [x] Taken and not-taken branch with a misaligned encoded target.
- [x] Misaligned JAL target.
- [x] JALR target with bit one set.
- [x] Confirm the destination register is not written on the exception.

### AR-007 — CSR legality, no-write semantics, and hazards are incomplete

**Status:** fixed and verified for the current M-mode CSR contract. See
[`AR007_CSR_LEGALITY_WARL_AND_HAZARDS.md`](AR007_CSR_LEGALITY_WARL_AND_HAZARDS.md)
for the exact implemented CSR set, RED/GREEN evidence, implementation
decisions, and concepts. Phase 3 now composes `mip.MTIP` from the hardware
timer level; ordinary CSR writes cannot manufacture or clear it.

**Evidence**

- Unknown CSR reads return zero in [`csr_regfile.sv`](../src/core/csr_regfile.sv#L79).
- Unsupported or read-only writes are ignored rather than trapping in
  [`csr_regfile.sv`](../src/core/csr_regfile.sv#L102).
- Every decoded CSRRS/CSRRC form creates a CSR operation in
  [`decode.sv`](../src/core/decode.sv#L392), even when the architectural source
  is zero and the instruction should perform no write.
- Only the special `mepc`-to-`mret` sequence has top-level forwarding.

**Handling**

- [x] Define the exact implemented CSR set needed by the FreeRTOS milestone.
- [x] Add an access checker for implemented address, minimum privilege, and
      read-only encoding.
- [x] Trap writes to read-only CSRs and accesses to unimplemented CSRs.
- [x] Suppress writes for CSRRS/CSRRC with `rs1=x0` and CSRRSI/CSRRCI with
      `zimm=0`.
- [x] Implement a same-address WB-to-EX CSR bypass or stall dependent CSR
      operations for one cycle.
- [x] Apply WARL masks to `mstatus`, `mie`, `mip`, `mtvec`, and `mepc`; do not
      allow unsupported state to be stored accidentally.
- [x] Compose `mip.MTIP` from hardware and make
      ordinary CSR writes unable to manufacture or clear that level-sensitive
      pending condition.

**Required tests**

- [x] CSRRW/CSRRS/CSRRC and all immediate forms.
- [x] Zero-source no-write cases.
- [x] Back-to-back write/read and write/modify sequences to the same CSR.
- [x] Unknown CSR and read-only write traps.
- [x] `mstatus.MIE/MPIE/MPP`, `mepc`, and `mtvec` WARL behavior.

### AR-008 — Interrupt entry needs an explicit retirement boundary

**Status:** implemented and verified 2026-08-09. **Target:** Phase 3 complete.

Interrupts occur between architectural instructions. Reusing only the current
synchronous-exception packet does not identify the correct resume PC after a
retired branch or jump, and it does not naturally describe an interrupt that is
not caused by a faulting instruction.

**Handling**

- [x] Add `next_pc` to the retiring packet. For sequential instructions it is
      `pc+4`; for a taken branch or jump it is the resolved target.
- [x] Use `next_pc` as interrupt `mepc` after the current instruction retires.
- [x] Give a synchronous exception on the current instruction priority over an
      eligible interrupt.
- [x] Defer interrupt entry while an accepted data-bus transaction is
      outstanding.
- [x] Suppress all younger RF, CSR, memory, and redirect effects.
- [x] Keep asynchronous trap-entry information separate from a fabricated
      instruction commit, for example with a `trap_entry` record containing
      interrupt/cause/mepc/mtval.
- [x] Define how WFI records its resume PC and waits for an eligible interrupt.

Timer interrupt eligibility should be equivalent to:

```text
mstatus.MIE && mie.MTIE && mip.MTIP
```

**Required tests**

- [x] Masked but pending timer interrupt.
- [x] Interrupt immediately after enabling `mstatus.MIE`/`mie.MTIE`.
- [x] Interrupt around sequential ALU, branch, jump, CSR, load, store, and bus
      stall boundaries.
- [x] Synchronous exception and interrupt pending in the same cycle.
- [x] Repeated interrupt/`mret` loop with no duplicate or skipped work.
- [x] At least 10,000 simulated timer interrupts before closing Phase 3.

Implementation rationale, limitations, signal flow, and evidence are in
[`AR008_PRECISE_MACHINE_TIMER_INTERRUPTS.md`](AR008_PRECISE_MACHINE_TIMER_INTERRUPTS.md).

### AR-009 — The accepted memory map requires migration from the current ACT4 flow

**Status:** accepted on 2026-08-01; data-RAM/default RTL partially adopted by
AR-019. **Target:** Phase 1 complete, with remaining behavioral/software
adoption owned by Phase 2.

**Evidence**

- The accepted map in [`TODO.md`](../TODO.md#phase-1--define-the-minimal-freertos-soc-contract)
  places instruction BRAM at `0x0000_0000` and data BRAM at `0x8000_0000`.
- The current ACT4 linker uses one 16 KiB executable/readable/writable region at
  zero in [`link.ld`](../verif/act4/rv32im_core/link.ld#L4).
- The current converter copies every loadable segment into both Harvard images
  in [`elf_to_mem.py`](../sim/regress/elf_to_mem.py#L1).
- Current SoC defaults are 4096 words, or 16 KiB at 32 bits per word, in
  [`riscv_soc.sv`](../src/riscv_soc.sv#L3), while the accepted contract requires
  64 KiB banks.

**Decision accepted to close Phase 1**

Option A — one dual-port BRAM in a unified architectural address region:

- instruction fetch uses one read port;
- the data bus uses the second read/write port;
- linker and ACT4 integration remain simpler;
- physical memory capacity is not duplicated;
- self-modifying code remains unsupported or explicitly constrained.

Selected Option B — physically and architecturally split instruction/data BRAM
regions:

- preserves the existing two-array implementation style;
- requires a split linker script and address-aware image generation;
- requires updates to the ACT4 linker, Sail regions, UDB description, converter,
  manifests, and `tohost` placement;
- consumes the sum of the two BRAM capacities.

**Handling**

- [x] Establish a validated machine-readable accepted map and deterministically
      generate SystemVerilog, C, linker, simulation, Vivado Tcl, and ACT4-facing
      artifacts. AR-014 records their provenance and validation; generation does
      not itself implement behavior, while AR-019 now consumes the generated
      SystemVerilog constants in the data fabric.
- [x] Select 64 KiB per instruction/data RAM bank using the paired AR-015
      resource and timing evidence.
- [x] Record the selected option in `TODO.md` and the architecture documentation.
- [x] Express all memory sizes in bytes at the SoC contract boundary; translate
      to words only inside RAM modules.
- [x] Update hardware parameters, linker scripts, firmware image generation,
      ACT4 configuration, and testbench ranges as each accepted-map consumer is
      adopted; the generated-map staleness check prevents drift.
- [x] Use an explicit registered default error target for unmapped data-bus
      addresses. See
      [`AR019_CENTRALIZED_DATA_FABRIC.md`](AR019_CENTRALIZED_DATA_FABRIC.md).
- [x] Add isolated executable RED cases for unmapped load/store and invalid
      fetch without adding expected failures to the default smoke suite. See
      [`AR018_SOC_FABRIC_RED_TESTS.md`](AR018_SOC_FABRIC_RED_TESTS.md).
- [x] Reserve a large enough timer decode window for standard offsets:
      `mtimecmp=0x4000` and `mtime=0xBFF8` require a window extending beyond
      4 KiB.

### AR-018 — The accepted SoC error contract lacked executable system-level RED evidence

**Status:** Implemented and verified; closed 2026-08-03.
**Target:** Phase 2.

**Evidence**

- The common source list compiles `tb_riscv_soc` with zero errors.
- An isolated manifest runs accepted 64 KiB depths and
  `tohost=0x8000_FFFC` through the real `riscv_soc` wrapper.
- The original RED run showed unmapped load and store reaching failure code 6
  because the wrapper routed them to data RAM instead of an error target.
- AR-019 now makes both data cases pass with causes 5/7 and proves that the
  invalid store cannot alter the aliased RAM sentinel.
- The original invalid-fetch RED reached failure code 2 after replacement
  EBREAK. The paired fetch-error implementation now reports precise cause 1
  with `mepc=mtval=PC`.
- The unchanged smoke suite remains 22/22 green and the regression classifier
  still passes.

**Handling**

- [x] Add the three RED firmware cases, SoC testbench, separate manifest, and
      backward-compatible runner top selection.
- [x] Add full-address decode and local-address subtraction.
- [x] Register response-source ownership and add the one-cycle, side-effect-free
      default target.
- [x] Add explicit fetch error signaling and precise cause-1 completion.
- [x] Add initial data-RAM boundary, inserted-request-wait, owner-stability, and
      back-to-back cross-target coverage.
- [x] Turn the AR-018 instruction case GREEN.
- [x] Extend coverage as real timer/UART/GPIO targets are added in their owning
      Phase 3/4 focused and SoC-level manifests.

Detailed rationale, failure codes, commands, and the acceptance evidence are in
[`AR018_SOC_FABRIC_RED_TESTS.md`](AR018_SOC_FABRIC_RED_TESTS.md). The data
implementation record is
[`AR019_CENTRALIZED_DATA_FABRIC.md`](AR019_CENTRALIZED_DATA_FABRIC.md).

### AR-010 — Current tests are green but too shallow for the claimed features

**Status:** ongoing. **Target:** continuous verification across all phases.

Several trap programs enter a handler and write PASS without checking every
value named in their comments. For example, the handler in
[`ebreak_test.S`](../testdata/ebreak_test.S#L40) does not read `mcause`, `mepc`,
or `mtval`. The existing [`illegal_jalr_funct3_test.S`](../testdata/illegal_jalr_funct3_test.S)
is not in the manifest. Its source now uses committed `tohost` completion, but
manifest adoption or deliberate removal remains open below.

**Handling**

- [x] Require a zero native simulator exit in addition to the existing
      PASS-marker, fatal-marker, and error-count checks. Keep the focused
      false-pass regression and RED/GREEN evidence in
      [`AR013_REGRESSION_EXIT_STATUS_GATE.md`](AR013_REGRESSION_EXIT_STATUS_GATE.md).
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

**Status:** paired utilization and early critical-path checkpoints verified;
AR-017 closes the MULDIV OOC timing blocker, while physical timing closure
remains open.
**Target:** an early feasibility checkpoint followed by full Phase 7 timing
closure. Instruction/data BRAM inference and the 16 KiB/64 KiB resource
comparison are recorded in AR-015. That RED evidence identifies an 87.102 ns
combinational divider path that fails both 25 MHz and 50 MHz. AR-017 replaces
it with a functionally verified iterative divider and both profiles now pass
the same OOC constraints; exact-board physical acceptance remains open.

The current roadmap leaves the first divider critical-path and BRAM-inference
inspection until the FPGA integration phase. A combinational RV32M divider or
non-inferred instruction BRAM can force changes to pipeline control, exactly the
area being redesigned for the bus.

**Handling**

- [x] Run paired early out-of-context Vivado synthesis on provisional
      `xc7z010clg400-1` using generated 16 KiB and 64 KiB profiles.
- [x] Confirm instruction and data memories infer the expected number of Block
      RAMs for both profiles.
- [x] Record paired LUT/FF/BRAM/DSP utilization in AR-015.
- [x] Record the MULDIV critical path with 25/50 MHz post-synthesis clock
      constraints for both generated RAM profiles.
- [x] Implement and verify the AR-017 restoring Radix-2 divider using the
      existing EX completion/backpressure mechanism.
- [x] Repeat paired constrained timing: both profiles pass 50 MHz with WNS
      +7.373 ns and 25 MHz with WNS +27.373 ns.
- [x] Rerun routed timing with the known XC7Z010 CLG400 package, 50 MHz board
      clock, and exact XDC. The build conservatively targets speed grade `-1`
      until the unreadable physical speed grade is independently identified.
- [x] Complete placement, routing, power estimation, DRC, BRAM initialization,
      and 25 MHz timing closure in Phase 7 for the board images.

### AR-012 — Documentation and interface cleanup

**Status:** implemented and verified on 2026-08-17.

The retirement owner, control ports, public core interface, and release-facing
documentation now describe the implemented FreeRTOS-oriented design. The
obsolete fixed-low halt output and its empty/test-only connections are removed;
completion uses committed `tohost` stores.

**Handling**

- [x] Update `README.md` after the target architecture and memory map are frozen.
- [x] Document the real pipeline stages and actual instruction/data memory
      latency rather than the conceptual five-stage labels.
- [x] Remove or explicitly deprecate `halt_o` and obsolete halt-based tests.
- [x] Make one module own retirement, CSR writes, trap entry, and commit record
      construction.
- [x] Remove unused control ports after the bus/interrupt control contract is
      stable.
- [x] Remove empty placeholder RTL files; add implemented modules when their
      owning phase starts and defines a real interface.

See [`AR012_RETIREMENT_INTERFACE_CLEANUP.md`](AR012_RETIREMENT_INTERFACE_CLEANUP.md)
for alternatives, consequences, and the fresh 47/47 ACT4 plus 22/22 smoke
preservation evidence.

### AR-013 — Regression PASS ignored the simulator process status

**Status:** fixed and verified. See
[`AR013_REGRESSION_EXIT_STATUS_GATE.md`](AR013_REGRESSION_EXIT_STATUS_GATE.md)
for the root cause, alternatives, shared classifier, focused RED/GREEN test,
and 22/22 full-regression evidence.

The runner already captured and displayed the native `vsim` exit status, but
the PASS predicate ignored it. Result classification now requires a zero
simulator exit together with the existing PASS-marker, fatal-marker, and
ModelSim error-count checks.

## Accepted data-bus contract

The Phase 1 contract states the following behavior, not just the signal names:

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

- [x] Reset `mtime` to zero.
- [x] Reset `mtimecmp` to all ones so reset does not create an immediate tick.
- [x] Increment `mtime` at an explicitly documented frequency.
- [x] Assert MTIP as a level while `mtime >= mtimecmp`.
- [x] Define RV32 high/low read and write sequencing.
- [x] Require and document the conventional safe software update sequence;
      hardware shadowing is not needed for this milestone.
- [x] Keep MTIP hardware-owned even if other writable `mip` bits are added.

## Revised execution order and current position

Steps 1–6 are complete. AR-003/AR-004 complete transaction/result ownership,
AR-019 completes centralized data decoding/default routing, and Phase 3 adds
the timer target as a registered response owner. AR-018's data and fetch fault
cases are GREEN. Remaining accepted-map software consumers and Phase 4
peripheral targets are open. AR-017's MULDIV redesign and repeated OOC timing
checkpoint are complete.

1. **Checkpoint the current working tree and archived 9/9 + 4/4 evidence.**
2. **Complete Phase 0A:** precise side-effect gating, complete bubbles, CSR
   legality/hazards, control-flow misalignment, and real instruction BRAM timing.
3. **Freeze the memory topology and map.** Update all hardware, linker, ACT4,
   and converter descriptions together.
4. **Externalize the data bus.** Implement the LSU transaction FSM, decoder,
   registered responses, access faults, and protocol assertions.
5. **Run early synthesis and close the MULDIV blocker.** BRAM inference is
   confirmed and AR-017's multi-cycle divider passes the repeated OOC timing
   checkpoint; exact-board closure remains later work.
6. **Add the machine timer interrupt.** Implement retirement-boundary entry,
   hardware MTIP, timer MMIO, WFI, and long repeated-interrupt tests. **Done.**
7. **Add startup/linker/driver infrastructure.** This should begin immediately
   after the memory map is frozen rather than waiting until every peripheral is
   complete.
8. **Implement GPIO and polling UART.** Verify each independently, then at SoC
   level.
9. **Run bare-metal simulation and FPGA sanity programs.** Prove UART, GPIO, and
   timer interrupts before adding the kernel.
10. **Integrate the pinned official FreeRTOS RISC-V port.** Port, stack/heap,
    queue, preemption, and context sentinels are GREEN in ModelSim; the extended
    run remains open. See `AR025_OFFICIAL_FREERTOS_RISCV_PORT.md`.
11. **Complete FPGA timing and physical-board validation.**

Official RV32I/RV32M ACT4 execution remains a continuous parallel track. It is
not a substitute for the directed pipeline, CSR, bus, interrupt, or peripheral
tests listed here.

## Whole-project review closure criteria

These are end-to-end project criteria, not the Phase 0A exit gate. This review
document can be considered fully handled only when:

- [ ] Every AR item is either implemented and verified or explicitly deferred
      with a reason and risk statement.
- [ ] The full directed and Python regression is reproducible from a clean
      checkout. The unified command passes on the current tree and supports
      clean-checkout ACT4 generation through `-RegenerateAct4`; a fresh-clone
      execution remains the final evidence for this checkbox.
- [ ] ACT4 configuration describes the implemented hardware and final memory
      map accurately.
- [x] Vivado reports confirm BRAM inference and non-negative routed timing at
      the selected 25 MHz clock on conservative `xc7z010clg400-1` builds.
- [x] A bare-metal timer handler survives at least 10,000 interrupts.
- [ ] FreeRTOS preempts tasks, preserves context, communicates through a queue,
      writes UART output, and controls GPIO in simulation and on the board.
