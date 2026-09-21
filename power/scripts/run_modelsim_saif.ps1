[CmdletBinding()]
param(
    [string]$Workload = "p0_mix",
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$RunId,
    [switch]$DumpVcd
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\.."))
$simDir = Join-Path $repoRoot "sim"
$workloadDir = Join-Path $repoRoot "power\workloads\$Workload"
$manifestPath = Join-Path $workloadDir "workload.json"
$regressionManifestPath = Join-Path $simDir "regress\power_tests.json"
$captureDoPath = Join-Path $repoRoot "power\common\capture_window.do"

foreach ($required in @($manifestPath, $regressionManifestPath, $captureDoPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Required input not found: $required"
    }
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$regressionManifest = Get-Content -LiteralPath $regressionManifestPath -Raw | ConvertFrom-Json
$testName = "${Workload}_power_tb"
$testCase = @($regressionManifest.tests | Where-Object { $_.name -eq $testName })
if ($testCase.Count -ne 1) {
    throw "Expected exactly one '$testName' entry in $regressionManifestPath"
}
$testCase = $testCase[0]

if ($manifest.target.simulation_top -ne "tb_power" -or
    $manifest.target.dut_instance -ne "u_soc") {
    throw "Workload hierarchy must be tb_power/u_soc for this capture flow"
}
if ($manifest.target.clock_hz -ne 95000000) {
    throw "This P0 capture flow requires an exact 95 MHz workload declaration"
}

function Convert-Hex32([string]$Value, [string]$FieldName) {
    if ($Value -notmatch '^0x[0-9A-Fa-f]{1,8}$') {
        throw "$FieldName must be a 32-bit hexadecimal string, got '$Value'"
    }
    return [Convert]::ToUInt32($Value.Substring(2), 16)
}

$markerAddr = Convert-Hex32 $manifest.measurement.marker_address_from_elf "marker_address_from_elf"
$startMarker = Convert-Hex32 $manifest.measurement.start_marker "start_marker"
$endMarker = Convert-Hex32 $manifest.measurement.end_marker "end_marker"
$tohostAddr = [uint32]$regressionManifest.defaults.tohost_addr
$progRamDepth = [int]$regressionManifest.defaults.prog_ram_depth
$dataRamDepth = [int]$regressionManifest.defaults.data_ram_depth
$timeoutCycles = [int]$testCase.timeout_cycles

$programPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$testCase.image)))
$dataPath = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ([string]$testCase.data_image)))
foreach ($imagePath in @($programPath, $dataPath)) {
    if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) {
        throw "Firmware image not found: $imagePath"
    }
}

$outputDir = Join-Path $repoRoot "build\power\$Workload\$RunId"
if (Test-Path -LiteralPath $outputDir) {
    throw "Run directory already exists; choose a new RunId: $outputDir"
}
New-Item -ItemType Directory -Path $outputDir | Out-Null

$modelSimBuildDir = Join-Path $outputDir "modelsim"
$workLibrary = Join-Path $modelSimBuildDir "work"
New-Item -ItemType Directory -Force -Path $modelSimBuildDir | Out-Null

foreach ($tool in @("vlib", "vmap", "vlog", "vsim")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required ModelSim tool '$tool' was not found in PATH"
    }
}

