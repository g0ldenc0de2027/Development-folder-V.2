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
    exit 23
}
