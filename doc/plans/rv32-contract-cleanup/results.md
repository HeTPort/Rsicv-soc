# RV32 Contract Cleanup Results

**Phase:** rv32-contract-cleanup
**Status:** PASS
**Owner:** RTL verification
**Last updated:** 2026-09-24
**Depends on:** implementation working tree
**Related evidence:** [verification plan](verification_plan.md)

## Tested identity

- Branch: `codex/phase2-act4-cleanup`
- Base before changes: `18fa918`
- Tool: ModelSim SE-64 2019.2
- Date: 2026-09-24

## Results

| Gate | Result | Evidence |
|---|---|---|
| Full RTL/SoC/testbench compile | PASS | `cd sim; vsim -c -do run_compile_soc.do`; zero errors, 34 existing relaxed input-port warnings |
| Focused core/protocol/peripheral tests | PASS | divider 42 cases; RV32M 172 cases; LSU, CSR retire order, timer, fabric, UART TX/RX, GPIO, retirement, decode fetch error, and fetch-error timing all PASS |
| Directed smoke | PASS | `run_regression.ps1 -Tag smoke`; 23/23 PASS |
| Official ACT4 | PASS | existing generated manifest; `-Tag act4`; 47/47 PASS (39 RV32I, 8 RV32M) |
| Strict lint | PASS | Verilator 5.032 leaf/core/SoC scopes |
| AR-003 OOC synthesis | PASS | Vivado 2019.2, `xc7z010clg400-1`; zero errors, 32 RAMB36E1, 4 DSP48E1, LSU state=2 cells, UART=394 cells, GPIO=20 cells |
| Source audit | PASS | fake core/bus/peripheral width parameters absent; only generic RAM/divider width parameters and their instantiations remain |

## Exit verdict

PASS. REQ-RV32-001 through REQ-RV32-006, SAFE-RV32-001, and
PERF-RV32-001 have passing evidence. This OOC synthesis has no board clock/XDC
and therefore proves elaboration/resource retention, not timing closure.
