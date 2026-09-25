# Research Records

**Purpose:** keep source provenance, reading priority, paper audits, and later
reproduction evidence separate from the central program plan.

**Last updated:** 2026-09-25

## What belongs here

| Artifact | Purpose | Creation rule |
| --- | --- | --- |
| [`SOURCE_REGISTRY.md`](SOURCE_REGISTRY.md) | Exact citations, canonical source links, access notes, intended use, priority, and current state | Add a row after identity and source are checked |
| [`PAPER_AUDIT_TEMPLATE.md`](PAPER_AUDIT_TEMPLATE.md) | Claim, assumption, equation, baseline, reproduction, and decision audit | Keep as the reusable template |
| `papers/<paper-id>-<short-name>.md` | One detailed audit for one active paper | Create only when screening or close reading starts |
| `../../research/reproductions/<paper-id>/` | Code, inputs, compact outputs, hashes, and commands for an active reproduction | Create only when an experiment starts |

The [central research plan](../RESEARCH_PROGRAM_PLAN.md) owns research
questions, dependencies, gates, and concise decisions. The
[TODO](../../TODO.md) owns execution status. This directory must not become a
second project-status ledger.

## Original-source boundary

The tracked record is the citation and provenance, not a copied PDF. Keep
copyrighted originals in a lawful personal library by default. When a local
copy is used, record its source URL, retrieval date, exact version, access or
license terms, local ignored location, and SHA-256 in the registry or audit.
Possession of a file does not grant redistribution rights.

Before committing any paper, dataset, model, figure, or third-party
implementation, confirm compatible redistribution terms and update
[`THIRD_PARTY_NOTICES.md`](../../THIRD_PARTY_NOTICES.md). A DOI or public web
page is not by itself permission to copy the full work into this repository.

## Source workflow

1. Register an exact source in `SOURCE_REGISTRY.md` as `Candidate` or
   `Deferred`.
2. When work begins, copy the audit template to `papers/` and change the source
   state to `Screening`.
3. Record claims and equations from the original, not from an AI summary or a
   later citation.
4. Define the local question, baseline, acceptance oracle, and failure test
   before reproduction.
5. Link retained evidence and update the central decision register only after
   the audit reaches a decision.

Do not create empty `papers/` or reproduction directories for future work.
