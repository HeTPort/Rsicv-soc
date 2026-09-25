# AR-030 — Registered Blocking Multiplier

**Date:** 2026-09-24

**State:** Implemented and verified; accepted for the 95 MHz production profile

**Stage:** Post-AR-029 timing and workload-energy experiment

## Problem

The shared combinational RV32M multiplier has zero extra instruction latency
and uses four DSP48E1 cells, but the controlled exact-board 100 MHz route fails
with WNS -0.387 ns and TNS -3.637 ns. The worst path runs from an ID/EX operand
through two DSP48E1 and eleven CARRY4 cells into EX/WB. The same unconditionally
active combinational cone also toggles during non-MUL code, as observed by the
P0 spin-idle activity capture.

## Root cause

Operands, signed extension, a 33-by-33 product, high/low selection, execute
writeback selection, and the EX/WB endpoint share one cycle. There is no local
operand or result register to bound the multiplier timing/activity domain.

## Options considered

1. Keep the combinational backend: preserves CPI but retains the measured
   100 MHz failure and avoidable operand-driven switching.
2. Add arbitrary latency or register-count parameters: rejected because delay
   registers do not guarantee a cut through the arithmetic path or DSP packing.
3. Add a fixed registered blocking backend: selected and implemented.
4. Add a throughput-one pipeline: deferred because the core has one ID/EX owner,
   no tags/scoreboard, and no consumer for multiple in-flight results.
5. Use an iterative shift/add multiplier: deferred unless area or active-energy
   evidence outweighs its much larger CPI cost.

## Candidate contract

The multiplier accepts one request in `IDLE`, captures `op/lhs/rhs`, then runs
`PARTIAL -> REDUCE -> COMBINE -> RESP`. `PARTIAL` registers four independent
17-bit partial products, `REDUCE` registers two aligned 66-bit sums, and
`COMBINE` registers the final product. `RESP` holds the selected RV32 result
until accepted. It never accepts another request while busy. `kill_i` cancels
every state without a later response. Datapath registers are deliberately not
reset; the reset/kill-cleared state bit is their validity contract and permits
DSP-boundary register inference.

The existing `rv32m_unit` remains the only core-facing arithmetic facade and
continues to arbitrate the unchanged iterative divider.

## Acceptance evidence

See [`plans/p1-registered-multiplier/results.md`](../plans/p1-registered-multiplier/results.md).
The naive request/product-boundary probe failed 100 MHz at WNS -0.648 ns and
was rejected. The staged implementation removes multiplication from the worst
path. At 95 MHz it routes with WNS +0.430 ns versus the retained P0 +0.006 ns.
At 100 MHz whole-SoC WNS improves from -0.387 ns to -0.312 ns, but the new
worst path is `mtime_q` to EX/WB (14 logic levels, 72% route delay), so 100 MHz
remains an unaccepted SoC target rather than a multiplier failure.

On `p0_mix`, cycles rise 2.42% while activity dynamic power falls 6.30%; energy
per iteration falls from 220.66 nJ to 211.77 nJ (-4.03%). On `p0_idle_spin`,
dynamic power falls from 0.158 W to 0.149 W (-5.70%) and multiplier bridge
transitions fall from 4,194,296 to zero. Both power workloads reproduce at
0.0% dynamic-power difference. The staged registered backend is therefore the
production default for the current 95 MHz goal. A future 100 MHz closure phase
must address the timer/read-to-writeback path independently.
