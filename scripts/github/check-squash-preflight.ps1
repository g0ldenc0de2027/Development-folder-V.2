#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateRange(1,2147483647)][int]$Number,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$HeadSha,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$BaseSha,
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{40}$')][string]$MergeResultSha,
    [Parameter(Mandatory)][ValidatePattern('^[1-9][0-9]*$')][string]$RunId
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-GitHubJson {
    param([string[]]$Arguments)
    $response = & gh @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'GitHub read failed' }
    $result = ($response -join [char]10) | ConvertFrom-Json -AsHashtable
    if ($null -eq $result -or ($result -is [System.Collections.IDictionary] -and $result.Contains('errors'))) {
        throw 'GitHub returned incomplete data'
    }
    return $result
}

$config = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../config/github/repository.json') -Raw | ConvertFrom-Json
$slug = [string]$config.repository
if ($slug -notmatch '^[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+$') { throw 'Invalid repository policy' }
$repo = "github.com/$slug"
$account = Read-GitHubJson @('api','--hostname','github.com','user')
if ([string]$account.id -cne [string]$config.commitIdentity.userId -or $account.login -ine $config.commitIdentity.login) {
    throw 'GitHub account differs from repository policy'
}

$pr = Read-GitHubJson @('pr','view',"$Number",'-R',$repo,'--json','state,isDraft,baseRefName,headRefOid,baseRefOid,mergeStateStatus,statusCheckRollup')
if ($pr.state -cne 'OPEN' -or $pr.isDraft -ne $false -or $pr.mergeStateStatus -cne 'CLEAN' -or
    $pr.baseRefName -cne 'main' -or $pr.headRefOid -cne $HeadSha -or $pr.baseRefOid -cne $BaseSha) {
    throw 'PR is not ready or differs from the reviewed head/base'
}
$base = Read-GitHubJson @('api','--hostname','github.com',"repos/$slug/git/ref/heads/main")
$merge = Read-GitHubJson @('api','--hostname','github.com',"repos/$slug/git/ref/pull/$Number/merge")
if ($base.object.sha -cne $BaseSha -or $merge.object.sha -cne $MergeResultSha) { throw 'GitHub refs moved' }

$commit = Read-GitHubJson @('api','--hostname','github.com',"repos/$slug/git/commits/$MergeResultSha")
if ($commit.parents.Count -ne 2 -or $commit.parents[0].sha -cne $BaseSha -or $commit.parents[1].sha -cne $HeadSha) {
    throw 'Merge-result parent tuple differs'
}

$rules = Read-GitHubJson @('api','--hostname','github.com',"repos/$slug/rules/branches/main")
$required = @($rules | Where-Object {
    $_.type -ceq 'required_status_checks' -and $_.parameters.strict_required_status_checks_policy -eq $true -and
    ($_.parameters.required_status_checks | Where-Object { $_.context -ceq 'quality-gate' -and $_.integration_id -eq 15368 })
})
if ($required.Count -eq 0) { throw 'Strict GitHub Actions quality-gate is not required' }

$query = 'query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){reviewThreads(first:100){pageInfo{hasNextPage} nodes{isResolved}}}}}'
$owner, $name = $slug.Split('/')
$review = Read-GitHubJson @('api','--hostname','github.com','graphql','-f',"query=$query",'-f',"owner=$owner",'-f',"name=$name",'-F',"number=$Number")
$threads = $review.data.repository.pullRequest.reviewThreads
if (!$threads -or $threads.pageInfo.hasNextPage -ne $false -or !($threads.Contains('nodes')) -or $null -eq $threads.nodes -or
    ($threads.nodes | Where-Object { $_.isResolved -ne $true })) {
    throw 'Review threads are unresolved or could not all be checked'
}

$run = Read-GitHubJson @('run','view',$RunId,'-R',$repo,'--json','event,status,conclusion,headSha,workflowName,jobs,url')
if ($run.event -cne 'pull_request' -or $run.status -cne 'completed' -or $run.conclusion -cne 'success' -or
    $run.headSha -cne $HeadSha -or $run.workflowName -cne 'quality-gate' -or
    $run.url -cne "https://github.com/$slug/actions/runs/$RunId") {
    throw 'Hosted run differs from the approved PR evidence'
}
$jobs = @($run.jobs | Where-Object { $_.name -ceq 'quality-gate' -and $_.conclusion -ceq 'success' })
if ($jobs.Count -ne 1) { throw 'Expected one successful quality-gate job' }
$jobId = [string]$jobs[0].databaseId
if ($jobId -notmatch '^[1-9][0-9]*$') { throw 'Invalid CI job ID' }
$checks = @($pr.statusCheckRollup | Where-Object { $_.name -ceq 'quality-gate' })
if ($checks.Count -ne 1 -or $checks[0].conclusion -cne 'SUCCESS' -or
    $checks[0].detailsUrl -cne "$($run.url)/job/$jobId") { throw 'PR check does not match the hosted job' }

$log = & gh run view $RunId -R $repo --job $jobId --log 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Unable to read hosted job log' }
foreach ($entry in @{PR_HEAD_SHA=$HeadSha; PR_BASE_SHA=$BaseSha; EVENT_TEST_SHA=$MergeResultSha}.GetEnumerator()) {
    $observed = @([regex]::Matches(($log -join [char]10), "(?m)\s+$($entry.Key):[ \t]+([0-9a-f]{40})[ \t]*\r?$") |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    if ($observed.Count -ne 1 -or $observed[0] -cne $entry.Value) { throw "Hosted log SHA mismatch: $($entry.Key)" }
}
Write-Output "PR #$Number passed GitHub preflight for run $RunId. Verify independent review and owner acceptance before merge."
