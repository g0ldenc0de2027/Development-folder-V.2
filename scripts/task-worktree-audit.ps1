#Requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Audit','Commit','Publish')]
    [string]$Mode = 'Audit',
    [string]$RepositoryRoot,
    [string]$QuarantineConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

function Invoke-GitText {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )
    # Inherited Git environment can redirect repository discovery, config, or object storage.
    $gitContext = @{}
    $previousConsoleEncoding = [Console]::OutputEncoding
    $scriptRepositoryRoot = Split-Path -Parent $PSScriptRoot
    $emptyConfig = Join-Path $scriptRepositoryRoot 'config/git-empty.config'
    if (-not (Test-Path -LiteralPath $emptyConfig -PathType Leaf)) { throw 'WORKTREE_AUDIT_EMPTY_GIT_CONFIG_MISSING' }
    foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        $name = [string]$entry.Key
        if (-not $name.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)) { continue }
        $gitContext[$name] = $entry.Value
        Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
    }
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM','1','Process')
        [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL',$emptyConfig,'Process')
        $output = @(& git --no-pager --no-optional-locks -c core.fsmonitor=false -C $Directory @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $previousConsoleEncoding
        Remove-Item -LiteralPath 'Env:GIT_CONFIG_NOSYSTEM' -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath 'Env:GIT_CONFIG_GLOBAL' -ErrorAction SilentlyContinue
        foreach ($name in $gitContext.Keys) {
            if ($null -eq $gitContext[$name]) { Remove-Item -LiteralPath ('Env:' + [string]$name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable([string]$name,[string]$gitContext[$name],'Process') }
        }
    }
    if ($exitCode -ne 0) { throw ("WORKTREE_AUDIT_GIT_FAILED:${Operation} at " + [IO.Path]::GetFileName($Directory) + ": " + [string]::Join([Environment]::NewLine,@($output | ForEach-Object { [string]$_ }))) }
    return @($output | ForEach-Object { [string]$_ })
}

function Get-WorktreeRecords {
    param([Parameter(Mandatory)][string]$Directory)
    $lines = Invoke-GitText -Directory $Directory -Arguments @('worktree','list','--porcelain') -Operation 'list'
    $records = [Collections.Generic.List[object]]::new()
    $record = [ordered]@{ Path = $null; Head = $null; Branch = $null; Bare = $false; Prunable = $false }
    foreach ($line in @($lines + '')) {
        if ([string]::IsNullOrEmpty($line)) {
            if ($record.Path) { $records.Add([pscustomobject]$record) }
            $record = [ordered]@{ Path = $null; Head = $null; Branch = $null; Bare = $false; Prunable = $false }
            continue
        }
        if ($line.StartsWith('worktree ',[StringComparison]::Ordinal)) { $record.Path = $line.Substring(9); continue }
        if ($line.StartsWith('HEAD ',[StringComparison]::Ordinal)) { $record.Head = $line.Substring(5); continue }
        if ($line.StartsWith('branch refs/heads/',[StringComparison]::Ordinal)) { $record.Branch = $line.Substring(18); continue }
        if ($line -ceq 'bare') { $record.Bare = $true; continue }
        if ($line.StartsWith('prunable',[StringComparison]::Ordinal)) { $record.Prunable = $true }
    }
    return $records.ToArray()
}

function Test-SafeRelativeManifestPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    $normalized = $Path.Replace('\','/')
    if ($normalized.StartsWith('/',[StringComparison]::Ordinal) -or $normalized.Contains(':')) { return $false }
    $invalidCharacters = [IO.Path]::GetInvalidFileNameChars()
    $segments = $normalized.Split('/')
    if ($segments.Count -eq 0) { return $false }
    foreach ($segment in $segments) {
        if ([string]::IsNullOrEmpty($segment) -or $segment -in @('.','..') -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) { return $false }
        foreach ($character in $segment.ToCharArray()) {
            if ([char]::IsControl($character) -or $invalidCharacters -contains $character) { return $false }
        }
        $deviceStem = ($segment -split '\.',2)[0]
        if ($deviceStem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³])$') { return $false }
    }
    return $true
}

