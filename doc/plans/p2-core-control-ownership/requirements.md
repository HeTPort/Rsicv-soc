# P2 Core Control Ownership Requirements

**Phase:** p2-core-control-ownership
**Status:** Verified
**Owner:** RTL architecture and verification
**Last updated:** 2026-09-25
**Depends on:** AR-003, AR-008, AR-018, AR-029, AR-030
**Related evidence:** [AR-031](../../ar/AR031_CORE_CONTROL_OWNERSHIP.md)

## Scope and outcome

Make `core_ctrl` the single owner of redirect priority and PC/pipeline movement
while preserving precise retirement and the LSU/RV32M protocol boundaries.

## Functional requirements

| ID | Requirement | Verification | Priority |
|---|---|---|---|
| REQ-CTRL-001 | Accept typed EX and retirement redirect candidates and select retirement over EX | Focused simultaneous-candidate test | Must |
| REQ-CTRL-002 | Own PC hold/fetch request, IF/ID and ID/EX hold/flush, RAW bubble insertion, and delayed synchronous-fetch invalidation | Focused control matrix and fetch timing test | Must |
| REQ-CTRL-003 | Convert retirement redirect or WFI entry into one younger-pipeline kill and convert EX exception facts into functional-unit kill | Focused kill matrix and core assertions | Must |
| REQ-CTRL-004 | Make retirement select MRET redirect and CSR restoration at the same architectural boundary using a packet-captured target | Retirement and end-to-end MRET tests | Must |
| SAFE-CTRL-001 | A younger EX redirect cannot override an older retirement redirect or survive its kill | Simultaneous redirect test and assertions | Must |
| SAFE-CTRL-002 | EX wait holds the owning ID/EX packet and inserts no RAW bubble until the owner can advance | Focused wait/hazard overlap test and LSU/RV32M regressions | Must |
| SAFE-CTRL-003 | LSU and RV32M retain all local FSM/handshake ownership; no wait signal may depend combinationally on kill | Structural review, lint, protocol tests | Must |
| PERF-CTRL-001 | Preserve ordinary branch/load/RV32M cycle behavior; report MRET timing change and relevant workload cycles | Fixed-work regression comparison | Must |
| PERF-CTRL-002 | Record post-route WNS/TNS and LUT/FF/BRAM/DSP delta against the accepted AR-030 95 MHz build | Same part/XDC route | Must |
| PERF-CTRL-003 | Record activity-based power delta on at least `p0_mix`; treat sub-resolution differences as neutral | Matching SAIF/route flow | Should |

## Preconditions and assumptions

- One core clock, active-low asynchronous reset, no new CDC/RDC crossing.
- Synchronous instruction memory has one-cycle response latency.
- EX/WB has no downstream backpressure consumer and advances every cycle.
- Production scalar and address widths remain fixed RV32.

## Safety and failure consequences

| Failure | Consequence | Detection | Safe response |
|---|---|---|---|
| Wrong redirect priority | Younger path executes after an older trap/interrupt | Candidate-priority assertion/test | Retirement redirect wins and younger packets are killed |
| MRET PC/CSR split | PC can move before privilege restoration owns the boundary | Retirement MRET test | Capture target in EX/WB and issue redirect with MRET command |
| Missing delayed fetch kill | Stale synchronous response enters IF/ID | Fetch timing test | One registered invalidation after redirect/WFI entry |
| Kill/wait combinational loop | Unstable control or failed timing | Lint/synthesis and structural assertion review | Wait remains independent of kill |

## Non-goals

- Forwarding, scoreboarding, out-of-order issue, branch prediction, or a deeper pipeline.
- Moving branch arithmetic, CSR/interrupt policy, LSU/RV32M FSMs, or bus state into `core_ctrl`.
- Inventing EX/WB backpressure before a real consumer exists.
- Claiming physical-board or ASIC power from Vivado estimates.

## Acceptance gate

All Must requirements pass focused tests, smoke, ACT4, lint, and 95 MHz exact
board routing. Any cycle, area, timing, or power delta is reported from actual
matching evidence; expected values are not evidence.

**Verdict:** met. See [`results.md`](results.md).
