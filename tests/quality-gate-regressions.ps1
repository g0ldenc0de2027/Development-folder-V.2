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
if (
    $settingsVerifier -notmatch "gh api user --jq .login" -or
    $settingsVerifier -notmatch 'dependencyGraphVerification' -or
    $settingsVerifier -notmatch 'dependency-graph/sbom' -or
    $settingsVerifier -notmatch 'sbom\.spdxVersion' -or
    $settingsVerifier -notmatch 'requiresRepositoryPackage'
) {
    throw 'Live GitHub verifier must fail closed on authentication gaps and directly verify the dependency graph SBOM'
}
foreach ($ruleParameter in @(
    'dismiss_stale_reviews_on_push',
    'required_reviewers',
    'require_code_owner_review',
    'require_last_push_approval',
    'require_extra_approval_for_unattributed_changes'
)) {
    if ($settingsVerifier -notmatch [regex]::Escape($ruleParameter)) {
        throw "Live GitHub verifier does not compare pull-request parameter $ruleParameter"
    }
}
$prePushHook = Get-Content -LiteralPath (Join-Path $repoRoot '.githooks/pre-push') -Raw
if ($prePushHook -notmatch 'read -r local_ref local_sha remote_ref remote_sha' -or -not $prePushHook.Contains('-PushRange')) {
    throw 'Pre-push hook must pass Git-provided ref update ranges to the secret scan'
}
$excludedRepositoryPathPattern = '(^|[\\/])(\.git|\.worktrees|temp)([\\/]|$)'
$simulatedWorktreeRoot = Join-Path $repoRoot '.worktrees/T-SIMULATED'
$expectedWorktreeScript = Join-Path $simulatedWorktreeRoot 'scripts/quality-gate.ps1'
$nestedWorktreeScript = Join-Path $simulatedWorktreeRoot '.worktrees/T-OTHER/scripts/quality-gate.ps1'
$expectedRelativePath = [System.IO.Path]::GetRelativePath($simulatedWorktreeRoot, $expectedWorktreeScript)
$nestedRelativePath = [System.IO.Path]::GetRelativePath($simulatedWorktreeRoot, $nestedWorktreeScript)
if ($expectedRelativePath -match $excludedRepositoryPathPattern -or $nestedRelativePath -notmatch $excludedRepositoryPathPattern) {
    throw 'Worktree path fixture must include files at the checkout root and exclude nested worktrees'
}
$qualityGate = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/quality-gate.ps1') -Raw
$expectedPathFilterSource = '$relativePath -notmatch ' + [char]39 + $excludedRepositoryPathPattern + [char]39
if (
    -not $qualityGate.Contains('[System.IO.Path]::GetRelativePath($repoRoot, $_.FullName)') -or
    -not $qualityGate.Contains($expectedPathFilterSource) -or
    $qualityGate -notmatch 'if \(\$scriptFiles\.Count -eq 0\)'
) {
    throw 'Quality gate must use relative worktree path exclusions and fail when no scripts are scanned'
}
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
$expectedPullRequestRule = @{
    dismissStaleReviewsOnPush = $true
    requiredReviewers = @()
    requireCodeOwnerReview = $false
    requireLastPushApproval = $false
    requireExtraApprovalForUnattributedChanges = $true
}
foreach ($propertyName in $expectedPullRequestRule.Keys) {
    if (-not $ruleset.rules.PSObject.Properties[$propertyName]) {
        throw "Ruleset manifest is missing live pull-request setting $propertyName"
    }
    if ($propertyName -eq 'requiredReviewers') {
        if (@($ruleset.rules.$propertyName).Count -ne 0) {
            throw 'Ruleset manifest unexpectedly requires named reviewers'
        }
    } elseif ($ruleset.rules.$propertyName -ne $expectedPullRequestRule[$propertyName]) {
        throw "Ruleset manifest has unexpected value for $propertyName"
    }
}
$taskCloseout = Get-Content -LiteralPath (Join-Path $repoRoot 'tasks/T-001-sync-required-status-check.md') -Raw
if ($taskCloseout -notmatch '(?m)^\*\*Статус:\*\* merged;' -or $taskCloseout -notmatch 'review-доказательства') {
    throw 'T-001 closeout must record merge state and the review-evidence gap'
}
$handoff = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/handoff.md') -Raw
if ($handoff -match 'После merge T-001' -or $handoff -notmatch 'T-003') {
    throw 'Handoff must not leave the merged T-001 step open and must identify current T-003 work'
}
$taskTwoCloseout = Get-Content -LiteralPath (Join-Path $repoRoot 'tasks/T-002-reconcile-github-settings-and-closeout.md') -Raw
if (
    $taskTwoCloseout -notmatch '(?m)^\*\*Статус:\*\* merged\s*$' -or
    $taskTwoCloseout -notmatch 'Merge SHA:\*\* c98a1922dee2dedeaed6eeb528d72098beb3a128' -or
    $taskTwoCloseout -notmatch 'PR head `e9db06ad083d007d15e0674d195f16999fbfc93b`' -or
    $taskTwoCloseout -notmatch 'base `65b5ab35d46b81e5af1963c351d05ac5da0291dc`' -or
    $taskTwoCloseout -notmatch 'hosted run `43592810050` — `SUCCESS`' -or
    $taskTwoCloseout -notmatch 'event merge-result `04bf30fd6879f4d18abf3c270cd05e5428e55079`' -or
    $taskTwoCloseout -notmatch 'GitHub прикрепил check к PR head' -or
    $taskTwoCloseout -notmatch 'workflow проверил `github.sha`'
) {
    throw 'T-002 closeout must distinguish the check association SHA from the tested event SHA'
}
$handoff = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/handoff.md') -Raw
if (
    $handoff -match '(?i)draft.{0,20}PR #2|PR #2.{0,20}draft|до merge PR #2' -or
    $handoff -notmatch 'c98a1922dee2dedeaed6eeb528d72098beb3a128' -or
    $handoff -notmatch 'T-002 закрыта' -or
    $handoff -notmatch 'run #43592810050' -or
    $handoff -notmatch '04bf30fd6879f4d18abf3c270cd05e5428e55079'
) {
    throw 'Handoff must reflect the merged T-002 state and its exact CI SHA roles'
}
$githubResearch = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/github-research.md') -Raw
$historicalResearchSection = [regex]::Match($githubResearch, '(?ms)^## Исторический срез до merge PR #2\b.*?(?=^## |\z)').Value
$currentResearch = [regex]::Replace($githubResearch, '(?ms)^## Исторический срез до merge PR #2\b.*?(?=^## |\z)', '')
if (
    [string]::IsNullOrWhiteSpace($historicalResearchSection) -or
    $historicalResearchSection -notmatch 'T-002 остаётся отдельной draft PR' -or
    $currentResearch -match '(?i)T-002 остаётся отдельной draft PR|Завершить T-002 после независимого review' -or
    $githubResearch -notmatch 'GET /user вернул email = null' -or
    $githubResearch -notmatch 'не подтверждает приватный commit email' -or
    $githubResearch -notmatch 'Owner decision for the next CI-trust stage: do not add an external GitHub App'
) {
    throw 'Research must label pre-merge T-002 state as historical and preserve the current closeout/owner decision'
}
$nullEmailInferenceIsUnsafe = {
    param([string]$Text)
    foreach ($paragraph in ($Text -split '(?:\r?\n){2,}|(?m)(?=^\s*[-*]\s)')) {
        if ($paragraph -notmatch '(?i)(?:email\s*=\s*null|null\s+email)') { continue }
        $claims = $paragraph -split '(?i)[;.!?]+|\b(?:but|however|но|однако)\b'
        foreach ($claim in $claims) {
            if (
                $claim -match '(?i)(?:\b(?:prove|proves|confirm|confirms|demonstrate|demonstrates)\b|доказывает|подтверждает)' -and
                $claim -match '(?i)(?:commit[\s-]*email|noreply|privacy|private|приватн\w*)' -and
                $claim -notmatch '(?i)(?:\bnot\b|\bnever\b|\bcannot\b|doesn''t|isn''t|\bне\b|\bнельзя\b)'
            ) { return $true }
        }
    }
    return $false
}
$unsafePrivacyFixture = 'GET /user email = null. This proves private commit email.'
$safePrivacyFixture = 'GET /user email = null. This does not prove private commit email.'
$separateBulletFixture = [string]::Join([Environment]::NewLine, @('- GET /user email = null.', '- A separate note confirms that the task records commit privacy decisions.'))
if (-not (& $nullEmailInferenceIsUnsafe $unsafePrivacyFixture) -or (& $nullEmailInferenceIsUnsafe $safePrivacyFixture) -or (& $nullEmailInferenceIsUnsafe $separateBulletFixture)) {
    throw 'Privacy regression detector must reject an unnegated false claim and accept a negated one'
}
$privacyDocs = @(
    $handoff
    $githubResearch
    $taskTwoCloseout
    (Get-Content -LiteralPath (Join-Path $repoRoot 'tasks/T-003-closeout-and-email-privacy-plan.md') -Raw)
    (Get-Content -LiteralPath (Join-Path $repoRoot 'docs/roadmap.md') -Raw)
) -join [Environment]::NewLine
if (
    $privacyDocs -match '[A-Za-z0-9._%+-]+@(?!users\.noreply\.github\.com)[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -or
    (& $nullEmailInferenceIsUnsafe $privacyDocs)
) {
    throw 'Public T-003 docs must not publish external email addresses or infer commit privacy from profile email=null'
}
$roadmap = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/roadmap.md') -Raw
if ($roadmap -notmatch 'no-App CI model: repository owner is the trust root') {
    throw 'Roadmap must preserve the owner-approved no-App trust decision'
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
