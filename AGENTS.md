# AGENTS.md

Stable working rules for human and AI contributors. Detailed architecture,
status, commands, research, and evidence are loaded just in time through
[`doc/CONTEXT_ROUTER.md`](doc/CONTEXT_ROUTER.md), not duplicated here.

## 1. Start with scoped context

Before non-trivial work:

1. Read the user's exact request and inspect `git status`.
2. Use [`doc/CONTEXT_ROUTER.md`](doc/CONTEXT_ROUTER.md) to select one primary
   phase and at most one supporting track.
3. Search with `rg` before opening large documents. Start with no more than five
   focused files; expand only for a concrete dependency.
4. For files longer than 400 lines, prefer headings and line ranges instead of
   reading the entire file without a stated reason.
5. Never recursively ingest `doc/`, `docs/`, logs, generated output, or
   `notes/inbox/` by default.

Authority is divided deliberately:

- `TODO.md` — implementation checkbox/status ledger;
- `doc/ROADMAP_AND_LEARNING_PATH.md` — dependency order and gates;
- `doc/plans/<phase-id>/requirements.md` and `results.md` — phase scope and
  actual evidence;
- `doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md` plus `doc/ar/AR*.md` — accepted
  design decisions and focused evidence;
- `doc/PROJECT_KNOWLEDGE_BASE.md` — beginner-oriented current explanation;
- `doc/RESEARCH_PROGRAM_PLAN.md` plus paper audits — research decisions;
- `notes/inbox/` — unreviewed ideas, never requirements or proof.

When two documents disagree, correct the owning artifact first and update
public summaries in the same change.

## 2. Preserve user work and evidence integrity

- The worktree may contain unrelated edits. Do not overwrite, revert, move, or
  reformat them.
- Use `apply_patch` for hand edits. Use formatting/generation tools only for
  mechanical output they own.
- Do not use destructive Git or filesystem commands unless explicitly asked.
- Expected results are not evidence. Mark unexecuted results `NOT RUN`.
- Preserve exact commands, tool versions, input/hash/seed identity, native exit
  status, and limitations for reported runs.
- Keep large generated artifacts out of Git where practical; retain compact
  reports, hashes, failing seeds, and reproduction instructions.
- Do not create empty future module or phase directories.

## 3. Living documentation requirement

Architecture-changing work is incomplete until the relevant living documents
are updated in the same change:

- update `doc/PROJECT_KNOWLEDGE_BASE.md` for behavior, timing, module boundary,
  packet, build, or current-status changes;
- update `doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md` for a proposed, accepted,
  implemented, verified, deferred, or superseded decision;
- record problem, root cause, options, decision, consequences, and actual
  verification in a focused `doc/ar/AR*.md` when resolving a material problem;
- update diagrams and open risks when the data/control path changes;
- update `TODO.md` when scope, phase order, exit gates, or implementation status
  changes.

Avoid copying mutable status into many documents. Link to the owning result or
ledger instead.

## 4. Phase evidence packages

For every active substantial feature, IP block, architecture change,
verification expansion, or system experiment, create
`doc/plans/<phase-id>/` using
[`doc/PHASE_EVIDENCE_TEMPLATE.md`](doc/PHASE_EVIDENCE_TEMPLATE.md).

Maintain as applicable:

- `requirements.md` — scope, non-goals, assumptions, failure consequences, and
  measurable performance/power/safety targets;
- `architecture.md` — boundaries, interfaces, clocks/resets, CDC/RDC,
  state/timing, units/numeric formats, faults, and alternatives;
- `registers.rdl` plus generated `registers.md` — only when MMIO exists;
- `verification_plan.md` — positive, boundary, negative, fault, reset/race,
  coverage, assertion, reproducibility, and pass/fail oracles;
- `results.md` — actual regression, waveform, synthesis, timing, area, power,
  hardware/model evidence, limitations, and exit verdict.

Give requirements stable IDs and trace them into tests/assertions/results. Link
existing AR and guide evidence; do not silently duplicate or supersede it.

## 5. License and provenance boundary

- Original material is governed by the root noncommercial source-available
  `LICENSE`; do not call the repository OSI open source.
- Commercial-use requests go to `Hetport@outlook.com`.
- Never relicense `third_party/FreeRTOS-Kernel/`; retain its MIT license and
  `UPSTREAM.md` provenance.
- Before committing third-party source, models, datasets, papers, or generated
  artifacts, record upstream revision and license in
  `THIRD_PARTY_NOTICES.md` and confirm redistribution rights.
- Do not copy CoralNPU or another implementation merely to reproduce its tree.
  Reuse ideas through independently specified local contracts unless source
  reuse and notices are deliberately reviewed.
- Do not accept substantial external code/RTL contributions until written
  contribution terms preserve the project's licensing options.

## 6. Stable project facts and invariants

This repository is a small in-order RV32IM RISC-V control SoC in SystemVerilog,
simulated with ModelSim/Questa and synthesized with Vivado. It is an
experimental computing/control foundation, not a demonstrated propulsion
system.

Stable architectural boundaries:

- `src/core/riscv.sv` integrates the CPU pipeline;
- `core_ctrl.sv` owns pipeline movement, redirect priority, stall/flush/kill,
  and delayed synchronous-fetch invalidation;
- `retire_stage.sv` owns final RF/CSR effects, traps/interrupts, MRET, WFI,
  redirects, and architectural commit;
- `lsu.sv` owns the single-outstanding data transaction and load/store
  alignment;
- `rv32m_unit.sv` owns registered multiply and iterative divide arbitration;
- `soc_data_fabric.sv` owns full-address decode and registered response-owner
  selection;
- timer/UART/GPIO/RAM/default targets live outside the CPU;
- program/data memory is little-endian synchronous BRAM;
- tests complete through a committed `tohost` store (`1` is PASS; another
  nonzero value is a test-specific failure code);
- production architecture is RV32; future RV64 is a separately specified core,
  not a width macro.

For details, load only the relevant section of the
[`project knowledge base`](doc/PROJECT_KNOWLEDGE_BASE.md),
[`architecture decision log`](doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md), or
focused AR named by the context router.

## 7. Build and verification routing

All production/testbench sources are listed explicitly; do not rely on wildcard
compilation or unreviewed generated source discovery.

Common entry points:

```powershell
Set-Location sim
vsim -do run.do
vsim -c -do run_divider_protocol.do
vsim -c -do run_soc_data_fabric.do
vsim -c -do run_retire_stage.do
```

Use the relevant focused runner first, then the required smoke/ACT4/firmware/
synthesis/board gate for the changed contract. The complete command inventory
and result semantics are in `sim/regress/README.md`, the applicable phase
package, focused AR, or legacy guide routed by `doc/CONTEXT_ROUTER.md`.

Documentation-only governance changes run:

```powershell
& .\tools\check_doc_governance.ps1
git diff --check
```

Do not claim board timing closure from an unconstrained or OOC synthesis run.
Keep board clock, routed clock, power-analysis identity, and physical
measurement claims separate.

## 8. Directory placement

- New canonical engineering/research documents go under `doc/`.
- `docs/` is a frozen legacy accepted-guide set; follow `docs/README.md`.
- Cross-device raw ideas go under `notes/inbox/` and are excluded from default
  reads.
- Local agent plans go under ignored `.planning/<task-id>/`.
- Generated/local outputs go under ignored build/output/tmp paths, not the
  repository root.
- New W0/M0 research code directories are created only when their first real
  workload/model begins.
