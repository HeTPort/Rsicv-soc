# AR-031 — Core Control Ownership Consolidation

**Date:** 2026-09-25
**State:** Implemented and verified
**Stage:** P2 control ownership

## Problem and root cause

`core_ctrl` already generates most holds and flushes, but policy is still split:
`riscv.sv` selects redirect priority, derives fetch request and EX kill, and
`execute.sv` emits both a redirect and a redundant flush request. More
importantly, EX redirects MRET before retirement applies its CSR restoration.
The implementation therefore disagrees with the semantic rule assigning
architectural MRET selection to retirement and pipeline movement to control.

## Decision

Use typed EX/retirement redirect candidates. Make `core_ctrl` select the older
retirement candidate and emit one `pipe_ctrl_t` movement decision. Capture the
MRET target in EX/WB so retirement emits MRET redirect and CSR restoration at
one boundary. Keep branch arithmetic, interrupt eligibility, LSU/RV32M FSMs,
and EX/WB completion payload assembly with their present owners.

## Consequences and evidence

The design gains one reviewable priority point and removes contradictory flush,
fetch, kill, and MRET policy from composition/arithmetic modules. MRET redirect
moves to its retirement boundary. The 64-wake workload changes by only one
cycle across the whole measurement window, while `p0_mix` cycles are identical.

The implementation adds a typed `pipe_ctrl_t`; EX and retirement emit typed
redirect candidates; `core_ctrl` selects retirement over EX and owns fetch,
hold, flush, delayed-fetch invalidation, pipeline kill, and EX-unit kill.
LSU/RV32M FSMs and CSR/trap policy remain with their semantic owners.

Focused and system verification passes: core-control 10 cases, retirement/CSR,
fetch timing, LSU, RV32M 175 cases, divider 42 cases, smoke 23/23, ACT4 47/47,
10,000 interrupts/MRETs, and layered lint. The exact 95 MHz route closes at
+0.078 ns and the exact 100 MHz route at +0.098 ns. Against the P1 95 MHz
baseline the design uses +121 LUT, -2 FF, unchanged 32 RAMB36 and 4 DSP.
Two `p0_mix` runs are unchanged at 0.119 W dynamic and 211.77 nJ/iteration at
report resolution. The new worst path crosses operand/branch/redirect/ID-EX
control, so the area and fanout cost is explicit and must be reconsidered for
a deeper or faster pipeline.

Full commands, identities, limitations, and QoR tables are recorded in
[`plans/p2-core-control-ownership/results.md`](../plans/p2-core-control-ownership/results.md).
