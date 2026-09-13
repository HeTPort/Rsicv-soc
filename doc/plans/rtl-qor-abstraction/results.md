# RTL QoR and RV32M Abstraction Results

**Status:** Initial vertical slice complete; activity-based power comparison deferred

## Baseline

| Check | Result |
|---|---|
| Focused Radix-2 divider protocol | PASS, 42 cases, ModelSim 2019.2, 2026-09-13 |
| RV32M facade test | PASS, 172 directed/random/protocol cases, Questa 2019.2 |
| Directed smoke | PASS, 23/23 |
| ACT4 | PASS, all 8 RV32M cases |
| Phase 6 | PASS, normal run (500,000-cycle timeout) and soak (15,000,000-cycle timeout) |
| Layered production RTL lint | PASS, leaf/core/full SoC, Verilator 5.032 |
| AR-003 OOC synthesis | PASS, `xc7z010clg400-1`, 4 DSP48E1, 32 RAMB36E1, 0 errors/critical warnings |
| Exact-board implementation | PASS, 25 MHz, routed WNS +17.517 ns, TNS 0, 0 failed nets, 0 blocking DRC violations, bitstream generated |
| Exact-board 100 MHz experiment | FAIL timing gate as expected: WNS -0.387 ns, TNS -3.637 ns, 30 failing endpoints; route complete, no bitstream emitted |
| Interface cleanup | PASS: 14 observation/debug outputs plus the MRET alias removed; consumers migrated |
| Accepted activity-based power comparison | NOT RUN; existing P0 mapping remains insufficient |

The prior AR-017 OOC implementation recorded 12 DSP48E1 cells. The new OOC
result records 4 on the same device part, but this is a resource-mapping
comparison rather than a same-run routed timing or power comparison. The exact
board build proves comfortable closure at the current 25 MHz constraint; it
does not establish maximum frequency.

At 100 MHz, the worst path is ID/EX operand bit 1 to EX/WB result bit 31. Its
10.183 ns data delay comprises 8.329 ns logic and 1.854 ns routing across
2 DSP48E1, 11 CARRY4, 1 LUT2, and 1 LUT6. The 100 MHz build retained 4 DSP48E1
and 32 RAMB36E1 cells. This triggers registered-backend development but does
not accept an unverified CPI change.

## Commands and retained evidence

- `vsim -c -do run_rv32m_unit.do`
- `vsim -c -do run_divider_protocol.do`
- `run_regression.ps1 -Tag smoke`
- `run_regression.ps1 -Test rv32im` and the seven remaining RV32M ACT4 cases
- `run_regression.ps1 -Test firmware_freertos_demo`
- `run_regression.ps1 -Manifest phase6_tests.json -Test firmware_freertos_soak`
- `sim/lint/run_lint.ps1 -Scope leaf,core,soc`
- `sim/synth/check_riscv_soc_ar003.tcl`
- `fpga/zynq_mini_revb/build.tcl hello`

The exact-board metadata is retained in the ignored build tree at
`build/zynq_mini_revb/hello/build_metadata.txt`; compact architectural results
are recorded here because large generated implementation products are not
committed.

## Exit verdict

RQA-REQ-001 through RQA-REQ-008 pass for this slice. RQA-REQ-009 passes for
the exact-board post-change evidence and resource accounting; a controlled
before/after routed timing and accepted workload-power comparison remains
deferred. The registered multiplier gate did not trigger at 25 MHz, but the
failed 100 MHz experiment now triggers registered-backend development. The
shared combinational backend remains selected until that latency-changing
implementation passes protocol, ISA, performance, and timing verification.

## Tooling note

The planning skill's preferred `.planning/rtl_qor_abstraction/` location is
read-only in this workspace, and the tracked root planning files describe an
unrelated FreeRTOS task. To avoid overwriting unrelated work, this required
phase evidence package is the durable implementation record.

## Errors

- Initial creation under `.planning/rtl_qor_abstraction/` failed with access
  denied. Work continued under this repository-mandated phase directory.
- The first post-change compile used ``default_nettype none`` in the new
  modules. Questa 2019.2 classified ANSI `input logic` ports as lacking an
  explicit net type under this project configuration. The new files were
  returned to the repository's portable ``default_nettype wire`` convention;
  the next compile and `rv32im` regression passed. A later targeted rollout
  restored ``default_nettype none`` in the modified ownership-boundary files
  by declaring ANSI input ports as explicit nets; strict lint then passed.
- The first WSL lint launcher attempted to pass a Windows path directly to
  `wslpath`, which failed before lint ran. The launcher now converts validated
  drive-letter paths deterministically to `/mnt/<drive>/...` form.
- The first core-level lint identified a combinational loop through
  `ex_wait -> interrupt selection -> pipe_kill -> kill_i -> rsp_valid ->
  ex_wait`. The facade now exposes a separate loop-free `wait_o` ownership
  signal that deliberately remains independent of `kill_i`, while the public
  response remains suppressed on kill.
- The first smoke run after changing RAM disabled-read behavior exposed stale
  held RAM data on store responses (`EX/WB raw memory data does not match its
  response`). The physical RAM now holds its native output, while
  `core_bus_data_ram` normalizes write/error response data to zero at the
  protocol boundary. This preserves the prior bus contract without adding
  logic to the BRAM read process.
- The first exact-board Vivado invocation ran from the repository root, where
  the sandbox prevented creation of transient `.Xil` and log files. Rerunning
  the unchanged build script from `sim/synth` kept transients in a writable
  location and completed synthesis, route, DRC, and bitstream generation.
- A final in-sandbox WSL lint launch was denied while creating the WSL process.
  The approved identical lint command then passed all three scopes.
