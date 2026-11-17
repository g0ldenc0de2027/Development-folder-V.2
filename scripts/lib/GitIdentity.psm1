Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitIdentityCommand {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -C $RepositoryRoot @Arguments 2>$null)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw 'GIT_IDENTITY_GIT_COMMAND_FAILED' }
    return [string]::Join("`n", [string[]]$output).Trim()
}

function Get-GitIdentityConfigValue {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -C $RepositoryRoot @Arguments 2>$null)
    $code = $LASTEXITCODE
    if ($code -eq 1) { return $null }
    if ($code -ne 0) { throw 'GIT_IDENTITY_CONFIG_READ_FAILED' }
    return [string]::Join("`n", [string[]]$output).Trim()
}

function Get-GitIdentityPolicy {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $path = Join-Path $RepositoryRoot 'config/github/repository.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'GIT_IDENTITY_POLICY_MISSING' }
    try { $config = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop }
    catch { throw 'GIT_IDENTITY_POLICY_INVALID' }
    $identity = $config.commitIdentity
    if (-not $identity -or [string]$identity.login -notmatch '^[A-Za-z0-9-]{1,39}$' -or [string]$identity.userId -notmatch '^[1-9][0-9]{0,19}$') {
        throw 'GIT_IDENTITY_POLICY_INVALID'
    }
    return [pscustomobject]@{
        Login = [string]$identity.login
        UserId = [string]$identity.userId
        Email = ([string]$identity.userId + '+' + [string]$identity.login + '@users.noreply.github.com')
    }
}

function Assert-GitIdentityWorktree {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    $inside = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('rev-parse','--is-inside-work-tree')
    if ($inside -cne 'true') { throw 'GIT_IDENTITY_NOT_A_WORKTREE' }
    $actual = [IO.Path]::GetFullPath((Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('rev-parse','--show-toplevel'))).TrimEnd('\','/')
    if (-not $actual.Equals($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_WRONG_WORKTREE_ROOT' }
    $worktreeConfig = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('config','--get','extensions.worktreeConfig')
    if ($worktreeConfig -cne 'true') { throw 'GIT_IDENTITY_WORKTREE_CONFIG_DISABLED' }
}

function Get-GitIdentityVar {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][ValidateSet('GIT_AUTHOR_IDENT','GIT_COMMITTER_IDENT')][string]$Name)
    $value = Invoke-GitIdentityCommand -RepositoryRoot $RepositoryRoot -Arguments @('var',$Name)
    if ($value -notmatch '^(?<name>[^<>]+) <(?<email>[^<>]+)> [0-9]+ [+-][0-9]{4}$') { throw 'GIT_IDENTITY_EFFECTIVE_VALUE_INVALID' }
    return [pscustomobject]@{ Name=$Matches.name; Email=$Matches.email }
}

function Assert-GitWorktreeIdentity {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    Assert-GitIdentityWorktree -RepositoryRoot $root
    $policy = Get-GitIdentityPolicy -RepositoryRoot $root
    $identityMismatches = @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL' | Where-Object {
        $value = [Environment]::GetEnvironmentVariable($_,'Process')
        if ([string]::IsNullOrEmpty($value)) { return $false }
        $expected = if ($_ -match '(^GIT_AUTHOR_NAME$|^GIT_COMMITTER_NAME$)') { $policy.Login } else { $policy.Email }
        return $value -cne $expected
    })
    if ($identityMismatches.Count -gt 0) { throw ('GIT_IDENTITY_ENVIRONMENT_OVERRIDE:' + ($identityMismatches -join ',')) }
    $configOverrides = @(Get-ChildItem Env: | Where-Object {
        $_.Name -match '^GIT_CONFIG_(COUNT|PARAMETERS|KEY_[0-9]+|VALUE_[0-9]+)$'
    } | ForEach-Object { $_.Name })
    if ($configOverrides.Count -gt 0) { throw ('GIT_IDENTITY_CONFIG_ENVIRONMENT_OVERRIDE:' + ($configOverrides -join ',')) }
    $name = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--worktree','--get','user.name')
    $email = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--worktree','--get','user.email')
    $useOnly = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--worktree','--get','user.useConfigOnly')
    $accountId = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--worktree','--get','etalon.identity.userId')
    $accountLogin = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--worktree','--get','etalon.identity.login')
    if ($name -cne $policy.Login) { throw 'GIT_IDENTITY_WORKTREE_NAME_MISMATCH' }
    if ($email -cne $policy.Email) { throw 'GIT_IDENTITY_WORKTREE_EMAIL_MISMATCH' }
    if ($useOnly -cne 'true') { throw 'GIT_IDENTITY_CONFIG_ONLY_REQUIRED' }
    if ($accountId -cne $policy.UserId -or $accountLogin -cne $policy.Login) { throw 'GIT_IDENTITY_WORKTREE_ACCOUNT_MISMATCH' }
    foreach ($varName in @('GIT_AUTHOR_IDENT','GIT_COMMITTER_IDENT')) {
        $effective = Get-GitIdentityVar -RepositoryRoot $root -Name $varName
        if ($effective.Name -cne $policy.Login) { throw 'GIT_IDENTITY_EFFECTIVE_NAME_MISMATCH' }
        if ($effective.Email -cne $policy.Email) { throw 'GIT_IDENTITY_EFFECTIVE_EMAIL_MISMATCH' }
    }
    return $policy
}

