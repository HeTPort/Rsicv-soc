<#
.SYNOPSIS
  Run the repository's complete release-verification sequence.

.DESCRIPTION
  Runs deterministic generators/tests, focused fetch-error and SoC data-fabric
  tests, directed smoke, Phase 3 through Phase 6 regressions, and the applicable
  ACT4 manifest. The sequence stops at the first failed gate.

  By default, the command consumes build/act4/tests.json. Use -RegenerateAct4
  for a clean checkout with the pinned ACT4/WSL prerequisites installed.
  -SkipAct4 is a local preflight only and is not a complete release result.

.EXAMPLE
  .\run_release_verification.ps1

.EXAMPLE
  .\run_release_verification.ps1 -RegenerateAct4 -Act4Jobs 8

.EXAMPLE
  .\run_release_verification.ps1 -SkipAct4
#>
[CmdletBinding()]
param(
    [switch]$RegenerateAct4,
    [switch]$SkipAct4,

    [ValidateRange(1, 256)]
    [int]$Act4Jobs = 8,

    [string]$Act4Root = "",
    [string]$Act4WorkDir = "",
    [string]$WslRepoPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($RegenerateAct4 -and $SkipAct4) {
    throw "-RegenerateAct4 and -SkipAct4 cannot be used together."
}

$scriptDir = $PSScriptRoot
$simDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $simDir ".."))
$regressionScript = Join-Path $scriptDir "run_regression.ps1"
$act4BuildScript = Join-Path $scriptDir "run_act4_build.ps1"
$act4Manifest = Join-Path $repoRoot "build\act4\tests.json"
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-ReleaseStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Action
    )

    Write-Host ""
    Write-Host "=== RELEASE: $Name ==="
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $global:LASTEXITCODE = 0
    try {
        & $Action
        $exitCode = [int]$LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Step '$Name' exited with code $exitCode."
        }
    } catch {
        $timer.Stop()
        $results.Add([PSCustomObject]@{
            Step = $Name
            Status = "FAIL"
            Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
        })
        Write-Host ""
        Write-Host "Release verification stopped at '$Name'."
        $results | Format-Table Step, Status, Seconds -AutoSize
        throw
    }
    $timer.Stop()
    $results.Add([PSCustomObject]@{
        Step = $Name
        Status = "PASS"
        Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
    })
}

function Test-Act4Manifest {
    if (-not (Test-Path -LiteralPath $act4Manifest -PathType Leaf)) {
        throw "ACT4 manifest not found: $act4Manifest. Rerun with -RegenerateAct4."
    }

    $manifest = Get-Content -LiteralPath $act4Manifest -Raw | ConvertFrom-Json
    $tests = @($manifest.tests)
    $rv32i = @($tests | Where-Object {
        @($_.tags) -contains "rv32i" -and @($_.tags) -notcontains "rv32m"
    })
    $rv32m = @($tests | Where-Object {
        @($_.tags) -contains "rv32m" -and @($_.tags) -notcontains "rv32i"
    })
    $act4 = @($tests | Where-Object { @($_.tags) -contains "act4" })

    if ($tests.Count -ne 47 -or $act4.Count -ne 47 -or
        $rv32i.Count -ne 39 -or $rv32m.Count -ne 8) {
        throw "ACT4 manifest classification mismatch: total=$($tests.Count), act4=$($act4.Count), rv32i=$($rv32i.Count), rv32m=$($rv32m.Count); expected 47/47/39/8."
    }

    Write-Host "ACT4 manifest classification: 47 total, 39 RV32I, 8 RV32M."
}

Push-Location $repoRoot
try {
    Invoke-ReleaseStep "generated SoC map is current" {
        & python (Join-Path $repoRoot "tools\gen_soc_map.py") --check
    }

    Invoke-ReleaseStep "map generator unit tests" {
        & python -m unittest tools/test_gen_soc_map.py
    }

    Invoke-ReleaseStep "ELF converter and ACT4 importer unit tests" {
        Push-Location $scriptDir
        try {
            & python -m unittest test_elf_to_mem.py test_import_act4.py
        } finally {
            Pop-Location
        }
    }

    Invoke-ReleaseStep "regression result classifier" {
        & (Join-Path $scriptDir "test_regression_result.ps1")
    }

    Invoke-ReleaseStep "focused fetch-error timing" {
        Push-Location $simDir
        try {
            & vsim -c -do run_fetch_error_timing.do
        } finally {
            Pop-Location
        }
    }

    Invoke-ReleaseStep "focused SoC data-fabric protocol" {
        Push-Location $simDir
        try {
            & vsim -c -do run_soc_data_fabric.do
        } finally {
            Pop-Location
        }
    }

    Invoke-ReleaseStep "directed smoke regression" {
        & $regressionScript -Tag smoke
    }

    Invoke-ReleaseStep "Phase 3 timer and 10,000-interrupt regressions" {
        & $regressionScript `
            -Manifest (Join-Path $scriptDir "phase3_tests.json") `
            -Test soc_timer_wfi,soc_timer_10k `
            -NoCompile
    }

    Invoke-ReleaseStep "Phase 4 UART/GPIO regressions" {
        & $regressionScript `
            -Manifest (Join-Path $scriptDir "phase4_tests.json") `
            -Tag phase4 `
            -NoCompile
    }

    Invoke-ReleaseStep "Phase 5 firmware regressions" {
        & $regressionScript `
            -Manifest (Join-Path $scriptDir "phase5_tests.json") `
            -Tag phase5 `
            -NoCompile
    }

    Invoke-ReleaseStep "Phase 6 FreeRTOS regression" {
        & $regressionScript `
            -Manifest (Join-Path $scriptDir "phase6_tests.json") `
            -Tag phase6 `
            -NoCompile
    }

    if (-not $SkipAct4) {
        if ($RegenerateAct4) {
            $act4Arguments = @{
                Jobs = $Act4Jobs
            }
            if (-not [string]::IsNullOrWhiteSpace($Act4Root)) {
                $act4Arguments["Act4Root"] = $Act4Root
            }
            if (-not [string]::IsNullOrWhiteSpace($Act4WorkDir)) {
                $act4Arguments["Act4WorkDir"] = $Act4WorkDir
            }
            if (-not [string]::IsNullOrWhiteSpace($WslRepoPath)) {
                $act4Arguments["WslRepoPath"] = $WslRepoPath
            }

            Invoke-ReleaseStep "regenerate ACT4 RV32I artifacts" {
                & $act4BuildScript -Extension I @act4Arguments
            }
            Invoke-ReleaseStep "regenerate ACT4 RV32M artifacts" {
                & $act4BuildScript -Extension M @act4Arguments
            }
        }

        Invoke-ReleaseStep "ACT4 manifest classification" {
            Test-Act4Manifest
        }
        Invoke-ReleaseStep "applicable ACT4 RV32I/RV32M regression" {
            & $regressionScript `
                -Manifest $act4Manifest `
                -Tag act4 `
                -NoCompile
        }
    } else {
        Write-Warning "ACT4 was skipped; this is not a complete release-verification result."
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Release verification summary"
$results | Format-Table Step, Status, Seconds -AutoSize
if ($SkipAct4) {
    Write-Host "Local preflight passed with ACT4 explicitly skipped."
} else {
    Write-Host "All release-verification gates passed."
}
exit 0
