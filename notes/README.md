# Notes Workspace

`notes/` is the Git-synchronised capture area for rough ideas created on this
or another device. It is intentionally separate from requirements, accepted
architecture, phase evidence, and implementation status.

## Authority boundary

- Content under `notes/inbox/` is **unreviewed and non-authoritative**.
- An inbox note does not create a TODO item, phase, requirement, architecture
  decision, implementation claim, or research result.
- AI tools must not read the whole inbox by default. Read a note only when the
  user names it or a scoped search identifies it as relevant.
- Do not store secrets, credentials, personal data, copyrighted paper PDFs, or
  third-party source code here.

## Workflow

1. Capture one idea per Markdown file under `notes/inbox/`.
2. Name it `YYYY-MM-DD-short-topic.md`.
3. During review, choose exactly one disposition:
   - actionable engineering work -> `TODO.md` and, when active, a phase package;
   - research source/claim -> the research registry and a paper audit;
   - accepted design decision -> an AR document and the decision log;
   - still speculative -> leave in the inbox;
   - processed but worth retaining -> move to `notes/archive/` when that
     directory is first needed.
4. Link the promoted artifact back to the note before archiving it.

## What belongs elsewhere

| Information | Canonical location |
| --- | --- |
| Implementation checkbox/status | `TODO.md` |
| Dependency order and entry gates | `doc/ROADMAP_AND_LEARNING_PATH.md` |
| Active phase requirements/evidence | `doc/plans/<phase-id>/` |
| Scientific claim/reproduction decision | `doc/RESEARCH_PROGRAM_PLAN.md` and `doc/research/` |
| Accepted architecture decision | `doc/ARCHITECTURE_DESIGN_AND_DECISIONS.md` and `doc/ar/AR*.md` |
| Generated/local scratch output | ignored build, output, `tmp/`, or `.planning/` paths |
