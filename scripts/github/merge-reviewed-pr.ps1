#Requires -Version 7.6
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Number,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$HeadSha,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$BaseSha,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$MergeResultSha,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]*$')][string]$RunId,
    [switch]$Execute,
    [string]$AcceptedHeadSha
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Execute -and $AcceptedHeadSha -cne $HeadSha) { throw 'Explicit acceptance for the exact head is required' }

& (Join-Path $PSScriptRoot 'check-squash-preflight.ps1') -Number $Number -HeadSha $HeadSha -BaseSha $BaseSha -MergeResultSha $MergeResultSha -RunId $RunId
if (-not $Execute) { return }

$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../config/github/repository.json') -Raw | ConvertFrom-Json
$slug = [string]$config.repository
$login = [string]$config.commitIdentity.login
$userId = [string]$config.commitIdentity.userId
if ($login -notmatch '^[A-Za-z0-9-]+$' -or $userId -notmatch '^[1-9][0-9]*$') { throw 'Invalid commit identity policy' }
$email = "$userId+$login@users.noreply.github.com"
if (-not $PSCmdlet.ShouldProcess("$slug PR #$Number at $HeadSha", 'Squash merge with noreply')) { return }

$prJson = & gh pr view $Number -R "github.com/$slug" --json id,state,isDraft,headRefOid,baseRefOid 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Unable to recheck PR' }
$pr = $prJson | ConvertFrom-Json
if (!$pr.id -or $pr.state -cne 'OPEN' -or $pr.isDraft -ne $false -or $pr.headRefOid -cne $HeadSha -or $pr.baseRefOid -cne $BaseSha) {
    throw 'PR changed after preflight'
}
$main = & gh api --hostname github.com "repos/$slug/git/ref/heads/main" --jq '.object.sha' 2>$null
if ($LASTEXITCODE -ne 0 -or $main -cne $BaseSha) { throw 'Main changed after preflight' }

$query = 'mutation($id:ID!,$head:GitObjectID!,$email:String!){mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head,mergeMethod:SQUASH,authorEmail:$email}){pullRequest{merged mergeCommit{oid author{email}}}}}'
$reply = & gh api --hostname github.com graphql -f "query=$query" -f "id=$($pr.id)" -f "head=$HeadSha" -f "email=$email" 2>$null
if ($LASTEXITCODE -ne 0) {
    & gh pr view $Number -R "github.com/$slug" --json state,mergeCommit
    throw 'Merge response failed. Check PR state before retrying.'
}
$result = ($reply -join [char]10) | ConvertFrom-Json -AsHashtable
$merged = $result.data.mergePullRequest.pullRequest
if (!$merged.merged -or $merged.mergeCommit.oid -cnotmatch '^[0-9a-f]{40}$' -or $merged.mergeCommit.author.email -cne $email) {
    throw 'Merge result or author could not be confirmed. Check PR state before retrying.'
}
Write-Output "PR #$Number merged at $($merged.mergeCommit.oid) with the expected noreply author."
