# Release Readiness Checklist

**Status:** planning baseline. This file does not authorize a commit, push,
branch switch, merge, release, or GitHub default-branch change.

Use this checklist before proposing integration into `main` or publishing a
tagged release.

## 1. Scope and identity

- [ ] Release purpose, included phases, non-goals, and known limitations are
      explicit.
- [ ] Exact commit/tree, branch, configuration, tool versions, FPGA part, and
      clock constraints are recorded.
- [ ] Generated files pass stale checks and their source is identified.
- [ ] Worktree contains no accidental logs, credentials, generated caches, or
      unrelated user files.

## 2. Requirements and architecture

- [ ] Active phase package follows
      [`PHASE_EVIDENCE_TEMPLATE.md`](PHASE_EVIDENCE_TEMPLATE.md).
- [ ] `TODO.md`, roadmap, knowledge base, architecture decisions, diagrams, and
      risk table agree.
- [ ] Each external interface has owner, timing, ordering, reset, error, and
      safe-state semantics.
- [ ] Product/flight claims are not inferred from simulation or FPGA evidence.

## 3. Verification

- [ ] Focused tests for every changed contract pass.
- [ ] Deliberate mismatch/negative infrastructure test fails correctly.
- [ ] Full directed smoke remains green.
- [ ] Applicable ACT4 tests remain green and unsupported/unexecuted cases are
      explicit.
- [ ] UVM/ISS/random/coverage claims identify exactly which layer ran.
- [ ] Fault, timeout, reset, interrupt race, and recovery behavior are tested
      when applicable.
- [ ] Native tool exit status and transcript/error gates agree.
- [ ] Commands, manifests, seeds, runtimes, and compact logs are retained.

## 4. Synthesis, timing, power, and hardware

- [ ] Synthesis and implementation use the intended part and constraints.
- [ ] Utilization, WNS/TNS, DRC, clocks, BRAM/DSP, and critical path are
      recorded.
- [ ] Power claims identify workload, activity source/window, clock, tool,
      assumptions, and comparison baseline.
- [ ] Bitstream/binary hashes and build identity are recorded.
- [ ] Hardware runs record wiring/instruments, duration, expected observations,
      failures/resets, and retained evidence.
- [ ] Speed-grade or board uncertainties remain visible rather than being
      silently assumed.

## 5. Software and reproducibility

- [ ] Firmware/compiler/ABI/linker/map versions match the hardware contract.
- [ ] From-clean commands reproduce software images, simulation, and FPGA
      artifacts.
- [ ] Memory/stack/heap bounds and failure hooks are enabled where relevant.
- [ ] Public examples use safe, low-energy defaults and document external
      hardware assumptions.

## 6. License and provenance

- [ ] A deliberate project license covers original code/RTL and states its
      scope.
- [ ] README/release metadata says source-available/noncommercial rather than
      OSI open source and includes the commercial contact.
- [ ] Documentation/media license is explicit if different.
- [ ] Every third-party dependency records upstream URL, version/commit,
      license, imported files, and modifications.
- [ ] Required license texts/notices/source offers are included.
- [ ] No copied code, image, datasheet content, AI-generated asset, or model is
      treated as original without provenance review.
- [ ] Custom-license enforceability plus patent/trademark/export/safety issues
      are professionally reviewed when commercially material.
- [ ] Substantial contributions have written terms that preserve public and
      commercial licensing authority.

## 7. Integration into `main` — later, explicit action

- [ ] Compare the development branch with current `origin/main`.
- [ ] Rebase/merge strategy is reviewed without discarding user work.
- [ ] Integration PR contains a concise change/evidence/risk summary.
- [ ] Required checks pass on the actual integration commit.
- [ ] Reviewer verifies no evidence or provenance was lost.
- [ ] Merge occurs before any default-branch setting change is considered.
- [ ] Tag/release notes/checksums are created only after the merge is verified.
- [ ] Rollback or superseding-release procedure is documented.

## 8. Current task boundary

As of 2026-09-07, this checklist and related planning documents are being
created on `codex/phase2-act4-cleanup`. `origin/main` remains the default branch.
No default-branch, commit, push, merge, or release action is part of this task.
