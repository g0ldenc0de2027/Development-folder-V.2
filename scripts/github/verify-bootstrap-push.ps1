#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RemoteName,
    [Parameter(Mandatory)][string]$RemoteUrl,
    [Parameter(Mandatory)][ValidatePattern('\A[0-9a-f]{40}\z')][string]$CommitSha
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path

function Read-BootstrapGit {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = @(& git --no-replace-objects -C $root @Arguments)
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap Git check failed: $($Arguments[0])" }
    return $result
}

$config = Get-Content -LiteralPath (Join-Path $root 'config/github/repository.json') -Raw | ConvertFrom-Json
$slug = [string]$config.repository
if ($slug -cnotmatch '\A[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+\z' -or $RemoteName -cne 'origin') {
    throw 'Bootstrap requires the configured origin on github.com.'
}
$expectedUrl = "https://github.com/$slug.git"
$fetchUrls = @(Read-BootstrapGit @('remote','get-url','--all','origin'))
$pushUrls = @(Read-BootstrapGit @('remote','get-url','--push','--all','origin'))
if ($RemoteUrl -cne $expectedUrl -or $fetchUrls.Count -ne 1 -or $fetchUrls[0] -cne $expectedUrl -or
    $pushUrls.Count -ne 1 -or $pushUrls[0] -cne $expectedUrl) {
    throw 'Bootstrap fetch and push URLs must match the configured origin exactly.'
}
if ($env:DF_APPROVED_BOOTSTRAP_SHA -cne $CommitSha) { throw 'Bootstrap requires explicit approval of the exact root commit SHA.' }

$head = @(Read-BootstrapGit @('rev-parse','--verify','HEAD'))
$branch = @(Read-BootstrapGit @('symbolic-ref','--quiet','HEAD'))
if ($head.Count -ne 1 -or $head[0] -cne $CommitSha -or $branch.Count -ne 1 -or $branch[0] -cne 'refs/heads/main') {
    throw 'Bootstrap requires the approved commit checked out on main.'
}
$replacements = @(Read-BootstrapGit @('for-each-ref','--format=%(refname)','refs/replace/'))
if ($replacements.Count -ne 0) { throw 'Bootstrap cannot verify commit identity while Git replacement refs exist.' }
$commit = @(Read-BootstrapGit @('cat-file','-p',$CommitSha))
# Read parent lines from the object header. A shallow boundary is not a root.
if ($commit.Count -eq 0 -or $commit[0] -cnotmatch '^tree [0-9a-f]{40}$') { throw 'Bootstrap commit object is invalid.' }
foreach ($line in $commit) {
    if ($line -ceq '') { break }
    if ($line.StartsWith('parent ',[StringComparison]::Ordinal)) { throw 'Bootstrap requires a root commit with no parent.' }
}
$remoteRefs = @(Read-BootstrapGit @('ls-remote','origin'))
if ($remoteRefs.Count -ne 0) { throw 'Bootstrap requires a remote with no advertised refs.' }
$status = @(Read-BootstrapGit @('--no-optional-locks','status','--porcelain=v1','--untracked-files=all','--ignore-submodules=none'))
$observedHead = @(Read-BootstrapGit @('rev-parse','--verify','HEAD'))
$observedBranch = @(Read-BootstrapGit @('symbolic-ref','--quiet','HEAD'))
if ($status.Count -ne 0 -or $observedHead.Count -ne 1 -or $observedHead[0] -cne $CommitSha -or
    $observedBranch.Count -ne 1 -or $observedBranch[0] -cne 'refs/heads/main') {
    throw 'Bootstrap requires a clean and unchanged main worktree.'
}
Write-Output "BOOTSTRAP-PUSH=PASS (approved root $CommitSha, empty origin)"
