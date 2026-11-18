#Requires -Version 7.6
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$pathSeparators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repoRootFull = [IO.Path]::GetFullPath($repoRoot).TrimEnd($pathSeparators)
$tempRootFull = [IO.Path]::GetFullPath($TempRoot).TrimEnd($pathSeparators)
$repositoryPrefix = $repoRootFull + [IO.Path]::DirectorySeparatorChar
if (
    [string]::Equals($tempRootFull, $repoRootFull, [StringComparison]::OrdinalIgnoreCase) -or
    $tempRootFull.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)
) {
    throw 'Task scope regression TempRoot must be outside every Git repository'
}
$scratch = Join-Path $tempRootFull ('ts-' + [guid]::NewGuid().ToString('N'))
$fixtureRoot = Join-Path $scratch 'repo'
$taskWorktree = Join-Path $scratch 'wt'
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
    'GIT_NAMESPACE',
    'GIT_CEILING_DIRECTORIES',
    'GIT_DISCOVERY_ACROSS_FILESYSTEM'
)
$script:OriginalGitHookEnvironment = @{}
foreach ($name in $script:GitHookEnvironmentNames) {
    $script:OriginalGitHookEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$sourceStateBefore = $null

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
        $savedValue = [string]$Saved[$name]
        if ([string]::IsNullOrEmpty($savedValue)) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $savedValue, 'Process')
        }
    }
}

function Invoke-Git([string]$WorkingDirectory, [string[]]$Arguments) {
    $savedEnvironment = Clear-GitHookEnvironment
    $originalOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $output = @(& git -C $WorkingDirectory @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        [Console]::OutputEncoding = $originalOutputEncoding
        Restore-GitHookEnvironment $savedEnvironment
    }
    if ($exitCode -ne 0) {
        throw ("Synthetic Git fixture command failed ({0}): {1}" -f ($Arguments -join ' '), ($output -join ' '))
    }
    return $output
}

function Get-SourceGitState {
    $head = ((Invoke-Git $repoRoot @('rev-parse', 'HEAD') | Select-Object -First 1).Trim())
    $statusLines = @(Invoke-Git $repoRoot @('status', '--porcelain=v1', '--untracked-files=all'))
    $refsLines = @(Invoke-Git $repoRoot @('for-each-ref', '--format=%(refname) %(objectname)'))
    $indexPath = ((Invoke-Git $repoRoot @('rev-parse', '--path-format=absolute', '--git-path', 'index') | Select-Object -First 1).Trim())
    if (-not (Test-Path -LiteralPath $indexPath -PathType Leaf)) {
        throw 'Unable to locate the source repository index for fixture isolation checks.'
    }
    $indexSha256 = (Get-FileHash -LiteralPath $indexPath -Algorithm SHA256).Hash
    return [pscustomobject]@{
        Head = $head
        Status = [string]::Join([string][char]10, [string[]]$statusLines)
        Refs = [string]::Join([string][char]10, [string[]]$refsLines)
        IndexSha256 = $indexSha256
    }
}

function Assert-Scope([int]$ExpectedExit, [string]$ExpectedMessage, [string]$ExpectedSummary = '', [switch]$UseFixtureGitContext) {
    $verifier = Join-Path $taskWorktree 'scripts/verify-task-scope.ps1'
    $savedEnvironment = Clear-GitHookEnvironment
    try {
        if ($UseFixtureGitContext) {
            $gitDir = ((Invoke-Git $taskWorktree @('rev-parse', '--path-format=absolute', '--git-dir') | Select-Object -First 1).Trim())
            $commonDir = ((Invoke-Git $taskWorktree @('rev-parse', '--path-format=absolute', '--git-common-dir') | Select-Object -First 1).Trim())
            $indexPath = ((Invoke-Git $taskWorktree @('rev-parse', '--path-format=absolute', '--git-path', 'index') | Select-Object -First 1).Trim())
            [Environment]::SetEnvironmentVariable('GIT_DIR', $gitDir, 'Process')
            [Environment]::SetEnvironmentVariable('GIT_WORK_TREE', $taskWorktree, 'Process')
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE', $indexPath, 'Process')
            [Environment]::SetEnvironmentVariable('GIT_COMMON_DIR', $commonDir, 'Process')
            [Environment]::SetEnvironmentVariable('GIT_CEILING_DIRECTORIES', $scratch, 'Process')
            [Environment]::SetEnvironmentVariable('GIT_DISCOVERY_ACROSS_FILESYSTEM', '0', 'Process')
        }
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

function Assert-TempRootOutsideGitRepositories {
    $probe = $tempRootFull
    while (-not [IO.Directory]::Exists($probe)) {
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $probe, [StringComparison]::OrdinalIgnoreCase)) { break }
        $probe = $parent
    }
    if (-not [IO.Directory]::Exists($probe)) { throw 'Task scope regression TempRoot has no existing parent directory' }

    $probeGuardNames = @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_PREFIX','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM')
    $savedProbeEnvironment = @{}
    foreach ($name in $probeGuardNames) {
        $savedProbeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }
    try {
        while ($probe) {
            $gitMarker = Join-Path $probe '.git'
            $bareRepositoryMarkers = (
                (Test-Path -LiteralPath (Join-Path $probe 'HEAD') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $probe 'config') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $probe 'objects') -PathType Container) -and
                (Test-Path -LiteralPath (Join-Path $probe 'refs') -PathType Container)
            )
            if ((Test-Path -LiteralPath $gitMarker) -or $bareRepositoryMarkers) {
                throw 'Task scope regression TempRoot must be outside every Git repository'
            }
            $gitRoot = @(& git -C $probe rev-parse --show-toplevel 2>$null)
            $gitRootExit = $LASTEXITCODE
            $bareState = @(& git -C $probe rev-parse --is-bare-repository 2>$null)
            $bareStateExit = $LASTEXITCODE
            if ($gitRootExit -eq 0 -or ($bareStateExit -eq 0 -and ($bareState -join '').Trim() -eq 'true')) {
                throw 'Task scope regression TempRoot must be outside every Git repository'
            }
            $parent = Split-Path -Parent $probe
            if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $probe, [StringComparison]::OrdinalIgnoreCase)) { break }
            $probe = $parent
        }
    } finally {
        foreach ($name in $probeGuardNames) {
            $savedValue = [string]$savedProbeEnvironment[$name]
            if ([string]::IsNullOrEmpty($savedValue)) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            } else {
                [Environment]::SetEnvironmentVariable($name, $savedValue, 'Process')
            }
        }
    }
}