Push-Location $modelSimBuildDir
try {
    if (-not (Test-Path -LiteralPath $workLibrary)) {
        & vlib $workLibrary | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "vlib failed" }
    }

    $sourceFiles = @(
        Get-Content -LiteralPath (Join-Path $simDir "filelist.f") |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" -and -not $_.StartsWith("#") } |
            ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $simDir $_)) }
    )
    $compileOutput = & vlog -sv -work $workLibrary @sourceFiles 2>&1
    $compileOutput | Set-Content -LiteralPath (Join-Path $outputDir "compile.log")
    if ($LASTEXITCODE -ne 0 -or $compileOutput -match 'Errors:\s*[1-9][0-9]*') {
        throw "RTL compilation failed; see $outputDir\compile.log"
    }

    & vmap work $workLibrary | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "vmap failed" }

    $saifPath = Join-Path $outputDir "$Workload.saif"
    $reportPath = Join-Path $outputDir "$Workload.power.rpt"
    $simLogPath = Join-Path $outputDir "simulation.log"
    $env:POWER_SAIF_PATH = $saifPath.Replace("\", "/")
    $env:POWER_REPORT_PATH = $reportPath.Replace("\", "/")
    $vcdPath = Join-Path $outputDir "$Workload.window.vcd"
    if ($DumpVcd) {
        $env:POWER_VCD_PATH = $vcdPath.Replace("\", "/")
    }

    $hexTohost = "32'h{0:X8}" -f $tohostAddr
    $hexMarkerAddr = "32'h{0:X8}" -f $markerAddr
    $hexStartMarker = "32'h{0:X8}" -f $startMarker
    $hexEndMarker = "32'h{0:X8}" -f $endMarker
    $allowEcallTraps = if ($null -ne $testCase.PSObject.Properties["allow_ecall_traps"]) {
        [int][bool]$testCase.allow_ecall_traps
    } else { 0 }
    $vsimArgs = @(
        "-c",
        "-voptargs=+acc",
        "-gPROGRAM_FILE=$($programPath.Replace('\', '/'))",
        "-gDATA_FILE=$($dataPath.Replace('\', '/'))",
        "-gTIMEOUT_CYCLES=$timeoutCycles",
        "-gTOHOST_ADDR=$hexTohost",
        "-gMARKER_ADDR=$hexMarkerAddr",
        "-gSTART_MARKER=$hexStartMarker",
        "-gEND_MARKER=$hexEndMarker",
        "-gALLOW_ECALL_TRAPS=$allowEcallTraps",
        "-gPROG_RAM_DEPTH=$progRamDepth",
        "-gDATA_RAM_DEPTH=$dataRamDepth"
    )
    foreach ($resultIndex in 0..2) {
        $resultField = "result${resultIndex}_addr"
        if ($null -ne $testCase.PSObject.Properties[$resultField]) {
            $resultGeneric = "32'h{0:X8}" -f [uint32]$testCase.$resultField
            $vsimArgs += "-gRESULT${resultIndex}_ADDR=$resultGeneric"
        }
    }
    $vsimArgs += @("work.tb_power", "-do", "do {$($captureDoPath.Replace('\', '/'))}")
    $simulationOutput = & vsim @vsimArgs 2>&1
    $simulationExit = $LASTEXITCODE
    $simulationOutput | Set-Content -LiteralPath $simLogPath
    $simulationText = $simulationOutput -join "`n"

    if ($simulationExit -ne 0 -or
        $simulationText -notmatch '\[POWER-TB\] CAPTURE: PASS' -or
        $simulationText -notmatch '\[TB\] RESULT: PASS') {
        throw "SAIF simulation failed; see $simLogPath"
    }
    $expectedArtifacts = @($saifPath, $reportPath)
    if ($DumpVcd) { $expectedArtifacts += $vcdPath }
    foreach ($artifact in $expectedArtifacts) {
        if (-not (Test-Path -LiteralPath $artifact -PathType Leaf) -or
            (Get-Item -LiteralPath $artifact).Length -eq 0) {
            throw "Expected capture artifact was not generated: $artifact"
        }
    }

    $windowCycles = [uint64]([regex]::Match(
        $simulationText, 'Window cycles = ([0-9]+)').Groups[1].Value)
    $retiredInstructions = [uint64]([regex]::Match(
        $simulationText, 'Retired instructions = ([0-9]+)').Groups[1].Value)
    $saifHash = (Get-FileHash -LiteralPath $saifPath -Algorithm SHA256).Hash
    $reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
    $programHash = (Get-FileHash -LiteralPath $programPath -Algorithm SHA256).Hash
    $dataHash = (Get-FileHash -LiteralPath $dataPath -Algorithm SHA256).Hash
    $vcdHash = if ($DumpVcd) {
        (Get-FileHash -LiteralPath $vcdPath -Algorithm SHA256).Hash
    } else { "NOT RUN" }

    [ordered]@{
        schema_version = 1
        workload = $Workload
        workload_version = $manifest.version
        run_id = $RunId
        simulation_top = "tb_power"
        dut_instance = "u_soc"
        clock_hz = 95000000
        window_cycles = $windowCycles
        retired_instructions = $retiredInstructions
        work_units = [int]$manifest.measurement.work_units
        saif_strip_path = $manifest.target.saif_strip_path
        program_sha256 = $programHash
        data_sha256 = $dataHash
        saif_sha256 = $saifHash
        report_sha256 = $reportHash
        vcd_sha256 = $vcdHash
        power_analysis_status = "NOT RUN"
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $outputDir "run.json")

    Write-Host "POWER_SAIF_CAPTURE: PASS"
    Write-Host "Run directory: $outputDir"
    Write-Host "Window cycles: $windowCycles"
    Write-Host "Retired instructions: $retiredInstructions"
    Write-Host "SAIF SHA-256: $saifHash"
} finally {
    Remove-Item Env:\POWER_SAIF_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\POWER_REPORT_PATH -ErrorAction SilentlyContinue
    Remove-Item Env:\POWER_VCD_PATH -ErrorAction SilentlyContinue
    Pop-Location
}
