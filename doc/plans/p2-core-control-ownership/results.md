# P2 Core Control Ownership Results

**Phase:** p2-core-control-ownership
**Status:** Verified
**Owner:** RTL architecture and verification
**Last updated:** 2026-09-25
**Depends on:** accepted requirements and architecture
**Related evidence:** [AR-031](../../AR031_CORE_CONTROL_OWNERSHIP.md)

## Tested identity

- Working branch: `codex/phase2-act4-cleanup`
- Worktree contains preserved unrelated user changes.
- ModelSim/Questa focused, protocol, smoke, and ACT4 regressions use the
  repository scripts and manifests.
- Verilator 5.032 layered lint passes for leaf, core, and SoC scopes.
- Exact-board implementation uses Vivado 2019.2, `xc7z010clg400-1`, the
  production ZYNQ MINI REVB hierarchy/XDC, and the `p0_mix` image.

## Results

| Gate | Result | Evidence |
|---|---|---|
| Focused RED/GREEN control test | PASS | Old RTL fails on missing `pipe_ctrl_t`; new `tb_core_ctrl` passes all 10 priority/hazard/wait/kill cases |
| Retirement/MRET and fetch timing | PASS | Retirement MRET test and CSR ordering pass; all three fetch timing scenarios pass at 980 ns |
| LSU/RV32M/divider preservation | PASS | LSU protocol PASS; RV32M 175/175; divider 42/42 |
| Smoke / ACT4 / lint | PASS | Smoke 23/23; ACT4 47/47 (39 RV32I + 8 RV32M); leaf/core/SoC lint PASS |
| Exact 95 MHz route | PASS | WNS +0.078 ns; 3,942 LUT, 3,096 FF, 32 RAMB36, 4 DSP; bitstream generated |
| Exact 100 MHz route | PASS | WNS +0.098 ns; 3,952 LUT, 3,096 FF, 32 RAMB36, 4 DSP; bitstream generated |
| `p0_mix` cycles/power | PASS, neutral | 346,235 cycles and 117,768 retired unchanged; two reviewed runs both report 0.119 W dynamic, 0.212 W total, 0.0% repeatability delta |
| WFI/MRET cycle check | PASS | 64-wake workload is 274,901 cycles versus 274,900 before P2: +1 cycle for the whole measured window, retired count unchanged at 6,867 |

## QoR interpretation

Against the accepted AR-030 95 MHz build, P2 adds 121 LUT (+3.17%), removes
two FF, and changes neither BRAM nor DSP count. The 95 MHz worst path is now an
ID/EX operand through branch/redirect selection to ID/EX flush/enable: 10.275 ns,
12 logic levels, about 73% routing. Centralization therefore has a real control
fanout/routing cost; it is not a timing optimization.

The exact current 100 MHz build closes at +0.098 ns, improving on AR-030's
-0.312 ns build. Its 9.594 ns worst data path is also operand -> redirect ->
ID/EX enable. This is evidence for this exact route, not a guarantee over place
and route seeds, device speed grades, voltage/temperature, or board operation.

At 95 MHz, `p0_mix` energy remains 211.77 nJ/iteration at the report's 1 mW
resolution. These are reviewed post-route Vivado estimates, not board-rail or
ASIC measurements.

## Exit verdict

PASS. All Must requirements and the declared timing/power evidence gates pass.
The change is accepted because it repairs ownership and MRET atomicity while
retaining the current performance target. A future deeper/faster pipeline must
revisit the same-cycle redirect-to-flush path rather than extending this cone.
