Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$workflowPath = Join-Path $repoRoot '.github/workflows/quality-gate.yml'
$workflow = Get-Content -LiteralPath $workflowPath -Raw
$actionsPolicy = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/actions-policy.json') -Raw | ConvertFrom-Json
$tools = Get-Content -LiteralPath (Join-Path $repoRoot 'config/security/tools.json') -Raw | ConvertFrom-Json
$developmentGuide = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/development.md') -Raw
if ($developmentGuide -notmatch '(?m)^\s+pwsh -NoProfile -File scripts/github/verify-settings\.ps1 -RequireStatusCheck\s*$') {
    throw 'Developer guide must show the live verifier in required-status mode'
}
$ruleset = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/main-ruleset.json') -Raw | ConvertFrom-Json
$roadmap = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/roadmap.md') -Raw
$foundationRoadmap = ($roadmap -split '(?m)^## Этап 1')[0]
if ($foundationRoadmap -match '(?m)^\s*-\s*\[\s\]') {
    throw 'GitHub foundation roadmap still contains unchecked bootstrap steps'
}
$settingsVerifier = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/github/verify-settings.ps1') -Raw
if ($settingsVerifier -notmatch "gh api user --jq .login" -or $settingsVerifier -notmatch 'dependencyGraphVerification' -or $settingsVerifier -notmatch 'INFERRED: Dependency graph') {
    throw 'Live GitHub verifier must fail closed on authentication gaps and verify the dependency graph'
}
$prePushHook = Get-Content -LiteralPath (Join-Path $repoRoot '.githooks/pre-push') -Raw
if ($prePushHook -notmatch 'read -r local_ref local_sha remote_ref remote_sha' -or -not $prePushHook.Contains('-PushRange')) {
    throw 'Pre-push hook must pass Git-provided ref update ranges to the secret scan'
}
$qualityGate = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/quality-gate.ps1') -Raw
if ($qualityGate -notmatch '\[string\[\]\]\$PushRange' -or -not $qualityGate.Contains('--log-opts=')) {
    throw 'Quality gate must scan exact incoming push history ranges'
}
if ($settingsVerifier -notmatch "state -eq 'pending-first-successful-workflow-run'" -or $settingsVerifier -notmatch "state -ne 'enforced'" ) {
    throw 'Settings verifier must reject a status-manifest/live-state mismatch'
}
if (-not $settingsVerifier.Contains('System.StringComparison]::Ordinal')) {
    throw 'Ruleset branch targeting comparison must be case-sensitive'
}
if (-not $settingsVerifier.Contains('conditions.ref_name.exclude') -or -not $settingsVerifier.Contains('expectedIncludedRefs')) {
    throw 'Settings verifier must reject ruleset exclusions and include drift'
}
if ($settingsVerifier -notmatch '(?s)required_review_thread_resolution.*requireResolvedReviewThreads') {
    throw 'Live GitHub verifier must compare review thread resolution with its manifest'
}

if ($workflow -match '(?im)^\s+(paths|paths-ignore)\s*:') {
    throw 'Workflow path filters can silently skip the required quality gate'
}
if ($workflow -match '(?im)^\s*pull_request_target\s*:') {
    throw 'pull_request_target requires a separate security design review'
}
if ($workflow -notmatch '(?m)^\s*permissions:\s*\r?\n\s+contents:\s*read\s*$') {
    throw 'Workflow must keep repository permissions read-only'
}

$actionReferences = [regex]::Matches($workflow, '(?im)^\s*uses:\s*(?<reference>\S+)\s*$')
if ($actionReferences.Count -eq 0) {
    throw 'Workflow contains no pinned actions'
}
foreach ($actionReference in $actionReferences) {
    if ($actionReference.Groups['reference'].Value -notmatch '^[^@]+@[0-9a-f]{40}$') {
        throw 'Every GitHub Action must be pinned to a full commit SHA'
    }
}

if ($workflow -notmatch '(?m)^\s*name:\s*quality-gate\s*$') {
    throw 'Stable required check context quality-gate is missing'
}
if ($workflow -notmatch '(?m)^\s*group:\s*quality-gate-\$\{\{\s*github\.event\.pull_request\.number') {
    throw 'Concurrency key must use a valid GitHub expression scoped by PR/ref'
}
if ($workflow -notmatch '(?m)^\s*ref:\s*\$\{\{\s*github\.sha\s*\}\}') {
    throw 'Checkout must pin the exact event SHA, including the PR merge-result SHA'
}

