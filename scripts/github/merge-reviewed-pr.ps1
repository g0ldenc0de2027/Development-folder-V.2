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

function Read-MergeEvidenceJson {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $response = & gh @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'GitHub evidence request failed.' }
    try {
        $json = $response -join [char]10
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.AllowDuplicateProperties = $false
        # Validate nested properties before converting to a dictionary.
        $document = [System.Text.Json.JsonDocument]::Parse($json, $options)
        $document.Dispose()
        $result = $json | ConvertFrom-Json -AsHashtable
    } catch {
        throw 'GitHub evidence response was not valid JSON.'
    }
    if ($result -isnot [System.Collections.IDictionary] -or $result.Contains('errors')) {
        throw 'GitHub evidence response was incomplete.'
    }
    return $result
}

$testedCommit = Read-MergeEvidenceJson @('api','--hostname','github.com',"repos/$slug/git/commits/$MergeResultSha")
if ($testedCommit['sha'] -cne $MergeResultSha -or
    $testedCommit['tree'] -isnot [System.Collections.IDictionary] -or
    $testedCommit['tree']['sha'] -cnotmatch '^[0-9a-f]{40}$') {
    throw 'Unable to identify the tree of the approved merge-result.'
}
$approvedTree = $testedCommit['tree']['sha']

$pr = Read-MergeEvidenceJson @('pr','view',"$Number",'-R',"github.com/$slug",'--json','id,state,isDraft,baseRefName,headRefOid,baseRefOid')
if (!$pr['id'] -or $pr['state'] -cne 'OPEN' -or $pr['isDraft'] -ne $false -or
    $pr['baseRefName'] -cne 'main' -or $pr['headRefOid'] -cne $HeadSha -or $pr['baseRefOid'] -cne $BaseSha) {
    throw 'PR changed after preflight'
}
$main = & gh api --hostname github.com "repos/$slug/git/ref/heads/main" --jq '.object.sha' 2>$null
if ($LASTEXITCODE -ne 0 -or $main -cne $BaseSha) { throw 'Main changed after preflight' }

$query = 'mutation($id:ID!,$head:GitObjectID!,$email:String!){mergePullRequest(input:{pullRequestId:$id,expectedHeadOid:$head,mergeMethod:SQUASH,authorEmail:$email}){pullRequest{merged}}}'
try {
    $null = & gh api --hostname github.com graphql -f "query=$query" -f "id=$($pr['id'])" -f "head=$HeadSha" -f "email=$email" 2>$null
} catch {
    Write-Verbose 'GitHub did not confirm the mutation. Checking the current PR and commit.'
}

try {
    $mergedPr = Read-MergeEvidenceJson @('pr','view',"$Number",'-R',"github.com/$slug",'--json','id,state,baseRefName,headRefOid,mergeCommit')
} catch {
    throw 'PR state could not be verified after the squash attempt. Check it before retrying.'
}
if ($mergedPr['state'] -cne 'MERGED') {
    throw 'PR was not confirmed merged after the squash attempt. Verify its current state before retrying.'
}
if ($mergedPr['id'] -cne $pr['id'] -or $mergedPr['baseRefName'] -cne 'main' -or
    $mergedPr['headRefOid'] -cne $HeadSha -or
    $mergedPr['mergeCommit'] -isnot [System.Collections.IDictionary] -or
    $mergedPr['mergeCommit']['oid'] -cnotmatch '^[0-9a-f]{40}$') {
    throw 'PR is already merged, but its recorded revision does not match the approval. Investigate the merged PR.'
}
$mergedSha = $mergedPr['mergeCommit']['oid']

try {
    $squash = Read-MergeEvidenceJson @('api','--hostname','github.com',"repos/$slug/git/commits/$mergedSha")
} catch {
    throw "PR is already merged at ${mergedSha}, but its commit evidence could not be read."
}
if ($squash['sha'] -cne $mergedSha) {
    throw "PR is already merged at ${mergedSha}, but GitHub returned a different commit."
}
$parents = @($squash['parents'])
if ($parents.Count -ne 1 -or $parents[0] -isnot [System.Collections.IDictionary] -or $parents[0]['sha'] -cne $BaseSha) {
    throw "PR is already merged at ${mergedSha}, but its sole parent does not match the approved base."
}
if ($squash['tree'] -isnot [System.Collections.IDictionary] -or $squash['tree']['sha'] -cne $approvedTree) {
    throw "PR is already merged at ${mergedSha}, but its tree does not match the tested merge-result."
}
if ($squash['author'] -isnot [System.Collections.IDictionary] -or $squash['author']['email'] -cne $email) {
    throw "PR is already merged at ${mergedSha}, but its author does not match the expected noreply identity."
}
Write-Output "PR #$Number merged at $mergedSha. Verified the approved base, tested tree and expected noreply author."
