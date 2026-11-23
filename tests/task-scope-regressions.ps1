#Requires -Version 7.6
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
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
$startupGitEnvironmentNames = @(
    $script:GitHookEnvironmentNames
    Get-ChildItem Env: | Where-Object { $_.Name -match '^GIT_' } | ForEach-Object Name
) | Sort-Object -Unique
foreach ($name in $startupGitEnvironmentNames) {
    $script:OriginalGitHookEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$sourceStateBefore = $null

function Get-GitHookEnvironmentNames {
    $currentGitEnvironmentNames = @(
        Get-ChildItem Env: | Where-Object { $_.Name -match '^GIT_' } | ForEach-Object Name
    )
    return @($script:GitHookEnvironmentNames + $currentGitEnvironmentNames | Sort-Object -Unique)
}

function Write-Text([string]$Path, [string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Value, $utf8)
}

function Clear-GitHookEnvironment {
    $saved = @{}
    foreach ($name in (Get-GitHookEnvironmentNames)) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
    }
    return $saved
}

function Restore-GitHookEnvironment([hashtable]$Saved) {
    $restoreNames = @(
        $script:GitHookEnvironmentNames
        $Saved.Keys
        Get-ChildItem Env: | Where-Object { $_.Name -match '^GIT_' } | ForEach-Object Name
    ) | Sort-Object -Unique
    foreach ($name in $restoreNames) {
        $savedValue = if ($Saved.ContainsKey($name)) { [string]$Saved[$name] } else { '' }
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
    $gitConfigFingerprints = @(
        foreach ($configName in @('config', 'config.worktree')) {
            $configPath = ((Invoke-Git $repoRoot @('rev-parse', '--path-format=absolute', '--git-path', $configName) | Select-Object -First 1).Trim())
            if (Test-Path -LiteralPath $configPath -PathType Leaf) {
                '{0}:{1}' -f $configName, (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
            } else {
                '{0}:missing' -f $configName
            }
        }
    )
    return [pscustomobject]@{
        Head = $head
        Status = [string]::Join([string][char]10, [string[]]$statusLines)
        Refs = [string]::Join([string][char]10, [string[]]$refsLines)
        IndexSha256 = $indexSha256
        GitConfigFingerprint = [string]::Join('|', [string[]]$gitConfigFingerprints)
    }
}

function Assert-Scope([int]$ExpectedExit, [string]$ExpectedMessage, [string]$ExpectedSummary = '', [switch]$UseFixtureGitContext, [string]$BaseRef = 'main', [string]$ExpectedHeadSha) {
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
        $scopeArguments = @('-TaskId','T-008','-BaseRef',$BaseRef)
        if ($ExpectedHeadSha) { $scopeArguments += @('-ExpectedHeadSha',$ExpectedHeadSha) }
        $output = @(& $pwsh -NoLogo -NoProfile -File $verifier @scopeArguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Restore-GitHookEnvironment $savedEnvironment
    }
    $joined = $output -join [Environment]::NewLine
    if ($exitCode -ne $ExpectedExit) {
        throw "Scope verifier returned exit $exitCode; expected $ExpectedExit. Output: $joined"
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

    $probeGuardNames = @(Get-GitHookEnvironmentNames)
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
    $fixtureGitDirProbe = [IO.Path]::GetFullPath((Join-Path $scratch 'repo\.git\worktrees\wt'))
    $fixtureGitDirUtf8Bytes = [Text.Encoding]::UTF8.GetByteCount($fixtureGitDirProbe)
    if ($fixtureGitDirUtf8Bytes -gt 200) {
        throw ("Task scope regression TempRoot would exceed Git for Windows GIT_DIR limit: {0} UTF-8 bytes; maximum is 200." -f $fixtureGitDirUtf8Bytes)
    }
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
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0', 'user.name', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0', 'Synthetic Config Fixture', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_AUTHOR_NAME', 'Synthetic Author Fixture', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_AUTHOR_EMAIL', ('synthetic-author' + [char]64 + 'example.invalid'), 'Process')
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_NAME', 'Synthetic Committer Fixture', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_EMAIL', ('synthetic-committer' + [char]64 + 'example.invalid'), 'Process')

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
    $identityPoisonNames = @(
        'GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0',
        'GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL'
    )
    $savedIdentityControlEnvironment = @{}
    foreach ($name in (Get-GitHookEnvironmentNames)) {
        $savedIdentityControlEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
        if ($identityPoisonNames -cnotcontains $name) {
            Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
        }
    }
    try {
        $controlConfigName = (@(& git -C $fixtureRoot config user.name 2>&1) -join [Environment]::NewLine).Trim()
        $controlExit = $LASTEXITCODE
        if ($controlExit -ne 0 -or $controlConfigName -cne 'Synthetic Config Fixture') {
            throw 'Unsanitized dynamic GIT_CONFIG_* poison failed its control check.'
        }
        $controlAuthor = (@(& git -C $fixtureRoot var GIT_AUTHOR_IDENT 2>&1) -join [Environment]::NewLine).Trim()
        $controlExit = $LASTEXITCODE
        if ($controlExit -ne 0 -or $controlAuthor -cnotmatch '^Synthetic Author Fixture <synthetic-author@example[.]invalid> [0-9]+ [+-][0-9]{4}$') {
            throw 'Unsanitized GIT_AUTHOR_* poison failed its control check.'
        }
        $controlCommitter = (@(& git -C $fixtureRoot var GIT_COMMITTER_IDENT 2>&1) -join [Environment]::NewLine).Trim()
        $controlExit = $LASTEXITCODE
        if ($controlExit -ne 0 -or $controlCommitter -cnotmatch '^Synthetic Committer Fixture <synthetic-committer@example[.]invalid> [0-9]+ [+-][0-9]{4}$') {
            throw 'Unsanitized GIT_COMMITTER_* poison failed its control check.'
        }
    } finally {
        Restore-GitHookEnvironment $savedIdentityControlEnvironment
    }
    Write-Output 'PASS: unsanitized dynamic GIT_* identity controls were effective'
    $null = Invoke-Git $fixtureRoot @('add', '--all')
    $null = Invoke-Git $fixtureRoot @('commit', '-m', 'test(scope): seed fixture')
    $fixtureIdentity = @(
        Invoke-Git $fixtureRoot @('show', '-s', '--format=%an%n%ae%n%cn%n%ce', 'HEAD') |
            ForEach-Object { $_.Trim() }
    )
    $expectedFixtureIdentity = @('Scope Fixture', $fixtureEmail, 'Scope Fixture', $fixtureEmail)
    if (
        $fixtureIdentity.Count -ne $expectedFixtureIdentity.Count -or
        [string]::Join('|', [string[]]$fixtureIdentity) -cne
            [string]::Join('|', [string[]]$expectedFixtureIdentity)
    ) {
        throw 'Synthetic Git fixture commit inherited untrusted identity overrides.'
    }
    Write-Output 'PASS: synthetic GIT_* identity overrides did not reach fixture commit'
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
    $bracketTempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ptr[1]-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($bracketTempRoot)
    $sentinel = Join-Path $bracketTempRoot 'keep.txt'
    $savedGitDir = [Environment]::GetEnvironmentVariable('GIT_DIR', 'Process')
    try {
        [IO.File]::WriteAllText($sentinel, 'keep')
        [Environment]::SetEnvironmentVariable('GIT_DIR', (Join-Path $scratch 'invalid-git-dir'), 'Process')
        $gateOutput = @(& $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'scripts/quality-gate.ps1') -TemporaryRoot $bracketTempRoot 2>&1)
        $gateExit = $LASTEXITCODE
        $gateText = $gateOutput -join [Environment]::NewLine
        if ($gateExit -ne 1 -or $gateText -notmatch 'QUALITY-GATE=FAIL: GIT_IDENTITY_' -or
            $gateText -match 'QUALITY-GATE=FAIL: cleanup' -or [IO.File]::ReadAllText($sentinel) -cne 'keep' -or
            @(Get-ChildItem -LiteralPath $bracketTempRoot -Force).Count -ne 1) {
            throw "Quality gate must use a literal temporary path and clean only its own directory. Exit: $gateExit. Output: $gateText"
        }
    } finally {
        [Environment]::SetEnvironmentVariable('GIT_DIR', $savedGitDir, 'Process')
        [IO.File]::Delete($sentinel)
        if (@(Get-ChildItem -LiteralPath $bracketTempRoot -Force).Count -eq 0) {
            [IO.Directory]::Delete($bracketTempRoot)
        }
    }
    $passed++
    Write-Output 'PASS: quality gate uses a literal temporary path and cleans its own directory'

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
    $longTempRoot = Join-Path $scratch ('я' * 80)
    $taskSuitePath = Join-Path $PSScriptRoot 'task-scope-regressions.ps1'
    $longTaskOutput = @(& $pwsh -NoLogo -NoProfile -File $taskSuitePath -TempRoot $longTempRoot 2>&1)
    $longTaskExit = $LASTEXITCODE
    $longTaskText = $longTaskOutput -join [Environment]::NewLine
    if (
        $longTaskExit -eq 0 -or
        -not $longTaskText.Contains('Task scope regression TempRoot would exceed Git for Windows GIT_DIR limit') -or
        (Test-Path -LiteralPath $longTempRoot)
    ) {
        throw 'Task-scope regressions must refuse a multibyte TempRoot above the Git GIT_DIR byte budget before writes.'
    }

    $longGateOutput = @(& $pwsh -NoLogo -NoProfile -File $gatePath -TemporaryRoot $longTempRoot 2>&1)
    $longGateExit = $LASTEXITCODE
    $longGateText = $longGateOutput -join [Environment]::NewLine
    if (
        $longGateExit -eq 0 -or
        -not $longGateText.Contains('QUALITY-GATE: temporary root would exceed Git for Windows GIT_DIR limit') -or
        (Test-Path -LiteralPath $longTempRoot)
    ) {
        throw 'Quality gate must refuse a multibyte TempRoot above the Git GIT_DIR byte budget before writes.'
    }
    $passed++
    Write-Output 'PASS: task-scope and quality gates refuse long UTF-8 Git paths before writes'
    Write-Output 'PASS: quality gate refuses a TempRoot inside a linked worktree before writes'

    $junctionTarget = Join-Path $scratch 'target'
    $junction = Join-Path $scratch 'link'
    $null = New-Item -ItemType Directory -Path $junctionTarget
    $null = New-Item -ItemType Junction -Path $junction -Target $junctionTarget
    try {
        $gateOutput = @(& $pwsh -NoLogo -NoProfile -File $gatePath -TemporaryRoot (Join-Path $junction 'missing') 2>&1)
        $gateExit = $LASTEXITCODE
        if ($gateExit -eq 0 -or
            ($gateOutput -join [Environment]::NewLine) -notlike '*temporary path must be a directory without reparse points*' -or
            @(Get-ChildItem -LiteralPath $junctionTarget -Force).Count -ne 0) {
            throw 'Quality gate must reject a junction ancestor before writing to its target.'
        }
        $passed++
        Write-Output 'PASS: quality gate refuses a junction ancestor before writes'
    } finally {
        [IO.Directory]::Delete($junction)
    }

    $null = Invoke-Git $taskWorktree @('branch', '-m', 'task/T-008-scope-fixture')
    Assert-Scope 0 'TASK-SCOPE=PASS' 'TASK-SCOPE=PASS (2 changed paths; 3 allowed paths)'
    $expectedHead = ((Invoke-Git $taskWorktree @('rev-parse','HEAD')) -join '').Trim()
    $expectedBase = ((Invoke-Git $taskWorktree @('rev-parse','main')) -join '').Trim()
    Assert-Scope 0 'TASK-SCOPE=PASS' -BaseRef $expectedBase -ExpectedHeadSha $expectedHead
    Assert-Scope 1 'Current HEAD does not match the outgoing push SHA' -BaseRef $expectedBase -ExpectedHeadSha $expectedBase
    Assert-Scope 1 'No local commit for the requested base' -BaseRef ('a' * 40) -ExpectedHeadSha $expectedHead
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

    if ($passed -ne 10) { throw ('Expected 10 task-scope cases; found ' + $passed) }
    Write-Output ("TASK-SCOPE-REGRESSIONS: {0} passed, 0 failed" -f $passed)
} finally {
    try {
        if ($sourceStateBefore) {
            $sourceStateAfter = Get-SourceGitState
            if (
                $sourceStateAfter.Head -cne $sourceStateBefore.Head -or
                $sourceStateAfter.Status -cne $sourceStateBefore.Status -or
                $sourceStateAfter.Refs -cne $sourceStateBefore.Refs -or
                $sourceStateAfter.IndexSha256 -cne $sourceStateBefore.IndexSha256 -or
                $sourceStateAfter.GitConfigFingerprint -cne $sourceStateBefore.GitConfigFingerprint
            ) {
                throw 'Synthetic Git fixture changed source repository HEAD, refs, index, working status, or Git config.'
            }
            Write-Output 'PASS: task-scope fixtures preserved source Git config and metadata'
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
