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
$envNames = @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL',
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

try {
    [IO.Directory]::CreateDirectory($scratch) | Out-Null
    $globalConfig = Join-Path $scratch 'global.gitconfig'
    $xdg = Join-Path $scratch 'xdg'
    [IO.Directory]::CreateDirectory($xdg) | Out-Null
    $env:GIT_CONFIG_GLOBAL = $globalConfig
    $env:GIT_CONFIG_NOSYSTEM = '1'
    foreach ($name in @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0','GIT_CONFIG_PARAMETERS')) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }

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
    Write-Output ('GIT-IDENTITY-REGRESSIONS: ' + $passed + ' passed, 0 failed')
}
finally {
    foreach ($name in $envNames) { [Environment]::SetEnvironmentVariable($name,$savedEnv[$name],'Process') }
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fullScratch = [IO.Path]::GetFullPath($scratch)
    if (-not $fullScratch.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_FIXTURE_CLEANUP_PATH_INVALID' }
    if (Test-Path -LiteralPath $fullScratch) { Remove-Item -LiteralPath $fullScratch -Recurse -Force }
}
