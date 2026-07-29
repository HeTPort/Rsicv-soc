# AR-013 Regression Simulator Exit-Status Gate

## Status

**Fixed and verified on 2026-07-29.**

The ModelSim regression runner now requires the simulator process to exit with
status zero in addition to satisfying the existing transcript checks. A
dependency-free PowerShell test permanently covers the false-pass case.

## Problem

`run_regression.ps1` captured `$LASTEXITCODE` from every `vsim` process and
reported it in the summary, but did not use it to decide PASS or FAIL.

The previous predicate accepted a test when:

1. `[TB] RESULT: PASS` appeared;
2. no `** Fatal:` marker appeared; and
3. the ModelSim error summary was zero.

A simulator process could therefore return a nonzero status after producing a
PASS-looking transcript and still be classified as passing.

This was a verification-infrastructure false-pass risk, not an RTL defect. The
existing 22-test evidence remains meaningful because the checked runs also had
valid PASS markers, zero fatal/error summaries, and zero simulator exits.

## Root cause

The runner treated the native exit status as diagnostic output rather than one
of the result-authority signals. The classification logic was also embedded in
the orchestration loop, which made it inconvenient to exercise failure
combinations without launching ModelSim.

## Options considered

### Option A — Add one condition directly in the runner

This is the smallest code change, but leaves the policy embedded in a long
orchestration script and makes focused testing awkward.

### Option B — Extract and test a shared classifier

Move the existing policy into a small PowerShell function, add the exit-status
condition there, and call the same function from both the production runner and
a focused test.

This adds one helper file but ensures the test exercises the production
classification code.

### Option C — Trust only the native process status

Rejected. ModelSim/Tcl can return zero for some simulation failures depending
on how the Tcl session terminates. PASS markers, fatal markers, and the final
error count remain necessary independent evidence.

### Option D — Use persistent PASS/FAIL marker files

Rejected for this milestone. Result files require per-test cleanup and can
introduce stale-file false passes. The existing captured process output already
contains the required signals.

## Decision

Option B is implemented.

`Get-RegressionSimulationResult` is the single result classifier. A test passes
only when all four conditions hold:

```text
simulator exit status == 0
and [TB] RESULT: PASS is present
and no ** Fatal: marker is present
and the final ModelSim error count is zero
```

`run_regression.ps1` remains responsible for orchestration, logs, summaries,
and its final aggregate exit status. It calls the shared classifier for each
test.

## Negative test contract

`test_regression_result.ps1` constructs a PASS-looking transcript:

```text
[TB] RESULT: PASS
Errors: 0, Warnings: 0
```

It then classifies the transcript with simulator exit status 7. The fixture
deliberately has:

- a valid PASS marker;
- no fatal marker;
- zero ModelSim errors;
- only the nonzero native exit as the failure condition.

The test also retains positive and negative controls for the three pre-existing
transcript gates.

## RED evidence

Before the exit-status condition was added:

```powershell
Set-Location D:\Rsicv-soc\sim\regress
& 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
  -NoProfile -ExecutionPolicy Bypass `
  -File .\test_regression_result.ps1
```

Result:

```text
Nonzero simulator exit was incorrectly classified as PASS
process exit: 1
```

## GREEN evidence

After adding `SimulationExitCode -eq 0` to the shared predicate:

```text
[REGRESSION-RESULT-TEST] RESULT: PASS
process exit: 0
```

The runner discovery path also remained green:

```powershell
.\run_regression.ps1 -List
```

## Full verification

Python utilities:

```text
Ran 4 tests
OK
```

Complete directed ModelSim regression:

```text
All 22 selected tests passed.
```

Every row reported `SimulatorExit = 0`.

## Consequences

- A nonzero simulator process status is now an unconditional test failure.
- Existing transcript checks remain active as defense in depth.
- The focused test requires only Windows PowerShell; Pester is not required.
- Result-classification policy has one production owner and can be extended
  without launching RTL simulation.
- RTL, test programs, architectural commit behavior, and phase ordering are
  unchanged.

## Reusable principles

1. A displayed PASS message is evidence, not sole authority.
2. Native process status and self-checking transcript evidence should agree.
3. Test the production classifier rather than a copied expression.
4. Negative infrastructure tests should isolate one rejected condition.
5. Avoid persistent result artifacts when captured process evidence is enough.
