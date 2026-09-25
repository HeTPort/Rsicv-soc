# P1 Registered Blocking Multiplier Results

**Phase:** p1-registered-multiplier
**Status:** PASS for 95 MHz production; 100 MHz SoC clock profile remains deferred
**Last updated:** 2026-09-25

## Identity

- Working branch: `codex/phase2-act4-cleanup`
- Base commit: `18fa918`
- Worktree contains preserved unrelated user changes; exact source/report hashes
  will identify retained measurements.

## Results

| Gate | Result | Evidence |
|---|---|---|
| RED protocol/latency test | PASS | Old combinational backend failed at 46 ns because it did not enter registered state |
| Registered backend focused tests | PASS | 175 cases; all MUL variants/random/backpressure/kill/recovery; divider 42/42 |
| Smoke / ACT4 / lint | PASS | smoke 23/23; ACT4 47/47 (39 I, 8 M); Verilator leaf/core/SoC PASS |
| 95 MHz exact-board route | PASS | WNS +0.430 ns, TNS 0; 32 RAMB36, 4 DSP48E1 |
| 100 MHz exact-board route | FAIL whole-SoC gate | WNS -0.312 ns, but worst path moved to `mtime_q -> EX/WB`; multiplier is absent from worst paths |
| Routed area | REPORTED | top 3,821 LUT / 3,098 FF versus retained combinational 3,768 LUT / 2,868 FF; +53 LUT (+1.41%), +230 FF (+8.02%), DSP/BRAM unchanged |
| `p0_mix` CPI/power/energy | PASS | 346,235 cycles, 117,768 retires, CPI 2.9400; 0.119 W dynamic; 211.77 nJ/iteration |
| `p0_idle_spin` switching/power | PASS | 458,759 cycles unchanged; multiplier transitions 0; 0.149 W dynamic; 10.98 nJ/iteration |
| Power repeatability | PASS | both workloads: two independent runs, 0.0% dynamic-power difference |

## Verdict

Accept `rv32m_mul_reg` as the production default for the timing-closed 95 MHz
profile. Relative to the retained P0 combinational baseline, `p0_mix` pays
+2.42% cycles/CPI but saves 6.30% dynamic power and 4.03% energy per iteration.
Idle dynamic power/energy fall 5.70% because non-MUL traffic no longer toggles
the DSP cone. Do not claim 100 MHz SoC closure: its remaining -0.312 ns path is
timer/read-to-EX/WB and belongs to a separate architecture task.
