<#
.SYNOPSIS
  Run layered production-RTL lint with the repository's WSL Verilator.

.EXAMPLE
  .\run_lint.ps1 -Scope leaf
  .\run_lint.ps1 -Scope core
  .\run_lint.ps1 -Scope soc
#>
[CmdletBinding()]
param(
    [ValidateSet("leaf", "core", "soc")]
    [string[]]$Scope = @("leaf", "core", "soc")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$lintDir = $PSScriptRoot
$simDir = [System.IO.Path]::GetFullPath((Join-Path $lintDir ".."))
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $simDir ".."))

function Convert-ToWslPath([string]$Path) {
    $resolved = [System.IO.Path]::GetFullPath($Path)
    if ($resolved -notmatch '^([A-Za-z]):\\(.*)$') {
        throw "Only drive-letter workspace paths are supported: $resolved"
    }
    $drive = $Matches[1].ToLowerInvariant()
    $tail = $Matches[2].Replace('\', '/')
    return "/mnt/$drive/$tail"
}

function Get-SourcePath([string]$RelativePath) {
    return Convert-ToWslPath (Join-Path $repoRoot $RelativePath)
}

$reviewedConfig = Convert-ToWslPath (Join-Path $lintDir "rtl_reviewed.vlt")
$package = Get-SourcePath "src/core/riscv_pkg.sv"
$leafSources = @(
    $package,
    (Get-SourcePath "src/core/radix2_divider.sv"),
    (Get-SourcePath "src/core/rv32m_mul_comb.sv"),
    (Get-SourcePath "src/core/rv32m_unit.sv")
)

$coreRelative = @(
    "src/core/riscv_pkg.sv",
    "src/core/pc_counter.sv",
    "src/core/if2id.sv",
    "src/core/id2ex.sv",
    "src/core/ex2wb.sv",
    "src/core/decode.sv",
    "src/core/radix2_divider.sv",
    "src/core/rv32m_mul_comb.sv",
    "src/core/rv32m_unit.sv",
    "src/core/execute.sv",
    "src/core/lsu.sv",
    "src/core/retire_stage.sv",
    "src/core/csr_regfile.sv",
    "src/core/regfile.sv",
    "src/core/core_ctrl.sv",
    "src/core/riscv.sv"
)
$coreSources = @($coreRelative | ForEach-Object { Get-SourcePath $_ })

$rtlList = Join-Path $simDir "filelist_rtl.f"
$socSources = @(
    Get-Content -LiteralPath $rtlList |
        Where-Object { $_ -and -not $_.TrimStart().StartsWith("#") } |
        ForEach-Object {
            Convert-ToWslPath (Join-Path $simDir $_.Trim())
        }
)

foreach ($selectedScope in $Scope) {
    switch ($selectedScope) {
        "leaf" { $top = "rv32m_unit"; $sources = $leafSources }
        "core" { $top = "riscv";       $sources = $coreSources }
        "soc"  { $top = "riscv_soc";   $sources = $socSources }
    }

    Write-Host "=== LINT: $selectedScope ($top) ==="
    & wsl.exe -e verilator --lint-only --sv --Wall -DSYNTHESIS `
        --top-module $top $reviewedConfig @sources
    if ($LASTEXITCODE -ne 0) {
        throw "Verilator lint failed for scope '$selectedScope' with exit code $LASTEXITCODE"
    }
}
