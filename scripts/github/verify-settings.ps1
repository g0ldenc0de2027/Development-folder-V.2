[CmdletBinding()]
param(
    [switch]$RequireStatusCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$setupIncomplete = $false


function Get-GitHubJson {
    param([Parameter(Mandatory)][string]$Endpoint)
    $raw = & gh api $Endpoint 2>$null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Read-only GitHub API request failed: $Endpoint"
    }
    return ($raw -join [Environment]::NewLine) | ConvertFrom-Json
}

function Assert-Value {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)]$Expected
    )
    if ($Actual -ne $Expected) {
        throw "$Name mismatch: expected '$Expected'"
    }
    Write-Output "PASS: $Name"
}

try {
    $null = Get-Command gh -ErrorAction Stop
    $repositoryConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json
    $actionConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/actions-policy.json') -Raw | ConvertFrom-Json
    $rulesConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/main-ruleset.json') -Raw | ConvertFrom-Json
    $login = & gh api user --jq .login 2>$null
    $authExit = $LASTEXITCODE
    if ($authExit -ne 0 -or -not ($login -join '').Trim()) {
        throw 'GitHub CLI authentication is missing, invalid, or expired; run gh auth login and retry.'
    }
    Write-Output 'PASS: GitHub CLI authentication'

    $slug = $repositoryConfig.repository

    $repo = Get-GitHubJson "repos/$slug"
    $requiredRepoProperties = @('visibility','default_branch','allow_squash_merge','allow_merge_commit','allow_rebase_merge','delete_branch_on_merge','has_issues','has_discussions','security_and_analysis')
    $missingRepoProperties = @($requiredRepoProperties | Where-Object { -not $repo.PSObject.Properties[$_] })
    if ($missingRepoProperties.Count -gt 0) {
        throw 'GitHub API did not expose required repository settings; verify this account has repository administration read access.'
    }
    if ($null -eq $repo.security_and_analysis) { throw 'GitHub API did not expose security settings; verify repository administration read access.' }
    Assert-Value 'repository visibility' $repo.visibility $repositoryConfig.visibility
    Assert-Value 'default branch' $repo.default_branch $repositoryConfig.defaultBranch
    Assert-Value 'squash merge enabled' $repo.allow_squash_merge $true
    Assert-Value 'merge commits disabled' $repo.allow_merge_commit $false
    Assert-Value 'rebase merge disabled' $repo.allow_rebase_merge $false
    Assert-Value 'delete branch after merge' $repo.delete_branch_on_merge $repositoryConfig.deleteHeadBranchAfterMerge
    Assert-Value 'issues enabled' $repo.has_issues $repositoryConfig.issues
    Assert-Value 'discussions setting' $repo.has_discussions $repositoryConfig.discussions

    $alertResponse = & gh api --include "repos/$slug/vulnerability-alerts" 2>$null
    $alertExit = $LASTEXITCODE
    $alertStatus = @($alertResponse | Where-Object { $_ -match '^HTTP/' } | Select-Object -Last 1)
    if ($alertExit -ne 0 -or $alertStatus.Count -eq 0 -or $alertStatus[0] -notmatch '\s204\s') {
        throw 'Dependabot vulnerability alerts are not enabled'
    }
    Write-Output 'PASS: Dependabot vulnerability alerts'
    $privateReporting = Get-GitHubJson "repos/$slug/private-vulnerability-reporting"
    Assert-Value 'private vulnerability reporting' $privateReporting.enabled $repositoryConfig.privateVulnerabilityReporting
    Assert-Value 'Dependabot security updates' $repo.security_and_analysis.dependabot_security_updates.status 'enabled'
    $dependencyGraphPolicy = $repositoryConfig.dependencyGraphVerification
    if ($dependencyGraphPolicy.method -ne 'github-sbom-api') { throw 'Dependency graph verification policy is invalid' }
    $sbom = Get-GitHubJson "repos/$slug/dependency-graph/sbom"
    if ($sbom.sbom.spdxVersion -ne $dependencyGraphPolicy.spdxVersion) { throw 'Dependency graph SBOM is missing or has an unexpected SPDX version' }
    $sbomPackages = @($sbom.sbom.packages)
    if ($sbomPackages.Count -eq 0) { throw 'Dependency graph SBOM contains no package records' }
    $repositoryPackageName = "com.github.$slug"
    if (@($sbomPackages | Where-Object name -eq $repositoryPackageName).Count -ne 1) { throw 'Dependency graph SBOM does not identify the expected repository package' }
    if ($dependencyGraphPolicy.requiresRepositoryPackage -ne $true) { throw 'Dependency graph repository-package policy is invalid' }
    Write-Output ('PASS: dependency graph SBOM ({0}; packages={1})' -f $sbom.sbom.spdxVersion, $sbomPackages.Count)

    $actions = Get-GitHubJson "repos/$slug/actions/permissions"
    $workflowPermissions = Get-GitHubJson "repos/$slug/actions/permissions/workflow"
    $selectedActions = Get-GitHubJson "repos/$slug/actions/permissions/selected-actions"
    Assert-Value 'Actions selected allowlist mode' $actions.allowed_actions $actionConfig.allowedActions
    foreach ($permission in @(
        @{ Name = 'Actions enabled'; Actual = $actions.enabled; Expected = $actionConfig.enabled }
        @{ Name = 'Actions GitHub-owned category'; Actual = $selectedActions.github_owned_allowed; Expected = $actionConfig.githubOwnedAllowed }
        @{ Name = 'Actions verified publisher category'; Actual = $selectedActions.verified_allowed; Expected = $actionConfig.verifiedCreatorsAllowed }
    )) {
        if ($permission.Actual -isnot [bool] -or $permission.Expected -isnot [bool]) {
            throw "$($permission.Name) must be expressed as a boolean in GitHub and in the manifest"
        }
        Assert-Value $permission.Name $permission.Actual $permission.Expected
    }
    Assert-Value 'Actions require full SHA pinning' $actions.sha_pinning_required $actionConfig.shaPinningRequired
    Assert-Value 'Actions default token permission' $workflowPermissions.default_workflow_permissions $actionConfig.defaultWorkflowTokenPermission
    Assert-Value 'Actions cannot approve PRs' $workflowPermissions.can_approve_pull_request_reviews $actionConfig.canApprovePullRequestReviews
    $actualAllowlist = @($selectedActions.patterns_allowed | Sort-Object) -join ','
    $expectedAllowlist = @($actionConfig.allowlist | Sort-Object) -join ','
    Assert-Value 'Actions allowlist' $actualAllowlist $expectedAllowlist

    $allRulesets = @(Get-GitHubJson "repos/$slug/rulesets?per_page=100")
    $rulesetSummary = $allRulesets | Where-Object { $_.name -eq $rulesConfig.name } | Select-Object -First 1
    if (-not $rulesetSummary) { throw 'Expected main ruleset was not found' }
    $ruleset = Get-GitHubJson ("repos/$slug/rulesets/{0}" -f $rulesetSummary.id)
    Assert-Value 'main ruleset active' $ruleset.enforcement $rulesConfig.enforcement
    if (@($ruleset.bypass_actors).Count -ne 0) { throw 'Main ruleset has unexpected bypass actors' }
    $actualIncludedRefs = @($ruleset.conditions.ref_name.include)
    $expectedIncludedRefs = @($rulesConfig.include)
    if ($actualIncludedRefs.Count -ne $expectedIncludedRefs.Count) { throw 'Main ruleset include refs do not exactly match the manifest' }
    foreach ($expectedRef in $expectedIncludedRefs) {
        $exactMatches = @($actualIncludedRefs | Where-Object { [string]::Equals([string]$_, [string]$expectedRef, [System.StringComparison]::Ordinal) })
        if ($exactMatches.Count -ne 1) { throw 'Main ruleset include refs do not exactly match the manifest' }
    }
    Write-Output 'PASS: main ruleset included refs (ordinal exact match)'
    $excludedRefs = @($ruleset.conditions.ref_name.exclude | Where-Object { $_ })
    if ($excludedRefs.Count -gt 0) { throw 'Main ruleset contains excluded refs and may not protect main' }
    $ruleTypes = @($ruleset.rules | ForEach-Object { $_.type })
    foreach ($requiredType in @('pull_request', 'deletion', 'non_fast_forward', 'required_linear_history')) {
        if ($ruleTypes -notcontains $requiredType) { throw "Main ruleset is missing $requiredType" }
    }
    $prRule = $ruleset.rules | Where-Object type -eq 'pull_request' | Select-Object -First 1
    Assert-Value 'main ruleset review count' $prRule.parameters.required_approving_review_count $rulesConfig.rules.requiredApprovingReviewCount
    Assert-Value 'main ruleset stale review dismissal' $prRule.parameters.dismiss_stale_reviews_on_push $rulesConfig.rules.dismissStaleReviewsOnPush
    $actualRequiredReviewers = @($prRule.parameters.required_reviewers | Sort-Object) -join ','
    $expectedRequiredReviewers = @($rulesConfig.rules.requiredReviewers | Sort-Object) -join ','
    Assert-Value 'main ruleset required reviewers' $actualRequiredReviewers $expectedRequiredReviewers
    Assert-Value 'main ruleset code-owner review' $prRule.parameters.require_code_owner_review $rulesConfig.rules.requireCodeOwnerReview
    Assert-Value 'main ruleset last-push approval' $prRule.parameters.require_last_push_approval $rulesConfig.rules.requireLastPushApproval
    Assert-Value 'main ruleset unattributed-change approval' $prRule.parameters.require_extra_approval_for_unattributed_changes $rulesConfig.rules.requireExtraApprovalForUnattributedChanges
    Assert-Value 'main ruleset review thread resolution' $prRule.parameters.required_review_thread_resolution $rulesConfig.rules.requireResolvedReviewThreads
    Assert-Value 'main ruleset merge method' (@($prRule.parameters.allowed_merge_methods) -join ',') $rulesConfig.mergeMethod

    $statusRule = $ruleset.rules | Where-Object type -eq 'required_status_checks' | Select-Object -First 1
    if ($rulesConfig.rules.requiredStatusChecks.state -eq 'pending-first-successful-workflow-run') {
        if ($statusRule) { throw 'Manifest says pending but live required status exists; update the manifest before verification' }
        Write-Output 'DEFERRED: required quality-gate status is not configured until its first successful run.'
        $setupIncomplete = $true
        if ($RequireStatusCheck) { throw 'Required status check is not active yet' }
    } elseif ($rulesConfig.rules.requiredStatusChecks.state -ne 'enforced') {
        throw 'Required status check rollout state is invalid'
    } elseif (-not $statusRule) {
        throw 'Required quality-gate status check is missing'
    } else {
        $check = $statusRule.parameters.required_status_checks | Where-Object context -eq $rulesConfig.rules.requiredStatusChecks.context | Select-Object -First 1
        if (-not $check) { throw 'Required quality-gate context is missing from main ruleset' }
        Assert-Value 'required status check strictness' $statusRule.parameters.strict_required_status_checks_policy $true
        Assert-Value 'required status check source' $check.integration_id $rulesConfig.rules.requiredStatusChecks.integrationId
        Write-Output ('PASS: required status context {0}' -f $check.context)
    }

    $security = $repo.security_and_analysis
    Assert-Value 'GitHub secret scanning' $security.secret_scanning.status 'enabled'
    Assert-Value 'GitHub push protection' $security.secret_scanning_push_protection.status 'enabled'
    if ($security.secret_scanning_non_provider_patterns.status -ne 'enabled') {
        Write-Output 'NOT COVERED: GitHub generic/non-provider secret patterns are disabled; local and CI Gitleaks remains required.'
    }
    if ($security.secret_scanning_validity_checks.status -ne 'enabled') {
        Write-Output 'NOT COVERED: GitHub secret validity checks are disabled.'
    }
    if ($setupIncomplete) {
        Write-Output 'GITHUB_SETTINGS_AUDIT=INCOMPLETE'
        exit 2
    }
    Write-Output 'GITHUB_SETTINGS_AUDIT=PASS_WITH_RECORDED_LIMITS'
    exit 0
}
catch {
    [Console]::Error.WriteLine('GITHUB_SETTINGS_AUDIT=FAIL: ' + $_.Exception.Message)
    exit 1
}
