# P3 Semantic Cleanup Verification Plan

**Phase:** p3-semantic-cleanup
**Status:** Complete
**Owner:** RTL verification
**Last updated:** 2026-09-25

| Requirement | Evidence | Status |
|---|---|---|
| REQ-CLEAN-001 | Structural search of local declarations | PASS |
| REQ-CLEAN-002 | RTL review, canonical-bubble regressions | PASS |
| SAFE-CLEAN-001 | decode fetch-error and 3-scenario fetch timing tests | PASS |
| SAFE-CLEAN-002 | core control, retirement/CSR, LSU, RV32M/divider, smoke, ACT4 | PASS |
| SAFE-CLEAN-003 | Port-list review and full hierarchy compile | PASS |
| QUAL-CLEAN-001 | Verilator 5.032 leaf/core/SoC lint | PASS |

There is no MMIO in this phase; `registers.rdl` is intentionally omitted.
