[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
Set-Location -LiteralPath $repoRoot

$config = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json
$expectedRemoteUrl = "https://github.com/$($config.repository).git"
$fetchUrls = @(& git remote get-url --all origin 2>$null)
$fetchExit = $LASTEXITCODE
$pushUrls = @(& git remote get-url --push --all origin 2>$null)
$pushExit = $LASTEXITCODE
if (
    $fetchExit -ne 0 -or $pushExit -ne 0 -or
    $fetchUrls.Count -ne 1 -or $pushUrls.Count -ne 1 -or
    $fetchUrls[0].TrimEnd('/') -ne $expectedRemoteUrl -or
    $pushUrls[0].TrimEnd('/') -ne $expectedRemoteUrl
) {
    throw 'origin fetch and push URLs must both match config/github/repository.json exactly'
}
$gitRoot = [System.IO.Path]::GetFullPath((& git rev-parse --show-toplevel).Trim())
$expectedRoot = [System.IO.Path]::GetFullPath($repoRoot)
if (-not [string]::Equals($gitRoot.TrimEnd('\','/'), $expectedRoot.TrimEnd('\','/'), [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Run this setup only in the repository root'
}

$ownerLogin = ($config.repository -split '/')[0]
$ownerData = & gh api "users/$ownerLogin" 2>$null | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $ownerData.id) {
    throw 'GitHub CLI could not resolve the repository owner for private noreply identity setup'
}
$authorName = $ownerLogin
$authorEmail = '{0}+{1}@users.noreply.github.com' -f $ownerData.id, $ownerLogin
git config --local user.name $authorName
if ($LASTEXITCODE -ne 0) { throw 'Could not set repository-local Git author name' }
git config --local user.email $authorEmail
if ($LASTEXITCODE -ne 0) { throw 'Could not set repository-local Git noreply email' }
git config --local user.useConfigOnly true
if ($LASTEXITCODE -ne 0) { throw 'Could not prevent fallback to global Git identity' }

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

if (-not (Test-Path -LiteralPath (Join-Path $repoRoot '.githooks/pre-push'))) {
    throw 'The required pre-push gate is missing'
}
Write-Output 'PASS: repository-local hooksPath, fast-forward-only pulls, pruned fetches, simple pushes, and GitHub CLI credential helper configured.'