$revisionExpressions = @{
    PR_BASE_BRANCH = '(?m)^\s*PR_BASE_BRANCH:\s*\$\{\{\s*github\.event\.pull_request\.base\.ref\s*\}\}'
    PR_HEAD_SHA = '(?m)^\s*PR_HEAD_SHA:\s*\$\{\{\s*github\.event\.pull_request\.head\.sha\s*\}\}'
    PR_BASE_SHA = '(?m)^\s*PR_BASE_SHA:\s*\$\{\{\s*github\.event\.pull_request\.base\.sha\s*\}\}'
    EVENT_TEST_SHA = '(?m)^\s*EVENT_TEST_SHA:\s*\$\{\{\s*github\.sha\s*\}\}'
}
foreach ($variable in $revisionExpressions.Keys) {
    if ($workflow -notmatch $revisionExpressions[$variable]) {
        throw "Workflow must record $variable using a valid GitHub expression"
    }
}

if ($actionsPolicy.defaultWorkflowTokenPermission -ne 'read' -or $actionsPolicy.shaPinningRequired -ne $true) {
    throw 'Actions policy manifest weakens token permissions or SHA pinning'
}
$prePush = Get-Content -LiteralPath (Join-Path $repoRoot '.githooks/pre-push') -Raw
if ($prePush -notmatch '(?m)^#!/bin/sh' -or $prePush -notmatch 'exec pwsh .*scripts/quality-gate\.ps1') {
    throw 'Pre-push hook must use a Git for Windows shell wrapper and invoke the full quality gate'
}
$localSetup = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/github/configure-local.ps1') -Raw
if ($localSetup -notmatch 'remote get-url --all origin' -or $localSetup -notmatch 'remote get-url --push --all origin') {
    throw 'Local Git setup must verify all fetch and push URLs before configuring Git'
}

if ($ruleset.bypassActors.Count -ne 0 -or -not $ruleset.rules.pullRequestRequired -or -not $ruleset.rules.blockForcePush) {
    throw 'Main ruleset manifest is missing a required protection'
}
if (
    $ruleset.rules.requiredStatusChecks.context -ne 'quality-gate' -or
    $ruleset.rules.requiredStatusChecks.strict -ne $true -or
    $ruleset.rules.requiredStatusChecks.integrationId -ne 15368 -or
    $ruleset.rules.requiredStatusChecks.state -cne 'enforced'
) {
    throw 'Required status check manifest must require the enforced strict quality-gate'
}

$gateScript = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/quality-gate.ps1') -Raw
if (
    $gateScript -notmatch "Arguments @\('dir'.*Gitleaks working-tree scan" -or
    $gateScript -notmatch "Gitleaks reachable-history scan" -or
    $gateScript -notmatch "Gitleaks pushed-history scan"
) {
    throw 'Quality gate must scan current files, all reachable history and each supplied push range'
}
foreach ($toolName in @('actionlint', 'gitleaks')) {
    if (
        $tools.tools.$toolName.sha256 -notmatch '^[0-9a-f]{64}$' -or
        $tools.tools.$toolName.version -notmatch '^\d+\.\d+\.\d+$'
    ) {
        throw "Pinned tool manifest is incomplete: $toolName"
    }
}

$textExtensions = @('.md', '.json', '.yml', '.yaml', '.ps1')
$specialTextNames = @('.gitignore', '.gitattributes', '.editorconfig', 'pre-push')
$textFiles = @(
    Get-ChildItem -LiteralPath $repoRoot -File -Recurse -Force |
        Where-Object {
            $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName)
            ($_.Extension -in $textExtensions -or $_.Name -in $specialTextNames) -and
            $relativePath -notmatch '(^|[\\/])(\.git|\.worktrees|temp)([\\/]|$)'
        }
)
if ($textFiles.Count -eq 0) {
    throw 'Text hygiene scan found no repository files'
}

$trailing = [System.Collections.Generic.List[string]]::new()
$missingFinalNewline = [System.Collections.Generic.List[string]]::new()
foreach ($file in $textFiles) {
    $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($bytes -contains 13) {
        throw ('Expected LF-only line endings: ' + $file.FullName)
    }
    if ($bytes.Length -eq 0 -or $bytes[$bytes.Length - 1] -ne 10) {
        $missingFinalNewline.Add($file.FullName)
    }
    $lines = [System.IO.File]::ReadAllLines($file.FullName)
    for ($index = 0; $index -lt $lines.Length; $index++) {
        if ($lines[$index] -match '[ \t]+$') {
            $trailing.Add(('{0}:{1}' -f $file.FullName, ($index + 1)))
        }
    }
}
if ($trailing.Count -gt 0) {
    throw ('Trailing whitespace found: ' + ($trailing -join ', '))
}
if ($missingFinalNewline.Count -gt 0) {
    throw ('Missing final newline: ' + ($missingFinalNewline -join ', '))
}

Write-Output ('PASS: GitHub gate invariants; checked {0} text files for whitespace and final newline' -f $textFiles.Count)
