# AR-033 — Document Governance and Just-in-Time Context Routing

**Date:** 2026-09-25

**State:** Verified

**Scope:** repository information architecture and AI/developer workflow only;
no RTL, firmware, verification behavior, phase result, or product capability
changes

## 1. Problem

The repository accumulated accepted architecture, phase evidence, guides,
research notes, local planning scratchpads, and generated outputs over many
development conversations. The content remains useful, but several symptoms
make long-horizon human and AI work less reliable:

- the always-loaded `AGENTS.md` duplicated detailed architecture and volatile
  project status already maintained elsewhere;
- both `doc/` and `docs/` existed without a current placement rule;
- ignored root planning files combined several completed tasks;
- no committed cross-device inbox existed for raw ideas;
- mutable P0/U0 status had drifted in routing documents;
- agents could respond by reading many large documents instead of selecting a
  small task-specific context pack.

## 2. Root cause

The project had strong evidence requirements but lacked an explicit separation
between:

1. stable, always-loaded working rules;
2. routing metadata;
3. authoritative status/decisions/evidence;
4. unreviewed ideas and local scratch;
5. generated artifacts.

Consequently, useful historical material was appended to convenient files and
status was repeated in several summaries.

## 3. Options considered

### Option A — Bulk-move and rewrite all documentation

This would produce an immediately uniform tree but risks broken links, lost Git
history, interference with active UVM work, and accidental changes to evidence
semantics. Rejected for this sprint.

### Option B — Leave the tree unchanged and add more prose

This avoids migration risk but preserves over-retrieval, ambiguous placement,
and status drift. Rejected.

### Option C — Progressive governance and just-in-time routing

Keep accepted legacy guides in place, freeze their directory, define new-file
destinations, add an idea inbox, slim always-loaded instructions, route tasks
to small context packs, correct known drift, and move legacy files only when
they next receive substantial revision. Accepted.

## 4. Decision

1. `TODO.md` remains the implementation checkbox/status ledger.
2. The roadmap owns dependency order and entry gates.
3. Active phase `requirements.md` and `results.md` own declared scope and actual
   evidence.
4. The architecture log plus focused AR reports own accepted design decisions.
5. `doc/CONTEXT_ROUTER.md` owns task-to-context routing and status vocabulary;
   it owns no implementation status.
6. `AGENTS.md` contains stable policy and pointers rather than full system
   narration or mutable detailed status.
7. `notes/inbox/` is committed for cross-device raw ideas, is
   non-authoritative, and is excluded from default AI reads.
8. `docs/` is frozen to its classified accepted legacy set. New canonical
   documents use `doc/`; migration is revision-triggered rather than bulk.
9. `.planning/<task-id>/` and ignored output directories remain local context,
   never product requirements or proof.
10. A documentation-governance script checks required entry points, relative
    links, and the frozen legacy set.
11. The tightly coupled numbered AR family lives under `doc/ar/` with a compact
    discovery index. Unlike independent legacy guides, the whole family moves
    atomically so one ordered namespace is never split across two directories.

## 5. Consequences

### Benefits

- New tasks can start from a small, explicit context pack.
- Raw ideas can sync across devices without silently changing the roadmap.
- Accepted legacy guides remain valid and active UVM edits are undisturbed.
- Status vocabulary and authority conflicts have deterministic resolution.
- Future directory convergence occurs in reviewable, link-safe increments.
- Numbered AR records no longer crowd the `doc/` root, while their stable IDs
  and cross-links remain intact behind one index.

### Costs and constraints

- Contributors must triage inbox notes before treating them as work.
- A legacy guide may remain under `docs/` until a natural migration event.
- Routing and link checks become another lightweight release/documentation
  gate.
- The context router must be updated when a genuinely new task class appears.

## 6. Verification

The change is accepted when:

- required routing, inbox, policy, and AR files exist;
- every checked repository-relative Markdown link resolves;
- no unclassified file is added under frozen `docs/`;
- `git diff --check` passes;
- the P0/U0 public/index state matches retained phase results;
- ignored root planning scratchpads are preserved under an archive path;
- no RTL, firmware, testbench, UVM implementation, or phase evidence result is
  changed by the governance work.

### Actual evidence

- `& .\tools\check_doc_governance.ps1` — **PASS**: 102 scoped Markdown
  files, 510 repository-local links, all required entry points, the frozen
  `docs/` inventory, P0/U0 status guards, and the 178-line `AGENTS.md` were
  checked. The command reported three pre-existing generated root artifacts as
  warnings rather than deleting user-owned files.
- `git diff --check` — **PASS**. Git emitted line-ending conversion warnings
  for existing working-copy policy, but no whitespace error.
- `task_plan.md`, `findings.md`, and `progress.md` were moved from the repository
  root to ignored `.planning/archive/legacy-root-planning-2026-09-25/` only
  after validating the absolute paths. SHA-256 matched before and after for all
  three files. `.planning/.active_plan` remains
  `fetch_error_corner_tests`.
- The phase index now reports P0's six-scenario technical portfolio as verified
  with its physical-sign-off limitation, and U0 as partial with only its
  toolchain-confirmation sub-gate verified.
- No RTL, firmware, testbench, UVM implementation, or retained phase-result
  file was changed for AR-033, so no simulation, synthesis, or board run was
  required.

### Follow-up structural migration

After explicit user approval, the 31-file numbered AR family moved atomically
from `doc/` to indexed `doc/ar/`. A target-aware pass recalculated 239 local
link destinations in 47 Markdown files, including links inside the moved
reports. A pre-move SHA-256 manifest and ZIP backup remain in the ignored local
planning package.

The follow-up governance run checked 104 scoped Markdown files and 545 local
links and passed. `git diff --check` also passed, with only the repository's
existing LF-to-CRLF notices. Searches found no remaining explicit legacy AR
path spellings; the root/nested numbered-AR counts are 0/31.

The explicitly approved root `transcript` and
`usage_statistics_webtalk.html/.xml` generated files were deleted after exact
path validation. Root-specific `.gitignore` rules now prevent their recurrence
from polluting Git status. No other untracked artifact was deleted.
