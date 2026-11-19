Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-GitIdentityNoReparsePath {
    param([Parameter(Mandatory)][string]$Path,[switch]$RequireExists)
    $full = [IO.Path]::GetFullPath($Path)
    if ($RequireExists -and -not (Test-Path -LiteralPath $full)) { throw 'GIT_IDENTITY_CONTEXT_PATH_MISSING' }
    $cursor = $full
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            try { $attributes = [IO.File]::GetAttributes($cursor) }
            catch { throw 'GIT_IDENTITY_CONTEXT_PATH_UNVERIFIED' }
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'GIT_IDENTITY_CONTEXT_REPARSE_POINT' }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent -or $parent.FullName.Equals($cursor,[StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $parent.FullName
    }
}

function Get-GitIdentityWorktreeContext {
    param([Parameter(Mandatory)][string]$RepositoryRoot)
    $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\','/')
    Assert-GitIdentityNoReparsePath -Path $root -RequireExists
    $marker = Join-Path $root '.git'
    Assert-GitIdentityNoReparsePath -Path $marker -RequireExists
    if (Test-Path -LiteralPath $marker -PathType Container) {
        $gitDir = [IO.Path]::GetFullPath($marker)
        $commonDir = $gitDir
    } else {
        $text = [IO.File]::ReadAllText($marker)
        $match = [regex]::Match($text,'^gitdir:\s*(?<path>[^\r\n]+)\s*$')
        if (-not $match.Success) { throw 'GIT_IDENTITY_GIT_MARKER_INVALID' }
        $gitDirPath = $match.Groups['path'].Value.Trim()
        if (-not [IO.Path]::IsPathRooted($gitDirPath)) { $gitDirPath = Join-Path $root $gitDirPath }
        Assert-GitIdentityNoReparsePath -Path $gitDirPath -RequireExists
        $gitDir = [IO.Path]::GetFullPath($gitDirPath)
        $commonFile = Join-Path $gitDir 'commondir'
        Assert-GitIdentityNoReparsePath -Path $commonFile -RequireExists
        $commonValue = [IO.File]::ReadAllText($commonFile).Trim()
        if ([string]::IsNullOrWhiteSpace($commonValue)) { throw 'GIT_IDENTITY_COMMON_DIR_INVALID' }
        $commonPath = if ([IO.Path]::IsPathRooted($commonValue)) { $commonValue } else { Join-Path $gitDir $commonValue }
        Assert-GitIdentityNoReparsePath -Path $commonPath -RequireExists
        $commonDir = [IO.Path]::GetFullPath($commonPath)
        $reverseMarker = Join-Path $gitDir 'gitdir'
        Assert-GitIdentityNoReparsePath -Path $reverseMarker -RequireExists
        $reverseValue = [IO.File]::ReadAllText($reverseMarker).Trim()
        if ([string]::IsNullOrWhiteSpace($reverseValue)) { throw 'GIT_IDENTITY_GITDIR_LINK_INVALID' }
        $reversePath = if ([IO.Path]::IsPathRooted($reverseValue)) { $reverseValue } else { Join-Path $gitDir $reverseValue }
        if (-not [IO.Path]::GetFullPath($reversePath).Equals([IO.Path]::GetFullPath($marker),[StringComparison]::OrdinalIgnoreCase)) {
            throw 'GIT_IDENTITY_GITDIR_LINK_MISMATCH'
        }
    }
    foreach ($metadataPath in @((Join-Path $commonDir 'config'),(Join-Path $commonDir 'config.worktree'),(Join-Path $gitDir 'config.worktree'),(Join-Path $gitDir 'index'))) {
        if (Test-Path -LiteralPath $metadataPath) { Assert-GitIdentityNoReparsePath -Path $metadataPath -RequireExists }
    }
    return [pscustomobject]@{ Root=$root; GitDir=$gitDir; CommonDir=$commonDir; Index=(Join-Path $gitDir 'index') }
}

function Convert-GitIdentityEnvironmentPath {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$BasePath)
    $value = $Path.Trim().Trim('"')
    if ($value -match '^/(?<drive>[A-Za-z])/(?<rest>.*)$') { $value = $Matches.drive + ':\' + $Matches.rest.Replace('/','\') }
    if (-not [IO.Path]::IsPathRooted($value)) { $value = Join-Path $BasePath $value }
    return [IO.Path]::GetFullPath($value)
}

