[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$config = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json -AsHashtable
$expectedRemoteUrl = "https://github.com/$($config.repository).git"
$fetchUrls = @(& git remote get-url --all origin 2>$null)
$fetchExit = $LASTEXITCODE
$pushUrls = @(& git remote get-url --push --all origin 2>$null)
$pushExit = $LASTEXITCODE
if ($fetchExit -ne 0 -or $pushExit -ne 0 -or $fetchUrls.Count -ne 1 -or $pushUrls.Count -ne 1 -or
    $fetchUrls[0].TrimEnd('/') -ne $expectedRemoteUrl -or $pushUrls[0].TrimEnd('/') -ne $expectedRemoteUrl) {
    throw 'origin fetch and push URLs must both match config/github/repository.json exactly'
}
$gitRoot = [System.IO.Path]::GetFullPath((& git rev-parse --show-toplevel).Trim())
$expectedRoot = [System.IO.Path]::GetFullPath($repoRoot)
if (-not [string]::Equals($gitRoot.TrimEnd('\','/'), $expectedRoot.TrimEnd('\','/'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Run this setup only in the repository worktree root'
}
if ((& git config --get extensions.worktreeConfig) -cne 'true') {
    throw 'GIT_IDENTITY_WORKTREE_CONFIG_DISABLED'
}
$profileJson = @(& gh api user 2>$null)
$ghExit = $LASTEXITCODE
if ($ghExit -ne 0 -or $profileJson.Count -eq 0) { throw 'GITHUB_AUTH_REQUIRED_FOR_GIT_IDENTITY_SETUP' }
try { $profile = ($profileJson -join "`n") | ConvertFrom-Json -ErrorAction Stop }
catch { throw 'GITHUB_AUTH_PROFILE_INVALID' }
$expectedIdentity = $config.commitIdentity
if ([string]$profile.login -ine [string]$expectedIdentity.login -or [string]$profile.id -cne [string]$expectedIdentity.userId) {
    throw 'GITHUB_AUTH_ACCOUNT_DOES_NOT_MATCH_REPOSITORY_POLICY'
}
Import-Module (Join-Path $repoRoot 'scripts/lib/GitIdentity.psm1') -Force
$null = Set-GitWorktreeIdentity -RepositoryRoot $repoRoot -Login ([string]$profile.login) -UserId ([string]$profile.id)

# Repository-wide settings remain common; identity above is deliberately worktree-scoped.
git config --local core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { throw 'Could not configure repository-local hooksPath' }
git config --local fetch.prune true
if ($LASTEXITCODE -ne 0) { throw 'Could not configure fetch.prune' }
git config --local pull.ff only
if ($LASTEXITCODE -ne 0) { throw 'Could not configure pull.ff' }
git config --local push.default simple
if ($LASTEXITCODE -ne 0) { throw 'Could not configure push.default' }
git config --local credential.helper '!gh auth git-credential'
if ($LASTEXITCODE -ne 0) { throw 'Could not configure GitHub CLI credential helper' }
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.githooks/pre-push'))) { throw 'The required pre-push gate is missing' }
if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.githooks/pre-commit'))) { throw 'The required pre-commit identity gate is missing' }
Write-Output 'PASS: authenticated repository identity is isolated to this worktree; shared hooks, fetch, pull, push and credential settings are configured.'
