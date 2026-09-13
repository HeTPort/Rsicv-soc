# RTL QoR and RV32M Abstraction Verification Plan

**Status:** Executed for the initial vertical slice

| Requirement | Verification |
|---|---|
| RQA-REQ-001 | Directed smoke, ACT4 RV32M, and relevant Phase 6 regressions. |
| RQA-REQ-002 | Focused request acceptance and held-request checks. |
| RQA-REQ-003 | Focused response-backpressure stability check. |
| RQA-REQ-004 | Kill during divide, no-response window, then clean restart. |
| RQA-REQ-005 | Assertions against accepting a second divide while busy/holding. |
| RQA-REQ-006 | RTL inspection plus synthesis DSP/cell report. |
| RQA-REQ-007 | Existing divider test and focused facade reference comparisons. |
| RQA-REQ-008 | Production file-list compile/lint command. |
| RQA-REQ-009 | Same-script before/after synthesis and timing comparison. |

Focused arithmetic cases include zero, one, all ones, minimum signed integer,
signed overflow, divide by zero, mixed-sign multiplication, and randomized
comparisons for all eight RV32M operations.

Pass/fail requires a zero simulator exit, an explicit test PASS marker, and no
fatal/error summary. Expected results are not evidence until the command is
recorded in `results.md`.