function Assert-NoReparseAncestors {
    param([Parameter(Mandatory)][string]$Path,[switch]$RequireDirectory,[switch]$RequireFile)
    try { $fullPath = [IO.Path]::GetFullPath($Path) }
    catch { throw 'WORKTREE_AUDIT_PATH_INVALID' }
    if (-not (Test-Path -LiteralPath $fullPath)) { throw 'WORKTREE_AUDIT_PATH_MISSING' }
    if ($RequireDirectory -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) { throw 'WORKTREE_AUDIT_DIRECTORY_REQUIRED' }
    if ($RequireFile -and -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw 'WORKTREE_AUDIT_FILE_REQUIRED' }
    $cursor = $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            try { $attributes = [IO.File]::GetAttributes($cursor) }
            catch { throw 'WORKTREE_AUDIT_PATH_UNVERIFIED' }
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'WORKTREE_AUDIT_REPARSE_PATH' }
        }
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent -or $parent.FullName.Equals($cursor,[StringComparison]::OrdinalIgnoreCase)) { break }
        $cursor = $parent.FullName
    }
    return $fullPath
}

function Get-ManifestIdentity {
    param([string]$WorktreePath,[string[]]$RelativePaths)
    $entries = [Collections.Generic.List[string]]::new()
    $root = [IO.Path]::GetFullPath($WorktreePath)
    $rootPrefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    foreach ($relativePath in $RelativePaths) {
        $normalized = $relativePath.Replace('\','/')
        if (-not (Test-SafeRelativeManifestPath -Path $normalized)) { return $null }
        $segments = $normalized.Split('/')
        $fullPath = $root
        for ($index = 0; $index -lt $segments.Count; $index++) {
            $fullPath = Join-Path $fullPath $segments[$index]
            if (-not (Test-Path -LiteralPath $fullPath)) { return $null }
            try { $attributes = [IO.File]::GetAttributes($fullPath) }
            catch { return $null }
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
            if ($index -lt ($segments.Count - 1) -and ($attributes -band [IO.FileAttributes]::Directory) -eq 0) { return $null }
        }
        $fullPath = [IO.Path]::GetFullPath($fullPath)
        if (-not $fullPath.StartsWith($rootPrefix,[StringComparison]::OrdinalIgnoreCase) -or
            ([IO.File]::GetAttributes($fullPath) -band [IO.FileAttributes]::Directory) -ne 0) { return $null }
        $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $entries.Add($normalized + ' ' + $hash)
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes([string]::Join([string][char]10,$entries))
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [pscustomobject]@{ Size=$bytes.Length; Sha256=([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant() } }
    finally { $sha.Dispose() }
}

function Test-ExactQuarantine {
    param($Record,[string]$RelativeWorktree,[string[]]$StatusLines,$Quarantine)
    if ($RelativeWorktree -cne [string]$Quarantine.relativeWorktree) { return $false }
    if ($Record.Branch -cne [string]$Quarantine.branch -or $Record.Head -cne [string]$Quarantine.head) { return $false }
    if ($StatusLines.Count -ne @($Quarantine.paths).Count) { return $false }
    $actualPaths = [Collections.Generic.List[string]]::new()
    foreach ($line in $StatusLines) {
        if ($line.Length -lt 4 -or $line.Substring(0,3) -cne ' M ') { return $false }
        $actualPaths.Add($line.Substring(3).Replace('\','/'))
    }
    $expectedPaths = @($Quarantine.paths | ForEach-Object { ([string]$_).Replace('\','/') })
    [Array]::Sort($expectedPaths,[StringComparer]::Ordinal)
    $actual = $actualPaths.ToArray()
    [Array]::Sort($actual,[StringComparer]::Ordinal)
    $separator = [string][char]10
    if ([string]::Join($separator,$actual) -cne [string]::Join($separator,$expectedPaths)) { return $false }
    if ($Quarantine.manifestFormat -ne 1 -or [string]$Quarantine.disposition -cne 'read-only-source') { return $false }
    $identity = Get-ManifestIdentity -WorktreePath $Record.Path -RelativePaths $expectedPaths
    return ($null -ne $identity -and $identity.Size -eq $Quarantine.manifestSize -and $identity.Sha256 -ceq [string]$Quarantine.manifestSha256)
}

try {
    $repositoryRootFull = Assert-NoReparseAncestors -Path $RepositoryRoot -RequireDirectory
    $rootOutput = @(Invoke-GitText -Directory $repositoryRootFull -Arguments @('rev-parse','--show-toplevel') -Operation 'resolve-root')
    if ($rootOutput.Count -ne 1) { throw 'WORKTREE_AUDIT_ROOT_AMBIGUOUS' }
    $currentRoot = Assert-NoReparseAncestors -Path ([IO.Path]::GetFullPath($rootOutput[0])) -RequireDirectory
    $bareOutput = @(Invoke-GitText -Directory $currentRoot -Arguments @('rev-parse','--is-bare-repository') -Operation 'verify-worktree')
    if ($bareOutput.Count -ne 1 -or $bareOutput[0] -cne 'false') { throw 'WORKTREE_AUDIT_REQUIRES_LINKED_WORKTREE' }

    $commonOutput = @(Invoke-GitText -Directory $currentRoot -Arguments @('rev-parse','--git-common-dir') -Operation 'resolve-common-dir')
    if ($commonOutput.Count -ne 1) { throw 'WORKTREE_AUDIT_COMMON_DIR_AMBIGUOUS' }
    $commonDir = $commonOutput[0]
    if (-not [IO.Path]::IsPathRooted($commonDir)) { $commonDir = [IO.Path]::GetFullPath((Join-Path $currentRoot $commonDir)) }
    $commonDir = Assert-NoReparseAncestors -Path $commonDir -RequireDirectory

    $records = @(Get-WorktreeRecords -Directory $currentRoot)
    if ($records.Count -eq 0) { throw 'WORKTREE_AUDIT_NO_REGISTERED_WORKTREES' }
    $bareRecord = @($records | Where-Object { $_.Bare } | Select-Object -First 1)
    if ($bareRecord.Count -gt 0) { $adminRoot = [IO.Path]::GetFullPath($bareRecord[0].Path) }
    elseif ([IO.Path]::GetFileName($commonDir.TrimEnd('\','/')) -ceq '.git') { $adminRoot = [IO.Path]::GetDirectoryName($commonDir) }
    else { $adminRoot = $commonDir }
    $adminRoot = Assert-NoReparseAncestors -Path $adminRoot -RequireDirectory

    if ([string]::IsNullOrWhiteSpace($QuarantineConfigPath)) { $QuarantineConfigPath = Join-Path $currentRoot 'config/worktree-quarantine.json' }
    try { $QuarantineConfigPath = [IO.Path]::GetFullPath($QuarantineConfigPath) }
    catch { throw 'WORKTREE_AUDIT_QUARANTINE_CONFIG_PATH_INVALID' }
    $QuarantineConfigPath = Assert-NoReparseAncestors -Path $QuarantineConfigPath -RequireFile
    $config = Get-Content -LiteralPath $QuarantineConfigPath -Raw | ConvertFrom-Json
    if ($config.schemaVersion -ne 1 -or $null -eq $config.quarantines) { throw 'WORKTREE_AUDIT_QUARANTINE_CONFIG_INVALID' }
    foreach ($entry in @($config.quarantines)) {
        if (-not (Test-SafeRelativeManifestPath -Path ([string]$entry.relativeWorktree)) -or
            @($entry.paths).Count -eq 0 -or
            [string]$entry.manifestSha256 -notmatch '^[0-9a-f]{64}$' -or
            [int]$entry.manifestSize -lt 1) {
            throw 'WORKTREE_AUDIT_QUARANTINE_CONFIG_INVALID'
        }
        $seenPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($path in @($entry.paths)) {
            $pathValue = [string]$path
            if (-not (Test-SafeRelativeManifestPath -Path $pathValue) -or -not $seenPaths.Add($pathValue)) {
                throw 'WORKTREE_AUDIT_QUARANTINE_PATH_INVALID'
            }
        }
    }

    $failed = $false
    $registeredTaskPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($record in $records) {
        if (-not $record.Bare) { $null = $registeredTaskPaths.Add([IO.Path]::GetFullPath($record.Path)) }
    }
    $taskDirectoryRoot = Join-Path $adminRoot '.worktrees'
    if (Test-Path -LiteralPath $taskDirectoryRoot -PathType Container) {
        $taskRootAttributes = [IO.File]::GetAttributes($taskDirectoryRoot)
        if (($taskRootAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'WORKTREE_AUDIT_TASK_ROOT_REPARSE_POINT'
        }
        foreach ($directory in [IO.Directory]::EnumerateDirectories($taskDirectoryRoot)) {
            $directoryName = [IO.Path]::GetFileName($directory)
            try { $directoryAttributes = [IO.File]::GetAttributes($directory) }
            catch {
                Write-Output ('BLOCKED: task directory attributes could not be verified: ' + $directoryName + ' (preserved; no cleanup performed)')
                $failed = $true
                continue
            }
            if (($directoryAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Output ('BLOCKED: reparse point in task directory root: ' + $directoryName + ' (preserved; no cleanup performed)')
                $failed = $true
                continue
            }
            if ($directoryName -notmatch '^T-\d{3,}$') {
                Write-Output ('BLOCKED: unexpected physical directory in task directory root: ' + $directoryName + ' (preserved; no cleanup performed)')
                $failed = $true
                continue
            }
            $directoryFullPath = [IO.Path]::GetFullPath($directory)
            if (-not $registeredTaskPaths.Contains($directoryFullPath)) {
                Write-Output ('BLOCKED: unregistered task directory detected: ' + $directoryName + ' (preserved; no cleanup performed)')
                $failed = $true
            }
        }
    }
    foreach ($record in $records) {
        if ($record.Bare) { continue }
        if ($record.Prunable) {
            Write-Output ('BLOCKED: registered worktree missing or prunable: ' + [IO.Path]::GetFileName($record.Path))
            $failed = $true
            continue
        }
        try {
            $treePath = Assert-NoReparseAncestors -Path $record.Path -RequireDirectory
            $registeredAttributes = [IO.File]::GetAttributes($treePath)
        }
        catch {
            Write-Output ('BLOCKED: registered worktree path could not be verified: ' + [IO.Path]::GetFileName($record.Path))
            $failed = $true
            continue
        }
        if (($registeredAttributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Write-Output ('BLOCKED: registered worktree is a reparse point: ' + [IO.Path]::GetFileName($record.Path))
            $failed = $true
            continue
        }
        $treePath = [IO.Path]::GetFullPath($record.Path)
        $bareState = @(Invoke-GitText -Directory $treePath -Arguments @('rev-parse','--is-bare-repository') -Operation 'verify-worktree-kind')
        if ($bareState.Count -eq 1 -and $bareState[0] -ceq 'true') { continue }
        $relativeWorktree = [IO.Path]::GetRelativePath($adminRoot,$treePath).Replace('\','/')
        $isCurrent = $treePath.Equals($currentRoot,[StringComparison]::OrdinalIgnoreCase)
        if ($isCurrent -and $Mode -ceq 'Publish') {
            $branchOutput = @(Invoke-GitText -Directory $treePath -Arguments @('branch','--show-current') -Operation 'resolve-publish-branch')
            if ($branchOutput.Count -ne 1 -or [string]::IsNullOrWhiteSpace($branchOutput[0])) { throw 'WORKTREE_AUDIT_PUBLISH_BRANCH_UNVERIFIED' }
            if ($branchOutput[0] -match '^task/T-013(?:-|$)') {
                Write-Output ('BLOCKED: T-013 is a read-only recovery source and cannot be published: ' + $relativeWorktree)
                $failed = $true
                continue
            }
        }
        if ($relativeWorktree -match '^\.worktrees/T-(?<id>\d{3,})$' -and $record.Branch -notmatch ('^task/T-' + $Matches.id + '(?:-|$)')) {
            Write-Output ('BLOCKED: task branch/worktree ID mismatch: ' + $relativeWorktree)
            $failed = $true
            continue
        }

        $statusLines = @(Invoke-GitText -Directory $treePath -Arguments @('-c','core.quotepath=false','status','--porcelain=v1','--untracked-files=all','--ignore-submodules=none') -Operation 'status')
        $ignoredLines = @(Invoke-GitText -Directory $treePath -Arguments @('-c','core.quotepath=false','status','--porcelain=v1','--ignored=matching','--untracked-files=all','--ignore-submodules=none') -Operation 'ignored-status')
        $visualStudioArtifacts = @($ignoredLines | Where-Object {
            $_.StartsWith('!! ',[StringComparison]::Ordinal) -and $_.Substring(3).Trim('"') -match '(?i)(?:^|[\\/])\.vs(?:[\\/]|["]|$)'
        })
        if ($visualStudioArtifacts.Count -gt 0) {
            Write-Output ('BLOCKED: ignored Visual Studio artifact detected in ' + $relativeWorktree)
            $failed = $true
            continue
        }

        if ($statusLines.Count -eq 0) {
            Write-Output ('CLEAN: ' + $relativeWorktree)
            continue
        }
        $quarantine = @($config.quarantines | Where-Object { [string]$_.relativeWorktree -ceq $relativeWorktree } | Select-Object -First 1)
        $matchesQuarantine = $quarantine.Count -eq 1 -and (Test-ExactQuarantine -Record $record -RelativeWorktree $relativeWorktree -StatusLines $statusLines -Quarantine $quarantine[0])
        if ($matchesQuarantine) {
            if ($isCurrent) {
                Write-Output ('BLOCKED: quarantined source cannot be used as a task worktree: ' + $relativeWorktree)
                $failed = $true
            } else {
                Write-Output ('QUARANTINED_READ_ONLY: ' + $relativeWorktree + ' (exact manifest verified; no cleanup or history action permitted)')
            }
            continue
        }

        if ($isCurrent -and $Mode -ceq 'Commit') {
            $unstagedOrUntracked = @($statusLines | Where-Object {
                if ($_.Length -lt 3) { return $true }
                $xy = $_.Substring(0,2)
                if ($xy -ceq '??') { return $true }
                return ($xy[1] -cne ' ' -or $xy[0] -notin @('A','M','D','R','C'))
            })
            if ($unstagedOrUntracked.Count -eq 0) {
                Write-Output ('STAGED_ONLY: ' + $relativeWorktree)
                continue
            }
        }
        if ($isCurrent -and $Mode -ceq 'Audit') {
            Write-Output ('BLOCKED: current task worktree has uncommitted changes (' + $statusLines.Count + ' paths): ' + $relativeWorktree)
            $failed = $true
            continue
        }
        if ($isCurrent -and $Mode -ceq 'Publish') {
            Write-Output ('BLOCKED: current worktree is not clean (' + $statusLines.Count + ' paths): ' + $relativeWorktree)
            $failed = $true
            continue
        }
        Write-Output ('BLOCKED: registered dirty sibling worktree (' + $statusLines.Count + ' paths): ' + $relativeWorktree)
        $failed = $true
    }

    if ($failed) { Write-Output 'WORKTREE-AUDIT=BLOCKED'; exit 1 }
    if (@($config.quarantines).Count -gt 0) { Write-Output 'WORKTREE-AUDIT=PASS_WITH_RECORDED_QUARANTINE' }
    else { Write-Output 'WORKTREE-AUDIT=PASS' }
    exit 0
}
catch {
    [Console]::Error.WriteLine('WORKTREE-AUDIT=ERROR ' + $_.Exception.Message)
    exit 1
}