function Assert-GitWorktreeEnvironment {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[switch]$HookContext)
    $context = Get-GitIdentityWorktreeContext -RepositoryRoot $RepositoryRoot
    $environment = [Environment]::GetEnvironmentVariables('Process')
    $configNames = @($environment.Keys | ForEach-Object { [string]$_ } | Where-Object { $_.StartsWith('GIT_CONFIG_',[StringComparison]::OrdinalIgnoreCase) } | Sort-Object -Unique)
    if ($configNames.Count -gt 0) { throw ('GIT_IDENTITY_CONFIG_ENVIRONMENT_OVERRIDE:' + ($configNames -join ',')) }

    $allowed = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($name in @('GIT_PAGER','GIT_EDITOR','GIT_OPTIONAL_LOCKS','GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')) { $null = $allowed.Add($name) }
    if ($HookContext) {
        foreach ($name in @('GIT_DIR','GIT_INDEX_FILE','GIT_PREFIX','GIT_AUTHOR_DATE','GIT_COMMITTER_DATE','GIT_EXEC_PATH')) {
            $null = $allowed.Add($name)
        }
    }
    $unexpected = @($environment.Keys | ForEach-Object { [string]$_ } | Where-Object {
        $_.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) -and -not $allowed.Contains($_)
    } | Sort-Object -Unique)
    if ($unexpected.Count -gt 0) { throw ('GIT_IDENTITY_REPOSITORY_CONTEXT_OVERRIDE:' + ($unexpected -join ',')) }

    if ($HookContext) {
        $actualCwd = [IO.Path]::GetFullPath((Get-Location).Path).TrimEnd('\','/')
        if (-not $actualCwd.Equals($context.Root,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_HOOK_CWD_MISMATCH' }
        $execPath = [Environment]::GetEnvironmentVariable('GIT_EXEC_PATH','Process')
        if (-not [string]::IsNullOrWhiteSpace($execPath)) {
            $expectedExecResult = Invoke-GitIdentityProcess -Arguments @('--exec-path')
            if ($expectedExecResult.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($expectedExecResult.StdOut)) {
                throw 'GIT_IDENTITY_HOOK_EXEC_PATH_UNVERIFIABLE'
            }
            try {
                $actualExecPath = Convert-GitIdentityEnvironmentPath -Path $execPath -BasePath $context.Root
                $expectedExecPath = [IO.Path]::GetFullPath($expectedExecResult.StdOut.Trim())
            }
            catch { throw 'GIT_IDENTITY_HOOK_EXEC_PATH_INVALID' }
            if (-not $actualExecPath.TrimEnd('\','/').Equals($expectedExecPath.TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase)) {
                throw 'GIT_IDENTITY_HOOK_EXEC_PATH_MISMATCH'
            }
        }
        $gitDirValue = [Environment]::GetEnvironmentVariable('GIT_DIR','Process')
        if (-not [string]::IsNullOrWhiteSpace($gitDirValue)) {
            $actualGitDir = Convert-GitIdentityEnvironmentPath -Path $gitDirValue -BasePath $context.Root
            if (-not $actualGitDir.Equals($context.GitDir,[StringComparison]::OrdinalIgnoreCase)) { throw 'GIT_IDENTITY_HOOK_GIT_DIR_MISMATCH' }
        }
        $indexValue = [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process')
        if (-not [string]::IsNullOrWhiteSpace($indexValue)) {
            try { $actualIndex = Convert-GitIdentityEnvironmentPath -Path $indexValue -BasePath $context.Root }
            catch { throw 'GIT_IDENTITY_HOOK_GIT_INDEX_FILE_MISMATCH' }
            $indexDirectory = [IO.Path]::GetDirectoryName($actualIndex)
            $indexName = [IO.Path]::GetFileName($actualIndex)
            $expectedIndex = [IO.Path]::GetFullPath($context.Index)
            $isCanonicalIndex = $actualIndex.Equals($expectedIndex,[StringComparison]::OrdinalIgnoreCase)
            $isGitCommitIndex = $indexDirectory.Equals($context.GitDir,[StringComparison]::OrdinalIgnoreCase) -and
                $indexName -cmatch '^(?:index\.lock|next-index-[0-9]+\.lock)$'
            if (-not $isCanonicalIndex -and -not $isGitCommitIndex) { throw 'GIT_IDENTITY_HOOK_GIT_INDEX_FILE_MISMATCH' }
            Assert-GitIdentityNoReparsePath -Path $indexDirectory -RequireExists
            if (Test-Path -LiteralPath $actualIndex) { Assert-GitIdentityNoReparsePath -Path $actualIndex -RequireExists }
        }
        $prefix = [Environment]::GetEnvironmentVariable('GIT_PREFIX','Process')
        if (-not [string]::IsNullOrEmpty($prefix) -and $prefix -notin @('.','./','.\')) {
            $normalizedPrefix = $prefix.Replace('/','\')
            if ([IO.Path]::IsPathRooted($normalizedPrefix) -or $normalizedPrefix -match '(^|\\)\.\.?($|\\)') {
                throw 'GIT_IDENTITY_HOOK_PREFIX_INVALID'
            }
            try { $prefixPath = [IO.Path]::GetFullPath((Join-Path $context.Root $normalizedPrefix)) }
            catch { throw 'GIT_IDENTITY_HOOK_PREFIX_INVALID' }
            $rootPrefix = $context.Root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
            if (-not $prefixPath.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or
                -not (Test-Path -LiteralPath $prefixPath -PathType Container)) {
                throw 'GIT_IDENTITY_HOOK_PREFIX_INVALID'
            }
        }
    } elseif ($null -ne [Environment]::GetEnvironmentVariable('GIT_DIR','Process') -or
              $null -ne [Environment]::GetEnvironmentVariable('GIT_WORK_TREE','Process') -or
              $null -ne [Environment]::GetEnvironmentVariable('GIT_COMMON_DIR','Process') -or
              $null -ne [Environment]::GetEnvironmentVariable('GIT_INDEX_FILE','Process')) {
        throw 'GIT_IDENTITY_REPOSITORY_CONTEXT_OVERRIDE:GIT_REPOSITORY_OR_INDEX'
    }

    $policy = Get-GitIdentityPolicy -RepositoryRoot $context.Root
    $mismatches = [Collections.Generic.List[string]]::new()
    foreach ($name in @('GIT_AUTHOR_NAME','GIT_AUTHOR_EMAIL','GIT_COMMITTER_NAME','GIT_COMMITTER_EMAIL')) {
        $value = [Environment]::GetEnvironmentVariable($name,'Process')
        if ([string]::IsNullOrEmpty($value)) { continue }
        $expected = if ($name -match '_NAME$') { $policy.Login } else { $policy.Email }
        if ($value -cne $expected) { $mismatches.Add($name) }
    }
    if ($mismatches.Count -gt 0) {
        $unmatchedIdentityEnvironment = [Collections.Generic.List[string]]::new()
        if ($HookContext) {
            $configuredName = Get-GitIdentityConfigValue -RepositoryRoot $context.Root -Arguments @('config','--worktree','--get','user.name')
            $configuredEmail = Get-GitIdentityConfigValue -RepositoryRoot $context.Root -Arguments @('config','--worktree','--get','user.email')
            foreach ($name in $mismatches) {
                $value = [Environment]::GetEnvironmentVariable($name,'Process')
                $configured = if ($name -match '_NAME$') { $configuredName } else { $configuredEmail }
                if ([string]::IsNullOrEmpty($configured) -or $value -cne $configured) { $unmatchedIdentityEnvironment.Add($name) }
            }
        } else {
            $unmatchedIdentityEnvironment.AddRange([string[]]$mismatches)
        }
        if ($unmatchedIdentityEnvironment.Count -gt 0) {
            throw ('GIT_IDENTITY_ENVIRONMENT_OVERRIDE:' + ($unmatchedIdentityEnvironment -join ','))
        }
    }
    return $context
}

function Invoke-GitIdentityProcess {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $git = (Get-Command git -ErrorAction Stop).Source
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $emptyConfig = Join-Path $repoRoot 'config/git-empty.config'
    if (-not (Test-Path -LiteralPath $emptyConfig -PathType Leaf)) { throw 'GIT_IDENTITY_EMPTY_CONFIG_MISSING' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $git
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    $start.ArgumentList.Add('--no-pager')
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    foreach ($name in @($start.Environment.Keys | Where-Object { ([string]$_).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) })) {
        $null = $start.Environment.Remove([string]$name)
    }
    $start.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
    $start.Environment['GIT_CONFIG_GLOBAL'] = $emptyConfig
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode=$process.ExitCode; StdOut=$stdout.Result; StdErr=$stderr.Result }
}

function Invoke-GitIdentityCommand {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-GitIdentityProcess -Arguments (@('-C',$RepositoryRoot) + $Arguments)
    if ($result.ExitCode -ne 0) { throw 'GIT_IDENTITY_GIT_COMMAND_FAILED' }
    return $result.StdOut.Trim()
}

function Get-GitIdentityConfigValue {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-GitIdentityProcess -Arguments (@('-C',$RepositoryRoot) + $Arguments)
    if ($result.ExitCode -eq 1) { return $null }
    if ($result.ExitCode -ne 0) { throw 'GIT_IDENTITY_CONFIG_READ_FAILED' }
    return $result.StdOut.Trim()
}

function Invoke-GitIdentityAdminCommand {
    param([Parameter(Mandatory)][string]$GitDirectory,[Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-GitIdentityProcess -Arguments (@('--git-dir=' + $GitDirectory) + $Arguments)
    if ($result.ExitCode -ne 0) { throw 'GIT_IDENTITY_ADMIN_COMMAND_FAILED' }
    return $result.StdOut.Trim()
}

function Get-GitIdentityAdminConfigValue {
    param([Parameter(Mandatory)][string]$GitDirectory,[Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-GitIdentityProcess -Arguments (@('--git-dir=' + $GitDirectory) + $Arguments)
    if ($result.ExitCode -eq 1) { return $null }
    if ($result.ExitCode -ne 0) { throw 'GIT_IDENTITY_ADMIN_CONFIG_READ_FAILED' }
    return $result.StdOut.Trim()
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
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $RepositoryRoot
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

    $worktreeListingResult = Invoke-GitIdentityProcess -Arguments @('-C',$root,'worktree','list','--porcelain')
    $worktreeListingOutput = @($worktreeListingResult.StdOut -split '\r?\n')
    $worktreeListingExitCode = $worktreeListingResult.ExitCode
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
    $adminPathFound = @($listedPaths | Where-Object { $_.TrimEnd('\','/').Equals($commonDir.TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if ($adminPathFound) { $hasBareAdmin = $true }
    $registeredPathFound = @($listedPaths | Where-Object { $_.TrimEnd('\','/').Equals($root,[StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if (-not $registeredPathFound) { throw 'GIT_IDENTITY_WORKTREE_NOT_REGISTERED' }

    $adminBareValues = @()
    $adminConfigWorktree = Join-Path $commonDir 'config.worktree'
    if ($hasBareAdmin) {
        $adminBareValue = Get-GitIdentityAdminConfigValue -GitDirectory $commonDir -Arguments @('config','--file',$adminConfigWorktree,'--get-all','core.bare')
        if ($null -ne $adminBareValue) { $adminBareValues = @($adminBareValue -split '\n') }
        if ($adminBareValues.Count -gt 1 -or ($adminBareValues.Count -eq 1 -and $adminBareValues[0] -cne 'true')) {
            throw 'GIT_IDENTITY_ADMIN_CORE_BARE_CONFLICT'
        }
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
    param([Parameter(Mandatory)][string]$RepositoryRoot,[switch]$HookContext)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $root -HookContext:$HookContext
    Assert-GitIdentityWorktree -RepositoryRoot $root
    $policy = Get-GitIdentityPolicy -RepositoryRoot $root
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
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $root
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
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string[]]$CommitRange,[string]$RemoteName,[string]$PublishedMainSha)
    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $null = Assert-GitWorktreeEnvironment -RepositoryRoot $root
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

        } else {
            throw 'GIT_IDENTITY_COMMIT_RANGE_INVALID'
        }
        if ($PublishedMainSha) {
            if ($PublishedMainSha -notmatch ('^'+$shaPattern+'$')) { throw 'GIT_IDENTITY_PUBLISHED_MAIN_INVALID' }
            $revArgs += @('--not',$PublishedMainSha)
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

Export-ModuleMember -Function Assert-GitWorktreeIdentity,Set-GitWorktreeIdentity,Assert-GitCommitIdentity,Get-GitIdentityPolicy,Initialize-GitWorktreeConfig,Assert-GitWorktreeEnvironment
