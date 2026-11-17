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

function Invoke-GitIdentityAdminCommand {
    param([Parameter(Mandatory)][string]$GitDirectory,[Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git ('--git-dir=' + $GitDirectory) @Arguments 2>$null)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw 'GIT_IDENTITY_ADMIN_COMMAND_FAILED' }
    return [string]::Join([string][char]10, [string[]]$output).Trim()
}

function Get-GitIdentityAdminConfigValue {
    param([Parameter(Mandatory)][string]$GitDirectory,[Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git ('--git-dir=' + $GitDirectory) @Arguments 2>$null)
    $code = $LASTEXITCODE
    if ($code -eq 1) { return $null }
    if ($code -ne 0) { throw 'GIT_IDENTITY_ADMIN_CONFIG_READ_FAILED' }
    return [string]::Join([string][char]10, [string[]]$output).Trim()
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

function Initialize-GitWorktreeConfig {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    $gitMarker = Join-Path $root '.git'
    if (-not (Test-Path -LiteralPath $gitMarker)) { throw 'GIT_IDENTITY_NOT_A_WORKTREE' }

    if (Test-Path -LiteralPath $gitMarker -PathType Container) {
        $gitDirectory = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $gitMarker).Path)
        $commonDir = $gitDirectory
    } else {
        $markerText = Get-Content -LiteralPath $gitMarker -Raw -ErrorAction Stop
        $markerMatch = [regex]::Match($markerText,'^gitdir:\s*(?<path>[^\r\n]+)\s*$')
        if (-not $markerMatch.Success) { throw 'GIT_IDENTITY_GIT_MARKER_INVALID' }
        $gitDirectoryPath = $markerMatch.Groups['path'].Value.Trim()
        if (-not [IO.Path]::IsPathRooted($gitDirectoryPath)) { $gitDirectoryPath = Join-Path $root $gitDirectoryPath }
        if (-not (Test-Path -LiteralPath $gitDirectoryPath -PathType Container)) { throw 'GIT_IDENTITY_GIT_DIRECTORY_MISSING' }
        $gitDirectory = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $gitDirectoryPath).Path)
        $commonDirFile = Join-Path $gitDirectory 'commondir'
        if (Test-Path -LiteralPath $commonDirFile -PathType Leaf) {
            $commonDirValue = (Get-Content -LiteralPath $commonDirFile -Raw -ErrorAction Stop).Trim()
            if ([string]::IsNullOrWhiteSpace($commonDirValue)) { throw 'GIT_IDENTITY_COMMON_DIR_INVALID' }
            $commonDirPath = if ([IO.Path]::IsPathRooted($commonDirValue)) { $commonDirValue } else { Join-Path $gitDirectory $commonDirValue }
            if (-not (Test-Path -LiteralPath $commonDirPath -PathType Container)) { throw 'GIT_IDENTITY_COMMON_DIR_MISSING' }
            $commonDir = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $commonDirPath).Path)
        } else {
            $commonDir = $gitDirectory
        }
    }

    $commonCoreWorktree = Get-GitIdentityAdminConfigValue -GitDirectory $commonDir -Arguments @('config','--local','--get-all','core.worktree')
    if ($null -ne $commonCoreWorktree) { throw 'GIT_IDENTITY_SHARED_CORE_WORKTREE_UNSAFE' }
    $extensionValue = Get-GitIdentityAdminConfigValue -GitDirectory $commonDir -Arguments @('config','--local','--get-all','extensions.worktreeConfig')
    $extensionValues = @()
    if ($null -ne $extensionValue) { $extensionValues = @($extensionValue -split '\n') }
    if ($extensionValues.Count -gt 1 -or ($extensionValues.Count -eq 1 -and $extensionValues[0] -notin @('true','false'))) {
        throw 'GIT_IDENTITY_WORKTREE_CONFIG_INVALID'
    }
    $sharedBareValue = Get-GitIdentityAdminConfigValue -GitDirectory $commonDir -Arguments @('config','--local','--get-all','core.bare')
    $sharedBareValues = @()
    if ($null -ne $sharedBareValue) { $sharedBareValues = @($sharedBareValue -split '\n') }
    if ($sharedBareValues.Count -gt 1 -or ($sharedBareValues.Count -eq 1 -and $sharedBareValues[0] -notin @('true','false'))) {
        throw 'GIT_IDENTITY_SHARED_CORE_BARE_INVALID'
    }

    $worktreeListingOutput = @(& git ('--git-dir=' + $commonDir) worktree list --porcelain 2>$null)
    $worktreeListingExitCode = $LASTEXITCODE
    if ($worktreeListingExitCode -ne 0) { throw 'GIT_IDENTITY_WORKTREE_LIST_FAILED' }
    $worktreeListing = [string]::Join("`n",[string[]]$worktreeListingOutput).Trim()
    $listedPaths = [System.Collections.Generic.List[string]]::new()
    $hasBareAdmin = $false
    foreach ($line in ($worktreeListing -split '\n')) {
        if ($line -ceq 'bare') { $hasBareAdmin = $true; continue }
        if ($line.StartsWith('worktree ',[StringComparison]::Ordinal)) {
            try { $listedPaths.Add([IO.Path]::GetFullPath($line.Substring(9).Trim())) }
            catch { throw 'GIT_IDENTITY_WORKTREE_LIST_INVALID' }
        }
    }
    $registeredPathFound = @($listedPaths | Where-Object { $_.TrimEnd('\','/').Equals($root,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if (-not $registeredPathFound) { throw 'GIT_IDENTITY_WORKTREE_NOT_REGISTERED' }

    $adminConfigWorktree = Join-Path $commonDir 'config.worktree'
    $adminBareValue = Get-GitIdentityAdminConfigValue -GitDirectory $commonDir -Arguments @('config','--file',$adminConfigWorktree,'--get-all','core.bare')
    $adminBareValues = @()
    if ($null -ne $adminBareValue) { $adminBareValues = @($adminBareValue -split '\n') }
    if ($adminBareValues.Count -gt 1 -or ($adminBareValues.Count -eq 1 -and $adminBareValues[0] -cne 'true')) {
        throw 'GIT_IDENTITY_ADMIN_CORE_BARE_CONFLICT'
    }

    $addedAdminBare = $false
    if ($hasBareAdmin) {
        if ($sharedBareValues.Count -eq 1 -and $sharedBareValues[0] -ceq 'false') { throw 'GIT_IDENTITY_ADMIN_CORE_BARE_CONFLICT' }
        if ($adminBareValues.Count -eq 0) {
            $null = Invoke-GitIdentityAdminCommand -GitDirectory $commonDir -Arguments @('config','--file',$adminConfigWorktree,'core.bare','true')
            $addedAdminBare = $true
        }
        if ($sharedBareValues.Count -eq 1 -and $sharedBareValues[0] -ceq 'true') {
            if (-not (Test-Path -LiteralPath $gitMarker -PathType Leaf)) {
                if ($addedAdminBare) { & git ('--git-dir=' + $commonDir) config --file $adminConfigWorktree --unset-all core.bare 2>$null | Out-Null }
                throw 'GIT_IDENTITY_SHARED_CORE_BARE_UNSAFE'
            }
            try {
                $null = Invoke-GitIdentityAdminCommand -GitDirectory $commonDir -Arguments @('config','--local','--unset-all','core.bare')
            } catch {
                if ($addedAdminBare) { & git ('--git-dir=' + $commonDir) config --file $adminConfigWorktree --unset-all core.bare 2>$null | Out-Null }
                throw 'GIT_IDENTITY_CORE_BARE_MIGRATION_FAILED'
            }
        }
    } elseif ($sharedBareValues.Count -eq 1 -and $sharedBareValues[0] -ceq 'true') {
        throw 'GIT_IDENTITY_SHARED_CORE_BARE_UNSAFE'
    }

    if ($extensionValues.Count -eq 0 -or $extensionValues[0] -cne 'true') {
        $null = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('config','--local','extensions.worktreeConfig','true')
    }
    $null = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('config','--worktree','core.bare','false')
    if ((Get-GitIdentityConfigValue -RepositoryRoot $root -Arguments @('config','--worktree','--get','core.bare')) -cne 'false') {
        throw 'GIT_IDENTITY_WORKTREE_CORE_BARE_NOT_SET'
    }
    if ((Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('rev-parse','--is-inside-work-tree')) -cne 'true') {
        throw 'GIT_IDENTITY_NOT_A_WORKTREE'
    }
    $actualRoot = [IO.Path]::GetFullPath((Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('rev-parse','--show-toplevel'))).TrimEnd('\','/')
    if (-not $actualRoot.Equals($root,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_WRONG_WORKTREE_ROOT' }
    try { $null = Invoke-GitIdentityCommand -RepositoryRoot $root -Arguments @('status','--porcelain','--untracked-files=no') }
    catch { throw 'GIT_IDENTITY_WORKTREE_STATUS_UNAVAILABLE' }
    return $true
}

function Assert-GitIdentityWorktree {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    if (-not (Test-Path -LiteralPath (Join-Path $root '.git'))) { throw 'GIT_IDENTITY_NOT_A_WORKTREE' }
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
    $policy = Get-GitIdentityPolicy -RepositoryRoot $root
    if (-not $Login.Equals($policy.Login,[StringComparison]::OrdinalIgnoreCase) -or $UserId -cne $policy.UserId) { throw 'GIT_IDENTITY_AUTHENTICATED_ACCOUNT_MISMATCH' }
    $null = Initialize-GitWorktreeConfig -RepositoryRoot $root
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
    foreach ($rangeArgument in $CommitRange) {
      foreach ($range in ($rangeArgument -split '\r?\n')) {
        if ([string]::IsNullOrWhiteSpace($range)) { continue }
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
    }
    return $true
}

Export-ModuleMember -Function Assert-GitWorktreeIdentity,Set-GitWorktreeIdentity,Assert-GitCommitIdentity,Get-GitIdentityPolicy,Initialize-GitWorktreeConfig
