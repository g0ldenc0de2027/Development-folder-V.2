[CmdletBinding()]
param(
    [string]$BaseRef,
    [string]$RemoteName,
    [string]$RemoteUrl,
    [string[]]$PushRange,
    [string]$TemporaryRoot = [System.IO.Path]::GetTempPath()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$temporaryBaseRoot = [System.IO.Path]::GetFullPath($TemporaryRoot)
$temporaryRoot = Join-Path $temporaryBaseRoot ('gate-' + [guid]::NewGuid().ToString('N'))
$taskScopeGitDirByteBudget = 200

function Assert-TemporaryRootOutsideRepository {
    $separators = [char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $repoFull = [IO.Path]::GetFullPath($repoRoot).TrimEnd($separators)
    $candidate = $temporaryBaseRoot.TrimEnd($separators)
    $repoPrefix = $repoFull + [IO.Path]::DirectorySeparatorChar
    if ([string]::Equals($candidate, $repoFull, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'QUALITY-GATE: temporary root must be outside the source repository and every Git repository'
    }

    $probe = $candidate
    while (-not [IO.Directory]::Exists($probe)) {
        $parent = Split-Path -Parent $probe
        if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $probe, [StringComparison]::OrdinalIgnoreCase)) { break }
        $probe = $parent
    }
    if (-not [IO.Directory]::Exists($probe)) { throw 'QUALITY-GATE: temporary root has no existing parent directory' }

    $gitEnvironmentNames = @(
        'GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_PREFIX','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY',
        'GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_NAMESPACE','GIT_CEILING_DIRECTORIES','GIT_DISCOVERY_ACROSS_FILESYSTEM'
        Get-ChildItem Env: | Where-Object { $_.Name -match '^GIT_' } | ForEach-Object Name
    ) | Sort-Object -Unique
    $savedEnvironment = @{}
    foreach ($name in $gitEnvironmentNames) {
        $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
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
                throw 'QUALITY-GATE: temporary root must be outside the source repository and every Git repository'
            }
            $gitRoot = @(& git -C $probe rev-parse --show-toplevel 2>$null)
            $gitRootExit = $LASTEXITCODE
            $bareState = @(& git -C $probe rev-parse --is-bare-repository 2>$null)
            $bareStateExit = $LASTEXITCODE
            if ($gitRootExit -eq 0 -or ($bareStateExit -eq 0 -and ($bareState -join '').Trim() -eq 'true')) {
                throw 'QUALITY-GATE: temporary root must be outside the source repository and every Git repository'
            }
            $parent = Split-Path -Parent $probe
            if ([string]::IsNullOrWhiteSpace($parent) -or [string]::Equals($parent, $probe, [StringComparison]::OrdinalIgnoreCase)) { break }
            $probe = $parent
        }
        $gitDirProbe = [IO.Path]::GetFullPath((Join-Path $temporaryRoot ('ts-' + ('0' * 32) + '\repo\.git\worktrees\wt')))
        $gitDirUtf8Bytes = [Text.Encoding]::UTF8.GetByteCount($gitDirProbe)
        if ($gitDirUtf8Bytes -gt $taskScopeGitDirByteBudget) {
            throw ("QUALITY-GATE: temporary root would exceed Git for Windows GIT_DIR limit ({0} UTF-8 bytes); choose a shorter TemporaryRoot." -f $taskScopeGitDirByteBudget)
        }
    } finally {
        foreach ($name in $gitEnvironmentNames) {
            $savedValue = [string]$savedEnvironment[$name]
            if ([string]::IsNullOrEmpty($savedValue)) {
                Remove-Item -LiteralPath "Env:$name" -ErrorAction SilentlyContinue
            } else {
                [Environment]::SetEnvironmentVariable($name, $savedValue, 'Process')
            }
        }
    }
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory)][string]$Executable,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Label
    )
    & $Executable @Arguments
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "$Label failed with exit code $code"
    }
}

function Get-PinnedExecutable {
    param(
        [Parameter(Mandatory)]$Tool,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Tool.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "$Name has an invalid SHA-256 pin"
    }
    $toolRoot = Join-Path $temporaryRoot $Name
    New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
    $archive = Join-Path $toolRoot 'download.zip'
    Invoke-WebRequest -Uri $Tool.url -OutFile $archive
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -ne $Tool.sha256.ToLowerInvariant()) {
        throw "$Name archive SHA-256 did not match the pinned value"
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $toolRoot -Force
    $executable = Get-ChildItem -LiteralPath $toolRoot -Filter $Tool.executable -File -Recurse | Select-Object -First 1
    if (-not $executable) {
        throw "$Name executable was not found in the verified archive"
    }
    return $executable.FullName
}

