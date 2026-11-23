#Requires -Version 7.4
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = [IO.Path]::GetFullPath($TempRoot)
[IO.Directory]::CreateDirectory($root) | Out-Null
$scratch = Join-Path $root ('Проверка-идентичности-Git-' + [guid]::NewGuid().ToString('N'))
$seed = Join-Path $scratch 'seed'
$worktree = Join-Path $scratch 'worktree'
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/GitIdentity.psm1'
$repoRoot = Split-Path $PSScriptRoot -Parent
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0
$envNames = @([Environment]::GetEnvironmentVariables('Process').Keys | ForEach-Object { [string]$_ } | Where-Object {
    $_.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)
} | Sort-Object -Unique)
$savedEnv = @{}
foreach ($name in $envNames) {
    $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
    Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
}
$remainingGitEnvironment = @([Environment]::GetEnvironmentVariables('Process').Keys | ForEach-Object { [string]$_ } | Where-Object {
    $_.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)
})
if ($remainingGitEnvironment.Count -gt 0) { throw ('GIT_IDENTITY_TEST_ENVIRONMENT_NOT_CLEAN:' + ($remainingGitEnvironment -join ',')) }

function Invoke-GitFixture([string]$Directory,[string[]]$Arguments,[hashtable]$GitEnvironment=@{}) {
    $git = (Get-Command git -ErrorAction Stop).Source
    if ([string]::IsNullOrWhiteSpace($script:fixtureGlobalConfig)) { throw 'GIT_FIXTURE_GLOBAL_CONFIG_UNSET' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $git
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $start.ArgumentList.Add('-C')
    $start.ArgumentList.Add($Directory)
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($name in @($start.Environment.Keys | Where-Object { ([string]$_).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) })) {
        $null = $start.Environment.Remove([string]$name)
    }
    $start.Environment['GIT_CONFIG_GLOBAL'] = $script:fixtureGlobalConfig
    $start.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $allowedFixtureEnvironment = @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')
    foreach ($name in $GitEnvironment.Keys) {
        if ($name -notin $allowedFixtureEnvironment) { throw ('GIT_FIXTURE_ENVIRONMENT_NOT_ALLOWED:' + $name) }
        $start.Environment[$name] = [string]$GitEnvironment[$name]
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $detail = ($stdout.Result + ' ' + $stderr.Result) -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+','<redacted>'
        throw ('GIT_FIXTURE_COMMAND_FAILED:' + $process.ExitCode + ':' + ($Arguments -join ' ') + ':' + $detail.Trim())
    }
    return $stdout.Result.Trim()
}
function WriteText([string]$Path,[string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Value,$utf8)
}
function ExpectFailure([scriptblock]$Action,[string]$Code) {
    try { & $Action; throw 'EXPECTED_FAILURE_NOT_RAISED' }
    catch {
        if ($_.Exception.Message -notlike ('*'+$Code+'*')) { throw }
        if ($_.Exception.Message.Contains('fixture@example.invalid')) { throw 'GIT_IDENTITY_ERROR_LEAKED_EMAIL' }
    }
}
function Case([string]$Name,[scriptblock]$Action) {
    & $Action
    $script:passed++
    Write-Output ('PASS: ' + $Name)
}
function Invoke-GitProcess([string[]]$Arguments,[hashtable]$Environment=@{},[string]$Executable=(Get-Command git -ErrorAction Stop).Source,[string]$WorkingDirectory,[string]$InputLine) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    if ($WorkingDirectory) { $startInfo.WorkingDirectory = $WorkingDirectory }
    $startInfo.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputLine')
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $startInfo.ArgumentList.Add($argument) }
    foreach ($entry in $Environment.GetEnumerator()) { $startInfo.Environment[$entry.Key] = [string]$entry.Value }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($startInfo.RedirectStandardInput) {
        $process.StandardInput.Write($InputLine + [char]10)
        $process.StandardInput.Close()
    }
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode=$process.ExitCode; StdOut=$stdoutTask.Result; StdErr=$stderrTask.Result }
}
function Find-GitForWindowsShellRoot([string[]]$StartPaths) {
    foreach ($startPath in $StartPaths) {
        if ([string]::IsNullOrWhiteSpace($startPath)) { continue }
        try { $current = [IO.Path]::GetFullPath($startPath) }
        catch { continue }
        if (Test-Path -LiteralPath $current -PathType Leaf) { $current = [IO.Path]::GetDirectoryName($current) }
        while (-not [string]::IsNullOrWhiteSpace($current)) {
            $sh = Join-Path $current 'bin/sh.exe'
            $cygpath = Join-Path $current 'usr/bin/cygpath.exe'
            if ((Test-Path -LiteralPath $sh -PathType Leaf) -and (Test-Path -LiteralPath $cygpath -PathType Leaf)) {
                return [IO.Path]::GetFullPath($current)
            }
            $parentInfo = [IO.Directory]::GetParent($current)
            if ($null -eq $parentInfo) { break }
            $parent = $parentInfo.FullName
            if ($parent.Equals($current,[StringComparison]::OrdinalIgnoreCase)) { break }
            $current = $parent
        }
    }
    return $null
}
function New-PwshShim([string]$Directory,[string]$LogPath) {
    $gitExe = (Get-Command git -ErrorAction Stop).Source
    $execPathOutput = @(& git --exec-path 2>$null)
    $execPathExitCode = $LASTEXITCODE
    if ($execPathExitCode -ne 0 -or $execPathOutput.Count -eq 0) { throw 'GIT_IDENTITY_GIT_EXEC_PATH_UNAVAILABLE' }
    $gitRoot = Find-GitForWindowsShellRoot -StartPaths @($gitExe,([string]$execPathOutput[0]).Trim())
    if ([string]::IsNullOrWhiteSpace($gitRoot)) { throw 'GIT_IDENTITY_GIT_FOR_WINDOWS_SHELL_MISSING' }
    $sh = Join-Path $gitRoot 'bin/sh.exe'
    $cygpath = Join-Path $gitRoot 'usr/bin/cygpath.exe'
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    $shim = Join-Path $Directory 'pwsh'
    WriteText $shim @'
#!/bin/sh
set -eu
printf '%s\000' "$#" >> "$PWSSHIM_LOG"
for argument in "$@"; do printf '%s\000' "$argument" >> "$PWSSHIM_LOG"; done
printf '\000' >> "$PWSSHIM_LOG"
case "$PWSSHIM_MODE" in
    precommit-block)
        case "$*" in *verify-git-identity.ps1*) exit 23 ;; esac
        ;;
    precommit-repair)
        case "$*" in
            *verify-git-identity.ps1*)
                count=0
                if [ -f "$PWSSHIM_STATE" ]; then count=$(cat "$PWSSHIM_STATE"); fi
                count=$((count + 1))
                printf '%s' "$count" > "$PWSSHIM_STATE"
                if [ "$count" -eq 1 ]; then exit 24; fi
                ;;
        esac
        ;;
