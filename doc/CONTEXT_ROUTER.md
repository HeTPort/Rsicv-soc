# Project Context Router

**Purpose:** select the smallest sufficient document and evidence set for one
task. This file is a routing map, not an additional status ledger.

**Last updated:** 2026-09-26

## 1. Authority map

When documents disagree, resolve the conflict using the owning artifact rather
than whichever text was read most recently.

| Question | Owner |
| --- | --- |
| What is checked off or next? | [`TODO.md`](../TODO.md) |
| What must precede what? | [`ROADMAP_AND_LEARNING_PATH.md`](ROADMAP_AND_LEARNING_PATH.md) |
| What does an active phase require and what actually ran? | Its `doc/plans/<phase-id>/requirements.md` and `results.md` |
| What architecture decision is accepted? | [`ARCHITECTURE_DESIGN_AND_DECISIONS.md`](ARCHITECTURE_DESIGN_AND_DECISIONS.md) plus the indexed [`ar/AR*.md`](ar/README.md) evidence |
| What is the current beginner-oriented system explanation? | [`PROJECT_KNOWLEDGE_BASE.md`](PROJECT_KNOWLEDGE_BASE.md) |
| What research direction or paper decision exists? | [`RESEARCH_PROGRAM_PLAN.md`](RESEARCH_PROGRAM_PLAN.md) plus the relevant paper audit |
| What research claim or product hypothesis is current? | The claim/hypothesis registers in [`RESEARCH_PROGRAM_PLAN.md`](RESEARCH_PROGRAM_PLAN.md) |
| What source is queued and where did it come from? | [`research/SOURCE_REGISTRY.md`](research/SOURCE_REGISTRY.md) |
| What is merely an unreviewed idea? | [`notes/inbox/`](../notes/inbox/) |
| What may be reused and under what boundary? | [`REFERENCE_INDEX.md`](REFERENCE_INDEX.md), [`THIRD_PARTY_NOTICES.md`](../THIRD_PARTY_NOTICES.md), and the root license |
| May this information be committed, shared, or uploaded? | [`INFORMATION_CLASSIFICATION_AND_HANDLING.md`](INFORMATION_CLASSIFICATION_AND_HANDLING.md) |

`README.md` is the public orientation and quick-start page. It must link to the
owners above rather than become another detailed status database.

## 2. Default task-start protocol

1. Read `AGENTS.md` and the user's exact request.
2. Use `rg` to locate the relevant TODO item, phase ID, module, interface, or
   decision ID. Do not recursively read every Markdown file.
3. Select one primary phase and at most one supporting track.
4. Load an initial context pack of no more than five focused documents/files.
5. Prefer headings and line ranges for documents longer than 400 lines.
6. Expand the pack only when a concrete missing dependency appears.
7. Before editing, inspect `git status` and preserve unrelated work.
8. After editing, update the owning document and verification evidence, not
   every document that happens to mention the topic.

The five-document limit is an initial retrieval budget, not a correctness cap.
Safety, licensing, or interface dependencies may justify additional reads.

## 3. Context recipes

### RTL bug or architectural change

Start with:

1. relevant RTL and focused test;
2. matching `ar/AR*.md` or decision entry found by `rg`;
3. relevant section of the knowledge base;
4. active phase requirements/results if one exists;
5. `SEMANTIC_SIGNAL_SPEC.md` only when naming or interface semantics matter.

Do not read the full architecture log or knowledge base unless the change spans
several subsystems.

### New feature or phase work

Start with:

1. the phase row in `TODO.md`;
2. the stage in the roadmap;
3. `doc/plans/README.md`;
4. the active phase requirements and architecture;
5. its verification plan and latest results before claiming completion.

Create a package only when the phase becomes active. Do not create empty future
trees.

### Verification/UVM work

Start with the relevant test/runner, the focused AR, and
[`../docs/verification_framework.md`](../docs/verification_framework.md).
For U0, also read the U0 phase package and AR-026. Do not load future cache,
MMU, multicore, GPU, or NPU material without a matching feature.

### Firmware/FreeRTOS work

Start with the affected source/build files, the Phase 5 guide or AR-025, the
memory-map contract, and the relevant focused regression. Load CPU internals
only when the software-visible contract depends on them.

### FPGA, timing, or power work

Start with the exact board/power phase package, build script/XDC, retained
report summary, and matching AR. Keep 25 MHz board, 95/100 MHz routes, OOC, and
physical measurements as separate identities.

### W0/M0/C0 research work

Start with one registered claim ID, the relevant section of the research plan,
the source-registry row, the active phase package when created, one bounded
decision question, and only the selected paper/model audit. The first planned
decision is `W0-D1`. Do not browse every candidate source or treat an inbox
note as a requirement.

### Release, licensing, or external reuse

Start with the root license, `LICENSE_STRATEGY.md`, `RELEASE_CHECKLIST.md`,
`THIRD_PARTY_NOTICES.md`, and the exact upstream license/version. Never infer
reuse rights from repository popularity.

## 4. Storage and handoff rules

- `notes/inbox/`: committed, cross-device, unreviewed ideas; excluded from
  default reads and limited to `DATA-PUBLIC` or explicitly approved
  `DATA-INTERNAL` content.
- `doc/research/`: tracked source provenance and active audits; full-text
  originals stay outside Git by default.
- confidential/restricted evidence: approved encrypted storage outside the
  repository; tracked documents contain only a sanitized summary, stable ID,
  safe hash, and non-secret storage alias allowed by the
  [classification policy](INFORMATION_CLASSIFICATION_AND_HANDLING.md).
- `.planning/<task-id>/`: ignored local agent plan/findings/progress; never the
  source of product requirements or proof.
- `doc/plans/<phase-id>/`: committed cross-conversation requirements and
  evidence for substantial active work.
- ignored build/output/tmp paths: large generated data; retain compact reports,
  hashes, seeds, commands, and tool versions in the phase package.
- `docs/`: frozen accepted legacy guides; see [`../docs/README.md`](../docs/README.md).

At a handoff, state the objective, scope/non-goals, exact files changed, commands
run, actual results, open risks, and the next precise action. Do not paste full
logs into a planning document when a searchable retained artifact exists.

## 5. Status vocabulary

Use these words precisely:

- `Planned`: scoped but not active.
- `Active`: implementation/research is currently producing evidence.
- `NOT RUN`: expected result only; no execution evidence.
- `Partial`: some requirements passed and named gaps remain.
- `Verified`: the declared gate passed with retained actual evidence.
- `Deferred`: intentionally postponed with a stated entry condition.
- `Superseded`: replaced by a linked newer decision/evidence set.

Keep lifecycle and outcome words separate from the status above:

- research claims: `Proposed`, `Active`, `Supported`, `Refuted`,
  `Inconclusive`, `Deferred`, or `Superseded`;
- product hypotheses: `Unvalidated`, `Testing`, `Supported`, `Refuted`,
  `Deferred`, or `Superseded`;
- phase decision outcome: `GO`, `PIVOT`, `DEFER`, or `NO-GO`.

An evidence package can be `Verified` with a `NO-GO` outcome when the declared
experiment successfully disproves the route. A `PIVOT` creates a linked
successor instead of editing the old question into a different one.

If status drift is found, correct the owning ledger/result first, then update
public summaries in the same change.
