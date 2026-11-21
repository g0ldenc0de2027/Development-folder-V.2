[CmdletBinding()]
param(
    [switch]$IdentityOnly,
    [switch]$HookContext
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot
$config = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json -AsHashtable
Import-Module (Join-Path $repoRoot 'scripts/lib/GitIdentity.psm1') -Force
$null = Assert-GitWorktreeEnvironment -RepositoryRoot $repoRoot -HookContext:$HookContext
foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys | Where-Object { ([string]$_).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) })) {
    Remove-Item -LiteralPath ('Env:' + [string]$name) -ErrorAction SilentlyContinue
}
foreach ($hookPath in @('.githooks/pre-commit','.githooks/pre-push','scripts/verify-git-hook-context.ps1')) {
    $fullHookPath = Join-Path $repoRoot $hookPath
    if (-not (Test-Path -LiteralPath $fullHookPath -PathType Leaf)) { throw ('Required Git gate is missing: ' + $hookPath) }
}
$expectedRemoteUrl = "https://github.com/$($config.repository).git"
$fetchUrls = @(& git -C $repoRoot remote get-url --all origin 2>$null)
$fetchExit = $LASTEXITCODE
$pushUrls = @(& git -C $repoRoot remote get-url --push --all origin 2>$null)
$pushExit = $LASTEXITCODE
if ($fetchExit -ne 0 -or $pushExit -ne 0 -or $fetchUrls.Count -ne 1 -or $pushUrls.Count -ne 1 -or
    $fetchUrls[0].TrimEnd('/') -ne $expectedRemoteUrl -or $pushUrls[0].TrimEnd('/') -ne $expectedRemoteUrl) {
    throw 'origin fetch and push URLs must both match config/github/repository.json exactly'
}
$profileJson = @(& gh api user 2>$null)
$ghExit = $LASTEXITCODE
if ($ghExit -ne 0 -or $profileJson.Count -eq 0) { throw 'GITHUB_AUTH_REQUIRED_FOR_GIT_IDENTITY_SETUP' }
try { $profile = ($profileJson -join "`n") | ConvertFrom-Json -ErrorAction Stop }
catch { throw 'GITHUB_AUTH_PROFILE_INVALID' }
$expectedIdentity = $config.commitIdentity
if (-not [string]::Equals([string]$profile.login,[string]$expectedIdentity.login,[System.StringComparison]::OrdinalIgnoreCase) -or [string]$profile.id -cne [string]$expectedIdentity.userId) {
    throw 'GITHUB_AUTH_ACCOUNT_DOES_NOT_MATCH_REPOSITORY_POLICY'
}
$null = Set-GitWorktreeIdentity -RepositoryRoot $repoRoot -Login ([string]$profile.login) -UserId ([string]$profile.id)

if ($IdentityOnly) {
    Write-Output 'PASS: authenticated worktree identity configured; shared repository settings were not changed.'
    exit 0
}

# Repository-wide settings remain common; identity above is deliberately worktree-scoped.
git -C $repoRoot config --local core.hooksPath .githooks
if ($LASTEXITCODE -ne 0) { throw 'Could not configure repository-local hooksPath' }
git -C $repoRoot config --local fetch.prune true
if ($LASTEXITCODE -ne 0) { throw 'Could not configure fetch.prune' }
git -C $repoRoot config --local pull.ff only
if ($LASTEXITCODE -ne 0) { throw 'Could not configure pull.ff' }
git -C $repoRoot config --local push.default simple
if ($LASTEXITCODE -ne 0) { throw 'Could not configure push.default' }
git -C $repoRoot config --local credential.helper '!gh auth git-credential'
if ($LASTEXITCODE -ne 0) { throw 'Could not configure GitHub CLI credential helper' }
Write-Output 'PASS: authenticated repository identity is isolated to this worktree; shared hooks, fetch, pull, push and credential settings are configured.'