try {
    Assert-TemporaryRootOutsideRepository
    & (Join-Path $PSScriptRoot 'verify-runtime.ps1')
    $null = Get-Command git -ErrorAction Stop
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Set-Location -LiteralPath $repoRoot
    Import-Module (Join-Path $PSScriptRoot 'lib/GitIdentity.psm1') -Force
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $repoRoot -HookContext

    Write-Output 'QUALITY-GATE: validating configuration and PowerShell syntax'
    $jsonFiles = @(
        'config/github/repository.json',
        'config/github/main-ruleset.json',
        'config/github/actions-policy.json',
        'config/security/tools.json'
    )
    foreach ($relative in $jsonFiles) {
        $path = Join-Path $repoRoot $relative
        $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }

    . (Join-Path $repoRoot 'scripts/ide-cache.ps1')
    $scriptFiles = @(
        Get-ProjectFiles $repoRoot | Where-Object { $_.Extension -ieq '.ps1' } |
            Where-Object {
                $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName)
                $relativePath -notmatch '(^|[\\/])(\.git|\.worktrees|\.work|\.manus|temp)([\\/]|$)'
            }
    )
    if ($scriptFiles.Count -eq 0) {
        throw 'PowerShell syntax scan found no repository scripts'
    }
    foreach ($file in $scriptFiles) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0) {
            $summary = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
            throw "PowerShell parse error in $($file.FullName): $summary"
        }
    }
    Write-Output ("PASS: JSON manifests and {0} PowerShell files parsed" -f $scriptFiles.Count)

    Write-Output 'QUALITY-GATE: running regression checks'
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/quality-gate-regressions.ps1')
    $testExit = $LASTEXITCODE
    if ($testExit -ne 0) {
        throw "quality-gate-regressions.ps1 failed with exit code $testExit"
    }
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/git-identity-regressions.ps1') -TempRoot $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw 'Git identity regressions failed' }
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/task-worktree-regressions.ps1') -TempRoot $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw 'Task worktree regressions failed' }

    Write-Output 'QUALITY-GATE: validating IDE cache isolation'
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/ide-cache-regressions.ps1') -TempRoot $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw 'IDE cache regressions failed' }

    if ($env:GITHUB_EVENT_NAME -ne 'pull_request') {
        Write-Output 'NOT APPLICABLE: hosted PR merge-result assertion requires pull_request event'
    }
    Write-Output 'QUALITY-GATE: running PR merge-result regressions'
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/pr-merge-result-regressions.ps1') -TempRoot $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw 'PR merge-result regressions failed' }
    Write-Output 'QUALITY-GATE: checking local knowledge and pinned rules'
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'scripts/kb.ps1') check
    if ($LASTEXITCODE -ne 0) { throw 'Knowledge integrity check failed' }
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/kb-regressions.ps1') -TempRoot $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw 'Knowledge regressions failed' }

    Write-Output 'QUALITY-GATE: running task-scope regression fixtures'
    & $pwsh -NoLogo -NoProfile -File (Join-Path $repoRoot 'tests/task-scope-regressions.ps1') -TempRoot $temporaryRoot
    if ($LASTEXITCODE -ne 0) { throw 'Task-scope regressions failed' }

    $manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'config/security/tools.json') -Raw | ConvertFrom-Json
    $actionlint = Get-PinnedExecutable -Tool $manifest.tools.actionlint -Name 'actionlint'
    $gitleaks = Get-PinnedExecutable -Tool $manifest.tools.gitleaks -Name 'gitleaks'

    Write-Output 'QUALITY-GATE: validating GitHub Actions workflow'
    Invoke-NativeChecked -Executable $actionlint -Arguments @('-no-color') -Label 'actionlint'
    Write-Output 'PASS: actionlint'

    Write-Output 'QUALITY-GATE: scanning current files and Git history for secrets'
    Invoke-NativeChecked -Executable $gitleaks -Arguments @('dir', '--redact=100', '--no-banner', $repoRoot) -Label 'Gitleaks working-tree scan'

    $repositoryConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json
    if ($RemoteName) {
        $expectedRemoteUrl = 'https://github.com/' + $repositoryConfig.repository + '.git'
        if ($RemoteName -cne 'origin' -or $RemoteUrl -cne $expectedRemoteUrl) {
            throw 'Push destination does not match the configured origin repository'
        }
    }

    $insideWorkTree = & git --no-pager rev-parse --is-inside-work-tree 2>$null
    $insideWorkTreeExit = $LASTEXITCODE
    if ($insideWorkTreeExit -ne 0 -or ($insideWorkTree -join '').Trim() -ne 'true') {
        throw 'Git history scan requires a valid non-bare worktree'
    }
    $head = & git --no-pager rev-parse --verify 'HEAD^{commit}' 2>$null
    $headExit = $LASTEXITCODE
    $refs = @(& git --no-pager for-each-ref '--format=%(objectname)' 2>$null)
    $refsExit = $LASTEXITCODE
    if ($refsExit -ne 0) { throw 'Could not enumerate Git refs for secret scanning' }
    if ($headExit -eq 0 -and $head) {
        & git --no-pager log --format=%H --all HEAD *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Git could not enumerate HEAD and ref history for secret scanning' }
        Invoke-NativeChecked -Executable $gitleaks -Arguments @('git', '--redact=100', '--no-banner', '--log-opts=--all HEAD', $repoRoot) -Label 'Gitleaks reachable-history scan'
    } elseif ($refs.Count -gt 0) {
        & git --no-pager log --format=%H --all *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Git could not enumerate ref history for secret scanning' }
        Invoke-NativeChecked -Executable $gitleaks -Arguments @('git', '--redact=100', '--no-banner', $repoRoot) -Label 'Gitleaks ref-history scan'
    } else {
        $headRef = & git --no-pager symbolic-ref --quiet HEAD 2>$null
        $symbolicExit = $LASTEXITCODE
        if ($symbolicExit -ne 0 -or ($headRef -join '') -notmatch '^refs/heads/[A-Za-z0-9._/-]+$') {
            throw 'Git history is unavailable and HEAD is not a valid unborn branch'
        }
        & git --no-pager show-ref --verify --quiet ($headRef -join '') 2>$null
        $branchRefExit = $LASTEXITCODE
        if ($branchRefExit -ne 1) { throw 'HEAD could not be resolved and is not a clean unborn branch' }
        Write-Output 'NOT APPLICABLE: no commits or refs exist yet on the valid unborn branch.'
    }

    $normalizedPushRanges = [System.Collections.Generic.List[string]]::new()
    $pushRangeLines = foreach ($rangeArgument in @($PushRange | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $rangeArgument -split '\r?\n'
    }
    foreach ($range in @($pushRangeLines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($range -match '^(?<head>(?:[0-9a-f]{40}|[0-9a-f]{64}))$') {
            $headInput = $Matches.head
            $baseInput = $null
        } elseif ($range -match '^(?<base>(?:[0-9a-f]{40}|[0-9a-f]{64}))\.\.(?<head>(?:[0-9a-f]{40}|[0-9a-f]{64}))$') {
            $headInput = $Matches.head
            $baseInput = $Matches.base
        } else {
            throw 'Pre-push supplied an invalid commit range for secret scanning'
        }

        $headCommit = & git --no-pager rev-parse --verify ($headInput + '^{commit}') 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $headCommit) { throw 'Pushed object does not resolve to a commit for secret scanning' }
        if ($baseInput) {
            $baseCommit = & git --no-pager rev-parse --verify ($baseInput + '^{commit}') 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $baseCommit) { throw 'Remote base object is unavailable; fetch it before pushing' }
            $normalizedRange = ($baseCommit -join '') + '..' + ($headCommit -join '')
        } else {
            $normalizedRange = $headCommit -join ''
        }
        & git --no-pager rev-list --max-count=1 $normalizedRange *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Git could not enumerate a pushed commit range for secret scanning' }
        if (-not $normalizedPushRanges.Contains($normalizedRange)) { $normalizedPushRanges.Add($normalizedRange) }
    }
    if ($normalizedPushRanges.Count -gt 0) {
        $pushLogOptions = '--no-textconv --full-history ' + ($normalizedPushRanges -join ' ')
        Invoke-NativeChecked -Executable $gitleaks -Arguments @('git', '--redact=100', '--no-banner', ('--log-opts=' + $pushLogOptions), $repoRoot) -Label 'Gitleaks pushed-history scan'
    }
    Write-Output 'PASS: Gitleaks working tree, reachable history and supplied push ranges'

    if (-not $BaseRef -and $env:PR_BASE_BRANCH) {
        $BaseRef = 'origin/' + $env:PR_BASE_BRANCH
    }
    if ($BaseRef) {
        & git --no-pager merge-base $BaseRef HEAD *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Base ref is unavailable or unrelated: $BaseRef"
        }
        Invoke-NativeChecked -Executable (Get-Command git).Source -Arguments @('--no-pager','diff', '--check', "$BaseRef...HEAD") -Label 'git diff check'
    }
    Invoke-NativeChecked -Executable (Get-Command git).Source -Arguments @('--no-pager','diff', '--check') -Label 'unstaged diff check'
    Invoke-NativeChecked -Executable (Get-Command git).Source -Arguments @('--no-pager','diff', '--cached', '--check') -Label 'staged diff check'

    Write-Output 'NOT COVERED: no application stack is selected in the template; stack build and dependency audit do not apply to this baseline.'
    Write-Output 'QUALITY-GATE=PASS'
    exit 0
}
catch {
    [Console]::Error.WriteLine('QUALITY-GATE=FAIL: ' + $_.Exception.Message)
    exit 1
}
finally {
    Set-Location -LiteralPath $repoRoot
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
