Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "regression_result.ps1")

function Assert-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

$passLookingOutput = @(
    "[TB] RESULT: PASS",
    "Errors: 0, Warnings: 0"
)

$positiveResult = Get-RegressionSimulationResult `
    -SimulationExitCode 0 `
    -SimulationOutput $passLookingOutput
Assert-Condition $positiveResult.Passed `
    "A clean simulator exit with a valid PASS transcript was not accepted"

$negativeResult = Get-RegressionSimulationResult `
    -SimulationExitCode 7 `
    -SimulationOutput $passLookingOutput

Assert-Condition $negativeResult.HasPassMarker `
    "Negative fixture must retain the PASS marker"
Assert-Condition (-not $negativeResult.HasFatal) `
    "Negative fixture must not contain a fatal marker"
Assert-Condition (-not $negativeResult.HasErrors) `
    "Negative fixture must report zero ModelSim errors"
Assert-Condition (-not $negativeResult.Passed) `
    "Nonzero simulator exit was incorrectly classified as PASS"

$missingPassResult = Get-RegressionSimulationResult `
    -SimulationExitCode 0 `
    -SimulationOutput @("Errors: 0, Warnings: 0")
Assert-Condition (-not $missingPassResult.Passed) `
    "Transcript without a PASS marker was incorrectly accepted"

$fatalResult = Get-RegressionSimulationResult `
    -SimulationExitCode 0 `
    -SimulationOutput @("[TB] RESULT: PASS", "** Fatal: forced failure", "Errors: 0")
Assert-Condition (-not $fatalResult.Passed) `
    "Transcript containing a fatal marker was incorrectly accepted"

$errorResult = Get-RegressionSimulationResult `
    -SimulationExitCode 0 `
    -SimulationOutput @("[TB] RESULT: PASS", "Errors: 2, Warnings: 0")
Assert-Condition (-not $errorResult.Passed) `
    "Transcript containing ModelSim errors was incorrectly accepted"

Write-Host "[REGRESSION-RESULT-TEST] RESULT: PASS"
