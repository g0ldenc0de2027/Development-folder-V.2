[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$BaseSha,
    [Parameter(Mandatory)][string]$HeadSha,
    [Parameter(Mandatory)][string]$TestSha,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedSha {
    param([Parameter(Mandatory)][string]$Value, [Parameter(Mandatory)][string]$Name)
    if ($Value -notmatch '(?i)^(?:[0-9a-f]{40}|[0-9a-f]{64})$') {
        throw "PR_MERGE_RESULT_INVALID_$Name"
    }
    return $Value.ToLowerInvariant()
}

$base = Get-NormalizedSha -Value $BaseSha -Name 'BASE_SHA'
$head = Get-NormalizedSha -Value $HeadSha -Name 'HEAD_SHA'
$test = Get-NormalizedSha -Value $TestSha -Name 'TEST_SHA'
$repositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$rootItem = Get-Item -LiteralPath $repositoryRoot -Force
if (-not $rootItem.PSIsContainer -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'PR_MERGE_RESULT_REPOSITORY_INVALID'
}
$null = Get-Command git -ErrorAction Stop

function Invoke-GitReadOnly {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -C $repositoryRoot @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw 'PR_MERGE_RESULT_GIT_READ_FAILED'
    }
    return ($output -join '').Trim()
}

$resolvedTest = Invoke-GitReadOnly @('rev-parse', '--verify', ($test + '^{commit}'))
if ($resolvedTest.ToLowerInvariant() -cne $test) {
    throw 'PR_MERGE_RESULT_TEST_SHA_NOT_COMMIT'
}
$actualHead = Invoke-GitReadOnly @('rev-parse', '--verify', 'HEAD^{commit}')
if ($actualHead.ToLowerInvariant() -cne $test) {
    throw 'PR_MERGE_RESULT_CHECKOUT_MISMATCH'
}
$parentLine = Invoke-GitReadOnly @('rev-list', '--parents', '-n', '1', $test)
$parts = @($parentLine -split '\s+' | Where-Object { $_ })
if ($parts.Count -ne 3) {
    throw 'PR_MERGE_RESULT_PARENT_COUNT_MISMATCH'
}
if ($parts[0].ToLowerInvariant() -cne $test) {
    throw 'PR_MERGE_RESULT_COMMIT_MISMATCH'
}
if ($parts[1].ToLowerInvariant() -cne $base -or $parts[2].ToLowerInvariant() -cne $head) {
    throw 'PR_MERGE_RESULT_PARENT_TUPLE_MISMATCH'
}

Write-Output 'PASS: checked-out PR merge-result has the exact [base, head] parent tuple'
