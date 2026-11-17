#Requires -Version 7.4
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = [IO.Path]::GetFullPath($TempRoot)
[IO.Directory]::CreateDirectory($root) | Out-Null
$scratch = Join-Path $root ('git-identity-regressions-' + [guid]::NewGuid().ToString('N'))
$seed = Join-Path $scratch 'seed'
$worktree = Join-Path $scratch 'worktree'
$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/GitIdentity.psm1'
$repoRoot = Split-Path $PSScriptRoot -Parent
$utf8 = [Text.UTF8Encoding]::new($false)
$passed = 0
$envNames = @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_PREFIX','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_CEILING_DIRECTORIES',
    'GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL',
    'GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_CONFIG_PARAMETERS','GIT_CONFIG_GLOBAL',
    'GIT_CONFIG_NOSYSTEM')
$savedEnv = @{}
foreach ($name in $envNames) { $savedEnv[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }

function Invoke-GitFixture([string]$Directory,[string[]]$Arguments) {
    $output = @(& git -C $Directory @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $detail = (($output | ForEach-Object { [string]$_ }) -join ' ') -replace '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+','<redacted>'
        throw ('GIT_FIXTURE_COMMAND_FAILED:' + $exitCode + ':' + ($Arguments -join ' ') + ':' + $detail)
    }
    return (($output | ForEach-Object { [string]$_ }) -join [Environment]::NewLine).Trim()
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
function Invoke-GitProcess([string[]]$Arguments,[hashtable]$Environment=@{}) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command git -ErrorAction Stop).Source
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
                if [ "$count" -eq 1 ]; then exit 1; fi
                ;;
        esac
        ;;
esac
exit 0
'@
    & $sh -c 'chmod +x "$1"' sh $shim
    if ($LASTEXITCODE -ne 0) { throw 'GIT_IDENTITY_PWSH_SHIM_NOT_EXECUTABLE' }
    $logPosix = (& $cygpath -u $LogPath).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($logPosix)) { throw 'GIT_IDENTITY_SHIM_LOG_PATH_INVALID' }
    return [pscustomobject]@{
        Directory=$Directory
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
    $env:GIT_CONFIG_GLOBAL = $globalConfig
    $env:GIT_CONFIG_NOSYSTEM = '1'
    foreach ($name in @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_PREFIX','GIT_COMMON_DIR','GIT_OBJECT_DIRECTORY','GIT_ALTERNATE_OBJECT_DIRECTORIES','GIT_CEILING_DIRECTORIES',
        'GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_CONFIG_PARAMETERS')) {
        Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
    }

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
    Case 'GIT-ID-007 correct outgoing commit and single-SHA push range pass' {
        WriteText (Join-Path $worktree 'good.txt') 'Good synthetic commit.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','good.txt') | Out-Null
        Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: valid identity') | Out-Null
        $script:good = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        $null = Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($base+'..'+$script:good)
        $null = Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good) -RemoteName 'origin'
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
    }
    Case 'GIT-ID-010 explicit bad committer name is rejected' {
        Invoke-GitFixture -Directory $worktree -Arguments @('switch','--quiet','-c','task/bad-committer-name',$script:good) | Out-Null
        WriteText (Join-Path $worktree 'bad-committer-name.txt') 'Synthetic bad committer name.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','bad-committer-name.txt') | Out-Null
        $env:GIT_COMMITTER_NAME = 'Scope Fixture'
        $env:GIT_COMMITTER_EMAIL = '123456+synthetic-owner@users.noreply.github.com'
        try { Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: invalid committer name') | Out-Null }
        finally {
            Remove-Item -LiteralPath Env:GIT_COMMITTER_NAME -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath Env:GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue
        }
        $bad = Invoke-GitFixture -Directory $worktree -Arguments @('rev-parse','HEAD')
        ExpectFailure { Assert-GitCommitIdentity -RepositoryRoot $worktree -CommitRange @($script:good+'..'+$bad) } 'GIT_IDENTITY_COMMITTER_NAME_MISMATCH'
    }
    Case 'GIT-ID-011 explicit bad committer email is rejected' {
        Invoke-GitFixture -Directory $worktree -Arguments @('switch','--quiet','-c','task/bad-committer-email',$script:good) | Out-Null
        WriteText (Join-Path $worktree 'bad-committer-email.txt') 'Synthetic bad committer email.'
        Invoke-GitFixture -Directory $worktree -Arguments @('add','bad-committer-email.txt') | Out-Null
        $env:GIT_COMMITTER_NAME = 'synthetic-owner'
        $env:GIT_COMMITTER_EMAIL = 'fixture@example.invalid'
        try { Invoke-GitFixture -Directory $worktree -Arguments @('commit','--quiet','-m','test: invalid committer email') | Out-Null }
        finally {
            Remove-Item -LiteralPath Env:GIT_COMMITTER_NAME -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath Env:GIT_COMMITTER_EMAIL -ErrorAction SilentlyContinue
        }
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
    Case 'GIT-ID-015 multi-ref pre-push passes every range as one delimited argument' {
        $script:hookRemote = Join-Path $scratch 'hook-remote.git'
        $script:hookRepo = Join-Path $scratch 'hook-repo'
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--bare','--quiet',$hookRemote) | Out-Null
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$hookRepo) | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','user.name','Hook Fixture') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','user.email','hook@example.invalid') | Out-Null
        WriteText (Join-Path $hookRepo 'README.md') 'Synthetic hook fixture.'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','README.md') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('commit','--quiet','-m','test: hook fixture') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('branch','-M','main') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('remote','add','origin',$hookRemote) | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('push','--quiet','origin','main') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','-c','task/hook-a','main') | Out-Null
        WriteText (Join-Path $hookRepo 'hook-a.txt') 'first ref'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','hook-a.txt') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('commit','--quiet','-m','test: first hook ref') | Out-Null
        $script:hookShaA = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','main') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','-c','task/hook-b','main') | Out-Null
        WriteText (Join-Path $hookRepo 'hook-b.txt') 'second ref'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','hook-b.txt') | Out-Null
        Invoke-GitFixture -Directory $hookRepo -Arguments @('commit','--quiet','-m','test: second hook ref') | Out-Null
        $script:hookShaB = Invoke-GitFixture -Directory $hookRepo -Arguments @('rev-parse','HEAD')
        $script:hookShim = New-PwshShim -Directory (Join-Path $scratch 'pwsh-shim') -LogPath (Join-Path $scratch 'pwsh-calls.bin')
        $script:hookProxy = New-HookProxy -Directory (Join-Path $scratch 'hook-proxy')
        Invoke-GitFixture -Directory $hookRepo -Arguments @('config','core.hooksPath',$hookProxy.Directory) | Out-Null
        $envs = @{
            PATH=($hookShim.Directory + [IO.Path]::PathSeparator + $env:PATH)
            PWSSHIM_LOG=$hookShim.LogPath
            PWSSHIM_STATE=$hookShim.StatePath
            PWSSHIM_MODE='pass'
            PWSSHIM_DIR=$hookShim.DirectoryPosix
            REAL_PRE_PUSH_HOOK=$hookShim.PrePushHookPosix
            REAL_PRE_COMMIT_HOOK=$hookShim.PreCommitHookPosix
        }
        $result = Invoke-GitProcess -Arguments @('-C',$hookRepo,'push','origin','task/hook-a','task/hook-b') -Environment $envs
        if ($result.ExitCode -ne 0) { throw ('MULTI_REF_PUSH_HOOK_FAILED:' + $result.StdErr) }
        $calls = @((Read-PwshShimCalls -LogPath (Join-Path $scratch 'pwsh-calls.bin')).Calls)
        if ($calls.Count -ne 2) { throw ('MULTI_REF_PWSH_CALL_COUNT_INVALID:' + $calls.Count + ':' + [string]::Join('||',@($calls | ForEach-Object { [string]::Join(' ',$_) }))) }
        $verifyRange = Get-PwshParameterValue -Arguments $calls[0] -Name '-CommitRange'
        $gateRange = Get-PwshParameterValue -Arguments $calls[1] -Name '-PushRange'
        $actualRanges = @($verifyRange -split '\r?\n' | Sort-Object)
        $expectedRanges = @($hookShaA,$hookShaB | Sort-Object)
        if (Compare-Object -ReferenceObject $expectedRanges -DifferenceObject $actualRanges) { throw 'MULTI_REF_COMMIT_RANGES_NOT_PRESERVED' }
        if ($gateRange -cne $verifyRange) { throw 'MULTI_REF_GATE_RANGE_MISMATCH' }
    }
    Case 'GIT-ID-016 pre-commit dynamically blocks identity override before creating commit' {
        Invoke-GitFixture -Directory $hookRepo -Arguments @('switch','--quiet','-c','task/hook-block','main') | Out-Null
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
        if ($calls.Count -ne 1 -or [string]::Join(' ',$calls[0]) -notlike '*verify-git-identity.ps1*') { throw 'PRE_COMMIT_OVERRIDE_HOOK_SEQUENCE_INVALID' }
    }
    Case 'GIT-ID-017 pre-commit dynamically repairs identity drift and rechecks' {
        WriteText (Join-Path $hookRepo 'repaired.txt') 'repaired commit'
        Invoke-GitFixture -Directory $hookRepo -Arguments @('add','repaired.txt') | Out-Null
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
        if ($result.ExitCode -ne 0) { throw ('PRE_COMMIT_REPAIR_HOOK_FAILED:' + $result.StdErr) }
        $calls = @((Read-PwshShimCalls -LogPath $logPath).Calls)
        if ($calls.Count -ne 3) { throw ('PRE_COMMIT_REPAIR_CALL_COUNT_INVALID:' + $calls.Count) }
        $sequence = @($calls | ForEach-Object { [string]::Join(' ',$_) })
        if ($sequence[0] -notlike '*verify-git-identity.ps1*' -or
            $sequence[1] -notlike '*configure-local.ps1*' -or
            $sequence[2] -notlike '*verify-git-identity.ps1*') {
            throw 'PRE_COMMIT_REPAIR_HOOK_SEQUENCE_INVALID'
        }
    }
    Case 'GIT-ID-018 bare-admin core.bare migration enables future linked worktrees' {
        $bareAdmin = Join-Path $scratch 'bare-admin.git'
        $bareSeed = Join-Path $scratch 'bare-seed'
        $bareWorktree = Join-Path $scratch 'bare-worktree'
        $newWorktree = Join-Path $scratch 'bare-worktree-next'
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--bare','--quiet',$bareAdmin) | Out-Null
        Invoke-GitFixture -Directory $scratch -Arguments @('init','--quiet',$bareSeed) | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('config','user.name','Bare Fixture') | Out-Null
        Invoke-GitFixture -Directory $bareSeed -Arguments @('config','user.email','bare@example.invalid') | Out-Null
        WriteText (Join-Path $bareSeed 'README.md') 'Bare admin migration fixture.'
        Invoke-GitFixture -Directory $bareSeed -Arguments @('add','README.md') | Out-Null
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
        $null = Initialize-GitWorktreeConfig -RepositoryRoot $bareWorktree
        if ((Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--file',(Join-Path $bareAdmin 'config.worktree'),'--get','core.bare')) -cne 'true') { throw 'BARE_ADMIN_CONFIG_WORKTREE_NOT_PRESERVED' }
        if ((Invoke-GitFixture -Directory $bareWorktree -Arguments @('config','--worktree','--get','core.bare')) -cne 'false') { throw 'LINKED_WORKTREE_CORE_BARE_NOT_FALSE' }
        $sharedBare = @(& git -C $bareWorktree config --local --get-all core.bare 2>$null)
        if ($LASTEXITCODE -ne 1 -or $sharedBare.Count -ne 0) { throw 'SHARED_CORE_BARE_NOT_MIGRATED' }
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
    Write-Output ('GIT-IDENTITY-REGRESSIONS: ' + $passed + ' passed, 0 failed')
}
finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process') }
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fullScratch = [IO.Path]::GetFullPath($scratch)
    if (-not $fullScratch.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_FIXTURE_CLEANUP_PATH_INVALID' }
    if (Test-Path -LiteralPath $fullScratch) { Remove-Item -LiteralPath $fullScratch -Recurse -Force }
}
