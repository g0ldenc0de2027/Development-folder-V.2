#Requires -Version 7.4
[CmdletBinding()]
param(
    [ValidateSet('Audit','Commit','Publish')]
    [string]$Mode = 'Audit',
    [string]$RepositoryRoot = (Get-Location).Path,
    [string]$QuarantineConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitText {
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$Operation
    )
    # Inherited Git environment can redirect repository discovery, config, or object storage.
    $gitContext = @{}
    foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        $name = [string]$entry.Key
        if (-not $name.StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase)) { continue }
        $gitContext[$name] = $entry.Value
        Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue
    }
    try {
        $output = @(& git -C $Directory @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
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

function Get-ManifestIdentity {
    param([string]$WorktreePath,[string[]]$RelativePaths)
    $entries = [Collections.Generic.List[string]]::new()
    foreach ($relativePath in $RelativePaths) {
        $normalized = $relativePath.Replace('\','/')
        $fullPath = Join-Path $WorktreePath ($normalized.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
        $attributes = [IO.File]::GetAttributes($fullPath)
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $null }
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
    $repositoryRootFull = [IO.Path]::GetFullPath($RepositoryRoot)
    $rootOutput = @(Invoke-GitText -Directory $repositoryRootFull -Arguments @('rev-parse','--show-toplevel') -Operation 'resolve-root')
    if ($rootOutput.Count -ne 1) { throw 'WORKTREE_AUDIT_ROOT_AMBIGUOUS' }
    $currentRoot = [IO.Path]::GetFullPath($rootOutput[0])
    $bareOutput = @(Invoke-GitText -Directory $currentRoot -Arguments @('rev-parse','--is-bare-repository') -Operation 'verify-worktree')
    if ($bareOutput.Count -ne 1 -or $bareOutput[0] -cne 'false') { throw 'WORKTREE_AUDIT_REQUIRES_LINKED_WORKTREE' }

    $commonOutput = @(Invoke-GitText -Directory $currentRoot -Arguments @('rev-parse','--git-common-dir') -Operation 'resolve-common-dir')
    if ($commonOutput.Count -ne 1) { throw 'WORKTREE_AUDIT_COMMON_DIR_AMBIGUOUS' }
    $commonDir = $commonOutput[0]
    if (-not [IO.Path]::IsPathRooted($commonDir)) { $commonDir = [IO.Path]::GetFullPath((Join-Path $currentRoot $commonDir)) }

    $records = @(Get-WorktreeRecords -Directory $currentRoot)
    if ($records.Count -eq 0) { throw 'WORKTREE_AUDIT_NO_REGISTERED_WORKTREES' }
    $bareRecord = @($records | Where-Object { $_.Bare } | Select-Object -First 1)
    if ($bareRecord.Count -gt 0) { $adminRoot = [IO.Path]::GetFullPath($bareRecord[0].Path) }
    elseif ([IO.Path]::GetFileName($commonDir.TrimEnd('\','/')) -ceq '.git') { $adminRoot = [IO.Path]::GetDirectoryName($commonDir) }
    else { $adminRoot = $commonDir }

    if ([string]::IsNullOrWhiteSpace($QuarantineConfigPath)) { $QuarantineConfigPath = Join-Path $currentRoot 'config/worktree-quarantine.json' }
    if (-not (Test-Path -LiteralPath $QuarantineConfigPath -PathType Leaf)) { throw 'WORKTREE_AUDIT_QUARANTINE_CONFIG_MISSING' }
    $config = Get-Content -LiteralPath $QuarantineConfigPath -Raw | ConvertFrom-Json
    if ($config.schemaVersion -ne 1 -or $null -eq $config.quarantines) { throw 'WORKTREE_AUDIT_QUARANTINE_CONFIG_INVALID' }

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
            if ($directoryName -notmatch '^T-\d{3}$') { continue }
            $directoryFullPath = [IO.Path]::GetFullPath($directory)
            if (-not $registeredTaskPaths.Contains($directoryFullPath)) {
                Write-Output ('BLOCKED: unregistered task directory detected: ' + $directoryName + ' (preserved; no cleanup performed)')
                $failed = $true
            }
        }
    }
    foreach ($record in $records) {
        if ($record.Bare) { continue }
        if ($record.Prunable -or -not (Test-Path -LiteralPath $record.Path -PathType Container)) {
            Write-Output ('BLOCKED: registered worktree missing or prunable: ' + [IO.Path]::GetFileName($record.Path))
            $failed = $true
            continue
        }
        $treePath = [IO.Path]::GetFullPath($record.Path)
        $bareState = @(Invoke-GitText -Directory $treePath -Arguments @('rev-parse','--is-bare-repository') -Operation 'verify-worktree-kind')
        if ($bareState.Count -eq 1 -and $bareState[0] -ceq 'true') { continue }
        $relativeWorktree = [IO.Path]::GetRelativePath($adminRoot,$treePath).Replace('\','/')
        $isCurrent = $treePath.Equals($currentRoot,[StringComparison]::OrdinalIgnoreCase)
        if ($relativeWorktree -match '^\.worktrees/T-(?<id>\d{3})$' -and $record.Branch -notmatch ('^task/T-' + $Matches.id + '(?:-|$)')) {
            Write-Output ('BLOCKED: task branch/worktree ID mismatch: ' + $relativeWorktree)
            $failed = $true
            continue
        }

        $statusLines = @(Invoke-GitText -Directory $treePath -Arguments @('status','--porcelain=v1','--untracked-files=all','--ignore-submodules=none') -Operation 'status')
        $ignoredLines = @(Invoke-GitText -Directory $treePath -Arguments @('status','--porcelain=v1','--ignored=matching','--untracked-files=all','--ignore-submodules=none') -Operation 'ignored-status')
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
        Write-Output ('BLOCKED: unregistered dirty worktree (' + $statusLines.Count + ' paths): ' + $relativeWorktree)
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