esac
case "$*" in *-PassThruPublishedMainSha*) printf '%s\r\n' "$PWSSHIM_PUBLISHED_MAIN" ;; esac
exit 0
'@
    & $sh -c 'chmod +x "$1"' sh $shim
    if ($LASTEXITCODE -ne 0) { throw 'GIT_IDENTITY_PWSH_SHIM_NOT_EXECUTABLE' }
    $logPosix = (& $cygpath -u $LogPath).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logPosix)) { throw 'GIT_IDENTITY_SHIM_LOG_PATH_INVALID' }
    return [pscustomobject]@{
        Directory=$Directory
        ShellPath=$sh
        DirectoryPosix=(& $cygpath -u $Directory).Trim()
        LogPath=$logPosix
        StatePath=(& $cygpath -u (Join-Path $Directory 'state.txt')).Trim()
        PrePushHookPosix=(& $cygpath -u (Join-Path $repoRoot '.githooks/pre-push')).Trim()
        PreCommitHookPosix=(& $cygpath -u (Join-Path $repoRoot '.githooks/pre-commit')).Trim()
        Sh=$sh
    }
}
function New-HookProxy([string]$Directory) {
    [IO.Directory]::CreateDirectory($Directory) | Out-Null
    foreach ($name in @('pre-push','pre-commit')) {
        $variable = if ($name -ceq 'pre-push') { 'REAL_PRE_PUSH_HOOK' } else { 'REAL_PRE_COMMIT_HOOK' }
        $proxy = Join-Path $Directory $name
        $proxyContents = @'
#!/bin/sh
PATH="$PWSSHIM_DIR:$PATH"
export PATH
. "__HOOK_TARGET__"
'@
        $proxyContents = $proxyContents.Replace('__HOOK_TARGET__','$' + $variable)
        WriteText $proxy $proxyContents
        & $script:hookShim.Sh -c 'chmod +x "$1"' sh $proxy
        if ($LASTEXITCODE -ne 0) { throw 'GIT_IDENTITY_HOOK_PROXY_NOT_EXECUTABLE' }
    }
    return [pscustomobject]@{ Directory=$Directory }
}
function Read-PwshShimCalls([string]$LogPath) {
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return [pscustomobject]@{ Calls=@() } }
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($LogPath))
    $tokens = $text.Split([char]0)
    $calls = [System.Collections.Generic.List[object]]::new()
    $index = 0
    while ($index -lt $tokens.Count) {
        if ([string]::IsNullOrEmpty($tokens[$index])) { $index++; continue }
        $argumentCount = 0
        if (-not [int]::TryParse($tokens[$index], [ref]$argumentCount) -or $argumentCount -lt 0) {
            throw 'GIT_IDENTITY_SHIM_LOG_INVALID'
        }
        $index++
        $arguments = [string[]]::new($argumentCount)
        for ($argumentIndex = 0; $argumentIndex -lt $argumentCount; $argumentIndex++) {
            if ($index -ge $tokens.Count) { throw 'GIT_IDENTITY_SHIM_LOG_TRUNCATED' }
            $arguments[$argumentIndex] = $tokens[$index]
            $index++
        }
        $calls.Add($arguments)
        if ($index -lt $tokens.Count -and [string]::IsNullOrEmpty($tokens[$index])) { $index++ }
    }
    return [pscustomobject]@{ Calls=$calls.ToArray() }
}
function Get-PwshParameterValue([string[]]$Arguments,[string]$Name) {
    $position = [Array]::IndexOf($Arguments,$Name)
    if ($position -lt 0 -or $position + 1 -ge $Arguments.Count) { throw ('GIT_IDENTITY_SHIM_PARAMETER_MISSING:' + $Name) }
    return $Arguments[$position + 1]
}

