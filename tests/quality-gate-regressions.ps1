Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $repoRoot 'scripts/ide-cache.ps1')
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
$directorySeparatorClass = '[/\x5c]'
$excludedRepositoryPathPattern = '(^|' + $directorySeparatorClass + ')(\.git|\.worktrees|temp)(' + $directorySeparatorClass + '|$)'
$simulatedWorktreeRoot = Join-Path $repoRoot '.worktrees/T-SIMULATED'
$expectedWorktreeScript = Join-Path $simulatedWorktreeRoot 'scripts/quality-gate.ps1'
$nestedWorktreeScript = Join-Path $simulatedWorktreeRoot '.worktrees/T-OTHER/scripts/quality-gate.ps1'
$expectedRelativePath = [System.IO.Path]::GetRelativePath($simulatedWorktreeRoot, $expectedWorktreeScript)
$nestedRelativePath = [System.IO.Path]::GetRelativePath($simulatedWorktreeRoot, $nestedWorktreeScript)
if ($expectedRelativePath -match $excludedRepositoryPathPattern -or $nestedRelativePath -notmatch $excludedRepositoryPathPattern) {
    throw 'Worktree path fixture must include files at the checkout root and exclude nested worktrees'
}
$qualityGate = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/quality-gate.ps1') -Raw
if (-not $qualityGate.Contains('Get-ProjectFiles $repoRoot') -or
    $qualityGate -notmatch 'if \(\$scriptFiles\.Count -eq 0\)') {
    throw 'Quality gate must use scoped file enumeration and fail when no scripts are scanned'
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
$revisionMetadata = @([regex]::Matches($taskTwoCloseout, '(?m)^\*\*Проверенные ревизии:\*\*.*$'))
$expectedRevisionMetadata = '^\*\*Проверенные ревизии:\*\* PR head `e9db06ad083d007d15e0674d195f16999fbfc93b`; base `65b5ab35d46b81e5af1963c351d05ac5da0291dc`; hosted run `43592810050` — `SUCCESS`; тестовый event merge-result `04bf30fd6879f4d18abf3c270cd05e5428e55079`\.$'
if (
    $taskTwoCloseout -notmatch '(?m)^\*\*Статус:\*\* merged\s*$' -or
    $taskTwoCloseout -notmatch '(?m)^\*\*PR:\*\* #2 — https://github\.com/g0ldenc0de2027/Development-folder-V\.2/pull/2$' -or
    $revisionMetadata.Count -ne 1 -or
    $revisionMetadata[0].Value -notmatch $expectedRevisionMetadata -or
    $taskTwoCloseout -notmatch '(?m)^\*\*Merge SHA:\*\* c98a1922dee2dedeaed6eeb528d72098beb3a128$' -or
    $taskTwoCloseout -notmatch '(?m)^\*\*Review:\*\* Gemini 4 Argon \(Antigravity\) вынес APPROVE для точной указанной тройки SHA\. Отчёт не является GitHub-native approval; GitHub API не содержит review submission\.$' -or
    $taskTwoCloseout -notmatch '(?ms)^### Результат приёмки\r?\nВсе шесть критериев выполнены\.[^\r\n]*\r?\n\r?\n\*\*Тип:\*\* .+\r?\n\*\*База:\*\*'
) {
    throw 'T-002 must bind its exact PR/review/revision tuple and keep task metadata separate from the acceptance paragraph'
}
if (
    $handoff -match '(?i)draft.{0,20}PR #2|PR #2.{0,20}draft|до merge PR #2' -or
    $handoff -notmatch 'c98a1922dee2dedeaed6eeb528d72098beb3a128' -or
    $handoff -match 'e9db06ad083d007d15e0674d195f16999fbfc93b|65b5ab35d46b81e5af1963c351d05ac5da0291dc|43592810050|04bf30fd6879f4d18abf3c270cd05e5428e55079' -or
    $handoff -notmatch 'T-002-reconcile-github-settings-and-closeout\.md' -or
    $handoff -notmatch 'T-002.*слита'
) {
    throw 'Handoff must summarize merged T-002, point to its immutable evidence card and avoid duplicating its stale revision tuple'
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
    $githubResearch -notmatch 'Owner decision for the next CI-trust stage: do not add an external GitHub App' -or
    $currentResearch -notmatch 'PR synthetic merge-result commits are PR refs, not commits on main\.'
) {
    throw 'Research must preserve the historical boundary, email limitation, no-App decision and main-versus-synthetic-ref distinction'
}
$roadmap = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/roadmap.md') -Raw
if ($roadmap -notmatch 'Implement remaining no-App merge safeguards: owner remains the trust root') {
    throw 'Roadmap must preserve the owner-approved no-App trust decision'
}
$githubWorkflowGuide = Get-Content -LiteralPath (Join-Path $repoRoot 'docs/github-workflow.md') -Raw
if (
    $githubWorkflowGuide -notmatch 'корнем доверия' -or
    $githubWorkflowGuide -notmatch 'организационный merge gate' -or
    $githubWorkflowGuide -notmatch 'GitHub её не обеспечивает' -or
    $githubWorkflowGuide -notmatch 'PR может изменить собственное определение workflow или quality gate' -or
    $githubWorkflowGuide -notmatch 'Остаточный риск принят владельцем' -or
    $handoff -notmatch 'организационный контроль'
) {
    throw 'No-App owner-root-of-trust decision and non-enforced gate residual risk must be explicit in workflow and handoff'
}
if (
    $roadmap -notmatch 'Code-fix verification tuple: head 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982, base c98a1922dee2dedeaed6eeb528d72098beb3a128' -or
    $roadmap -notmatch 'hosted run 43622066954 SUCCESS' -or
    $roadmap -notmatch 'event/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f' -or
    $roadmap -notmatch 'GitHub Actions validates every later PR revision separately' -or
    $roadmap -notmatch 'No per-file blob or aggregate push-size gate exists yet' -or
    $roadmap -match 'existing per-file staged-blob limit' -or
    $roadmap -notmatch 'fresh independent review on the latest PR head remains required' -or
    $handoff -notmatch 'code-fix commit 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982' -or
    $handoff -notmatch 'hosted run 43622066954 SUCCESS' -or
    $handoff -notmatch 'актуальный статус смотреть в PR #3'
) {
    throw 'Roadmap and handoff must retain code-fix provenance without claiming stale live PR status'
}
$taskThree = Get-Content -LiteralPath (Join-Path $repoRoot 'tasks/T-003-closeout-and-email-privacy-plan.md') -Raw
if (
    $taskThree -notmatch 'Antigravity \(Gemini 4 Argon\)' -or
    $taskThree -notmatch '9c486a3a653f423add97ee93b376ffde8a42154e' -or
    $taskThree -notmatch 'GitHub Copilot проверил head 363cfdbc' -or
    $taskThree -notmatch 'P2-1\.\.P2-3 и P3-1' -or
    $taskThree -notmatch 'Copilot checked exact PR #3 head bbd8abc223099b368407cd7082f6cec409d5c6e6' -or
    $taskThree -notmatch 'Run 43618469816 succeeded.*merge-result 4592797ecefdf767903ae37d37522f52fa1a3146' -or
    $taskThree -notmatch 'P2:.*copular privacy predicate' -or
    $taskThree -notmatch 'code-fix commit 5c3eaf06dd5ee9a518659db015e4ffbc54b8a982' -or
    $taskThree -notmatch 'hosted run 43622066954 SUCCESS.*event/test merge-result 5fb052c8094ceb3f530b306d8ba164416411d63f' -or
    $taskThree -notmatch 'This tuple records that code-fix revision only' -or
    $taskThree -notmatch 'GitHub API showed no native review submissions' -or
    $taskThree -notmatch 'bounded heuristic and does not guarantee recognition of arbitrary paraphrases'
) {
    throw 'T-003 must preserve review provenance and distinguish historical code-fix evidence from later PR revisions'
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
    Get-ProjectFiles $repoRoot |
        Where-Object { $_.Extension -in $textExtensions -or $_.Name -in $specialTextNames }
)
if ($textFiles.Count -eq 0) {
    throw 'Text hygiene scan found no repository files'
}

$privacyMarkdownFiles = @($textFiles | Where-Object { $_.Extension -ieq '.md' })
$privacyTestSource = Get-Item -LiteralPath (Join-Path $repoRoot 'tests/quality-gate-regressions.ps1')
$privacyScanFiles = @($privacyMarkdownFiles) + @($privacyTestSource)
$privacyScanRelativePaths = @(
    $privacyScanFiles | ForEach-Object {
        [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/')
    }
)
$requiredPrivacyPaths = @(
    'docs/handoff.md',
    'docs/github-research.md',
    'docs/roadmap.md',
    'tasks/T-002-reconcile-github-settings-and-closeout.md',
    'tasks/T-003-closeout-and-email-privacy-plan.md',
    'tests/quality-gate-regressions.ps1'
)
$missingPrivacyPaths = @($requiredPrivacyPaths | Where-Object { $_ -notin $privacyScanRelativePaths })
if ($privacyMarkdownFiles.Count -eq 0 -or $missingPrivacyPaths.Count -gt 0) {
    throw ('Privacy scan must cover every public Markdown document and all T-003 files; missing: ' + ($missingPrivacyPaths -join ', '))
}

$emailLocalPartPattern = '[\p{L}\p{N}._%+-]+'
$emailDomainLabel = '[\p{L}\p{N}](?:[\p{L}\p{M}\p{N}-]{0,61}[\p{L}\p{M}\p{N}])?'
$emailTldPattern = '(?:[A-Z]{2,63}|xn--[A-Z0-9-]{2,59}|[\p{L}]{2,63})'
$emailDomainPattern = "(?:$emailDomainLabel\.)+$emailTldPattern"
$emailPattern = "(?i)(?<![\p{L}\p{N}._%+-])(?<local>$emailLocalPartPattern)@(?<domain>$emailDomainPattern)(?![\p{L}\p{N}-])"
$emailAtObfuscationPattern = '(?:\[at\]|\(at\)|\{at\}|%40|&#0*64;|&#x0*40;|&commat;|＠|[ \t]+at[ \t]+)'
$emailDomainSeparator = '(?:[ \t]*\.[ \t]*|[ \t]+dot[ \t]+|[ \t]*\[(?:dot)\][ \t]*|[ \t]*\(dot\)[ \t]*|[ \t]*\{dot\}[ \t]*)'
$emailObfuscatedTldPattern = '(?:[A-Z]{2,63}|xn--[A-Z0-9-]{2,59}|[\p{L}]{2,63})'
$emailDomainObfuscationPattern = "(?:$emailDomainLabel(?:$emailDomainSeparator$emailDomainLabel)*$emailDomainSeparator$emailObfuscatedTldPattern)"
$obfuscatedEmailPattern = "(?i)(?<![\p{L}\p{N}._%+-])$emailLocalPartPattern[ \t]*$emailAtObfuscationPattern[ \t]*$emailDomainObfuscationPattern(?![\p{L}\p{N}-])"
$drivePathPattern = '(?<![A-Z0-9])[A-Z]:[/\x5c][^\s\x60<>]+'
$uncPathPattern = '(?<!\w)\x5c{2}[^\x5c\s\x60<>]+\x5c[^\x5c\s\x60<>]+(?:\x5c[^\s\x60<>]+)*'
$slash = [string][char]47
$slashUncPattern = '(?<!\w)(?<!:)(?<!/)' + $slash + $slash + '[^/\s\x60<>]+/[^/\s\x60<>]+(?:/[^\s\x60<>]+)*'
$posixPathPattern = '(?<!\w)(?<!:)(?<!/)/(?:home|users|mnt|media|volumes|tmp|var|etc|opt|srv|root|private|workspace|workspaces|applications|library|system|run)/[^\s\x60<>]+'
$msysPathPattern = '(?<!\w)(?<!:)(?<!/)/[a-z]/(?:users|home|mnt|msys64|mingw64|program files)/[^\s\x60<>]+'
$absoluteLocalPathPattern = "(?i)$drivePathPattern|$uncPathPattern|$slashUncPattern|$posixPathPattern|$msysPathPattern"
$allowedSystemCommitterLocalPart = 'noreply'
$allowedSystemCommitterDomain = 'github.com'
$findPrivacyFindings = {
    param([string]$Text)
    $findings = [System.Collections.Generic.List[string]]::new()
    foreach ($match in [regex]::Matches($Text, $emailPattern)) {
        $localPart = $match.Groups['local'].Value
        $domain = $match.Groups['domain'].Value
        if ($localPart -ine $allowedSystemCommitterLocalPart -or $domain -ine $allowedSystemCommitterDomain) {
            $findings.Add('email')
        }
    }
    if ([regex]::IsMatch($Text, $obfuscatedEmailPattern)) {
        $findings.Add('obfuscated-email')
    }
    foreach ($line in ($Text -split '\r?\n')) {
        $urls = [regex]::Matches($line, '(?i)\bhttps?://[^\s\x60<>]+')
        foreach ($match in [regex]::Matches($line, $absoluteLocalPathPattern)) {
            $insideUrl = $false
            foreach ($url in $urls) {
                if ($match.Index -ge $url.Index -and $match.Index -lt ($url.Index + $url.Length)) {
                    $insideUrl = $true
                    break
                }
            }
            if ($insideUrl) { continue }
            $prefix = $line.Substring(0, $match.Index)
            if ($prefix -match '(?i)\b(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)\s*$') { continue }
            $findings.Add('absolute-local-path')
            break
        }
    }
    return $findings.ToArray()
}
# Bounded English/Russian text heuristic, not a semantic parser; fixtures define supported claim patterns.
$nullEmailInferenceIsUnsafe = {
    param([string]$Text)
    $normalizedText = $Text.Replace([string][char]96, '').Replace('"', '')
    $nullEmailSignal = '(?i)(?:/user[\s._/-]{0,20})?(?:email(?:\s+(?:field|property))?|\b(?:field|property)\s+email)\s*(?:==|=|:|\b(?:is|was|returned|equals?)\b|равен|равно)\s*(?:null|nil|none)\b|\bemail\s+(?:is\s+)?(?:null|nil|none)\b|\b(?:null|nil|none)\s+email\b'
    $positiveVerbPattern = '(?:prove\w*|proven|confirm\w*|demonstrat\w*|show\w*|shown|mean\w*|indicat\w*|establish\w*|доказ\w*|подтвержд\w*|показ\w*|означа\w*|свидетельств\w*|установ\w*)'
    $copularPrivacyPredicate = '(?:\b(?:is|are|was|were|remain(?:s|ed)?|stay(?:s|ed)?|become(?:s|d)?)(?:\s+(?:not|never|no\s+longer))?\s+(?:private|privat\w*|приватн\w*))'
    $positiveClaim = "(?i)\b(?:$positiveVerbPattern|$copularPrivacyPredicate)\b"
    $pairedPredicatePattern = "(?i)\b(?:$positiveVerbPattern|disprove\w*|refute\w*|опроверг\w*)\b"
    $privacyTarget = '(?i)(?:commit[\s-]*email|email[\s-]*(?:privacy|private|privat\w*)|(?:privacy|private|privat\w*)[\s-]+email|(?:email|почт\w*)[\s-]*(?:address|адрес)?\s*.{0,24}\b(?:private|privat\w*|приватн\w*)|noreply)'
    $claimSeparators = '(?i)[,:](?=\s*(?:it|this|that|these|those|the|a|an|we|you|they|he|she|i|поле|это|данн\w*)\b)|\s+(?:but|however|whereas|while|although|though|но|однако|зато|и\s+при\s+этом|а)\s+|\s+(?:because|since|потому\s+что|так\s+как|поскольку)\s+|\s+(?:and|и)\s+(?=(?:it|this|that|these|those|we|you|they|he|she|i|поле|это|данн\w*)\b)|\s+-\s+|[\u2012-\u2015]|\s+/\s+|[;()]'
    $negativeBeforePredicate = '(?i)(?:\b(?:does\s+not|do\s+not|did\s+not|doesn''t|don''t|didn''t|cannot|can''t|never|не)\b|\bnot\b(?!\s+(?:only|just|insufficient|impossible)\b))(?:(?:[\s,;()]+)(?!(?:fail\w*|переста\w*)\b)[\p{L}\p{M}\p{N}_-]+){0,6}[\s,;()]*$|\b(?:is\s+)?insufficient\s+(?:to|for)\s*$|\bнедостаточн\w*\s+(?:чтобы|для)\s*$|\bno\s+(?:evidence|proof)\b.{0,40}$'
    $doubleNegationPattern = '(?i)\b(?:does\s+not\s+fail\w*\s+to|never\s+fails?\s+to|not\s+(?:is\s+)?insufficient\b|not\s+impossible\b|не\s+(?:переста\w*|может\s+не)\b)'
    $independentEvidenceSourcePattern = '(?i)\b(?:separate|independent|standalone|another|distinct)\b.{0,80}\b(?:api|check|verification|audit|source)\b|\b(?:отдельн\w*|независим\w*|друг\w*)\b.{0,80}\b(?:api|провер\w*|аудит|источник)\b'
    foreach ($block in ($normalizedText -split '(?:\r?\n){2,}|(?m)(?=^\s*(?:[-*]|\d+[.)])\s)')) {
        $previousSentenceHadSignal = $false
        $sentences = $block -split '(?<=[.!?])[\t ]+(?=[\p{L}\p{N}])|(?<=[.!?])\r?\n+'
        foreach ($sentence in $sentences) {
            $sentenceHasSignal = $sentence -match $nullEmailSignal
            $startsWithReference = $sentence -match '(?i)^\s*(?:it|this|that|these|those|therefore|thus|hence|consequently|while|although|though|whereas|neither|ни|a|an|the|это|поле|значение|результат|данн\w*\s+(?:поле|значение|результат)|поэтому|следовательно|значит|хотя|несмотря\s+на|впрочем)\b'
            $shouldAnalyze = $sentenceHasSignal -or ($previousSentenceHadSignal -and $startsWithReference)
            $previousSentenceHadSignal = $sentenceHasSignal
            if (-not $shouldAnalyze) { continue }
            $claims = @($sentence -split $claimSeparators)
            $firstRelevantClaim = 0
            if ($sentenceHasSignal) {
                $firstRelevantClaim = -1
                for ($index = 0; $index -lt $claims.Count; $index++) {
                    if ($claims[$index] -match $nullEmailSignal) {
                        $firstRelevantClaim = $index
                        break
                    }
                }
                if ($firstRelevantClaim -lt 0) { continue }
            }
            for ($index = $firstRelevantClaim; $index -lt $claims.Count; $index++) {
                $claim = $claims[$index]
                $independentEvidenceSources = [regex]::Matches($claim, $independentEvidenceSourcePattern)
                $verbs = [regex]::Matches($claim, $positiveClaim)
                $targets = [regex]::Matches($claim, $privacyTarget)
                $predicateNegations = [System.Collections.Generic.List[bool]]::new()
                for ($verbIndex = 0; $verbIndex -lt $verbs.Count; $verbIndex++) {
                    $verb = $verbs[$verbIndex]
                    $localStart = 0
                    if ($verbIndex -gt 0) {
                        $previousVerb = $verbs[$verbIndex - 1]
                        $localStart = $previousVerb.Index + $previousVerb.Length
                    }
                    $prefixStart = $localStart
                    if ($verb.Value -match '(?i)^(?:is|are|was|were|remain|remains|remained|stay|stays|stayed|become|becomes|became)\b') { $prefixStart = 0 }
                    $prefix = $claim.Substring($prefixStart, $verb.Index - $prefixStart)
                    $isDoubleNegation = $prefix -match $doubleNegationPattern
                    $isCopularNegation = $verb.Value -match '(?i)\b(?:not|never|no\s+longer)\b'
                    $isNegated = $isCopularNegation -or (-not $isDoubleNegation -and $prefix -match $negativeBeforePredicate)
                    if ($verbIndex -gt 0 -and $predicateNegations[$verbIndex - 1]) {
                        $previousVerb = $verbs[$verbIndex - 1]
                        $betweenVerbs = $claim.Substring(
                            $previousVerb.Index + $previousVerb.Length,
                            $verb.Index - ($previousVerb.Index + $previousVerb.Length)
                        )
                        if ($betweenVerbs -match '(?i)^\s*(?:,\s*)?(?:(?:and|or|nor|и|или|либо|ни)\s*)?$') {
                            $isNegated = $true
                        }
                    }
                    $predicateNegations.Add([bool]$isNegated)
                    if ($isNegated) { continue }

                    $hasDirectIndependentEvidence = $false
                    foreach ($source in $independentEvidenceSources) {
                        $sourceEnd = $source.Index + $source.Length
                        if ($verb.Index -lt $sourceEnd) { continue }
                        $evidenceGapLength = $verb.Index - $sourceEnd
                        if ($evidenceGapLength -gt 40) { continue }
                        $evidenceGap = $claim.Substring($sourceEnd, $evidenceGapLength)
                        if ($evidenceGap -match '(?i)^\s*(?:(?:directly|independently|separately|also|прямо|независимо|отдельно|также)\s+){0,2}$') {
                            $hasDirectIndependentEvidence = $true
                            break
                        }
                    }
                    if ($hasDirectIndependentEvidence) { continue }

                    foreach ($target in $targets) {
                        if ($target.Index -ge ($verb.Index + $verb.Length)) {
                            $distance = $target.Index - ($verb.Index + $verb.Length)
                        } elseif (($target.Index + $target.Length) -le $verb.Index) {
                            $distance = $verb.Index - ($target.Index + $target.Length)
                        } else {
                            $distance = 0
                        }
                        if ($distance -gt 120) { continue }

                        $negativePairStart = [regex]::Match($claim, '(?i)\bneither\b|\bни\b')
                        if ($negativePairStart.Success) {
                            if ($negativePairStart.Value -match '(?i)^neither$') {
                                $negativePairEndPattern = '(?i)\bnor\b'
                            } else {
                                $negativePairEndPattern = '(?i)\bни\b'
                            }
                            $negativePairEndMatcher = [regex]::new($negativePairEndPattern)
                            $negativePairEnd = $negativePairEndMatcher.Match(
                                $claim,
                                $negativePairStart.Index + $negativePairStart.Length
                            )
                            if ($negativePairEnd.Success) {
                                $pairEnd = $negativePairEnd.Index + $negativePairEnd.Length
                                $beforePairEnd = $claim.Substring(
                                    $negativePairStart.Index + $negativePairStart.Length,
                                    $negativePairEnd.Index - ($negativePairStart.Index + $negativePairStart.Length)
                                )
                                $afterPairEnd = $claim.Substring($pairEnd)
                                $firstPairedVerb = [regex]::Match($beforePairEnd, $pairedPredicatePattern)
                                $secondPairedVerb = [regex]::Match($afterPairEnd, $pairedPredicatePattern)
                                $pairedPredicateClaim = $false
                                if ($firstPairedVerb.Success -and $secondPairedVerb.Success) {
                                    $firstPairedVerbIndex = $negativePairStart.Index + $negativePairStart.Length + $firstPairedVerb.Index
                                    $secondPairedVerbIndex = $pairEnd + $secondPairedVerb.Index
                                    $verbIsInPair = $verb.Index -eq $firstPairedVerbIndex -or $verb.Index -eq $secondPairedVerbIndex
                                    $targetFollowsBothPredicates = $target.Index -ge ($secondPairedVerbIndex + $secondPairedVerb.Length)
                                    $pairedPredicateClaim = $verbIsInPair -and $targetFollowsBothPredicates
                                }
                                $nominalPairPrefix = $claim.Substring(0, $verb.Index)
                                $afterPairBeforeVerb = ''
                                if ($verb.Index -ge $pairEnd) {
                                    $afterPairBeforeVerb = $claim.Substring($pairEnd, $verb.Index - $pairEnd)
                                }
                                $nominalPairStartsWithNeither = $nominalPairPrefix -match '(?is)^\s*(?:it\s+)?neither\b(?:(?!\bnor\b)[\s\S]){1,80}\bnor\b.{1,32}$'
                                $nominalPairStartsWithRussianNi = $nominalPairPrefix -match '(?is)^\s*ни\b(?:(?!\bни\b)[\s\S]){1,80}\bни\b.{1,32}$'
                                $containsNewSubjectAfterPair = $afterPairBeforeVerb -match '(?i)\b(?:this|that|it|these|those|therefore|thus|hence|while|although|though|whereas|это|этот|эта|эти|он|она|они|поэтому|следовательно)\b'
                                $nominalPairSubject = (
                                    -not $firstPairedVerb.Success -and
                                    $verb.Index -ge $pairEnd -and
                                    $target.Index -ge ($verb.Index + $verb.Length) -and
                                    -not $containsNewSubjectAfterPair -and
                                    ($nominalPairStartsWithNeither -or $nominalPairStartsWithRussianNi)
                                )
                                if ($pairedPredicateClaim -or $nominalPairSubject) { continue }
                            }
                        }
                        return $true
                    }
                }
            }
        }
    }
    return $false
}

# GitHub documents the required system committer identity for web-based merges:
# https://docs.github.com/en/enterprise-cloud@latest/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
$allowedSystemAddressFixture = 'noreply' + [char]64 + 'github.com'
$externalEmailFixture = 'owner' + [char]64 + 'example.invalid'
$personalNoreplyFixture = 'owner' + [char]64 + 'users.noreply.github.com'
$suffixLookalikeFixture = 'owner' + [char]64 + 'users.noreply.github.com.attacker.invalid'
$underscoreNearAllowedFixture = 'x_' + 'noreply' + [char]64 + 'github.com'
$unicodeDomainFixture = 'owner' + [char]64 + 'пример.рф'
$punycodeDomainFixture = 'owner' + [char]64 + 'example.xn--p1ai'
$obfuscatedAtFixture = 'owner [' + 'at] example.invalid'
$encodedAtFixture = 'owner%' + '40example.invalid'
$wordAtDotFixture = 'owner' + ' at ' + 'example' + ' dot ' + 'invalid'
$tabAtDotFixture = 'owner' + [char]9 + 'at' + [char]9 + 'example' + [char]9 + 'dot' + [char]9 + 'invalid'
$bracketDotFixture = 'owner [at] example [' + 'dot] invalid'
$parentheticalDotFixture = 'owner (at) example (' + 'dot) invalid'
$multilineAtFixture = 'owner' + [char]10 + 'at' + [char]10 + 'example dot invalid'
$fullWidthAtFixture = 'owner' + [char]0xFF20 + 'example.invalid'
$absoluteWindowsPathFixture = 'D:' + [char]92 + 'Owner' + [char]92 + 'private.md'
$absolutePosixPathFixture = '/' + 'home/Owner/private.md'
$absoluteUncPathFixture = ([string][char]92 + [string][char]92 + 'server' + [char]92 + 'share' + [char]92 + 'private.md')
$absoluteSlashUncPathFixture = ([string][char]47 + [string][char]47 + 'server/share/private.md')
$absoluteMsysPathFixture = '/' + 'c/Users/Owner/private.md'
$absoluteMacPathFixture = '/' + 'Applications/Tool.app/Contents/Info.plist'
$absoluteLowercaseUsersPathFixture = '/' + 'users/owner/private.md'
$homeRouteFixture = 'GET /' + 'home/dashboard'
$privateRouteFixture = 'GET /' + 'private/keys'
$urlPathFixture = 'https://example.invalid/' + 'home/user/private.md'
$hyphenUsersUrlFixture = 'https://gitlab.example.invalid/group/proj/-' + '/' + 'users/me'
$hyphenHomeUrlFixture = 'https://example.invalid/api-' + '/' + 'home/dashboard'
$allowedFindings = @(& $findPrivacyFindings $allowedSystemAddressFixture)
$externalFindings = @(& $findPrivacyFindings $externalEmailFixture)
$personalNoreplyFindings = @(& $findPrivacyFindings $personalNoreplyFixture)
$suffixLookalikeFindings = @(& $findPrivacyFindings $suffixLookalikeFixture)
$underscoreNearAllowedFindings = @(& $findPrivacyFindings $underscoreNearAllowedFixture)
$unicodeDomainFindings = @(& $findPrivacyFindings $unicodeDomainFixture)
$punycodeDomainFindings = @(& $findPrivacyFindings $punycodeDomainFixture)
$obfuscatedAtFindings = @(& $findPrivacyFindings $obfuscatedAtFixture)
$encodedAtFindings = @(& $findPrivacyFindings $encodedAtFixture)
$wordAtDotFindings = @(& $findPrivacyFindings $wordAtDotFixture)
$tabAtDotFindings = @(& $findPrivacyFindings $tabAtDotFixture)
$bracketDotFindings = @(& $findPrivacyFindings $bracketDotFixture)
$parentheticalDotFindings = @(& $findPrivacyFindings $parentheticalDotFixture)
$multilineAtFindings = @(& $findPrivacyFindings $multilineAtFixture)
$fullWidthAtFindings = @(& $findPrivacyFindings $fullWidthAtFixture)
$absolutePathFindings = @(& $findPrivacyFindings $absoluteWindowsPathFixture)
$absolutePosixPathFindings = @(& $findPrivacyFindings $absolutePosixPathFixture)
$absoluteUncPathFindings = @(& $findPrivacyFindings $absoluteUncPathFixture)
$absoluteSlashUncPathFindings = @(& $findPrivacyFindings $absoluteSlashUncPathFixture)
$absoluteMsysPathFindings = @(& $findPrivacyFindings $absoluteMsysPathFixture)
$absoluteMacPathFindings = @(& $findPrivacyFindings $absoluteMacPathFixture)
$absoluteLowercaseUsersPathFindings = @(& $findPrivacyFindings $absoluteLowercaseUsersPathFixture)
$routeFindings = @(& $findPrivacyFindings ([string]::Join([Environment]::NewLine, @($homeRouteFixture, $privateRouteFixture, $urlPathFixture, $hyphenUsersUrlFixture, $hyphenHomeUrlFixture))))
$scannerFailures = [System.Collections.Generic.List[string]]::new()
$scannerExpectations = @(
    @{ Name = 'exact-system-allowlist'; Findings = $allowedFindings; Expected = $null; Finding = 'email' },
    @{ Name = 'external-email'; Findings = $externalFindings; Expected = 'email'; Finding = 'email' },
    @{ Name = 'personal-noreply'; Findings = $personalNoreplyFindings; Expected = 'email'; Finding = 'email' },
    @{ Name = 'domain-lookalike'; Findings = $suffixLookalikeFindings; Expected = 'email'; Finding = 'email' },
    @{ Name = 'local-part-boundary'; Findings = $underscoreNearAllowedFindings; Expected = 'email'; Finding = 'email' },
    @{ Name = 'unicode-domain'; Findings = $unicodeDomainFindings; Expected = 'email'; Finding = 'email' },
    @{ Name = 'punycode-domain'; Findings = $punycodeDomainFindings; Expected = 'email'; Finding = 'email' },
    @{ Name = 'at-obfuscation'; Findings = $obfuscatedAtFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'percent-encoding'; Findings = $encodedAtFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'word-at-dot'; Findings = $wordAtDotFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'horizontal-tab-obfuscation'; Findings = $tabAtDotFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'bracket-dot-obfuscation'; Findings = $bracketDotFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'parenthetical-dot-obfuscation'; Findings = $parentheticalDotFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'multiline-not-accepted'; Findings = $multilineAtFindings; Expected = $null; Finding = 'obfuscated-email' },
    @{ Name = 'fullwidth-at'; Findings = $fullWidthAtFindings; Expected = 'obfuscated-email'; Finding = 'obfuscated-email' },
    @{ Name = 'windows-path'; Findings = $absolutePathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'posix-path'; Findings = $absolutePosixPathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'backslash-unc'; Findings = $absoluteUncPathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'slash-unc'; Findings = $absoluteSlashUncPathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'msys-path'; Findings = $absoluteMsysPathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'mac-app-path'; Findings = $absoluteMacPathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'lowercase-users-path'; Findings = $absoluteLowercaseUsersPathFindings; Expected = 'absolute-local-path'; Finding = 'absolute-local-path' },
    @{ Name = 'http-routes-and-url'; Findings = $routeFindings; Expected = $null; Finding = 'absolute-local-path' }
)
foreach ($expectation in $scannerExpectations) {
    $hasFinding = $expectation.Finding -in $expectation.Findings
    $shouldFind = $null -ne $expectation.Expected
    if ($hasFinding -ne $shouldFind) {
        $scannerFailures.Add($expectation.Name)
    }
}
if ($scannerFailures.Count -gt 0) {
    throw ('Privacy scanner fixture failures (labels only): ' + ($scannerFailures -join ', '))
}
$unsafePrivacyFixtures = @(
    'GET /user.email == null; This proves private commit email.',
    'GET /user email = null. Это подтверждает приватность commit email.',
    'GET /user.email == null. This does not prove account privacy — it proves commit email privacy.',
    'GET /user.email == null. This does not prove account privacy, but it proves commit email privacy.',
    'GET /user.email == null. This does not prove account privacy, it proves commit email privacy.',
    'GET /user email = null and it proves commit email privacy.',
    'GET /user email = null while it proves private commit email.',
    'GET /user email = null. This does not prove account privacy - it proves commit email privacy.',
    'GET /user email = null. This does not prove account privacy (it proves commit email privacy).',
    'GET /user.email == null. This does not prove account privacy / it proves commit email privacy.',
    'Although GET /user email = null does not prove account privacy it proves commit email privacy.',
    'GET /user email = null. Поле не подтверждает приватность профиля и при этом доказывает приватность commit email.',
    ('GET /user email = null. This does not prove account privacy' + [Environment]::NewLine + 'it proves commit email privacy.'),
    'GET /user email = null. This does not fail to prove commit email privacy.',
    'GET /user email = null. It never fails to confirm commit email privacy.',
    'GET /user.email == null; приватность commit email подтверждена.',
    'GET /user.email == null подтверждают приватный commit email.',
    'GET /user.email == null означает приватный commit email.',
    ('GET /user.' + [char]96 + 'email' + [char]96 + ' = ' + [char]96 + 'null' + [char]96 + '; it proved private commit email.'),
    'The email field is null. This proves commit email privacy.',
    'GET /user returned "email" = "null". This proves commit email privacy.',
    'GET /user returned email is nil. This proves commit email privacy.',
    'Поле email равно null. Это означает приватный commit email.',
    'GET /user email = null. While this does not prove account privacy, it proves commit email privacy.',
    'GET /user email = null. Although this does not prove account privacy, it proves commit email privacy.',
    'GET /user email = null. Neither here nor there, this proves commit email privacy.',
    'GET /user email = null. Ни на секунду не сомневаюсь, ни капли: это доказывает приватность commit email.',
    'GET /user email = null. A separate check is not needed because this proves commit email privacy.',
    'GET /user email равен null. Это подтверждает приватность commit email.',
    'GET /user email = null. A separate check is not needed because commit email is private.',
    'GET /user email = null. The commit email is private.'
)
$safePrivacyFixtures = @(
    'GET /user email = null. This does not prove private commit email.',
    'GET /user email = null. This does not prove that the commit email is private.',
    'GET /user email = null. The commit email is not private.',
    'GET /user email = null. Публичное поле профиля не подтверждает приватный commit email.',
    'GET /user.email == null. It does not prove commit email privacy — the public profile field is insufficient.',
    'GET /user email = null. It does not, on its own, prove commit email privacy.',
    'GET /user email = null. It does not yet show commit email privacy.',
    'GET /user email = null. This does not show or prove commit email privacy.',
    'GET /user email = null. It does not prove, confirm, or show commit email privacy.',
    'GET /user email = null. This cannot prove and confirm commit email privacy.',
    'GET /user email = null. This cannot be used to prove commit email privacy.',
    'GET /user email = null. This is insufficient to prove commit email privacy.',
    'GET /user email = null. It neither proves nor disproves commit email privacy.',
    'GET /user email = null. It neither proves nor confirms commit email privacy.',
    'GET /user email = null. Neither account nor profile proves commit email privacy.',
    'GET /user email = null. Ни аккаунт, ни профиль подтверждают приватность commit email.',
    'GET /user email = null. Ни подтверждает, ни доказывает приватность commit email.',
    'GET /user email = null. It does not prove commit email privacy but merely shows that profile privacy is enabled.',
    'GET /user email = null; a separate API check confirms commit email privacy.'
)
$separateBulletFixture = [string]::Join([Environment]::NewLine, @(
    '- GET /user email = null.',
    '- A separate note confirms that the task records commit privacy decisions.'
))
for ($fixtureIndex = 0; $fixtureIndex -lt $unsafePrivacyFixtures.Count; $fixtureIndex++) {
    if (-not (& $nullEmailInferenceIsUnsafe $unsafePrivacyFixtures[$fixtureIndex])) {
        throw ('Privacy regression detector missed unsafe fixture index ' + $fixtureIndex)
    }
}
for ($fixtureIndex = 0; $fixtureIndex -lt $safePrivacyFixtures.Count; $fixtureIndex++) {
    if (& $nullEmailInferenceIsUnsafe $safePrivacyFixtures[$fixtureIndex]) {
        throw ('Privacy regression detector flagged safe fixture index ' + $fixtureIndex)
    }
}
if (& $nullEmailInferenceIsUnsafe $separateBulletFixture) {
    throw 'Privacy regression detector must not combine unrelated claims from separate bullets'
}

$privacyFindings = [System.Collections.Generic.List[string]]::new()
foreach ($file in $privacyScanFiles) {
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName).Replace('\', '/')
    $content = [System.IO.File]::ReadAllText($file.FullName)
    $filePrivacyFindings = @(& $findPrivacyFindings $content)

    foreach ($finding in $filePrivacyFindings) {
        $privacyFindings.Add(('{0}:{1}' -f $relativePath, $finding))
    }
    if ($file.Extension -ieq '.md' -and (& $nullEmailInferenceIsUnsafe $content)) {
        $privacyFindings.Add(('{0}:unsupported-email-privacy-inference' -f $relativePath))
    }
}
if ($privacyFindings.Count -gt 0) {
    throw ('Public documentation privacy checks found sensitive patterns without printing their contents: ' + ($privacyFindings -join ', '))
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

Write-Output ('PASS: GitHub gate invariants; privacy checks covered {0} Markdown documents and the regression source; hygiene checked {1} text files' -f $privacyMarkdownFiles.Count, $textFiles.Count)
