#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^T-[0-9]{3}$')][string]$TaskId,
    [string]$BaseRef = 'origin/main',
    [ValidatePattern('^(?:[0-9a-f]{40}|[0-9a-f]{64})$')][string]$ExpectedHeadSha
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'verify-runtime.ps1') -Quiet

function Invoke-Git([string[]]$Arguments) {
    $originalOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $output = @(& git @Arguments)
        $exitCode = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $originalOutputEncoding
    }
    if ($exitCode -ne 0) { throw 'Task scope check could not read Git state' }
    return $output
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$branch = ((Invoke-Git @('-C',$repoRoot,'symbolic-ref','--quiet','--short','HEAD')) -join '').Trim()
$expectedBranchPattern = '^task/' + [regex]::Escape($TaskId) + '(?:-[a-z0-9]+(?:-[a-z0-9]+)*)?$'
if ($branch -cnotmatch $expectedBranchPattern) { throw 'Current branch does not match the task ID or the documented lowercase slug format' }
$head = ((Invoke-Git @('-C',$repoRoot,'rev-parse','--verify','HEAD')) -join '').Trim()
if ($ExpectedHeadSha -and $head -cne $ExpectedHeadSha) { throw 'Current HEAD does not match the outgoing push SHA' }
try {
    $base = ((Invoke-Git @('-C',$repoRoot,'rev-parse','--verify','--end-of-options',"${BaseRef}^{commit}")) -join '').Trim()
} catch {
    throw 'No local commit for the requested base. Fetch the verified base and retry.'
}
$null = Invoke-Git @('-C',$repoRoot,'merge-base',$base,$head)
$gitDir = ((Invoke-Git @('-C',$repoRoot,'rev-parse','--path-format=absolute','--git-dir')) -join '').Trim()
$commonDir = ((Invoke-Git @('-C',$repoRoot,'rev-parse','--path-format=absolute','--git-common-dir')) -join '').Trim()
if ([string]::Equals([IO.Path]::GetFullPath($gitDir),[IO.Path]::GetFullPath($commonDir),[StringComparison]::OrdinalIgnoreCase)) {
    throw 'A dedicated linked task worktree is required'
}

$taskFiles = @(Invoke-Git @('-C',$repoRoot,'-c','core.quotepath=false','ls-tree','--name-only',$head,'tasks/') |
    Where-Object { $_ -match ('^tasks/' + [regex]::Escape($TaskId) + '-[^/]+\.md$') })
if ($taskFiles.Count -ne 1) { throw 'Task scope requires exactly one matching task card' }
$card = (Invoke-Git @('-C',$repoRoot,'show',"${head}:$($taskFiles[0])")) -join [char]10
$section = [regex]::Match($card,'(?ms)^## Зона файлов\s*\r?\n(?<body>.*?)(?=^## |\z)')
if (-not $section.Success) { throw 'Task card has no file-scope section' }
$scope = [Collections.Generic.List[string]]::new()
foreach ($match in [regex]::Matches($section.Groups['body'].Value,'(?m)^\s*-\s+`(?<path>[^`]+)`\s*$')) {
    $path = $match.Groups['path'].Value.Replace('\','/').Trim()
    if (-not $path -or $path.StartsWith('/') -or $path -match '(^|/)\.\.?(/|$)' -or $path.Contains('//') -or $path -notmatch '^[\p{L}\p{M}\p{N}._/*?-]+$') {
        throw 'Task card contains an invalid scope path'
    }
    $scope.Add($path)
}
if ($scope.Count -eq 0) { throw 'Task card scope is empty' }
$changes = @(Invoke-Git @('-C',$repoRoot,'-c','core.quotepath=false','diff','--no-renames','--name-only','--diff-filter=ACDMRTUXB',"$base...$head"))
if ($changes.Count -eq 0) { throw 'Task branch contains no changes relative to its base' }
$outside = [Collections.Generic.List[string]]::new()
foreach ($change in $changes) {
    $normalized = $change.Replace('\','/')
    $allowed = $false
    foreach ($pattern in $scope) {
        if ($normalized -like $pattern) { $allowed = $true; break }
    }
    if (-not $allowed) { $outside.Add($normalized) }
}
if ($outside.Count -gt 0) { throw ('Out-of-scope paths: ' + ($outside -join ', ')) }
$status = @(Invoke-Git @('-C',$repoRoot,'--no-optional-locks','status','--porcelain=v1','--untracked-files=all','--ignore-submodules=none'))
if ($status.Count -gt 0) { throw 'Working tree must be clean before push' }
$observedHead = ((Invoke-Git @('-C',$repoRoot,'rev-parse','--verify','HEAD')) -join '').Trim()
$observedBranch = ((Invoke-Git @('-C',$repoRoot,'symbolic-ref','--quiet','--short','HEAD')) -join '').Trim()
if ($observedHead -cne $head -or $observedBranch -cne $branch) { throw 'Task revision changed while checking scope' }
Write-Output ("TASK-SCOPE=PASS ({0} changed paths; {1} allowed paths)" -f $changes.Count,$scope.Count)