function Set-GitWorktreeIdentity {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Login,[Parameter(Mandatory)][string]$UserId)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    Assert-GitIdentityWorktree -RepositoryRoot $root
    $policy = Get-GitIdentityPolicy -RepositoryRoot $root
    if ($Login -cne $policy.Login -or $UserId -cne $policy.UserId) { throw 'GIT_IDENTITY_AUTHENTICATED_ACCOUNT_MISMATCH' }
    $commonName = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--local','--get','user.name')
    $commonEmail = Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--local','--get','user.email')
    foreach ($entry in @(
        @('user.name',$policy.Login),
        @('user.email',$policy.Email),
        @('user.useConfigOnly','true'),
        @('etalon.identity.login',$policy.Login),
        @('etalon.identity.userId',$policy.UserId)
    )) {
        $null = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments (@('config','--worktree',$entry[0],$entry[1]))
    }
    if ((Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--local','--get','user.name')) -cne $commonName -or
        (Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--local','--get','user.email')) -cne $commonEmail) {
        throw 'GIT_IDENTITY_COMMON_CONFIG_CHANGED'
    }
    return Assert-GitWorktreeIdentity -RepositoryRoot $root
}

function Assert-GitCommitIdentity {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$CommitRange,[string]$RemoteName)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $policy = Get-GitIdentityPolicy -RepositoryRoot $root
    $shaPattern = '(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})'
    if ($RemoteName -and $RemoteName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$') { throw 'GIT_IDENTITY_REMOTE_NAME_INVALID' }
    foreach ($range in $CommitRange) {
        if ($range -match ('^(?<left>'+$shaPattern+')\.\.(?<right>'+$shaPattern+')$')) {
            $revArgs = @('rev-list',$range)
        } elseif ($range -match ('^(?<single>'+$shaPattern+')$')) {
            $singleSha = $Matches.single
            $revArgs = @('rev-list',$singleSha)
            if ($RemoteName) { $revArgs += @('--not',('--remotes='+$RemoteName)) }
        } else {
            throw 'GIT_IDENTITY_COMMIT_RANGE_INVALID'
        }
        $listed = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments $revArgs
        $commits = @($listed -split "`n" | Where-Object { $_ -match '^([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$' })
        foreach ($sha in $commits) {
            $format = '%H%x1f%an%x1f%ae%x1f%cn%x1f%ce'
            $record = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('show','-s',('--format='+$format),$sha)
            $fields = $record -split [char]31
            if ($fields.Count -ne 5) { throw ('GIT_IDENTITY_COMMIT_METADATA_INVALID:'+$sha.Substring(0,12)) }
            if ($fields[1] -cne $policy.Login) { throw ('GIT_IDENTITY_COMMIT_AUTHOR_NAME_MISMATCH:'+$sha.Substring(0,12)) }
            if ($fields[2] -cne $policy.Email) { throw ('GIT_IDENTITY_COMMIT_AUTHOR_EMAIL_MISMATCH:'+$sha.Substring(0,12)) }
            if ($fields[3] -cne $policy.Login) { throw ('GIT_IDENTITY_COMMITTER_NAME_MISMATCH:'+$sha.Substring(0,12)) }
            if ($fields[4] -cne $policy.Email) { throw ('GIT_IDENTITY_COMMITTER_EMAIL_MISMATCH:'+$sha.Substring(0,12)) }
        }
    }
    return $true
}

Export-ModuleMember -Function Assert-GitWorktreeIdentity,Set-GitWorktreeIdentity,Assert-GitCommitIdentity,Get-GitIdentityPolicy
