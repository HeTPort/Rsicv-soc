[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-GovernanceError {
    param([string]$Message)
    $script:errors.Add($Message)
}

$requiredPaths = @(
    'AGENTS.md',
    'README.md',
    'TODO.md',
    'doc/CONTEXT_ROUTER.md',
    'doc/RESEARCH_PROGRAM_PLAN.md',
    'doc/research/README.md',
    'doc/research/SOURCE_REGISTRY.md',
    'doc/research/PAPER_AUDIT_TEMPLATE.md',
    'doc/ROADMAP_AND_LEARNING_PATH.md',
    'doc/PHASE_EVIDENCE_TEMPLATE.md',
    'doc/plans/README.md',
    'doc/ar/README.md',
    'doc/ar/AR033_DOCUMENT_GOVERNANCE_AND_CONTEXT_ROUTING.md',
    'docs/README.md',
    'notes/README.md',
    'notes/inbox/README.md'
)

foreach ($relativePath in $requiredPaths) {
    $absolutePath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $absolutePath)) {
        Add-GovernanceError "Missing required governance path: $relativePath"
    }
}

$agentLineCount = (Get-Content -LiteralPath (Join-Path $repoRoot 'AGENTS.md')).Count
if ($agentLineCount -gt 220) {
    Add-GovernanceError "AGENTS.md has $agentLineCount lines; keep stable routing guidance at or below 220 lines."
}

$legacyDocsAllowlist = @(
    'README.md',
    'AIR_POINTER_HANDWRITING_RESEARCH_REPORT.md',
    'INTERVIEW_GUIDE.md',
    'phase3-guide.md',
    'phase4-gpio-guide.md',
    'phase4-uart-guide.md',
    'phase5-startup-runtime-guide.md',
    'verification_framework.md'
)

$legacyDocs = Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -File
foreach ($legacyDoc in $legacyDocs) {
    if ($legacyDocsAllowlist -notcontains $legacyDoc.Name) {
        Add-GovernanceError "Unclassified file added to frozen docs/: docs/$($legacyDoc.Name)"
    }
}

$rootNumberedAr = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'doc') -File |
        Where-Object { $_.Name -match '^AR\d{3}.*\.md$' }
)
if ($rootNumberedAr.Count -gt 0) {
    Add-GovernanceError 'Numbered AR files must live under doc/ar/, not doc/ root.'
}

$numberedAr = @(
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'doc/ar') -File |
        Where-Object { $_.Name -match '^AR\d{3}.*\.md$' }
)
if ($numberedAr.Count -eq 0) {
    Add-GovernanceError 'No numbered AR files were found under doc/ar/.'
}
$duplicateArIds = @(
    $numberedAr |
        Group-Object { [regex]::Match($_.Name, '^AR\d{3}').Value } |
        Where-Object Count -gt 1
)
foreach ($duplicate in $duplicateArIds) {
    Add-GovernanceError "Duplicate architecture-review identifier: $($duplicate.Name)"
}
$arIndex = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/ar/README.md') -Raw
foreach ($arFile in $numberedAr) {
    if ($arIndex -notmatch [regex]::Escape($arFile.Name)) {
        Add-GovernanceError "Architecture-review index is missing: $($arFile.Name)"
    }
}

$phaseIndex = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/plans/README.md') -Raw
if ($phaseIndex -match '\*\*Active:\*\* requirements/capture plan accepted; results `NOT RUN`') {
    Add-GovernanceError 'The phase index contains the superseded P0 Active/NOT RUN status.'
}
if ($phaseIndex -match 'U0\s*\|\s*`u0-passive-uvm/`\s*\|\s*Create') {
    Add-GovernanceError 'The phase index still says the existing U0 package must be created.'
}

$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
if ($readme -match '\*\*P0 active; P1 gated\*\*') {
    Add-GovernanceError 'README.md contains the superseded P0-active status.'
}

$markdownFiles = @(
    Get-Item -LiteralPath (Join-Path $repoRoot 'AGENTS.md')
    Get-Item -LiteralPath (Join-Path $repoRoot 'README.md')
    Get-Item -LiteralPath (Join-Path $repoRoot 'TODO.md')
    Get-Item -LiteralPath (Join-Path $repoRoot 'config/README.md')
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'doc') -Recurse -File -Filter '*.md'
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'docs') -Recurse -File -Filter '*.md'
    Get-ChildItem -LiteralPath (Join-Path $repoRoot 'notes') -Recurse -File -Filter '*.md'
)

$linkPattern = [regex]'!?\[[^\]]*\]\((?<target>[^)]+)\)'
$checkedLinks = 0
foreach ($markdownFile in $markdownFiles) {
    $content = Get-Content -LiteralPath $markdownFile.FullName -Raw
    foreach ($match in $linkPattern.Matches($content)) {
        $target = $match.Groups['target'].Value.Trim()
        if ($target.StartsWith('<') -and $target.Contains('>')) {
            $target = $target.Substring(1, $target.IndexOf('>') - 1)
        } else {
            $target = ($target -split '\s+')[0]
        }

        if ([string]::IsNullOrWhiteSpace($target) -or
            $target.StartsWith('#') -or
            $target -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or
            $target -match '[{}*]' -or
            $target -in @('path', 'relative/path')) {
            continue
        }

        $target = ($target -split '#', 2)[0]
        if ([string]::IsNullOrWhiteSpace($target)) {
            continue
        }

        $target = [System.Uri]::UnescapeDataString($target)
        $candidate = Join-Path $markdownFile.DirectoryName $target
        $checkedLinks++
        if (-not (Test-Path -LiteralPath $candidate)) {
            $relativeSource = $markdownFile.FullName.Substring($repoRoot.Length + 1)
            Add-GovernanceError "Broken local link in ${relativeSource}: $target"
        }
    }
}

$generatedRootNames = @('transcript', 'usage_statistics_webtalk.html', 'usage_statistics_webtalk.xml')
foreach ($name in $generatedRootNames) {
    if (Test-Path -LiteralPath (Join-Path $repoRoot $name)) {
        $warnings.Add("Generated root artifact remains for later user-owned cleanup: $name")
    }
}

Write-Host "Governance files checked: $($markdownFiles.Count)"
Write-Host "Local links checked: $checkedLinks"
Write-Host "AGENTS.md lines: $agentLineCount"

foreach ($warning in $warnings) {
    Write-Warning $warning
}

if ($errors.Count -gt 0) {
    foreach ($governanceError in $errors) {
        Write-Error $governanceError
    }
    exit 1
}

Write-Host 'PASS: documentation governance checks completed.'
