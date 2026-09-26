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
    'doc/INFORMATION_CLASSIFICATION_AND_HANDLING.md',
    'doc/RESEARCH_PROGRAM_PLAN.md',
    'doc/research/README.md',
    'doc/research/SOURCE_REGISTRY.md',
    'doc/research/PAPER_AUDIT_TEMPLATE.md',
    'doc/research/W0_D1_EXECUTION_BRIEF.md',
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

$phaseTemplate = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/PHASE_EVIDENCE_TEMPLATE.md') -Raw
$requiredDecisionMarkers = @(
    '## Decision contract',
    '| Linked research claims |',
    '| Linked product hypotheses |',
    '| NO-GO condition |',
    '## Decision outcome',
    'GO | PIVOT | DEFER | NO-GO'
    '## Information classification before work'
    '## Information-classification review'
    'DATA-CONFIDENTIAL'
)
foreach ($marker in $requiredDecisionMarkers) {
    if (-not $phaseTemplate.Contains($marker)) {
        Add-GovernanceError "Phase evidence template is missing decision marker: $marker"
    }
}

$researchPlan = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/RESEARCH_PROGRAM_PLAN.md') -Raw
$requiredResearchMarkers = @(
    '### Program research-claim register',
    '### Product-hypothesis register',
    '`RES-H1`',
    '`RES-H2`',
    '`PROP-H1`',
    '`PROD-H1`',
    '`PROD-H2`',
    '### W0-D1 — bound the first surrogate use case'
)
foreach ($marker in $requiredResearchMarkers) {
    if (-not $researchPlan.Contains($marker)) {
        Add-GovernanceError "Research plan is missing decision-governance marker: $marker"
    }
}

$todo = Get-Content -LiteralPath (Join-Path $repoRoot 'TODO.md') -Raw
if (-not $todo.Contains('Execute `W0-D1`')) {
    Add-GovernanceError 'TODO.md does not identify W0-D1 as the next research decision.'
}

$classificationPolicy = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/INFORMATION_CLASSIFICATION_AND_HANDLING.md') -Raw
foreach ($marker in @('DATA-PUBLIC', 'DATA-INTERNAL', 'DATA-CONFIDENTIAL', 'DATA-RESTRICTED', 'If classification is unresolved')) {
    if (-not $classificationPolicy.Contains($marker)) {
        Add-GovernanceError "Information-classification policy is missing marker: $marker"
    }
}

$w0Brief = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/research/W0_D1_EXECUTION_BRIEF.md') -Raw
foreach ($marker in @('Planned / `NOT RUN`', 'Pass A — required boundary sources', '`BASE-0` mandatory rule baseline', '`GO` requires')) {
    if (-not $w0Brief.Contains($marker)) {
        Add-GovernanceError "W0-D1 execution brief is missing marker: $marker"
    }
}

$sourceRegistry = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/research/SOURCE_REGISTRY.md') -Raw
if (-not $sourceRegistry.Contains('### CTRL-002 — NASA TEEM MPC technical memorandum')) {
    Add-GovernanceError 'Research source registry is missing CTRL-002.'
}

$researchIndex = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/research/README.md') -Raw
if (-not $researchIndex.Contains('W0_D1_EXECUTION_BRIEF.md')) {
    Add-GovernanceError 'Research index is missing the W0-D1 execution brief.'
}

$inboxReadme = Get-Content -LiteralPath (Join-Path $repoRoot 'notes/inbox/README.md') -Raw
if (-not $inboxReadme.Contains('data_classification: REVIEW_REQUIRED') -or
    -not $inboxReadme.Contains('INFORMATION_CLASSIFICATION_AND_HANDLING.md')) {
    Add-GovernanceError 'Idea-inbox template is missing its pre-commit classification reminder.'
}

$u0Requirements = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/plans/u0-passive-uvm/requirements.md') -Raw
if (-not $u0Requirements.Contains('## Decision contract')) {
    Add-GovernanceError 'The active U0 requirements do not contain a decision contract.'
}
if (-not $u0Requirements.Contains('## Information classification before work')) {
    Add-GovernanceError 'The active U0 requirements do not contain an information-classification boundary.'
}

$u0Results = Get-Content -LiteralPath (Join-Path $repoRoot 'doc/plans/u0-passive-uvm/results.md') -Raw
if (-not $u0Results.Contains('## Decision outcome')) {
    Add-GovernanceError 'The active U0 results do not contain a decision outcome.'
}
if (-not $u0Results.Contains('## Information-classification review')) {
    Add-GovernanceError 'The active U0 results do not contain an information-classification review.'
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
