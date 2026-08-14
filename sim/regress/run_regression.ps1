<#
.SYNOPSIS
  Compile the RTL once and run manifest-selected ModelSim regressions.

.EXAMPLE
  .\run_regression.ps1
  .\run_regression.ps1 -Tag trap
  .\run_regression.ps1 -Test ebreak,mret -Trace
  .\run_regression.ps1 -List
#>
[CmdletBinding()]
param(
    [string[]]$Tag = @("smoke"),
    [string[]]$Test = @(),
    [switch]$List,
    [switch]$Trace,
    [switch]$DumpWaves,
    [switch]$NoCompile,
    [string]$Manifest = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "regression_result.ps1")

# Accept either PowerShell arrays (-Test ebreak,mret) or comma-separated text
# forwarded by another shell (-Test "ebreak,mret").
$Tag = @($Tag | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })
$Test = @($Test | ForEach-Object { $_ -split "," } | Where-Object { $_ -ne "" })

$scriptDir = $PSScriptRoot
$simDir = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $simDir ".."))

if ([string]::IsNullOrWhiteSpace($Manifest)) {
    $manifestPath = Join-Path $scriptDir "tests.json"
} else {
    # Resolve relative paths against PowerShell's current location, not .NET's
    # process-wide current directory, which may lag behind Set-Location.
    if ([System.IO.Path]::IsPathRooted($Manifest)) {
        $manifestPath = $Manifest
    } else {
        $manifestPath = Join-Path $PWD.Path $Manifest
    }
    $manifestPath = [System.IO.Path]::GetFullPath($manifestPath)
}

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Regression manifest not found: $manifestPath"
}

$manifestData = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifestData.schema_version -ne 1) {
    throw "Unsupported manifest schema_version: $($manifestData.schema_version)"
}

function Get-RegressionSimulationTop {
    param(
        [Parameter(Mandatory = $true)]
        [object]$TestCase,

        [Parameter(Mandatory = $true)]
        [object]$Defaults
    )

    if ($null -ne $TestCase.PSObject.Properties["top"] -and
        -not [string]::IsNullOrWhiteSpace([string]$TestCase.top)) {
        return [string]$TestCase.top
    }
    if ($null -ne $Defaults.PSObject.Properties["top"] -and
        -not [string]::IsNullOrWhiteSpace([string]$Defaults.top)) {
        return [string]$Defaults.top
    }
    return "work.tb_riscv_core"
}

$allTests = @($manifestData.tests)
if ($List) {
    $allTests |
        Select-Object name,
            @{Name="top"; Expression={
                Get-RegressionSimulationTop -TestCase $_ -Defaults $manifestData.defaults
            }},
            image, data_image, timeout_cycles, data_error_addr,
            @{Name="tags"; Expression={ $_.tags -join "," }} |
        Format-Table -AutoSize
    exit 0
}

if ($Test.Count -gt 0) {
    $selectedTests = @($allTests | Where-Object { $Test -contains $_.name })
    $unknownTests = @($Test | Where-Object { $_ -notin $allTests.name })
    if ($unknownTests.Count -gt 0) {
        throw "Unknown test name(s): $($unknownTests -join ', ')"
    }
} else {
    $selectedTests = @($allTests | Where-Object {
        $testTags = @($_.tags)
        @($Tag | Where-Object { $_ -in $testTags }).Count -gt 0
    })
}

if ($selectedTests.Count -eq 0) {
    throw "No tests selected. Use -List to inspect available names and tags."
}

foreach ($tool in @("vlib", "vmap", "vlog", "vsim")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required ModelSim tool '$tool' was not found in PATH."
    }
}

$buildDir = Join-Path $simDir "build\regression"
$logDir = Join-Path $simDir "logs\regression"
$workLibrary = Join-Path $buildDir "work"
New-Item -ItemType Directory -Force -Path $buildDir, $logDir | Out-Null

