#Requires -Version 7.6
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$tempRootFull = [IO.Path]::GetFullPath($TempRoot).TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
$scratch = Join-Path $tempRootFull ('task-scope-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $scratch 'repository'
$taskWorktree = Join-Path $scratch 'task-worktree'
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0
$script:GitHookEnvironmentNames = @(
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_PREFIX',
    'GIT_COMMON_DIR',
    'GIT_OBJECT_DIRECTORY',
    'GIT_ALTERNATE_OBJECT_DIRECTORIES',
    'GIT_NAMESPACE'
)
$script:OriginalGitHookEnvironment = @{}
foreach ($name in $script:GitHookEnvironmentNames) {
    $script:OriginalGitHookEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$sourceHeadBefore = $null

function Write-Text([string]$Path, [string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Value, $utf8)
}

function Clear-GitHookEnvironment {
    $saved = @{}
    foreach ($name in $script:GitHookEnvironmentNames) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }
    return $saved
}

function Restore-GitHookEnvironment([hashtable]$Saved) {
    foreach ($name in $script:GitHookEnvironmentNames) {
        if ($null -eq $Saved[$name]) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $Saved[$name], 'Process')
        }
    }
}

function Invoke-Git([string]$WorkingDirectory, [string[]]$Arguments) {
    $savedEnvironment = Clear-GitHookEnvironment
    try {
        $output = @(& git -C $WorkingDirectory @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Restore-GitHookEnvironment $savedEnvironment
    }
    if ($exitCode -ne 0) {
        throw ("Synthetic Git fixture command failed ({0}): {1}" -f ($Arguments -join ' '), ($output -join ' '))
    }
    return $output
}

function Assert-Scope([int]$ExpectedExit, [string]$ExpectedMessage, [string]$ExpectedSummary = '') {
    $verifier = Join-Path $taskWorktree 'scripts/verify-task-scope.ps1'
    $savedEnvironment = Clear-GitHookEnvironment
    try {
        $output = @(& $pwsh -NoLogo -NoProfile -File $verifier -TaskId T-008 -BaseRef main 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Restore-GitHookEnvironment $savedEnvironment
    }
    $joined = $output -join [Environment]::NewLine
    if ($exitCode -ne $ExpectedExit) {
        throw "Scope verifier returned exit $exitCode; expected $ExpectedExit."
    }
    if ($ExpectedMessage -and -not $joined.Contains($ExpectedMessage)) {
        throw 'Scope verifier returned an unexpected result.'
    }
    if ($ExpectedSummary -and -not $joined.Contains($ExpectedSummary)) {
        throw 'Scope verifier did not enumerate every changed path.'
    }
}

try {
    $sourceHeadBefore = (Invoke-Git $repoRoot @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
    $poisonRoot = Join-Path $scratch 'inherited-git-context'
    [Environment]::SetEnvironmentVariable('GIT_DIR', (Join-Path $poisonRoot 'git-dir'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_WORK_TREE', (Join-Path $poisonRoot 'work-tree'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', (Join-Path $poisonRoot 'index'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_PREFIX', 'poison-prefix/', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_COMMON_DIR', (Join-Path $poisonRoot 'common'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_OBJECT_DIRECTORY', (Join-Path $poisonRoot 'objects'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_ALTERNATE_OBJECT_DIRECTORIES', (Join-Path $poisonRoot 'alternates'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_NAMESPACE', 'poison', 'Process')

    [IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'tasks')) | Out-Null
    [IO.File]::Copy((Join-Path $repoRoot 'scripts/verify-runtime.ps1'), (Join-Path $fixtureRoot 'scripts/verify-runtime.ps1'))
    [IO.File]::Copy((Join-Path $repoRoot 'scripts/verify-task-scope.ps1'), (Join-Path $fixtureRoot 'scripts/verify-task-scope.ps1'))
    Write-Text (Join-Path $fixtureRoot 'README.md') "Synthetic scope fixture`n"
    $fixtureCard = [string]::Join("`n", @(
        '# T-008 fixture',
        '',
        '## Зона файлов',
        '',
        '- `README.md`',
        '- `spec/ТЗ.md`',
        '- `scripts/verify-task-scope.ps1`'
    )) + "`n"
    Write-Text (Join-Path $fixtureRoot 'tasks/T-008-scope-fixture.md') $fixtureCard
    $null = Invoke-Git $fixtureRoot @('init', '--initial-branch=main')
    $null = Invoke-Git $fixtureRoot @('config', 'core.quotepath', 'true')
    $null = Invoke-Git $fixtureRoot @('config', 'user.name', 'Scope Fixture')
    $fixtureEmail = 'scope-fixture' + [char]64 + 'example.invalid'
    $null = Invoke-Git $fixtureRoot @('config', 'user.email', $fixtureEmail)
    $null = Invoke-Git $fixtureRoot @('add', '--all')
    $null = Invoke-Git $fixtureRoot @('commit', '-m', 'test(scope): seed fixture')
    $actualFixtureRoot = (Invoke-Git $fixtureRoot @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
    if ([IO.Path]::GetFullPath($actualFixtureRoot) -ne [IO.Path]::GetFullPath($fixtureRoot)) {
        throw 'Synthetic Git fixture resolved outside its temporary repository.'
    }
    $null = Invoke-Git $fixtureRoot @('worktree', 'add', '-b', 'task/T-008', $taskWorktree, 'main')
    $actualTaskWorktree = (Invoke-Git $taskWorktree @('rev-parse', '--show-toplevel') | Select-Object -First 1).Trim()
    if ([IO.Path]::GetFullPath($actualTaskWorktree) -ne [IO.Path]::GetFullPath($taskWorktree)) {
        throw 'Synthetic task worktree resolved outside its temporary path.'
    }

    Write-Text (Join-Path $taskWorktree 'README.md') "Allowed change`n"
    Write-Text (Join-Path $taskWorktree 'spec/ТЗ.md') "Unicode path`n"
    $null = Invoke-Git $taskWorktree @('add', '--all')
    $null = Invoke-Git $taskWorktree @('commit', '-m', 'test(scope): add allowed files')
    Assert-Scope 0 'TASK-SCOPE=PASS' 'TASK-SCOPE=PASS (2 changed paths; 3 allowed paths)'
    $passed++
    Write-Output 'PASS: scope enumerates changes and Unicode filenames under inherited Git hook environment'

    Write-Text (Join-Path $taskWorktree 'uncommitted.txt') "Uncommitted change`n"
    Assert-Scope 1 'Working tree must be clean before push'
    Remove-Item -LiteralPath (Join-Path $taskWorktree 'uncommitted.txt') -Force
    $passed++
    Write-Output 'PASS: scope rejects a dirty task worktree'

    Write-Text (Join-Path $taskWorktree 'outside.txt') "Out of scope`n"
    $null = Invoke-Git $taskWorktree @('add', '--all')
    $null = Invoke-Git $taskWorktree @('commit', '-m', 'test(scope): add out of scope file')
    Assert-Scope 1 'Out-of-scope paths:'
    $passed++
    Write-Output 'PASS: scope rejects a committed out-of-scope path'

    Write-Output ("TASK-SCOPE-REGRESSIONS: {0} passed, 0 failed" -f $passed)
} finally {
    try {
        $sourceHeadAfter = (Invoke-Git $repoRoot @('rev-parse', 'HEAD') | Select-Object -First 1).Trim()
        if ($sourceHeadBefore -and $sourceHeadAfter -ne $sourceHeadBefore) {
            throw 'Synthetic Git fixture changed the source repository HEAD.'
        }
    } finally {
        Restore-GitHookEnvironment $script:OriginalGitHookEnvironment
        $scratchFull = [IO.Path]::GetFullPath($scratch)
        $prefix = $tempRootFull + [IO.Path]::DirectorySeparatorChar
        if (-not $scratchFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to clean a path outside the supplied temporary root.'
        }
        if (Test-Path -LiteralPath $scratchFull) {
            Remove-Item -LiteralPath $scratchFull -Recurse -Force
        }
    }
}