try {
    Assert-TempRootOutsideGitRepositories
    $sourceStateBefore = Get-SourceGitState
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
    [IO.Directory]::CreateDirectory((Join-Path $fixtureRoot 'config')) | Out-Null
    [IO.File]::Copy((Join-Path $repoRoot 'scripts/verify-runtime.ps1'), (Join-Path $fixtureRoot 'scripts/verify-runtime.ps1'))
    [IO.File]::Copy((Join-Path $repoRoot 'scripts/verify-task-scope.ps1'), (Join-Path $fixtureRoot 'scripts/verify-task-scope.ps1'))
    [IO.File]::Copy((Join-Path $repoRoot 'config/runtime-support.json'), (Join-Path $fixtureRoot 'config/runtime-support.json'))
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
    Assert-Scope 0 'TASK-SCOPE=PASS' 'TASK-SCOPE=PASS (2 changed paths; 3 allowed paths)' -UseFixtureGitContext
    $passed++
    Write-Output 'PASS: scope accepts Unicode paths with inherited task-worktree Git context'

    $originalOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(866)
        Assert-Scope 0 'TASK-SCOPE=PASS' 'TASK-SCOPE=PASS (2 changed paths; 3 allowed paths)' -UseFixtureGitContext
    } finally {
        [Console]::OutputEncoding = $originalOutputEncoding
    }
    $passed++
    Write-Output 'PASS: scope decodes Unicode Git paths under a non-UTF-8 console code page'

    if (-not (Test-Path -LiteralPath (Join-Path $taskWorktree '.git') -PathType Leaf)) {
        throw 'Synthetic task fixture must use a linked-worktree .git file marker.'
    }
    $linkedTempRoot = Join-Path $taskWorktree ('temp/T-GATE-LINKED-REJECT-' + [guid]::NewGuid().ToString('N'))
    $gatePath = Join-Path $repoRoot 'scripts/quality-gate.ps1'
    $gateOutput = @(& $pwsh -NoLogo -NoProfile -File $gatePath -BaseRef origin/main -TemporaryRoot $linkedTempRoot 2>&1)
    $gateExit = $LASTEXITCODE
    $gateText = $gateOutput -join [Environment]::NewLine
    if (
        $gateExit -eq 0 -or
        -not $gateText.Contains('QUALITY-GATE: temporary root must be outside the source repository') -or
        (Test-Path -LiteralPath $linkedTempRoot)
    ) {
        throw 'Quality gate must refuse a TempRoot inside a linked worktree before creating artifacts.'
    }
    $passed++
    Write-Output 'PASS: quality gate refuses a TempRoot inside a linked worktree before writes'

    $null = Invoke-Git $taskWorktree @('branch', '-m', 'task/T-008-scope-fixture')
    Assert-Scope 0 'TASK-SCOPE=PASS' 'TASK-SCOPE=PASS (2 changed paths; 3 allowed paths)'
    $passed++
    Write-Output 'PASS: scope accepts the documented task ID with a lowercase hyphenated slug'

    $null = Invoke-Git $taskWorktree @('branch', '-m', 'task/T-008-scope_fixture')
    Assert-Scope 1 'Current branch does not match the task ID'
    $passed++
    $null = Invoke-Git $taskWorktree @('branch', '-m', 'task/T-008-scope-fixture')
    Write-Output 'PASS: scope rejects a malformed task slug'

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

    if ($passed -ne 7) { throw ('Expected 7 task-scope cases; found ' + $passed) }
    Write-Output ("TASK-SCOPE-REGRESSIONS: {0} passed, 0 failed" -f $passed)
} finally {
    try {
        if ($sourceStateBefore) {
            $sourceStateAfter = Get-SourceGitState
            if (
                $sourceStateAfter.Head -cne $sourceStateBefore.Head -or
                $sourceStateAfter.Status -cne $sourceStateBefore.Status -or
                $sourceStateAfter.Refs -cne $sourceStateBefore.Refs -or
                $sourceStateAfter.IndexSha256 -cne $sourceStateBefore.IndexSha256
            ) {
                throw 'Synthetic Git fixture changed source repository HEAD, refs, index, or working status.'
            }
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
