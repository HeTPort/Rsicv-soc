<#
.SYNOPSIS
  Import ACT4 self-checking ELFs and run them through the ModelSim regression.

.EXAMPLE
  .\run_act4.ps1 -ElfDir D:\Rsicv-soc\build\act4\work\rsicv-soc-rv32im\elfs
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ElfDir,
    [string[]]$Test = @(),
    [switch]$Trace,
    [switch]$NoCompile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\.."))
$manifest = Join-Path $repoRoot "build\act4\tests.json"
$python = Get-Command python -ErrorAction SilentlyContinue
if ($null -eq $python) {
    throw "Python 3 is required to import ACT4 ELF files."
}

& $python.Source (Join-Path $scriptDir "import_act4.py") $ElfDir `
    --repo-root $repoRoot `
    --manifest $manifest `
    --tag rv32i
if ($LASTEXITCODE -ne 0) {
    throw "ACT4 ELF import failed."
}

$runnerParams = @{
    Manifest = $manifest
    Tag = @("act4")
}
if ($Test.Count -gt 0) {
    $runnerParams.Test = $Test
}
if ($Trace) {
    $runnerParams.Trace = $true
}
if ($NoCompile) {
    $runnerParams.NoCompile = $true
}

& (Join-Path $scriptDir "run_regression.ps1") @runnerParams
exit $LASTEXITCODE
