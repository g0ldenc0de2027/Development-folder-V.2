[CmdletBinding()]
param(
    [string]$BaseRef,
    [string]$RemoteName,
    [string]$RemoteUrl,
    [string[]]$PushRange
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('development-folder-v2-gate-' + [guid]::NewGuid().ToString('N'))

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
    if ($PSVersionTable.PSVersion -lt [version]'7.4') {
        throw 'PowerShell 7.4 or newer is required'
    }
    $null = Get-Command git -ErrorAction Stop
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Set-Location -LiteralPath $repoRoot

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

    $scriptFiles = Get-ChildItem -LiteralPath $repoRoot -File -Recurse -Force -Filter '*.ps1' |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|\.worktrees|temp)[\\/]' }
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

    $insideWorkTree = & git rev-parse --is-inside-work-tree 2>$null
    $insideWorkTreeExit = $LASTEXITCODE
    if ($insideWorkTreeExit -ne 0 -or ($insideWorkTree -join '').Trim() -ne 'true') {
        throw 'Git history scan requires a valid non-bare worktree'
    }
    $head = & git rev-parse --verify 'HEAD^{commit}' 2>$null
    $headExit = $LASTEXITCODE
    $refs = @(& git for-each-ref '--format=%(objectname)' 2>$null)
    $refsExit = $LASTEXITCODE
    if ($refsExit -ne 0) { throw 'Could not enumerate Git refs for secret scanning' }
    if ($headExit -eq 0 -and $head) {
        & git log --format=%H --all HEAD *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Git could not enumerate HEAD and ref history for secret scanning' }
        Invoke-NativeChecked -Executable $gitleaks -Arguments @('git', '--redact=100', '--no-banner', '--log-opts=--all HEAD', $repoRoot) -Label 'Gitleaks reachable-history scan'
    } elseif ($refs.Count -gt 0) {
        & git log --format=%H --all *> $null
        if ($LASTEXITCODE -ne 0) { throw 'Git could not enumerate ref history for secret scanning' }
        Invoke-NativeChecked -Executable $gitleaks -Arguments @('git', '--redact=100', '--no-banner', $repoRoot) -Label 'Gitleaks ref-history scan'
    } else {
        $headRef = & git symbolic-ref --quiet HEAD 2>$null
        $symbolicExit = $LASTEXITCODE
        if ($symbolicExit -ne 0 -or ($headRef -join '') -notmatch '^refs/heads/[A-Za-z0-9._/-]+$') {
            throw 'Git history is unavailable and HEAD is not a valid unborn branch'
        }
        & git show-ref --verify --quiet ($headRef -join '') 2>$null
        $branchRefExit = $LASTEXITCODE
        if ($branchRefExit -ne 1) { throw 'HEAD could not be resolved and is not a clean unborn branch' }
        Write-Output 'NOT APPLICABLE: no commits or refs exist yet on the valid unborn branch.'
    }

    $normalizedPushRanges = [System.Collections.Generic.List[string]]::new()
    foreach ($range in @($PushRange | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ($range -match '^(?<head>(?:[0-9a-f]{40}|[0-9a-f]{64}))$') {
            $headInput = $Matches.head
            $baseInput = $null
        } elseif ($range -match '^(?<base>(?:[0-9a-f]{40}|[0-9a-f]{64}))\.\.(?<head>(?:[0-9a-f]{40}|[0-9a-f]{64}))$') {
            $headInput = $Matches.head
            $baseInput = $Matches.base
        } else {
            throw 'Pre-push supplied an invalid commit range for secret scanning'
        }

        $headCommit = & git rev-parse --verify ($headInput + '^{commit}') 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $headCommit) { throw 'Pushed object does not resolve to a commit for secret scanning' }
        if ($baseInput) {
            $baseCommit = & git rev-parse --verify ($baseInput + '^{commit}') 2>$null
            if ($LASTEXITCODE -ne 0 -or -not $baseCommit) { throw 'Remote base object is unavailable; fetch it before pushing' }
            $normalizedRange = ($baseCommit -join '') + '..' + ($headCommit -join '')
        } else {
            $normalizedRange = $headCommit -join ''
        }
        & git rev-list --max-count=1 $normalizedRange *> $null
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
        & git merge-base $BaseRef HEAD *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Base ref is unavailable or unrelated: $BaseRef"
        }
        Invoke-NativeChecked -Executable (Get-Command git).Source -Arguments @('diff', '--check', "$BaseRef...HEAD") -Label 'git diff check'
    }
    Invoke-NativeChecked -Executable (Get-Command git).Source -Arguments @('diff', '--check') -Label 'unstaged diff check'
    Invoke-NativeChecked -Executable (Get-Command git).Source -Arguments @('diff', '--cached', '--check') -Label 'staged diff check'

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
