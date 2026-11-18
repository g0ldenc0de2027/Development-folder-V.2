[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [string]$RemoteName,
    [string[]]$CommitRange = @(),
    [switch]$HookContext
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/GitIdentity.psm1') -Force
try {
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $RepositoryRoot -HookContext:$HookContext
    foreach ($name in @([Environment]::GetEnvironmentVariables('Process').Keys | Where-Object { ([string]$_).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) })) {
        Remove-Item -LiteralPath ('Env:' + [string]$name) -ErrorAction SilentlyContinue
    }
    $null = Assert-GitWorktreeIdentity -RepositoryRoot $RepositoryRoot
    if ($CommitRange.Count -gt 0) { $null = Assert-GitCommitIdentity -RepositoryRoot $RepositoryRoot -CommitRange $CommitRange -RemoteName $RemoteName }
    Write-Output 'PASS: worktree-scoped Git identity and requested commit metadata match repository policy'
    exit 0
} catch {
    $message = [string]$_.Exception.Message
    [Console]::Error.WriteLine($message)
    if ($message -match '^GIT_IDENTITY_(CONFIG_)?ENVIRONMENT_OVERRIDE:|^GIT_IDENTITY_(REPOSITORY_CONTEXT_OVERRIDE|HOOK_|CONTEXT_REPARSE_POINT|CONTEXT_PATH_)') { exit 23 }
    if ($message -in @(
        'GIT_IDENTITY_WORKTREE_NAME_MISMATCH',
        'GIT_IDENTITY_WORKTREE_EMAIL_MISMATCH',
        'GIT_IDENTITY_CONFIG_ONLY_REQUIRED',
        'GIT_IDENTITY_WORKTREE_ACCOUNT_MISMATCH'
    )) { exit 24 }
    exit 1
}
