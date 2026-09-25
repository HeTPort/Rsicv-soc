# P3 Semantic Cleanup Requirements

**Phase:** p3-semantic-cleanup
**Status:** Verified
**Owner:** RTL architecture and verification
**Last updated:** 2026-09-25
**Depends on:** AR-029, AR-030, AR-031
**Related evidence:** [AR-032](../../AR032_P3_SEMANTIC_CODE_CLEANUP.md)

## Requirements

| ID | Requirement | Verification |
|---|---|---|
| REQ-CLEAN-001 | Reserve `_i/_o` for module ports in the selected decode/execute slice | Structural naming audit |
| REQ-CLEAN-002 | Build ID/EX and EX/WB packets from their canonical bubble before setting meaningful fields | Review plus canonical-bubble assertions/regressions |
| SAFE-CLEAN-001 | Preserve fail-closed fetch-error replacement and all illegal/trap precedence | Fetch-error and smoke regressions |
| SAFE-CLEAN-002 | Preserve branch/jump/MRET, CSR, memory, and RV32M timing and effects | Focused/protocol/ACT4 regressions |
| SAFE-CLEAN-003 | Do not change external core/SoC interfaces, stage count, or functional-unit ownership | Interface diff and architecture review |
| QUAL-CLEAN-001 | Do not add broad lint waivers; remove only waivers made obsolete by the cleanup | Layered lint |

## Non-goals

No ALU/immediate/alignment extraction, forwarding, new packet fields, latency
change, floorplanning, Pblock, fixed route, or new parameterization.

## Acceptance gate

Focused decode/fetch and retirement/control tests, protocol tests, smoke 23/23,
ACT4 47/47, and layered lint pass with no architecture-visible cycle change.

**Verdict:** all declared gates pass. No interface or cycle contract changed;
the phase is closed by the evidence in `results.md`.