Push-Location $buildDir
try {
    if (-not $NoCompile) {
        if (-not (Test-Path -LiteralPath $workLibrary)) {
            $vlibOutput = & vlib $workLibrary 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "vlib failed:`n$($vlibOutput -join [Environment]::NewLine)"
            }
        }

        $fileListPath = Join-Path $simDir "filelist.f"
        $sourceFiles = @(
            Get-Content -LiteralPath $fileListPath |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
                ForEach-Object {
                    [System.IO.Path]::GetFullPath((Join-Path $simDir $_))
                }
        )

        $compileLog = Join-Path $logDir "compile.log"
        $vlogArgs = @("-sv", "-work", $workLibrary) + $sourceFiles
        $compileOutput = & vlog @vlogArgs 2>&1
        $compileExitCode = $LASTEXITCODE
        $compileOutput | Set-Content -LiteralPath $compileLog

        $compileHasErrors = [bool]($compileOutput -match "Errors:\s*[1-9][0-9]*")
        if ($compileExitCode -ne 0 -or $compileHasErrors) {
            throw "RTL compilation failed. See $compileLog"
        }
    } elseif (-not (Test-Path -LiteralPath $workLibrary)) {
        throw "-NoCompile requested, but the work library does not exist: $workLibrary"
    }

    $vmapOutput = & vmap work $workLibrary 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "vmap failed:`n$($vmapOutput -join [Environment]::NewLine)"
    }

    $results = @()
    foreach ($testCase in $selectedTests) {
        $testName = [string]$testCase.name
        $simulationTop = Get-RegressionSimulationTop `
            -TestCase $testCase `
            -Defaults $manifestData.defaults
        $imagePath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$testCase.image)))
        if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
            throw "Test image not found for '$testName': $imagePath"
        }

        $dataImagePath = ""
        if ($null -ne $testCase.PSObject.Properties["data_image"] -and
            -not [string]::IsNullOrWhiteSpace([string]$testCase.data_image)) {
            $dataImagePath = [System.IO.Path]::GetFullPath(
                (Join-Path $repoRoot ([string]$testCase.data_image)))
            if (-not (Test-Path -LiteralPath $dataImagePath -PathType Leaf)) {
                throw "Data image not found for '$testName': $dataImagePath"
            }
        }

        if ($null -ne $testCase.PSObject.Properties["timeout_cycles"]) {
            $timeoutCycles = [int]$testCase.timeout_cycles
        } else {
            $timeoutCycles = [int]$manifestData.defaults.timeout_cycles
        }

        if ($null -ne $testCase.PSObject.Properties["tohost_addr"]) {
            $tohostAddr = [uint32]$testCase.tohost_addr
        } elseif ($null -ne $manifestData.defaults.PSObject.Properties["tohost_addr"]) {
            $tohostAddr = [uint32]$manifestData.defaults.tohost_addr
        } else {
            $tohostAddr = [uint32]4096
        }

        if ($null -ne $testCase.PSObject.Properties["prog_ram_depth"]) {
            $progRamDepth = [int]$testCase.prog_ram_depth
        } elseif ($null -ne $manifestData.defaults.PSObject.Properties["prog_ram_depth"]) {
            $progRamDepth = [int]$manifestData.defaults.prog_ram_depth
        } else {
            $progRamDepth = 4096
        }

        if ($null -ne $testCase.PSObject.Properties["data_ram_depth"]) {
            $dataRamDepth = [int]$testCase.data_ram_depth
        } elseif ($null -ne $manifestData.defaults.PSObject.Properties["data_ram_depth"]) {
            $dataRamDepth = [int]$manifestData.defaults.data_ram_depth
        } else {
            $dataRamDepth = 4096
        }

        if ($null -ne $testCase.PSObject.Properties["data_req_wait_cycles"]) {
            $dataReqWaitCycles = [int]$testCase.data_req_wait_cycles
        } else {
            $dataReqWaitCycles = 0
        }

        if ($null -ne $testCase.PSObject.Properties["data_rsp_wait_cycles"]) {
            $dataRspWaitCycles = [int]$testCase.data_rsp_wait_cycles
        } else {
            $dataRspWaitCycles = 0
        }

        $dataForceError = 0
        $dataErrorAddrEnable = 0
        $dataErrorAddr = [uint32]0
        if ($null -ne $testCase.PSObject.Properties["data_error_addr"]) {
            $dataForceError = 1
            $dataErrorAddrEnable = 1
            $dataErrorAddr = [uint32]$testCase.data_error_addr
        } elseif ($null -ne $testCase.PSObject.Properties["data_force_error"] -and
                  [bool]$testCase.data_force_error) {
            $dataForceError = 1
        }

        # ModelSim 2019.2 treats a large decimal generic override as an
        # unsized signed literal. Use explicitly sized hexadecimal literals so
        # architectural addresses at or above 0x8000_0000 elaborate cleanly.
        $tohostGeneric = "32'h{0:X8}" -f $tohostAddr
        $dataErrorAddrGeneric = "32'h{0:X8}" -f $dataErrorAddr

        $modelSimImagePath = $imagePath.Replace("\", "/")
        $logPath = Join-Path $logDir "$testName.log"
        $vsimArgs = @(
            "-c",
            "-voptargs=+acc",
            "-gPROGRAM_FILE=$modelSimImagePath",
            "-gTIMEOUT_CYCLES=$timeoutCycles",
            "-gTOHOST_ADDR=$tohostGeneric",
            "-gPROG_RAM_DEPTH=$progRamDepth",
            "-gDATA_RAM_DEPTH=$dataRamDepth",
            "-gDATA_REQ_WAIT_CYCLES=$dataReqWaitCycles",
            "-gDATA_RSP_WAIT_CYCLES=$dataRspWaitCycles",
            "-gDATA_FORCE_ERROR=$dataForceError",
            "-gDATA_ERROR_ADDR_ENABLE=$dataErrorAddrEnable",
            "-gDATA_ERROR_ADDR=$dataErrorAddrGeneric",
            "-gTRACE_ENABLE=$([int][bool]$Trace)",
            "-gDUMP_WAVES=$([int][bool]$DumpWaves)"
        )
        if ($null -ne $testCase.PSObject.Properties["uart_check_enable"]) {
            $vsimArgs += "-gUART_CHECK_ENABLE=$([int][bool]$testCase.uart_check_enable)"
        }
        if ($null -ne $testCase.PSObject.Properties["uart_rx_echo_enable"]) {
            $vsimArgs += "-gUART_RX_ECHO_ENABLE=$([int][bool]$testCase.uart_rx_echo_enable)"
        }
        if ($null -ne $testCase.PSObject.Properties["gpio_check_enable"]) {
            $vsimArgs += "-gGPIO_CHECK_ENABLE=$([int][bool]$testCase.gpio_check_enable)"
        }
        if ($null -ne $testCase.PSObject.Properties["timer_irq_check_enable"]) {
            $vsimArgs += "-gTIMER_IRQ_CHECK_ENABLE=$([int][bool]$testCase.timer_irq_check_enable)"
        }
        if ($null -ne $testCase.PSObject.Properties["timer_irq_expected_count"]) {
            $vsimArgs += "-gTIMER_IRQ_EXPECTED_COUNT=$([int]$testCase.timer_irq_expected_count)"
        }
        if (-not [string]::IsNullOrWhiteSpace($dataImagePath)) {
            $modelSimDataImagePath = $dataImagePath.Replace("\", "/")
            $vsimArgs += "-gDATA_FILE=$modelSimDataImagePath"
        }
        $vsimArgs += @(
            $simulationTop,
            "-do", "run -all; quit -f"
        )

        $timer = [System.Diagnostics.Stopwatch]::StartNew()
        $simulationOutput = & vsim @vsimArgs 2>&1
        $simulationExitCode = $LASTEXITCODE
        $timer.Stop()
        $simulationOutput | Set-Content -LiteralPath $logPath

        $simulationResult = Get-RegressionSimulationResult `
            -SimulationExitCode $simulationExitCode `
            -SimulationOutput $simulationOutput
        $passed = $simulationResult.Passed

        if ($passed) {
            $status = "PASS"
        } else {
            $status = "FAIL"
        }

        $results += [PSCustomObject]@{
            Test = $testName
            Status = $status
            Timeout = $timeoutCycles
            Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 2)
            SimulatorExit = $simulationExitCode
            Log = $logPath
        }
    }
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "RISC-V regression summary"
$results | Format-Table Test, Status, Timeout, Seconds, SimulatorExit -AutoSize

$failedTests = @($results | Where-Object { $_.Status -ne "PASS" })
if ($failedTests.Count -gt 0) {
    Write-Host "Failed test logs:"
    $failedTests | ForEach-Object { Write-Host "  $($_.Test): $($_.Log)" }
    exit 1
}

Write-Host "All $($results.Count) selected tests passed."
exit 0
