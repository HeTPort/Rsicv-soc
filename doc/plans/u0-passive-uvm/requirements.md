# U0 Passive UVM Toolchain Requirements

**Phase:** U0 passive UVM — toolchain confirmation
**Status:** Accepted
**Owner:** Verification
**Last updated:** 2026-09-26
**Depends on:** AR-026; installed ModelSim/Questa toolchain
**Related evidence:** [AR-026](../../ar/AR026_SCALABLE_UVM_VERIFICATION_ARCHITECTURE.md), [verification plan](verification_plan.md), [results](results.md)

## Scope and user/system outcome

Prove with a minimal standalone test whether the installed simulator can
compile and execute UVM, and retain the exact version, library selection,
commands, and pass/fail evidence needed before DUT integration begins.

## Decision contract

| Field | Definition |
|---|---|
| Decision question | Can the installed, legally available ModelSim/Questa path run a reproducible minimal UVM test well enough to permit DUT-facing passive UVM integration? |
| Linked research claims | None; U0 is verification infrastructure, not evidence for a research claim. |
| Linked product hypotheses | None. |
| Current baseline/alternative | Keep the existing directed tests, SVA, and regressions without depending on UVM. |
| GO condition | Exact simulator/UVM identity is recorded, the positive smoke passes, and a deliberately invalid result is rejected. |
| PIVOT condition | The installed path fails but another legally available and supportable simulator/UVM path can be evaluated. |
| DEFER and re-entry condition | License, installation, or host access is unavailable; re-enter only when the exact executable/library path can be tested. |
| NO-GO condition | No legally available and reproducible UVM path exists for the project, so the existing verification stack remains the selected approach. |

## Information classification before work

| Field | Value |
| --- | --- |
| Anticipated data class | `DATA-PUBLIC` for the retained source, commands, versions, and sanitized toolchain results. |
| Potential confidential/restricted fields | Simulator license credentials or entitlement records; none are required in this package. |
| Repository-safe content | Test source, runner, public executable/version identity, compact output summary, and result status. |
| Approved external storage | Not required for the retained U0 evidence; any license credential remains in its designated system. |
| Classification owner and review trigger | Verification owner; repeat on simulator, library, host, license path, or evidence-content change. |

## Preconditions and assumptions

- Windows host and the simulator installation available on `PATH`.
- Only simulator-provided, legally installed UVM collateral may be used.
- The smoke test is standalone and does not compile repository RTL.

## Functional requirements

| ID | Requirement | Rationale | Verification method | Priority |
|---|---|---|---|---|
| REQ-U0-001 | Record exact `vsim` and `vlog` executable paths and versions | Avoid an ambiguous tool claim | Command output | Must |
| REQ-U0-002 | Identify the UVM version/library actually selected by the compiler and simulator | A shipped source tree alone does not prove use | Compile/runtime banner and mapped libraries | Must |
| REQ-U0-003 | Compile a minimal class derived from `uvm_test` with `uvm_component_utils` registration | Prove UVM package and macro availability | `vlog` exit and transcript | Must |
| REQ-U0-004 | Execute `run_test` and emit an exact `U0_UVM_SMOKE_PASS` marker from `run_phase` | Prove factory construction and runtime phases | `vsim -c` exit and transcript | Must |
| REQ-U0-005 | Preserve exact commands and compact logs without adding external source | Reproducibility and license boundary | Checked-in script/result summary | Must |

## Non-functional requirements

| ID | Requirement | Verification method |
|---|---|---|
| VER-U0-001 | Normal smoke returns native process exit zero and contains the exact pass marker | Runner result gate |
| VER-U0-002 | Compile/runtime errors, UVM fatal/error counts, or missing marker return nonzero | Runner result gate or deliberate negative mode |
| VER-U0-003 | No production RTL, existing regression, or DUT timing behavior changes | Git diff audit |

## Safety and failure consequences

| Hazard/failure | Consequence | Detection | Safe response | Residual risk |
|---|---|---|---|---|
| Incorrect library selected | Later tests compile against a different UVM API | Version banner and library map | Stop U0 and pin explicit library/version | Vendor packaging may differ on another host |
| PASS marker without clean UVM status | False toolchain success | Native exit plus UVM error/fatal counts | Classify as FAIL | Simulator license failure can still be host-specific |
| External source copied without review | License/provenance violation | Diff and notice audit | Do not vendor source in U0 | None for simulator-provided collateral |

## Non-goals

- No DUT, `commit_pkt_t`, or `trap_entry_t` integration.
- No UVM driver, sequencer, scoreboard, coverage model, ISS, RAL, or riscv-dv.
- No performance or portability claim beyond the tested host/tool installation.

## Acceptance and exit gate

REQ-U0-001 through REQ-U0-005 and VER-U0-001/002 pass with retained commands
and compact evidence. VER-U0-003 confirms that only U0 experiment and required
documentation files changed.

## Open questions

- Which UVM version is precompiled or supported by the installed simulator?
- Does the installed license permit command-line UVM execution?
