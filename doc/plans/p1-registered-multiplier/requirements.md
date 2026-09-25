# P1 Registered Blocking Multiplier Requirements

**Phase:** p1-registered-multiplier
**Status:** Complete for the 95 MHz production profile; 100 MHz SoC closure deferred
**Owner:** RTL architecture and verification
**Last updated:** 2026-09-24
**Depends on:** AR-027, AR-028, AR-029, verified P0 workload framework
**Related evidence:** [AR-030](../../AR030_REGISTERED_BLOCKING_MULTIPLIER.md)

## Scope

Replace the zero-extra-latency combinational multiply path with a fixed-latency,
single-outstanding, registered blocking backend behind `rv32m_unit`, then make
an evidence-backed production decision.

## Requirements

| ID | Requirement | Verification | Priority |
|---|---|---|---|
| REQ-MUL-001 | Accept `MUL/MULH/MULHSU/MULHU` exactly once only when request valid and ready | Protocol assertions and focused test | Must |
| REQ-MUL-002 | Capture operation and operands, execute through fixed PARTIAL/REDUCE/COMBINE register stages, then return the correct RV32 result; EX/WB advances four cycles after acceptance | Directed/random reference comparison and latency assertion | Must |
| REQ-MUL-003 | Permit only one outstanding multiply and reject restart while any arithmetic/RESP state owns the backend | Focused overlap test/assertion | Must |
| REQ-MUL-004 | Hold `rsp_valid` and payload stable for arbitrary response backpressure | Focused backpressure test/assertion | Must |
| SAFE-MUL-001 | Reset or kill from any active state produces no response or architectural write | Reset/kill tests and pipeline integration | Must |
| SAFE-MUL-002 | Divider arithmetic, latency, backpressure, and kill behavior remain unchanged | Existing divider and RV32M tests | Must |
| SAFE-MUL-003 | No incomplete multiply enters EX/WB and retirement observes one result | Core assertions, smoke, ACT4 | Must |
| PERF-MUL-001 | Candidate removes multiplication from the controlled 100 MHz worst path; record whole-SoC slack and reject the 100 MHz clock profile if another path still fails | Same part/XDC route and critical-path report | Must |
| PERF-MUL-002 | Record LUT/FF/BRAM/DSP and critical-path differences against the retained combinational baseline | Routed reports | Must |
| PERF-MUL-003 | Record fixed-work cycles, retirements, CPI, activity dynamic power, and energy/work for `p0_mix` | Matching ModelSim/SAIF/route flow | Must |
| PERF-MUL-004 | Record non-MUL switching/power effect for `p0_idle_spin` | Matching ModelSim/SAIF/route flow | Should |

## Non-goals

- Multiple in-flight multiply requests, throughput-one issue, tags, or scoreboard.
- Changes to divider radix/latency, scalar XLEN, ISA results, memory map, or ABI.
- NPU/MAC integration or arbitrary latency/register-count parameterization.
- Claims of board-rail, ASIC, battery, or physical silicon power.

## Exit gate

All Must requirements pass. The registered backend may be the production
default at the timing-closed 95 MHz profile when architectural regressions and
the energy/CPI tradeoff pass. A 100 MHz bitstream still requires nonnegative
whole-SoC routed slack. Expected values never count as evidence.
