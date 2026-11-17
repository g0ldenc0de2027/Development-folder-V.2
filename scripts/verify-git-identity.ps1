[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [string]$RemoteName,
    [string[]]$CommitRange = @()
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/GitIdentity.psm1') -Force
try {
    $null = Assert-GitWorktreeIdentity -RepositoryRoot $RepositoryRoot
    if ($CommitRange.Count -gt 0) { $null = Assert-GitCommitIdentity -RepositoryRoot $RepositoryRoot -CommitRange $CommitRange -RemoteName $RemoteName }
    Write-Output 'PASS: worktree-scoped Git identity and requested commit metadata match repository policy'
    exit 0
} catch {
    $message = [string]$_.Exception.Message
    [Console]::Error.WriteLine($message)
    if ($message -match '^GIT_IDENTITY_(CONFIG_)?ENVIRONMENT_OVERRIDE:') { exit 23 }
    exit 1
}
