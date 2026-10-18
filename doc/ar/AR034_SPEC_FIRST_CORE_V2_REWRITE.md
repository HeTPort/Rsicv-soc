# AR-034 — Independent Specification-First Core V2 Rewrite

**Date:** 2026-10-16

**State:** Accepted direction; foundation documentation implemented, RTL NOT RUN

**Stage:** CV2 learning/architecture foundation

## Problem and root cause

The owner wants to understand and independently implement each module from a
specification. Accumulated AI-assisted implementation and coupled verification
make code-level cleanup alone an insufficient learning and architectural plan.
Existing tests remain useful but cannot make the existing implementation the
sole source of expected behavior for its replacement.

## Options

1. Continue behavior-preserving v1 cleanup: preserves existing gates, but does
   not meet the owner's explicit independent-rewrite objective.
2. Replace v1 files immediately: conflates reference and new implementation,
   build identity and evidence before the replacement is verified.
3. Create an independent branch and explicit v2 source/verification ownership,
   write module contracts and independent oracles before user-authored RTL.

## Decision

Use option 3 on `codex/core-v2-spec-first` from base
`e88bb3b62efa7074390bb948b96dfb1c3837a1de`. Define future v2 `rtl/`,
`verif/v2/`, `config/v2/` ownership in the active
[CV2 architecture](../plans/core-v2-foundation/architecture.md); create real
source directories only when actual work starts. Existing `src/` and runners
remain v1 reference. Do not duplicate all legacy sources into a new tree.

The user writes RTL; assistance may provide specifications, models, testbenches,
assertions and review. Each module passes specification/module/cluster gates;
core integration requires trustworthy passive events before ISS/generated ISA.
Keep normal precise retirement hart-local and trace observation passive.

The independent rewrite direction supersedes the assumption that all future
learning work must be behavior-preserving edits to v1. AR-029/031/032 remain
valid for the v1 implementation. ISA, pipeline count, native bus profile and
predictor/cache choices for v2 remain separately specified decisions.

## Consequences and risks

- Supports independent comprehension and product/research-driven boundaries.
- Retains old directed programs, regression cases and board identity without
  claiming cycle equivalence across different pipelines.
- Requires independent expected behavior, checker mutation, requirements-based
  coverage and versioned experiment identity; it costs additional model review.
- New trace/ISS/model adapters may introduce common-mode errors and must have
  negative tests. Random tests/coverage percentages alone cannot sign off a core.
- Future parameter/profile combinations need explicit supported configurations,
  tool capability checks and separate evidence.

## Actual verification

Local branch creation succeeded after approval to write Git common-directory
metadata outside the worktree. Documentation checks and exact commands are owned
by [CV2 results](../plans/core-v2-foundation/results.md). No new RTL test, formal
proof, synthesis or board run is claimed.
