<#
.SYNOPSIS
  Build and import one ACT4 extension through WSL.

.DESCRIPTION
  This is the Windows entry point for build_act4_wsl.sh. It replaces separate
  RV32I and RV32M launchers and derives the repository's WSL path from the
  current clone, so no user name or drive letter is embedded in the script.

.EXAMPLE
  .\run_act4_build.ps1 -Extension I

.EXAMPLE
  .\run_act4_build.ps1 -Extension M -Jobs 8 `
    -Act4Root /home/me/riscv-arch-test `
    -Act4WorkDir /home/me/act4-work/rsicv-soc
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("I", "M")]
    [string]$Extension,

    [ValidateRange(1, 256)]
    [int]$Jobs = 8,

    [string]$Act4Root = "",
    [string]$Act4WorkDir = "",
    [string]$WslRepoPath = "",
    [string]$TargetName = "rsicv-soc-rv32im-clang",
    [string]$ConfigRelativePath = "verif/act4/rv32im_core/test_config_clang.yaml",
    [string]$CompilerTool = "clang",
    [string]$ObjdumpTool = "llvm-objdump"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-BashSingleQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "'`"'`"'") + "'"
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if ($null -eq $wsl) {
    throw "wsl.exe was not found. Install WSL or run build_act4_wsl.sh from Linux."
}

$scriptDir = $PSScriptRoot
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir "..\.."))

if ([string]::IsNullOrWhiteSpace($WslRepoPath)) {
    $wslPathOutput = @(& $wsl.Source -e wslpath -a -u $repoRoot 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not translate the repository path through WSL: $($wslPathOutput -join [Environment]::NewLine)"
    }
    $WslRepoPath = ($wslPathOutput | Select-Object -First 1).ToString().Trim()
}
if ([string]::IsNullOrWhiteSpace($WslRepoPath)) {
    throw "The translated WSL repository path is empty. Supply -WslRepoPath explicitly."
}

$configFile = "$($WslRepoPath.TrimEnd('/'))/$($ConfigRelativePath.TrimStart('/'))"
$envVars = @(
    "ACT4_TARGET_NAME=$TargetName",
    "ACT4_EXTENSIONS=$Extension",
    "ACT4_JOBS=$Jobs",
    "ACT4_CONFIG_FILE=$configFile",
    "ACT4_COMPILER_TOOL=$CompilerTool",
    "ACT4_OBJDUMP_TOOL=$ObjdumpTool"
)
if (-not [string]::IsNullOrWhiteSpace($Act4Root)) {
    $envVars += "ACT4_ROOT=$Act4Root"
}
if (-not [string]::IsNullOrWhiteSpace($Act4WorkDir)) {
    $envVars += "ACT4_WORK_DIR=$Act4WorkDir"
}

$extensionName = $Extension.ToLowerInvariant()
$quotedRepo = ConvertTo-BashSingleQuoted $WslRepoPath
$logPath = "build/act4/act4_rv32${extensionName}_build.log"
$bashCommand = @"
export PATH="`$HOME/.local/bin:`$HOME/.local/sail-riscv-0.10/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
cd $quotedRepo
mkdir -p build/act4
bash sim/regress/build_act4_wsl.sh 2>&1 | tee $logPath
"@

$wslArgs = @("-e", "env") + $envVars + @(
    "bash", "-o", "pipefail", "-lc", $bashCommand
)

& $wsl.Source @wslArgs
if ($LASTEXITCODE -ne 0) {
    throw "ACT4 RV32$Extension build/import failed with exit code $LASTEXITCODE."
}
