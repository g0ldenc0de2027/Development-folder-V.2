[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/GitIdentity.psm1') -Force
try {
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $RepositoryRoot -HookContext
    Write-Output 'PASS: Git hook repository, index, and metadata paths match the current worktree'
    exit 0
} catch {
    $message = [string]$_.Exception.Message
    [Console]::Error.WriteLine($message)
    if ($message -in 'GIT_IDENTITY_PROCESS_START_FAILED','GIT_IDENTITY_PROCESS_TIMEOUT','GIT_IDENTITY_PROCESS_OUTPUT_TIMEOUT','GIT_IDENTITY_PROCESS_OUTPUT_FAILED') { exit 1 }
    exit 23
}