try {
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    $globalConfig = Join-Path $scratch 'global.gitconfig'
    $xdg = Join-Path $scratch 'xdg'
    [IO.Directory]::CreateDirectory($xdg) | Out-Null
    [IO.File]::WriteAllText($globalConfig,'',$utf8)
    $script:fixtureGlobalConfig = $globalConfig

    Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$seed) | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('config','extensions.worktreeConfig','true') | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('config','user.name','Seed Fixture') | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('config','user.email','seed@example.invalid') | Out-Null
    WriteText (Join-Path $seed 'README.md') 'Synthetic identity test fixture.'
    Invoke-GitFixture -Directory $seed -Arguments @('add','README.md') | Out-Null
    $env:GIT_AUTHOR_NAME = 'Seed Fixture'
    $env:GIT_AUTHOR_EMAIL = 'seed@example.invalid'
    $env:GIT_COMMITTER_NAME = 'Seed Fixture'
    $env:GIT_COMMITTER_EMAIL = 'seed@example.invalid'
    try { Invoke-GitFixture -Directory $seed -Arguments @('commit','--quiet','-m','test: seed synthetic identity repo') | Out-Null }
    finally {
        foreach ($name in @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
    }
    Invoke-GitFixture -Directory $seed -Arguments @('branch','-M','main') | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('config','--local','user.name','Scope Fixture') | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('config','--local','user.email','scope@example.invalid') | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('remote','add','origin',$seed) | Out-Null
    Invoke-GitFixture -Directory $seed -Arguments @('worktree','add','--quiet','-b','task/identity-fixture',$worktree,'main') | Out-Null
    $base = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
    Invoke-GitFixture -Directory $seed -Arguments @('update-ref','refs/remotes/origin/main',$base) | Out-Null
    WriteText (Join-Path $worktree 'config/github/repository.json') (@{commitIdentity=@{login='synthetic-owner';userId=123456}} | ConvertTo-Json -Depth 4)
    Import-Module $modulePath -Force

    Case 'GIT-ID-001 missing worktree identity fails closed' {
        ExpectFailure { Assert-GitWorktreeIdentity -RepositoryRoot $worktree } 'GIT_IDENTITY_WORKTREE_NAME_MISMATCH'
    }
    Case 'GIT-ID-002 authenticated identity is isolated to worktree' {
        $null = Set-GitWorktreeIdentity -RepositoryRoot $worktree -Login 'synthetic-owner' -UserId '123456'
        if ((Invoke-GitFixture -Directory $worktree -Arguments @('config','--local','--get','user.name')) -cne 'Scope Fixture') { throw 'COMMON_NAME_CHANGED' }
        if ((Invoke-GitFixture -Directory $worktree -Arguments @('config','--local','--get','user.email')) -cne 'scope@example.invalid') { throw 'COMMON_EMAIL_CHANGED' }
        if ((Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--get','user.name')) -cne 'synthetic-owner') { throw 'WORKTREE_NAME_MISSING' }
        if ((Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--get','user.email')) -cne '123456+synthetic-owner@users.noreply.github.com') { throw 'WORKTREE_EMAIL_MISSING' }
    }
    Case 'GIT-ID-003 account mismatch cannot auto-correct' {
        ExpectFailure { Set-GitWorktreeIdentity -RepositoryRoot $worktree -Login 'other-owner' -UserId '999999' } 'GIT_IDENTITY_AUTHENTICATED_ACCOUNT_MISMATCH'
    }
    Case 'GIT-ID-004 correct isolated identity passes' {
        $null = Assert-GitWorktreeIdentity -RepositoryRoot $worktree
    }
    Case 'GIT-ID-027 interrupted partial worktree identity converges on rerun' {
        Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','user.email','partial@example.invalid') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--unset-all','etalon.identity.userId') | Out-Null
        ExpectFailure { Assert-GitWorktreeIdentity -RepositoryRoot $worktree } 'GIT_IDENTITY_WORKTREE_EMAIL_MISMATCH'
        $null = Set-GitWorktreeIdentity -RepositoryRoot $worktree -Login 'synthetic-owner' -UserId '123456'
        $null = Assert-GitWorktreeIdentity -RepositoryRoot $worktree
        if ((Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--get','etalon.identity.userId')) -cne '123456') { throw 'PARTIAL_IDENTITY_RERUN_DID_NOT_CONVERGE' }
    }
    Case 'GIT-ID-025 valid subdirectory hook prefix stays bound to this worktree' {
        $gitDir = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','--absolute-git-dir')
        $indexFile = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','--git-path','index')
        $names = @('GIT_DIR','GIT_INDEX_FILE','GIT_PREFIX')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        $pushed = $false
        try {
            [Environment]::SetEnvironmentVariable('GIT_DIR',$gitDir,'Process')
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',$indexFile,'Process')
            [Environment]::SetEnvironmentVariable('GIT_PREFIX','config/','Process')
            Push-Location -LiteralPath $worktree
            $pushed = $true
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
            [Environment]::SetEnvironmentVariable('GIT_PREFIX','../outside/','Process')
            ExpectFailure { Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_HOOK_PREFIX_INVALID'
        }
        finally {
            if ($pushed) { Pop-Location }
            foreach ($name in $names) {
                if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($name,[string]$saved[$name],'Process') }
            }
        }
    }
    Case 'GIT-ID-026 editor and pager environment do not break noninteractive checks' {
        $names = @('GIT_PAGER','GIT_EDITOR','GIT_EXEC_PATH')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        $pushed = $false
        try {
            Push-Location -LiteralPath $worktree
            $pushed = $true
            [Environment]::SetEnvironmentVariable('GIT_EDITOR','false','Process')
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
            [Environment]::SetEnvironmentVariable('GIT_EDITOR','pwsh -NoProfile -Command exit 0','Process')
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
            [Environment]::SetEnvironmentVariable('GIT_EDITOR',$null,'Process')

            [Environment]::SetEnvironmentVariable('GIT_EXEC_PATH',(Join-Path $root 'untrusted-git-exec'),'Process')
            ExpectFailure { Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_HOOK_EXEC_PATH_MISMATCH'
            [Environment]::SetEnvironmentVariable('GIT_EXEC_PATH',(Invoke-GitFixture -Directory $worktree -Arguments @('--exec-path')),'Process')
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
            [Environment]::SetEnvironmentVariable('GIT_EXEC_PATH',$null,'Process')

            [Environment]::SetEnvironmentVariable('GIT_PAGER','pwsh -NoProfile -Command exit 0','Process')
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
        }
        finally {
            if ($pushed) { Pop-Location }
            foreach ($name in $names) {
                if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($name,[string]$saved[$name],'Process') }
            }
        }
    }
    Case 'quality gate validates its Git worktree context before checks' {
        $gateSource = [IO.File]::ReadAllText((Join-Path $repoRoot 'scripts/quality-gate.ps1'))
        if (-not $gateSource.Contains('Import-Module (Join-Path $PSScriptRoot ''lib/GitIdentity.psm1'') -Force')) { throw 'QUALITY_GATE_IDENTITY_MODULE_IMPORT_MISSING' }
        if ($gateSource -notmatch 'Assert-GitWorktreeEnvironment -RepositoryRoot \$repoRoot -HookContext') { throw 'QUALITY_GATE_GIT_CONTEXT_CHECK_MISSING' }
        if ([regex]::IsMatch($gateSource,'(?m)^\s*&\s*git\s+(?!--no-pager\b)[^\r\n]+')) { throw 'QUALITY_GATE_DIRECT_GIT_PAGER_NOT_DISABLED' }
        if ([regex]::IsMatch($gateSource,'(?m)^\s*Invoke-NativeChecked -Executable \(Get-Command git\)\.Source -Arguments @\((?!''--no-pager'')')) { throw 'QUALITY_GATE_DIFF_PAGER_NOT_DISABLED' }
    }
    Case 'GIT-ID-005 author environment override is refused' {
        $env:GIT_AUTHOR_NAME = 'Injected Author'
        try {
            ExpectFailure { Assert-GitWorktreeIdentity -RepositoryRoot $worktree } 'GIT_IDENTITY_ENVIRONMENT_OVERRIDE'
            try { Assert-GitWorktreeIdentity -RepositoryRoot $worktree; throw 'EXPECTED_ENV_OVERRIDE_FAILURE' }
            catch {
                if ($_.Exception.Message -notlike '*GIT_IDENTITY_ENVIRONMENT_OVERRIDE:GIT_AUTHOR_NAME*' -or $_.Exception.Message.Contains('Injected Author')) {
                    throw 'GIT_IDENTITY_OVERRIDE_DIAGNOSTIC_INVALID'
                }
            }
        }
        finally { $env:GIT_AUTHOR_NAME = $null }
    }
    Case 'GIT-ID-006 Git config environment injection is refused' {
        $env:GIT_CONFIG_COUNT = '1'
        $env:GIT_CONFIG_KEY_0 = 'user.name'
        $env:GIT_CONFIG_VALUE_0 = 'Injected Author'
        try { ExpectFailure { Assert-GitWorktreeIdentity -RepositoryRoot $worktree } 'GIT_IDENTITY_CONFIG_ENVIRONMENT_OVERRIDE' }
        finally {
            $env:GIT_CONFIG_COUNT = $null
            $env:GIT_CONFIG_KEY_0 = $null
            $env:GIT_CONFIG_VALUE_0 = $null
        }
    }
    Case 'GIT-ID-024 indexed config override in a later slot is refused' {
        $env:GIT_CONFIG_COUNT = '2'
        $env:GIT_CONFIG_KEY_0 = 'core.quotepath'
        $env:GIT_CONFIG_VALUE_0 = 'false'
        $env:GIT_CONFIG_KEY_1 = 'user.name'
        $env:GIT_CONFIG_VALUE_1 = 'Injected Author'
        try {
            try { Assert-GitWorktreeIdentity -RepositoryRoot $worktree; throw 'LATER_CONFIG_SLOT_NOT_REJECTED' }
            catch {
                $message = $_.Exception.Message
                if (-not $message.Contains('GIT_IDENTITY_CONFIG_ENVIRONMENT_OVERRIDE') -or
                    -not $message.Contains('GIT_CONFIG_KEY_1') -or
                    $message.Contains('Injected Author')) { throw 'LATER_CONFIG_SLOT_DIAGNOSTIC_INVALID' }
            }
        }
        finally {
            foreach ($name in @('GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_CONFIG_KEY_1','GIT_CONFIG_VALUE_1')) {
                Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
            }
        }
    }
    Case 'GIT-ID-007 correct outgoing commit and single-SHA push range pass' {
        WriteText (Join-Path $worktree 'good.txt') 'Good synthetic commit.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','good.txt') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: valid identity') | Out-Null
        $script:good = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        $range = $base + '..' + $script:good
        $rangePath = Join-Path $worktree $range
        WriteText $rangePath 'Synthetic file named like a revision range.'
        $commitPath = Join-Path $worktree $script:good
        WriteText $commitPath 'Synthetic file named like a commit SHA.'
        try {
            $null = Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($range)
        } finally {
            Remove-Item -LiteralPath $rangePath,$commitPath -ErrorAction Stop
        }
        $null = Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good) -RemoteName 'origin' -PublishedMainSha $base
        $null = Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @(($base+'..'+$script:good)+[Environment]::NewLine+($base+'..'+$script:good))
    }
    Case 'GIT-ID-008 explicit bad author name is rejected without leaking email' {
        Invoke-GitFixture -Directory $worktree -Arguments @('switch','--quiet','-c','task/bad-name',$script:good) | Out-Null
        WriteText (Join-Path $worktree 'bad-name.txt') 'Synthetic bad author name.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','bad-name.txt') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: invalid name','--author=Scope Fixture <fixture@example.invalid>') | Out-Null
        $bad = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        ExpectFailure { Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good+'..'+$bad) } 'GIT_IDENTITY_COMMIT_AUTHOR_NAME_MISMATCH'
    }
    Case 'GIT-ID-009 explicit bad author email is rejected' {
        Invoke-GitFixture -Directory $worktree -Arguments @('switch','--quiet','-c','task/bad-email',$script:good) | Out-Null
        WriteText (Join-Path $worktree 'bad-email.txt') 'Synthetic bad author email.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','bad-email.txt') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: invalid email','--author=synthetic-owner <fixture@example.invalid>') | Out-Null
        $bad = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        ExpectFailure { Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good+'..'+$bad) } 'GIT_IDENTITY_COMMIT_AUTHOR_EMAIL_MISMATCH'
        $null = Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good+'..'+$bad) -PublishedMainSha $bad
        Invoke-GitFixture -Directory $worktree -Arguments @('update-ref','refs/remotes/origin/untrusted',$bad) | Out-Null
        ExpectFailure { Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($bad) -RemoteName 'origin' -PublishedMainSha $base } 'GIT_IDENTITY_COMMIT_AUTHOR_EMAIL_MISMATCH'
    }
    Case 'GIT-ID-010 explicit bad committer name is rejected' {
        Invoke-GitFixture -Directory $worktree -Arguments @('switch','--quiet','-c','task/bad-committer-name',$script:good) | Out-Null
        WriteText (Join-Path $worktree 'bad-committer-name.txt') 'Synthetic bad committer name.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','bad-committer-name.txt') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: invalid committer name') -GitEnvironment @{
            GIT_COMMITTER_NAME='Scope Fixture'
            GIT_COMMITTER_EMAIL='123456+synthetic-owner@users.noreply.github.com'
        } | Out-Null
        $bad = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        ExpectFailure { Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good+'..'+$bad) } 'GIT_IDENTITY_COMMITTER_NAME_MISMATCH'
    }
    Case 'GIT-ID-011 explicit bad committer email is rejected' {
        Invoke-GitFixture -Directory $worktree -Arguments @('switch','--quiet','-c','task/bad-committer-email',$script:good) | Out-Null
        WriteText (Join-Path $worktree 'bad-committer-email.txt') 'Synthetic bad committer email.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','bad-committer-email.txt') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: invalid committer email') -GitEnvironment @{
            GIT_COMMITTER_NAME='synthetic-owner'
            GIT_COMMITTER_EMAIL='fixture@example.invalid'
        } | Out-Null
        $bad = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        ExpectFailure { Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good+'..'+$bad) } 'GIT_IDENTITY_COMMITTER_EMAIL_MISMATCH'
    }
    Case 'GIT-ID-012 pre-commit attempts account-verified repair before allowing commit' {
        $hook = [IO.File]::ReadAllText((Join-Path $repoRoot '.githooks/pre-commit'))
        $verifyAt = $hook.IndexOf('verify-git-identity.ps1',[StringComparison]::Ordinal)
        $overrideAt = $hook.IndexOf('verify_status" -eq 23',[StringComparison]::Ordinal)
        $repairAt = $hook.IndexOf('configure-local.ps1',[StringComparison]::Ordinal)
        if ($verifyAt -lt 0 -or $overrideAt -le $verifyAt -or $repairAt -le $overrideAt) { throw 'PRE_COMMIT_REPAIR_ORDER_INVALID' }
    }
    Case 'GIT-ID-013 pre-push verifies current identity and outgoing history before quality gate' {
        $hook = [IO.File]::ReadAllText((Join-Path $repoRoot '.githooks/pre-push'))
        $verifyAt = $hook.IndexOf('verify-git-identity.ps1',[StringComparison]::Ordinal)
        $gateAt = $hook.IndexOf('quality-gate.ps1',[StringComparison]::Ordinal)
        if ($verifyAt -lt 0 -or $gateAt -le $verifyAt -or $hook -notmatch '-CommitRange') { throw 'PRE_PUSH_IDENTITY_GATE_INVALID' }
    }
    Case 'GIT-ID-014 exact policy author and committer environment values pass' {
        $env:GIT_AUTHOR_NAME = 'synthetic-owner'
        $env:GIT_AUTHOR_EMAIL = '123456+synthetic-owner@users.noreply.github.com'
        $env:GIT_COMMITTER_NAME = 'synthetic-owner'
        $env:GIT_COMMITTER_EMAIL = '123456+synthetic-owner@users.noreply.github.com'
        try { $null = Assert-GitWorktreeIdentity -RepositoryRoot $worktree }
        finally {
            foreach ($name in @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        }
    }
    Case 'GIT-ID-015 pre-push rejects multiple refs and passes the single task range' {
        $script:hookRemote = Join-Path $scratch 'hook-remote.git'
        $script:hookRepo = Join-Path $scratch 'hook-repo'
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--bare','--quiet',$hookRemote) | Out-Null
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$hookRepo) | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','user.name','Hook Fixture') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','user.email','hook@example.invalid') | Out-Null
        WriteText (Join-Path $hookRepo 'config/github/repository.json') (@{commitIdentity=@{login='synthetic-owner';userId='123456'}} | ConvertTo-Json -Depth 4)
        WriteText (Join-Path $hookRepo 'README.md') 'Synthetic hook fixture.'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','.') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('commit','--quiet','-m','test: hook fixture') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('branch','-M','main') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('remote','add','origin',$hookRemote) | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('push','--quiet','origin','main') | Out-Null
        $publishedMain = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','main')
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','-c','task/T-901-hook-a','main') | Out-Null
        WriteText (Join-Path $hookRepo 'hook-a.txt') 'first ref'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','hook-a.txt') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('commit','--quiet','-m','test: first hook ref') | Out-Null
        $script:hookShaA = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','main') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','-c','task/T-902-hook-b','main') | Out-Null
        WriteText (Join-Path $hookRepo 'hook-b.txt') 'second ref'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','hook-b.txt') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('commit','--quiet','-m','test: second hook ref') | Out-Null
        $script:hookShaB = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')
        $script:hookShim = New-PwshShim -Directory (Join-Path $scratch 'pwsh-shim') -LogPath (Join-Path $scratch 'pwsh-calls.bin')
        $script:hookProxy = New-HookProxy -Directory (Join-Path $scratch 'hook-proxy')
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','core.hooksPath',$hookProxy.Directory) | Out-Null
        $script:hookTestEnvironment = @{
            PATH=($hookShim.Directory + [IO.Path]::PathSeparator + $env:PATH)
            PWSSHIM_LOG=$hookShim.LogPath
            PWSSHIM_STATE=$hookShim.StatePath
            PWSSHIM_MODE='pass'
            PWSSHIM_PUBLISHED_MAIN=$publishedMain
            PWSSHIM_DIR=$hookShim.DirectoryPosix
            REAL_PRE_PUSH_HOOK=$hookShim.PrePushHookPosix
            REAL_PRE_COMMIT_HOOK=$hookShim.PreCommitHookPosix
        }
        $result = Invoke-GitProcess -Arguments @('-C',$hookRepo,'push','origin','task/T-901-hook-a','task/T-902-hook-b') -Environment $script:hookTestEnvironment
        if ($result.ExitCode -eq 0 -or $result.StdErr -notmatch 'only the current same-named task branch') {
            throw 'MULTI_REF_PUSH_WAS_NOT_REJECTED_BY_TASK_BRANCH_GUARD'
        }
        $remoteRefs = Invoke-GitFixture -Directory $hookRemote -Arguments @('for-each-ref','refs/heads/task/')
        if ($remoteRefs) { throw 'REJECTED_PUSH_CHANGED_FIXTURE_REMOTE' }
        Remove-Item -LiteralPath (Join-Path $scratch 'pwsh-calls.bin')
        $result = Invoke-GitProcess -Arguments @('-C',$hookRepo,'push','origin','task/T-902-hook-b') -Environment $script:hookTestEnvironment
        if ($result.ExitCode -ne 0) { throw ('SINGLE_TASK_PUSH_FAILED:' + $result.StdErr) }
        $calls = @((Read-PwshShimCalls -LogPath (Join-Path $scratch 'pwsh-calls.bin')).Calls)
        if ($calls.Count -ne 5 -or
            [string]::Join(' ',$calls[0]) -notlike '*verify-git-hook-context.ps1*' -or
            [string]::Join(' ',$calls[1]) -notlike '*task-worktree-audit.ps1*-Mode Publish*' -or
            [string]::Join(' ',$calls[2]) -notlike '*verify-git-identity.ps1*-PassThruPublishedMainSha*' -or
            [string]::Join(' ',$calls[3]) -notlike '*verify-task-scope.ps1*-TaskId T-902*') {
            throw 'PRE_PUSH_TASK_CHECK_SEQUENCE_INVALID'
        }
        $verifyRange = Get-PwshParameterValue -Arguments $calls[2] -Name '-CommitRange'
        $scopeBase = Get-PwshParameterValue -Arguments $calls[3] -Name '-BaseRef'
        $scopeHead = Get-PwshParameterValue -Arguments $calls[3] -Name '-ExpectedHeadSha'
        $gateBase = Get-PwshParameterValue -Arguments $calls[4] -Name '-BaseRef'
        $gateRange = Get-PwshParameterValue -Arguments $calls[4] -Name '-PushRange'
        if ($verifyRange -cne $hookShaB -or $scopeHead -cne $hookShaB -or $gateRange -cne $verifyRange -or
            $scopeBase -cne $publishedMain -or $gateBase -cne $publishedMain) {
            throw 'TASK_PUSH_REVISIONS_MISMATCH'
        }
    }
    Case 'GIT-ID-032 pre-push rejects detached HEAD, invalid slug, deletion and non-fast-forward' {
        $ref = 'refs/heads/task/T-902-hook-b'
        $badRef = 'refs/heads/task/T-903-Bad'
        $zero = '0' * $hookShaB.Length
        $before = Invoke-GitFixture -Directory $hookRemote -Arguments @('show-ref')
        $cases = @(
            @{ checkout=@('--detach',$hookShaB); input="HEAD $hookShaB $ref $hookShaB"; error='detached HEAD is not allowed' }
            @{ checkout=@('-c','task/T-903-Bad',$hookShaB); input="$badRef $hookShaB $badRef $zero"; error='task branch slug must' }
            @{ checkout=@('task/T-902-hook-b'); input="(delete) $zero $ref $hookShaB"; error='only the current same-named task branch' }
            @{ checkout=@('task/T-902-hook-b'); input="$ref $hookShaB $ref $hookShaA"; error='non-fast-forward update' }
        )
        try {
            foreach ($case in $cases) {
                Invoke-GitFixture -Directory $hookRepo -Arguments (@('switch','--quiet') + $case.checkout) | Out-Null
                $result = Invoke-GitProcess -Executable $hookShim.ShellPath -WorkingDirectory $hookRepo -Arguments @($hookShim.PrePushHookPosix,'origin',$hookRemote) -Environment $script:hookTestEnvironment -InputLine $case.input
                if ($result.ExitCode -ne 1 -or $result.StdErr -notlike ('*' + $case.error + '*')) {
                    throw ('PRE_PUSH_EXPECTED_REJECTION:' + $case.error + ':' + $result.StdErr)
                }
            }
            $after = Invoke-GitFixture -Directory $hookRemote -Arguments @('show-ref')
            if ($before -cne $after) { throw 'REJECTED_PUSH_CHANGED_FIXTURE_REMOTE' }
        } finally {
            Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','task/T-902-hook-b') | Out-Null
        }
    }
    Case 'GIT-ID-028 pre-push blocks protected T-013 local and remote refs from another worktree' {
        $protectedRef = 'refs/heads/task/T-013-agent-orchestration-research'
        $otherRemoteRef = 'refs/heads/task/recovery-copy'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('update-ref',$protectedRef,$script:hookShaA) | Out-Null
        Remove-Item -LiteralPath (Join-Path $scratch 'pwsh-calls.bin') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $scratch 'pwsh-shim/state.txt') -Force -ErrorAction SilentlyContinue
        $hookEnvs = @{
            PATH=($script:hookShim.Directory + [IO.Path]::PathSeparator + $env:PATH)
            PWSSHIM_LOG=$script:hookShim.LogPath
            PWSSHIM_STATE=$script:hookShim.StatePath
            PWSSHIM_MODE='pass'
            PWSSHIM_DIR=$script:hookShim.DirectoryPosix
            REAL_PRE_PUSH_HOOK=$script:hookShim.PrePushHookPosix
            REAL_PRE_COMMIT_HOOK=$script:hookShim.PreCommitHookPosix
        }
        $localSourceResult = Invoke-GitProcess -Arguments @('-C',$hookRepo,'push','origin',($protectedRef + ':' + $otherRemoteRef)) -Environment $hookEnvs
        $localSourceOutput = [string]::Join([Environment]::NewLine,@($localSourceResult.StdOut,$localSourceResult.StdErr))
        if ($localSourceResult.ExitCode -eq 0 -or $localSourceOutput -notmatch 'T-013 is a read-only recovery source and cannot be published') {
            throw ('T013_LOCAL_REF_NOT_BLOCKED:' + $localSourceOutput)
        }
        $localDestination = Invoke-GitProcess -Arguments @('--git-dir',$hookRemote,'show-ref','--verify','--quiet',$otherRemoteRef)
        if ($localDestination.ExitCode -eq 0) { throw 'T013_LOCAL_REF_REACHED_SYNTHETIC_REMOTE' }
        if ($localDestination.ExitCode -ne 1) { throw ('T013_LOCAL_REMOTE_STATE_UNVERIFIABLE:' + $localDestination.StdErr) }

        $remoteTargetResult = Invoke-GitProcess -Arguments @('-C',$hookRepo,'push','origin',('refs/heads/task/T-901-hook-a:' + $protectedRef)) -Environment $hookEnvs
        $remoteTargetOutput = [string]::Join([Environment]::NewLine,@($remoteTargetResult.StdOut,$remoteTargetResult.StdErr))
        if ($remoteTargetResult.ExitCode -eq 0 -or $remoteTargetOutput -notmatch 'T-013 is a read-only recovery source and cannot be published') {
            throw ('T013_REMOTE_REF_NOT_BLOCKED:' + $remoteTargetOutput)
        }
        $remoteDestination = Invoke-GitProcess -Arguments @('--git-dir',$hookRemote,'show-ref','--verify','--quiet',$protectedRef)
        if ($remoteDestination.ExitCode -eq 0) { throw 'T013_REMOTE_REF_REACHED_SYNTHETIC_REMOTE' }
        if ($remoteDestination.ExitCode -ne 1) { throw ('T013_REMOTE_STATE_UNVERIFIABLE:' + $remoteDestination.StdErr) }
    }
    Case 'GIT-ID-029 hook treats only config-matching identity values as repairable drift' {
        $names = @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        $originalName = Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--get','user.name')
        $originalEmail = Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--get','user.email')
        $pushed = $false
        try {
            Push-Location -LiteralPath $worktree
            $pushed = $true
            Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','user.name','Drifted Fixture') | Out-Null
            Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','user.email','drifted@example.invalid') | Out-Null
            [Environment]::SetEnvironmentVariable('GIT_AUTHOR_NAME','Drifted Fixture','Process')
            [Environment]::SetEnvironmentVariable('GIT_AUTHOR_EMAIL','drifted@example.invalid','Process')
            [Environment]::SetEnvironmentVariable('GIT_COMMITTER_NAME','Drifted Fixture','Process')
            [Environment]::SetEnvironmentVariable('GIT_COMMITTER_EMAIL','drifted@example.invalid','Process')
            $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
            ExpectFailure { Assert-GitWorktreeIdentity -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_WORKTREE_NAME_MISMATCH'
            [Environment]::SetEnvironmentVariable('GIT_AUTHOR_NAME','Injected Identity','Process')
            ExpectFailure { Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_ENVIRONMENT_OVERRIDE:GIT_AUTHOR_NAME'
        }
        finally {
            if ($pushed) { Pop-Location }
            Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','user.name',$originalName) | Out-Null
            Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','user.email',$originalEmail) | Out-Null
            foreach ($name in $names) {
                if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($name,[string]$saved[$name],'Process') }
            }
        }
    }
    Case 'GIT-ID-030 hook accepts exact Git commit temporary indexes and rejects arbitrary indexes' {
        $savedIndex = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process')
        $pushed = $false
        try {
            Push-Location -LiteralPath $worktree
            $pushed = $true
            $gitDir = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','--absolute-git-dir')
            foreach ($name in @('index.lock','next-index-64424.lock')) {
                [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',(Join-Path $gitDir $name),'Process')
                $null = Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext
            }
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',(Join-Path $gitDir 'next-index-64424Xlock'),'Process')
            ExpectFailure { Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_HOOK_GIT_INDEX_FILE_MISMATCH'
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',(Join-Path $gitDir 'untrusted.lock'),'Process')
            ExpectFailure { Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_HOOK_GIT_INDEX_FILE_MISMATCH'
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',(Join-Path $root 'outside-index.lock'),'Process')
            ExpectFailure { Assert-GitWorktreeEnvironment -RepositoryRoot $worktree -HookContext } 'GIT_IDENTITY_HOOK_GIT_INDEX_FILE_MISMATCH'
        }
        finally {
            if ($pushed) { Pop-Location }
            if ($null -eq $savedIndex) { Remove-Item -LiteralPath Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',[string]$savedIndex,'Process') }
        }
    }
    Case 'GIT-ID-016 pre-commit dynamically blocks identity override before creating commit' {
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','-c','task/T-902-hook-block','main') | Out-Null
        WriteText (Join-Path $hookRepo 'blocked.txt') 'blocked commit'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','blocked.txt') | Out-Null
        $before = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')
        $logPath = Join-Path $scratch 'pwsh-calls.bin'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $scratch 'pwsh-shim/state.txt') -Force -ErrorAction SilentlyContinue
        $envs = @{
            PATH=($hookShim.Directory + [IO.Path]::PathSeparator + $env:PATH)
            PWSSHIM_LOG=$hookShim.LogPath
            PWSSHIM_STATE=$hookShim.StatePath
            PWSSHIM_MODE='precommit-block'
            PWSSHIM_DIR=$hookShim.DirectoryPosix
            REAL_PRE_PUSH_HOOK=$hookShim.PrePushHookPosix
            REAL_PRE_COMMIT_HOOK=$hookShim.PreCommitHookPosix
        }
        $result = Invoke-GitProcess -Arguments @('-C',$hookRepo,'commit','-m','test: blocked hook commit') -Environment $envs
        if ($result.ExitCode -eq 0) { throw 'PRE_COMMIT_OVERRIDE_WAS_NOT_BLOCKED' }
        if ((Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')) -cne $before) { throw 'PRE_COMMIT_BLOCK_CREATED_COMMIT' }
        $calls = @((Read-PwshShimCalls -LogPath $logPath).Calls)
        if ($calls.Count -ne 3 -or
            [string]::Join(' ',$calls[0]) -notlike '*verify-git-hook-context.ps1*' -or
            [string]::Join(' ',$calls[1]) -notlike '*task-worktree-audit.ps1*-Mode Commit*' -or
            [string]::Join(' ',$calls[2]) -notlike '*verify-git-identity.ps1*') { throw 'PRE_COMMIT_OVERRIDE_HOOK_SEQUENCE_INVALID' }
    }
    Case 'GIT-ID-017 pre-commit repairs drift but aborts the commit captured with stale identity' {
        WriteText (Join-Path $hookRepo 'repaired.txt') 'repaired commit'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','repaired.txt') | Out-Null
        $before = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')
        $logPath = Join-Path $scratch 'pwsh-calls.bin'
        Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $scratch 'pwsh-shim/state.txt') -Force -ErrorAction SilentlyContinue
        $envs = @{
            PATH=($hookShim.Directory + [IO.Path]::PathSeparator + $env:PATH)
            PWSSHIM_LOG=$hookShim.LogPath
            PWSSHIM_STATE=$hookShim.StatePath
            PWSSHIM_MODE='precommit-repair'
            PWSSHIM_DIR=$hookShim.DirectoryPosix
            REAL_PRE_PUSH_HOOK=$hookShim.PrePushHookPosix
            REAL_PRE_COMMIT_HOOK=$hookShim.PreCommitHookPosix
        }
        $result = Invoke-GitProcess -Arguments @('-C',$hookRepo,'commit','-m','test: repaired hook commit') -Environment $envs
        if ($result.ExitCode -eq 0 -or $result.StdErr -notmatch 'rerun git commit') {
            throw ('PRE_COMMIT_REPAIR_DID_NOT_REQUIRE_SAFE_RETRY:' + $result.StdErr)
        }
        $calls = @((Read-PwshShimCalls -LogPath $logPath).Calls)
        if ($calls.Count -ne 5) { throw ('PRE_COMMIT_REPAIR_CALL_COUNT_INVALID:' + $calls.Count) }
        $sequence = @($calls | ForEach-Object { [string]::Join(' ',$_) })
        if ($sequence[0] -notlike '*verify-git-hook-context.ps1*' -or
            $sequence[1] -notlike '*task-worktree-audit.ps1*-Mode Commit*' -or
            $sequence[2] -notlike '*verify-git-identity.ps1*' -or
            $sequence[3] -notlike '*configure-local.ps1*' -or
            $sequence[4] -notlike '*verify-git-identity.ps1*') {
            throw 'PRE_COMMIT_REPAIR_HOOK_SEQUENCE_INVALID'
        }
        if ((Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')) -cne $before) { throw 'STALE_IDENTITY_COMMIT_WAS_CREATED' }
        Invoke-GitFixture -Directory $hookRepo -Arguments @('reset','--quiet','HEAD','--','repaired.txt') | Out-Null
        Remove-Item -LiteralPath (Join-Path $hookRepo 'repaired.txt') -Force
    }
    Case 'GIT-ID-018 bare-admin core.bare migration enables future linked worktrees' {
        $bareAdmin = Join-Path $scratch 'bare-admin.git'
        $bareSeed = Join-Path $scratch 'bare-seed'
        $bareWorktree = Join-Path $scratch 'bare-worktree'
        $newWorktree = Join-Path $scratch 'bare-worktree-next'
        $preconfiguredWorktree = Join-Path $scratch 'bare-worktree-preconfigured'
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--bare','--quiet',$bareAdmin) | Out-Null
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$bareSeed) | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('config','user.name','Bare Fixture') | Out-Null
        WriteText (Join-Path $bareSeed 'config/github/repository.json') (@{commitIdentity=@{login='bare-owner';userId='654321'}} | ConvertTo-Json -Depth 4)
        Invoke-GitFixture -Directory $bareSeed -Arguments @('config','user.email','bare@example.invalid') | Out-Null
        WriteText (Join-Path $bareSeed 'README.md') 'Bare admin migration fixture.'
        Invoke-GitFixture -Directory $bareSeed -Arguments @('add','README.md') | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('add','config/github/repository.json') | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('commit','--quiet','-m','test: bare seed') | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('branch','-M','main') | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('remote','add','origin',$bareAdmin) | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('push','--quiet','origin','main') | Out-Null
        Invoke-GitFixture -Directory $bareAdmin -Arguments @('symbolic-ref','HEAD','refs/heads/main') | Out-Null
        Invoke-GitFixture -Directory $bareAdmin -Arguments @('config','extensions.worktreeConfig','true') | Out-Null
        Invoke-GitFixture -Directory $bareAdmin -Arguments @('worktree','add','--quiet','-b','task/bare-one',$bareWorktree,'main') | Out-Null
        $before = @(& git -C $bareWorktree status --short --branch 2>&1)
        if ($LASTEXITCODE -eq 0) { throw 'BARE_FIXTURE_DID_NOT_REPRODUCE_SHARED_CORE_BARE' }
        $assertFailed = $false
        try { Assert-GitIdentityWorktree -RepositoryRoot $bareWorktree }
        catch { $assertFailed = $true }
        if (-not $assertFailed) { throw 'BROKEN_BARE_WORKTREE_ASSERTION_UNEXPECTEDLY_PASSED' }
        if ((Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--local','--get','core.bare')) -cne 'true') {
            throw 'READ_ONLY_WORKTREE_ASSERTION_MUTATED_COMMON_CORE_BARE'
        }
        $sharedConfig = Join-Path $bareAdmin 'config'
        $sharedConfigBefore = (Get-FileHash -LiteralPath $sharedConfig).Hash
        $sharedLock = "$sharedConfig.lock"
        [IO.File]::Open($sharedLock, [IO.FileMode]::CreateNew).Dispose()
        try {
            ExpectFailure { Initialize-GitWorktreeConfig -RepositoryRoot $bareWorktree } 'GIT_IDENTITY_CORE_BARE_MIGRATION_FAILED'
            $adminBareAfterFailure = @(& git -C $bareWorktree config --file (Join-Path $bareAdmin 'config.worktree') --get-all core.bare)
            if ($LASTEXITCODE -ne 1 -or $adminBareAfterFailure.Count -ne 0) { throw 'CORE_BARE_ROLLBACK_LEFT_ADMIN_OVERRIDE' }
            if ((Get-FileHash -LiteralPath $sharedConfig).Hash -cne $sharedConfigBefore) { throw 'CORE_BARE_ROLLBACK_CHANGED_LOCKED_CONFIG' }
        } finally {
            [IO.File]::Delete($sharedLock)
        }
        $identityModule = (Get-Command Initialize-GitWorktreeConfig).Module
        $adminLock = Join-Path $bareAdmin 'config.worktree.lock'
        # Lock the admin file only after the real Git write has succeeded, so rollback hits a real lock.
        & $identityModule {
            param($LockPath)
            $script:fixtureAdminLock = $LockPath
            $script:fixtureAdminCommand = (Get-Item Function:Invoke-GitIdentityAdminCommand).ScriptBlock
            function script:Invoke-GitIdentityAdminCommand {
                param([string]$GitDirectory,[string[]]$Arguments)
                $result = & $script:fixtureAdminCommand -GitDirectory $GitDirectory -Arguments $Arguments
                if ($Arguments.Count -eq 5 -and $Arguments[1] -ceq '--file' -and
                    $Arguments[3] -ceq 'core.bare' -and $Arguments[4] -ceq 'true') {
                    [IO.File]::Open($script:fixtureAdminLock, [IO.FileMode]::CreateNew).Dispose()
                }
                return $result
            }
        } $adminLock
        try {
            [IO.File]::Open($sharedLock, [IO.FileMode]::CreateNew).Dispose()
            try {
                ExpectFailure { Initialize-GitWorktreeConfig -RepositoryRoot $bareWorktree } 'GIT_IDENTITY_CORE_BARE_ROLLBACK_FAILED'
                if (-not (Test-Path -LiteralPath $adminLock -PathType Leaf)) { throw 'CORE_BARE_ROLLBACK_LOCK_NOT_CREATED' }
                if ((Get-FileHash -LiteralPath $sharedConfig).Hash -cne $sharedConfigBefore) { throw 'CORE_BARE_ROLLBACK_CHANGED_LOCKED_CONFIG' }
                $retained = Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--file',(Join-Path $bareAdmin 'config.worktree'),'--get','core.bare')
                if ($retained -cne 'true') { throw 'CORE_BARE_ROLLBACK_OVERRIDE_NOT_RETAINED' }
            } finally {
                [IO.File]::Delete($sharedLock)
            }
        } finally {
            & $identityModule {
                Set-Item -LiteralPath Function:script:Invoke-GitIdentityAdminCommand -Value $script:fixtureAdminCommand
                Remove-Variable -Scope Script -Name fixtureAdminCommand,fixtureAdminLock
            }
            [IO.File]::Delete($adminLock)
        }
        $adminConfig = Join-Path $bareAdmin 'config.worktree'
        Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--file',$adminConfig,'--unset','core.bare') | Out-Null
        # Make a second Git process replace the temporary value before rollback reads it.
        & $identityModule {
            $script:fixtureAdminCommand = (Get-Item Function:Invoke-GitIdentityAdminCommand).ScriptBlock
            function script:Invoke-GitIdentityAdminCommand {
                param([string]$GitDirectory,[string[]]$Arguments)
                $result = & $script:fixtureAdminCommand -GitDirectory $GitDirectory -Arguments $Arguments
                if ($Arguments.Count -eq 5 -and $Arguments[1] -ceq '--file' -and
                    $Arguments[3] -ceq 'core.bare' -and $Arguments[4] -ceq 'true') {
                    $null = & $script:fixtureAdminCommand -GitDirectory $GitDirectory -Arguments @(
                        'config','--file',$Arguments[2],'--replace-all','core.bare','false')
                }
                return $result
            }
        }
        try {
            [IO.File]::Open($sharedLock, [IO.FileMode]::CreateNew).Dispose()
            try {
                ExpectFailure { Initialize-GitWorktreeConfig -RepositoryRoot $bareWorktree } 'GIT_IDENTITY_CORE_BARE_ROLLBACK_FAILED'
                $retained = Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--file',$adminConfig,'--get-all','core.bare')
                if ($retained -cne 'false') { throw 'CORE_BARE_CONCURRENT_VALUE_NOT_RETAINED' }
                if ((Get-FileHash -LiteralPath $sharedConfig).Hash -cne $sharedConfigBefore) { throw 'CORE_BARE_ROLLBACK_CHANGED_LOCKED_CONFIG' }
            } finally {
                [IO.File]::Delete($sharedLock)
            }
        } finally {
            & $identityModule {
                Set-Item -LiteralPath Function:script:Invoke-GitIdentityAdminCommand -Value $script:fixtureAdminCommand
                Remove-Variable -Scope Script -Name fixtureAdminCommand
            }
        }
        # Reset only this synthetic fixture before validating the normal retry.
        Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--file',$adminConfig,'--unset','core.bare') | Out-Null
        $null = Initialize-GitWorktreeConfig -RepositoryRoot $bareWorktree
        if ((Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--file',(Join-Path $bareAdmin 'config.worktree'),'--get','core.bare')) -cne 'true') { throw 'BARE_ADMIN_CONFIG_WORKTREE_NOT_PRESERVED' }
        if ((Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--worktree','--get','core.bare')) -cne 'false') { throw 'LINKED_WORKTREE_CORE_BARE_NOT_FALSE' }
        $sharedBare = @(& git -C $bareWorktree config --local --get-all core.bare 2>$null)
        if ($LASTEXITCODE -ne 1 -or $sharedBare.Count -ne 0) { throw 'SHARED_CORE_BARE_NOT_MIGRATED' }
        Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--local','core.bare','true') | Out-Null
        Invoke-GitFixture -Directory $bareAdmin -Arguments @('worktree','add','--quiet','-b','task/bare-preconfigured',$preconfiguredWorktree,'main') | Out-Null
        Invoke-GitFixture -Directory $preconfiguredWorktree -Arguments @('config','--worktree','core.bare','false') | Out-Null
        $null = Initialize-GitWorktreeConfig -RepositoryRoot $preconfiguredWorktree
        if ((Invoke-GitFixture -Directory $preconfiguredWorktree -Arguments @('config','--worktree','--get','core.bare')) -cne 'false') { throw 'PRECONFIGURED_LINKED_WORKTREE_CORE_BARE_NOT_FALSE' }
        $sharedBare = @(& git -C $preconfiguredWorktree config --local --get-all core.bare 2>$null)
        if ($LASTEXITCODE -ne 1 -or $sharedBare.Count -ne 0) { throw 'PRECONFIGURED_SHARED_CORE_BARE_NOT_MIGRATED' }
        Invoke-GitFixture -Directory $bareAdmin -Arguments @('worktree','add','--quiet','-b','task/bare-two',$newWorktree,'main') | Out-Null
        Invoke-GitFixture -Directory $newWorktree -Arguments @('status','--short','--branch') | Out-Null
        if ((Invoke-GitFixture -Directory $bareAdmin -Arguments @('rev-parse','--is-bare-repository')) -cne 'true') { throw 'BARE_ADMIN_ROOT_LOST_BARE_IDENTITY' }
    }
    Case 'GIT-ID-019 safe fresh checkout bootstrap enables worktree config' {
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','--local','extensions.worktreeConfig','false') | Out-Null
        $null = Initialize-GitWorktreeConfig -RepositoryRoot $hookRepo
        if ((Invoke-GitFixture -Directory $hookRepo -Arguments @('config','--local','--get','extensions.worktreeConfig')) -cne 'true') { throw 'SAFE_WORKTREE_CONFIG_BOOTSTRAP_FAILED' }
        Invoke-GitFixture -Directory $hookRepo -Arguments @('status','--short','--branch') | Out-Null
    }
    Case 'GIT-ID-020 ambiguous common core.worktree fails closed without enabling extension' {
        $unsafeRoot = Join-Path $scratch 'unsafe-core-worktree'
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$unsafeRoot) | Out-Null
        WriteText (Join-Path $unsafeRoot 'config/github/repository.json') (@{commitIdentity=@{login='unsafe-owner';userId='987654'}} | ConvertTo-Json -Depth 4)
        Invoke-GitFixture -Directory $unsafeRoot -Arguments @('config','user.name','Unsafe Fixture') | Out-Null
        Invoke-GitFixture -Directory $unsafeRoot -Arguments @('config','user.email','unsafe@example.invalid') | Out-Null
        WriteText (Join-Path $unsafeRoot 'README.md') 'Unsafe config fixture.'
        Invoke-GitFixture -Directory $unsafeRoot -Arguments @('add','README.md') | Out-Null
        Invoke-GitFixture -Directory $unsafeRoot -Arguments @('commit','--quiet','-m','test: unsafe config fixture') | Out-Null
        Invoke-GitFixture -Directory $unsafeRoot -Arguments @('config','--local','core.worktree',$unsafeRoot) | Out-Null
        ExpectFailure { Initialize-GitWorktreeConfig -RepositoryRoot $unsafeRoot } 'GIT_IDENTITY_SHARED_CORE_WORKTREE_UNSAFE'
        $extension = @(& git -C $unsafeRoot config --local --get extensions.worktreeConfig 2>$null)
        if ($LASTEXITCODE -ne 1 -or $extension.Count -ne 0) { throw 'UNSAFE_CORE_WORKTREE_MUTATED_EXTENSION' }
    }
    Case 'GIT-ID-021 GitHub login casing is normalized to canonical policy' {
        $null = Set-GitWorktreeIdentity -RepositoryRoot $worktree -Login 'SYNTHETIC-OWNER' -UserId '123456'
        if ((Invoke-GitFixture -Directory $worktree -Arguments @('config','--worktree','--get','user.name')) -cne 'synthetic-owner') {
            throw 'GIT_IDENTITY_LOGIN_CASE_NOT_CANONICALIZED'
        }
    }
    Case 'GIT-ID-022 nested Git executable resolves the installation shell root' {
        $syntheticGitRoot = Join-Path $scratch 'synthetic-git-install'
        $nestedGitExe = Join-Path $syntheticGitRoot 'mingw64/libexec/git-core/git.exe'
        $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($nestedGitExe))
        $null = [IO.Directory]::CreateDirectory((Join-Path $syntheticGitRoot 'bin'))
        $null = [IO.Directory]::CreateDirectory((Join-Path $syntheticGitRoot 'usr/bin'))
        WriteText (Join-Path $syntheticGitRoot 'bin/sh.exe') ''
        WriteText (Join-Path $syntheticGitRoot 'usr/bin/cygpath.exe') ''
        WriteText $nestedGitExe ''
        $resolvedRoot = Find-GitForWindowsShellRoot -StartPaths @($nestedGitExe)
        if (-not $resolvedRoot.Equals([IO.Path]::GetFullPath($syntheticGitRoot),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'GIT_IDENTITY_NESTED_EXECUTABLE_ROOT_NOT_FOUND'
        }
    }
    Case 'GIT-ID-023 primary config.worktree is not mistaken for bare-admin state' {
        foreach ($scenario in @('main-first','linked-first')) {
            $normalRoot = Join-Path $scratch ('normal-' + $scenario)
            $firstLinked = Join-Path $scratch ('normal-' + $scenario + '-linked-one')
            $secondLinked = Join-Path $scratch ('normal-' + $scenario + '-linked-two')
            Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$normalRoot) | Out-Null
            Invoke-GitFixture -Directory $normalRoot -Arguments @('config','user.name','Normal Fixture') | Out-Null
            Invoke-GitFixture -Directory $normalRoot -Arguments @('config','user.email','normal@example.invalid') | Out-Null
            WriteText (Join-Path $normalRoot 'config/github/repository.json') (@{commitIdentity=@{login='normal-owner';userId='123456'}} | ConvertTo-Json -Depth 4)
            WriteText (Join-Path $normalRoot 'README.md') 'Normal linked worktree fixture.'
            Invoke-GitFixture -Directory $normalRoot -Arguments @('add','.') | Out-Null
            Invoke-GitFixture -Directory $normalRoot -Arguments @('commit','--quiet','-m','test: normal worktree fixture') | Out-Null
            Invoke-GitFixture -Directory $normalRoot -Arguments @('branch','-M','main') | Out-Null
            if ($scenario -ceq 'linked-first') {
                Invoke-GitFixture -Directory $normalRoot -Arguments @('worktree','add','--quiet','-b','task/normal-one',$firstLinked,'main') | Out-Null
                $null = Initialize-GitWorktreeConfig -RepositoryRoot $firstLinked
            }
            $null = Initialize-GitWorktreeConfig -RepositoryRoot $normalRoot
            Invoke-GitFixture -Directory $normalRoot -Arguments @('worktree','add','--quiet','-b','task/normal-two',$secondLinked,'main') | Out-Null
            $null = Initialize-GitWorktreeConfig -RepositoryRoot $secondLinked
            if ((Invoke-GitFixture -Directory $normalRoot -Arguments @('config','--worktree','--get','core.bare')) -cne 'false') { throw ('PRIMARY_WORKTREE_CORE_BARE_INVALID:' + $scenario) }
            if ((Invoke-GitFixture -Directory $secondLinked -Arguments @('config','--worktree','--get','core.bare')) -cne 'false') { throw ('LINKED_WORKTREE_CORE_BARE_INVALID:' + $scenario) }
        }
    }
    if ($passed -ne 32) { throw ('GIT_IDENTITY_REGRESSION_COUNT_MISMATCH: expected 32, got ' + $passed) }
    Write-Output ('GIT-IDENTITY-REGRESSIONS: ' + $passed + ' passed, 0 failed')
}
finally {
    foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        if ([string]$entry.Key -like 'GIT_*') { Remove-Item -LiteralPath ('Env:' + [string]$entry.Key) -ErrorAction SilentlyContinue }
    }
    foreach ($name in $envNames) {
        if ($null -eq $savedEnv[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process') }
    }
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fullScratch = [IO.Path]::GetFullPath($scratch)
    if (-not $fullScratch.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_FIXTURE_CLEANUP_PATH_INVALID' }
    if (Test-Path -LiteralPath $fullScratch) { Remove-Item -LiteralPath $fullScratch -Recurse -Force }
}
