# U0 Passive UVM Toolchain Results

**Phase:** U0 passive UVM — toolchain confirmation
**Status:** Verified
**Owner:** Verification
**Last updated:** 2026-09-26
**Depends on:** [requirements](requirements.md), [verification plan](verification_plan.md)
**Related evidence:** [AR-026](../../ar/AR026_SCALABLE_UVM_VERIFICATION_ARCHITECTURE.md)

## Tested identity

- Repository HEAD before the experiment:
  `63b9cd3bc6e246056a50ff9eac2ddff832e88db5`.
- Host date/time zone: 2026-09-16, Asia/Shanghai, Windows execution environment.
- Simulator: Model Technology ModelSim SE-64 2019.2, build 2019.04,
  2019-04-17.
- Executables: `D:\Modelsim2019\win64\vsim.exe` and `vlog.exe`.
- Explicit UVM selection: precompiled `D:\Modelsim2019\uvm-1.2` plus macros
  from `D:\Modelsim2019\verilog_src\uvm-1.2\src`.
- Runtime identity: `UVM-1.2`, `QUESTA_UVM-1.2.3`, installed
  `uvm-1.2\win64\uvm_dpi.dll`.

## Regression summary

| Run | Command | Result |
|---|---|---|
| Positive | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\sim\run_uvm_toolchain_smoke.ps1` | PASS; compile 0 errors/0 warnings, runtime marker present, UVM error/fatal counts zero, native exit 0 |
| Negative oracle | `pwsh -NoProfile -ExecutionPolicy Bypass -File .\sim\run_uvm_toolchain_smoke.ps1 -NegativeGate` | Expected FAIL; nonexistent marker rejected and native runner exit 3 observed |

The first positive simulation performed optimization/DPI wrapper compilation
and completed in approximately 12 seconds of simulator elapsed time after the
one-second compile. The cached negative rerun completed in approximately four
seconds. These are diagnostics, not performance requirements.

## Focused evidence

| Requirement ID | Evidence | Result |
|---|---|---|
| REQ-U0-001 | Exact executable paths and 2019.2 version output | PASS |
| REQ-U0-002 | Built-in UVM 1.2 compile import, UVM-1.2/QUESTA_UVM-1.2.3 runtime banners, UVM 1.2 DPI load | PASS |
| REQ-U0-003 | Registered `uvm_test` compiled with 0 errors and 0 warnings | PASS |
| REQ-U0-004 | Factory created the test; `run_phase` emitted revision and exact pass marker | PASS |
| REQ-U0-005 | Checked-in runner/source plus compact [summary](evidence/toolchain_summary.txt); no UVM source copied | PASS |
| VER-U0-001 | Positive result gate returned 0 and `U0_UVM_TOOLCHAIN_RESULT: PASS` | PASS |
| VER-U0-002 | False-marker mode returned 3 and `U0_UVM_TOOLCHAIN_RESULT: FAIL` | PASS |
| VER-U0-003 | No production RTL changed; generated build output is ignored | PASS |

## Synthesis/implementation

Not applicable; no RTL is synthesized.

## Power/performance

Not applicable; no performance or power claim is made.

## Hardware/model evidence

Not applicable.

## Known limitations and confidence

- This proves technical availability only on the tested installation. It does
  not independently audit commercial-license entitlement or another host.
- The global `mtiUvm` mapping remains UVM 1.1d; the runner deliberately selects
  UVM 1.2 by explicit library and include paths.
- The runner currently describes this host's `D:\Modelsim2019` installation;
  portability can be parameterized when a second host is introduced.
- No DUT interface, passive monitor, retirement transaction, scoreboard, or
  coverage model was tested. The broader U0 passive-retirement exit gate
  remains open.
- A first attempted wrapper command used unavailable `powershell.exe`; the
  actual evidence uses the discovered PowerShell Core `pwsh` command.

## Information-classification review

- Highest class actually produced: `DATA-PUBLIC` for retained U0 material.
- Repository content retained and why it is safe: standalone test/runner,
  executable and library version identity, commands, pass/fail summary, and
  non-sensitive installation paths; no credential or entitlement token.
- External evidence IDs, safe hashes, and storage aliases: none required.
- Reclassification/incident action: none; verification owner reviewed this
  boundary on 2026-09-26.

## Exit-gate verdict

**PASS for the U0 toolchain-confirmation sub-gate.** ModelSim SE-64 2019.2 can
compile and run the installed UVM 1.2 library on this host, and the result gate
rejects a clean simulation that lacks its expected success marker. The full U0
passive retirement vertical slice is not implemented and remains open.

## Decision outcome

**GO for the toolchain-confirmation sub-gate.** This outcome permits the next
U0 step—the DUT-facing passive retirement contract, monitor, and scoreboard—to
start, but does not mark the full U0 phase complete.

- Linked research-claim disposition: none.
- Linked product-hypothesis implication: none.
- Reusable artifacts and last valid evidence: the standalone smoke source,
  checked-in runner, negative result gate, and compact toolchain summary remain
  valid for the tested host identity.
- Successor: the open passive retirement vertical slice in this U0 package.
- Re-entry condition: repeat the toolchain gate when the simulator, UVM
  library, host installation, or license path changes materially.
