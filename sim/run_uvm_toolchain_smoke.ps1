[CmdletBinding()]
param(
  [switch]$NegativeGate
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'verif\uvm\tests\u0_uvm_smoke.sv'
$buildDir = Join-Path $PSScriptRoot 'build\uvm_toolchain'
$uvmLibrary = 'D:\Modelsim2019\uvm-1.2'
$uvmSource = 'D:\Modelsim2019\verilog_src\uvm-1.2\src'
$compileLog = Join-Path $buildDir 'compile.log'
$runLog = Join-Path $buildDir 'run.log'

$requiredCommands = @('vlib', 'vmap', 'vlog', 'vsim')
foreach ($name in $requiredCommands) {
  if ($null -eq (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Error "Required simulator command is not on PATH: $name"
  }
}

if (-not (Test-Path -LiteralPath $uvmLibrary -PathType Container)) {
  Write-Error "Installed UVM 1.2 library not found: $uvmLibrary"
}
if (-not (Test-Path -LiteralPath (Join-Path $uvmSource 'uvm_macros.svh') -PathType Leaf)) {
  Write-Error "Installed UVM 1.2 macro header not found: $uvmSource"
}

New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
Push-Location $buildDir
try {
  if (-not (Test-Path -LiteralPath 'work' -PathType Container)) {
    & vlib work
    if ($LASTEXITCODE -ne 0) {
      throw "vlib failed with exit code $LASTEXITCODE"
    }
  }

  & vmap work work | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "vmap failed with exit code $LASTEXITCODE"
  }

  $includeArg = "+incdir+$($uvmSource -replace '\\', '/')"
  & vlog -sv -work work -L $uvmLibrary $includeArg $source 2>&1 |
    Tee-Object -FilePath $compileLog
  $compileExit = $LASTEXITCODE
  if ($compileExit -ne 0) {
    Write-Output "U0_UVM_TOOLCHAIN_RESULT: FAIL compile_exit=$compileExit"
    exit $compileExit
  }

  & vsim -c -L $uvmLibrary work.u0_uvm_smoke_top `
    -do 'run -all; quit -f' -l $runLog 2>&1 | Tee-Object -Variable runOutput
  $runExit = $LASTEXITCODE

  $expectedMarker = if ($NegativeGate) {
    'U0_UVM_SMOKE_INTENTIONALLY_MISSING'
  } else {
    'U0_UVM_SMOKE_PASS'
  }
  $runText = ($runOutput | Out-String)
  if (Test-Path -LiteralPath $runLog) {
    $runText += Get-Content -Raw -LiteralPath $runLog
  }

  $hasMarker = $runText.Contains($expectedMarker)
  $zeroErrors = $runText -match 'UVM_ERROR\s*:\s*0'
  $zeroFatals = $runText -match 'UVM_FATAL\s*:\s*0'
  $passed = ($runExit -eq 0) -and $hasMarker -and $zeroErrors -and $zeroFatals

  if (-not $passed) {
    Write-Output (
      'U0_UVM_TOOLCHAIN_RESULT: FAIL ' +
      "run_exit=$runExit marker=$hasMarker errors_zero=$zeroErrors fatals_zero=$zeroFatals"
    )
    exit 3
  }

  Write-Output 'U0_UVM_TOOLCHAIN_RESULT: PASS'
  exit 0
}
finally {
  Pop-Location
}
