#Requires -Version 7.4
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$root = [IO.Path]::GetFullPath($TempRoot)
[IO.Directory]::CreateDirectory($root) | Out-Null
$scratch = Join-Path $root ('Проверка-worktree-Git-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($scratch) | Out-Null
$admin = Join-Path $scratch 'admin'
$seed = Join-Path $scratch 'seed'
$remote = Join-Path $scratch 'remote.git'
$mainTree = Join-Path $admin '.worktrees/T-018'
$registeredMainTree = Join-Path $admin '.worktrees/main'
$quarantineTree = Join-Path $admin '.worktrees/T-013'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/task-worktree-audit.ps1'
$hooksPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.githooks'
$configPath = Join-Path $scratch 'quarantine.json'
$repoRoot = Split-Path $PSScriptRoot -Parent
$utf8 = [Text.UTF8Encoding]::new($false)
$fixtureEmptyConfig = Join-Path $scratch 'fixture-empty.config'
[IO.File]::WriteAllText($fixtureEmptyConfig,"# Isolated regression fixture config.`n",$utf8)
$passed = 0

function Invoke-Git {
    param([string]$Directory,[string[]]$Arguments)
    $git = (Get-Command git -ErrorAction Stop).Source
    $result = Invoke-NativeProcess $git (@('-C',$Directory) + $Arguments)
    if ($result.ExitCode -ne 0) {
        $details = [string]::Join([Environment]::NewLine,@($result.Output,$result.Error | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }))
        throw ('TASK_WORKTREE_FIXTURE_GIT_FAILED:' + ($Arguments -join ' ') + [Environment]::NewLine + $details)
    }
    return $result.Output.Trim()
}
function Write-Text([string]$Path,[string]$Text) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    [IO.File]::WriteAllText($Path,$Text,$utf8)
}
function Invoke-NativeProcess([string]$Executable,[string[]]$Arguments,[switch]$PreserveGitContext,[switch]$HookProcess,[string]$WorkingDirectory) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) { $start.WorkingDirectory = $WorkingDirectory }
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    if (-not $PreserveGitContext) {
        foreach ($name in @($start.Environment.Keys | Where-Object { ([string]$_).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) })) {
            $null = $start.Environment.Remove([string]$name)
        }
    }
    if (-not $HookProcess) {
        $start.Environment['GIT_CONFIG_NOSYSTEM'] = '1'
        $start.Environment['GIT_CONFIG_GLOBAL'] = $fixtureEmptyConfig
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode=$process.ExitCode; Output=$stdoutTask.Result; Error=$stderrTask.Result }
}
function Invoke-Audit([string]$Mode='Audit',[string]$RepositoryRoot=$mainTree) {
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    return Invoke-NativeProcess $pwsh @('-NoLogo','-NoProfile','-File',$scriptPath,'-Mode',$Mode,'-RepositoryRoot',$RepositoryRoot,'-QuarantineConfigPath',$configPath) -PreserveGitContext
}
function Assert-AuditExit([int]$Expected,[string]$Label) {
    $result = Invoke-Audit
    if ($result.ExitCode -ne $Expected) { throw ($Label + ': expected exit ' + $Expected + ', got ' + $result.ExitCode + '; ' + $result.Output + $result.Error) }
    return $result
}
function Write-QuarantineConfig([string]$Path,[string]$Head,[string]$Content,[string]$RelativePath='README.md') {
    $relative = $RelativePath
    $file = Join-Path $Path $relative
    Write-Text $file $Content
    $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [Text.UTF8Encoding]::new($false).GetBytes($relative + ' ' + $hash)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $digest = ([Convert]::ToHexString($sha.ComputeHash($manifest))).ToLowerInvariant() }
    finally { $sha.Dispose() }
    $record = @{
        id='T-013'; relativeWorktree='.worktrees/T-013'; branch='task/T-013-agent-orchestration-research'; head=$Head
        manifestFormat=1; manifestSize=$manifest.Length; manifestSha256=$digest; paths=@($relative); disposition='read-only-source'
    }
    $json = @{schemaVersion=1;quarantines=@($record)} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configPath,$json,$utf8)
    return $Content
}
function Case([string]$Name,[scriptblock]$Action) {
    & $Action
    $script:passed++
    Write-Output ('PASS: ' + $Name)
}

try {
    Invoke-Git $scratch @('init','--bare','--quiet',$admin) | Out-Null
    Invoke-Git $scratch @('init','--bare','--quiet',$remote) | Out-Null
    Invoke-Git $scratch @('init','--quiet',$seed) | Out-Null
    Invoke-Git $seed @('config','user.name','Synthetic Fixture') | Out-Null
    Invoke-Git $seed @('config','user.email','fixture@example.invalid') | Out-Null
    Write-Text (Join-Path $seed '.gitignore') ('.worktrees/' + [Environment]::NewLine)
    Write-Text (Join-Path $seed 'README.md') ('base' + [Environment]::NewLine)
    Write-Text (Join-Path $seed 'данные/снимок.txt') ('baseline' + [Environment]::NewLine)
    Write-Text (Join-Path $seed 'config/worktree-quarantine.json') '{"schemaVersion":1,"quarantines":[]}'
    Copy-Item -LiteralPath (Join-Path $repoRoot 'config/git-empty.config') -Destination (Join-Path $seed 'config/git-empty.config')

    Invoke-Git $seed @('add','.') | Out-Null
    Invoke-Git $seed @('commit','--quiet','-m','test: seed lifecycle fixture') | Out-Null
    Invoke-Git $seed @('branch','-M','main') | Out-Null
    Invoke-Git $seed @('remote','add','admin',$admin) | Out-Null
    Invoke-Git $seed @('push','--quiet','admin','main') | Out-Null
    Invoke-Git $seed @('remote','add','target',$remote) | Out-Null
    Invoke-Git $seed @('push','--quiet','target','main') | Out-Null
    Invoke-Git $admin @('symbolic-ref','HEAD','refs/heads/main') | Out-Null
    Invoke-Git $admin @('config','extensions.worktreeConfig','true') | Out-Null
    Invoke-Git $admin @('config','user.name','Synthetic Fixture') | Out-Null
    Invoke-Git $admin @('config','user.email','fixture@example.invalid') | Out-Null
    Invoke-Git $admin @('remote','add','origin',$remote) | Out-Null
    [IO.Directory]::CreateDirectory((Split-Path $mainTree -Parent)) | Out-Null
    Invoke-Git $admin @('worktree','add','--quiet','-b','task/T-018-worktree-guard',$mainTree,'main') | Out-Null
    Invoke-Git $mainTree @('config','--worktree','core.bare','false') | Out-Null
    [IO.Directory]::CreateDirectory((Split-Path $quarantineTree -Parent)) | Out-Null
    Invoke-Git $admin @('worktree','add','--quiet','-b','task/T-013-agent-orchestration-research',$quarantineTree,'main') | Out-Null
    Invoke-Git $quarantineTree @('config','--worktree','core.bare','false') | Out-Null
    Invoke-Git $admin @('worktree','add','--quiet',$registeredMainTree,'main') | Out-Null
    Invoke-Git $registeredMainTree @('config','--worktree','core.bare','false') | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $mainTree 'scripts')) | Out-Null
    Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $mainTree 'scripts/task-worktree-audit.ps1')
    Invoke-Git $mainTree @('add','scripts/task-worktree-audit.ps1') | Out-Null
    Invoke-Git $mainTree @('commit','--quiet','-m','test: add audit script fixture') | Out-Null
    $emptyConfig = @{schemaVersion=1;quarantines=@()} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configPath,$emptyConfig,$utf8)

    Case 'production quarantine registry remains empty' {
        $productionConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config/worktree-quarantine.json') -Raw | ConvertFrom-Json
        if ($productionConfig.schemaVersion -ne 1 -or @($productionConfig.quarantines).Count -ne 0) { throw 'PRODUCTION_QUARANTINE_REGISTRY_MUST_BE_EMPTY' }
    }
    Case 'clean registered worktrees and registered main directory pass audit' {
        $result = Assert-AuditExit 0 'CLEAN_AUDIT'
        if ($result.Output -notmatch 'WORKTREE-AUDIT=PASS') { throw 'CLEAN_AUDIT_MARKER_MISSING' }

        Invoke-Git $admin @('worktree','remove','--force',$registeredMainTree) | Out-Null
        [IO.Directory]::CreateDirectory($registeredMainTree) | Out-Null
        $preserved = Join-Path $registeredMainTree 'preserve.txt'
        Write-Text $preserved 'synthetic unregistered main directory'
        try {
            $result = Assert-AuditExit 1 'UNREGISTERED_MAIN_DIRECTORY_AUDIT'
            if ($result.Output -notmatch 'unexpected physical directory in task directory root: main') { throw 'UNREGISTERED_MAIN_DIRECTORY_REASON_MISSING' }
            if (-not (Test-Path -LiteralPath $preserved -PathType Leaf)) { throw 'UNREGISTERED_MAIN_DIRECTORY_DATA_CHANGED' }
        }
        finally {
            $worktreesRoot = [IO.Path]::GetFullPath((Join-Path $admin '.worktrees')).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
            $registeredMainFullPath = [IO.Path]::GetFullPath($registeredMainTree)
            if (-not $registeredMainFullPath.StartsWith($worktreesRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'REGISTERED_MAIN_FIXTURE_PATH_INVALID' }
            if (Test-Path -LiteralPath $registeredMainFullPath) { Remove-Item -LiteralPath $registeredMainFullPath -Recurse -Force }
            Invoke-Git $admin @('worktree','add','--quiet',$registeredMainTree,'main') | Out-Null
            Invoke-Git $registeredMainTree @('config','--worktree','core.bare','false') | Out-Null
        }
    }
    Case 'audit subprocess isolates system and global Git config' {
        $poison = Join-Path $scratch 'invalid-git.config'
        Write-Text $poison '[unterminated'
        $names = @('GIT_CONFIG_GLOBAL','GIT_CONFIG_SYSTEM','GIT_CONFIG_NOSYSTEM')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        try {
            foreach ($setting in @('GIT_CONFIG_GLOBAL','GIT_CONFIG_SYSTEM')) {
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL',$fixtureEmptyConfig,'Process')
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_SYSTEM',$fixtureEmptyConfig,'Process')
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM',$null,'Process')
                [Environment]::SetEnvironmentVariable($setting,$poison,'Process')
                $control = Invoke-NativeProcess 'git' @('-C',$mainTree,'status','--porcelain') -PreserveGitContext -HookProcess
                if ($control.ExitCode -eq 0 -or $control.Error -notmatch [regex]::Escape([IO.Path]::GetFileName($poison))) {
                    throw "AUDIT_CONFIG_CONTROL_DID_NOT_FAIL: $setting"
                }
                $argsList = @('-NoLogo','-NoProfile','-File',$scriptPath,'-Mode','Audit',
                    '-RepositoryRoot',$mainTree,'-QuarantineConfigPath',$configPath)
                $result = Invoke-NativeProcess (Get-Command pwsh -ErrorAction Stop).Source $argsList -PreserveGitContext -HookProcess
                if ($result.ExitCode -ne 0 -or $result.Output -notmatch 'WORKTREE-AUDIT=PASS') {
                    throw "AUDIT_CONFIG_ISOLATION_FAILED: $setting; $($result.Output)$($result.Error)"
                }
            }
        } finally {
            foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
        }

        # Structural checks for independent controls, pending their own behavioral fixtures.
        $auditSource = [IO.File]::ReadAllText($scriptPath)
        if ($auditSource -notmatch "--no-pager") { throw 'AUDIT_PAGER_ISOLATION_MISSING' }
        if ($auditSource -notmatch "--no-optional-locks") { throw 'AUDIT_OPTIONAL_LOCK_ISOLATION_MISSING' }
        if ($auditSource -notmatch "'-c','core\.fsmonitor=false'") { throw 'AUDIT_REPOSITORY_FSMONITOR_ISOLATION_MISSING' }
        foreach ($required in @(
            'function Assert-NoReparseAncestors',
            '$repositoryRootFull = Assert-NoReparseAncestors',
            '$currentRoot = Assert-NoReparseAncestors',
            '$commonDir = Assert-NoReparseAncestors',
            '$adminRoot = Assert-NoReparseAncestors',
            '$QuarantineConfigPath = Assert-NoReparseAncestors',
            '$treePath = Assert-NoReparseAncestors'
        )) {
            if (-not $auditSource.Contains($required)) { throw ('AUDIT_REPARSE_GUARD_MISSING:' + $required) }
        }
    }
    Case 'audit never executes repository-local fsmonitor commands' {
        $marker = Join-Path $scratch 'local-fsmonitor-ran.txt'
        $hookScript = Join-Path $scratch 'local-fsmonitor.ps1'
        $markerLiteral = $marker.Replace("'","''")
        $hookText = "[IO.File]::WriteAllText('$markerLiteral','invoked')" + [Environment]::NewLine + "'0'" + [Environment]::NewLine + "''" + [Environment]::NewLine
        Write-Text $hookScript $hookText
        $hookCommand = 'pwsh -NoLogo -NoProfile -File "' + $hookScript + '"'
        Invoke-Git $mainTree @('config','--worktree','core.fsmonitor',$hookCommand) | Out-Null
        $result = Invoke-Audit
        if ($result.ExitCode -ne 0 -or $result.Output -notmatch 'WORKTREE-AUDIT=PASS') {
            throw ('LOCAL_FSMONITOR_AUDIT_FAILED:' + $result.Output + $result.Error)
        }
        if (Test-Path -LiteralPath $marker) { throw 'AUDIT_EXECUTED_REPOSITORY_LOCAL_FSMONITOR' }
        Invoke-Git $mainTree @('config','--worktree','--unset-all','core.fsmonitor') | Out-Null
    }
    Case 'quarantine registry rejects rooted and traversal paths' {
        $head = Invoke-Git $quarantineTree @('rev-parse','HEAD')
        foreach ($unsafePath in @('../outside.txt',(Join-Path $scratch 'outside.txt'))) {
            $record = @{
                id='T-013'; relativeWorktree='.worktrees/T-013'; branch='task/T-013-agent-orchestration-research'; head=$head
                manifestFormat=1; manifestSize=1; manifestSha256=('0' * 64); paths=@($unsafePath); disposition='read-only-source'
            }
            $json = @{schemaVersion=1;quarantines=@($record)} | ConvertTo-Json -Depth 5
            [IO.File]::WriteAllText($configPath,$json,$utf8)
            $result = Invoke-Audit
            $details = [string]::Join([Environment]::NewLine,@($result.Output,$result.Error))
            if ($result.ExitCode -eq 0 -or $details -notmatch 'WORKTREE_AUDIT_QUARANTINE_PATH_INVALID') {
                throw ('UNSAFE_QUARANTINE_PATH_ACCEPTED:' + $unsafePath + ':' + $details)
            }
        }
        [IO.File]::WriteAllText($configPath,$emptyConfig,$utf8)
    }
    Case 'audit defaults root to script location from unrelated working directory' {
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
        $fixtureScript = Join-Path $mainTree 'scripts/task-worktree-audit.ps1'
        $result = Invoke-NativeProcess $pwsh @('-NoLogo','-NoProfile','-File',$fixtureScript,'-Mode','Audit') -PreserveGitContext -WorkingDirectory $scratch
        if ($result.ExitCode -ne 0) { throw ('SCRIPT_ROOT_DEFAULT_FAILED: ' + $result.Output + $result.Error) }
        if ($result.Output -notmatch 'WORKTREE-AUDIT=PASS') { throw ('SCRIPT_ROOT_DEFAULT_MARKER_MISSING: ' + $result.Output + $result.Error) }
        Invoke-Git $mainTree @('rm','--quiet','scripts/task-worktree-audit.ps1') | Out-Null
        Invoke-Git $mainTree @('commit','--quiet','-m','test: remove audit script fixture') | Out-Null
    }
    Case 'missing registered worktree blocks without deleting its data' {
        $parked = Join-Path $scratch 'parked-quarantine-worktree'
        Move-Item -LiteralPath $quarantineTree -Destination $parked
        try {
            $result = Assert-AuditExit 1 'MISSING_WORKTREE_AUDIT'
            if ($result.Output -notmatch 'registered worktree missing or prunable') { throw 'MISSING_WORKTREE_REASON_MISSING' }
            if (-not (Test-Path -LiteralPath (Join-Path $parked 'README.md') -PathType Leaf)) { throw 'MISSING_WORKTREE_DATA_CHANGED' }
        }
        finally { if (Test-Path -LiteralPath $parked -PathType Container) { Move-Item -LiteralPath $parked -Destination $quarantineTree } }
    }
    Case 'task directory without Git registration blocks admission' {
        $orphan = Join-Path $admin '.worktrees/T-019'
        [IO.Directory]::CreateDirectory($orphan) | Out-Null
        Write-Text (Join-Path $orphan 'preserve.txt') 'synthetic orphan'
        try {
            $result = Assert-AuditExit 1 'ORPHAN_WORKTREE_AUDIT'
            if ($result.Output -notmatch 'unregistered task directory detected: T-019') { throw 'ORPHAN_WORKTREE_REASON_MISSING' }
            if (-not (Test-Path -LiteralPath (Join-Path $orphan 'preserve.txt') -PathType Leaf)) { throw 'ORPHAN_WORKTREE_DATA_CHANGED' }
        }
        finally { if (Test-Path -LiteralPath $orphan -PathType Container) { Remove-Item -LiteralPath $orphan -Recurse -Force } }
    }
    Case 'unexpected and extended physical task directories are blocked without cleanup' {
        foreach ($name in @('T-019-extra','scratch','T-1000','t-020')) {
            $orphan = Join-Path (Join-Path $admin '.worktrees') $name
            [IO.Directory]::CreateDirectory($orphan) | Out-Null
            Write-Text (Join-Path $orphan 'preserve.txt') 'synthetic orphan'
            try {
                $result = Assert-AuditExit 1 ('UNEXPECTED_DIRECTORY_AUDIT_' + $name)
                $expected = if ($name -match '^T-\d{3,}$') { 'unregistered task directory detected' } else { 'unexpected physical directory in task directory root' }
                if ($result.Output -notmatch [regex]::Escape($expected)) { throw ('UNEXPECTED_DIRECTORY_REASON_MISSING:' + $name) }
                if (-not (Test-Path -LiteralPath (Join-Path $orphan 'preserve.txt') -PathType Leaf)) { throw ('UNEXPECTED_DIRECTORY_DATA_CHANGED:' + $name) }
            }
            finally { if (Test-Path -LiteralPath $orphan -PathType Container) { Remove-Item -LiteralPath $orphan -Recurse -Force } }
        }
    }
    Case 'task directory and branch IDs must match' {
        Invoke-Git $mainTree @('branch','-m','task/T-019-worktree-mismatch') | Out-Null
        try {
            $result = Assert-AuditExit 1 'TASK_ID_MISMATCH_AUDIT'
            if ($result.Output -notmatch 'task branch/worktree ID mismatch') { throw 'TASK_ID_MISMATCH_REASON_MISSING' }
        }
        finally { Invoke-Git $mainTree @('branch','-m','task/T-018-worktree-guard') | Out-Null }
    }
    Case 'fixture Git commands ignore inherited hook context' {
        $gitDir = Invoke-Git $mainTree @('rev-parse','--absolute-git-dir')
        $commonDir = Invoke-Git $mainTree @('rev-parse','--git-common-dir')
        if (-not [IO.Path]::IsPathRooted($commonDir)) { $commonDir = [IO.Path]::GetFullPath((Join-Path $mainTree $commonDir)) }
        $names = @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_COMMON_DIR','GIT_PREFIX','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0')
        $saved = @{}
        foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
        try {
            [Environment]::SetEnvironmentVariable('GIT_DIR',$gitDir,'Process')
            [Environment]::SetEnvironmentVariable('GIT_WORK_TREE',$mainTree,'Process')
            [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',(Join-Path $gitDir 'index'),'Process')
            [Environment]::SetEnvironmentVariable('GIT_COMMON_DIR',$commonDir,'Process')
            [Environment]::SetEnvironmentVariable('GIT_PREFIX','hook-prefix/','Process')
            [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT','1','Process')
            [Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0','core.bare','Process')
            [Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0','true','Process')
            if ((Invoke-Git $mainTree @('rev-parse','--is-bare-repository')) -cne 'false') { throw 'FIXTURE_GIT_CONFIG_WAS_NOT_ISOLATED' }
            Invoke-Git $seed @('remote','add','fixture-isolation',$remote) | Out-Null
            if ((Invoke-Git $seed @('remote','get-url','fixture-isolation')) -ne $remote) { throw 'FIXTURE_GIT_CONTEXT_WAS_NOT_ISOLATED' }
            if ((Invoke-Git $admin @('remote')) -contains 'fixture-isolation') { throw 'FIXTURE_GIT_CONTEXT_MUTATED_SIBLING' }
            Invoke-Git $seed @('remote','remove','fixture-isolation') | Out-Null
        }
        finally {
            foreach ($name in $names) {
                if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
                else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
            }
        }
    }
    Case 'tracked modifications block task admission' {
        Write-Text (Join-Path $mainTree 'README.md') ('modified' + [Environment]::NewLine)
        $result = Assert-AuditExit 1 'TRACKED_DIRTY_AUDIT'
        if ($result.Output -notmatch 'BLOCKED: current task worktree') { throw 'TRACKED_DIRTY_REASON_MISSING' }
        Write-Text (Join-Path $mainTree 'README.md') ('base' + [Environment]::NewLine)
    }
    Case 'untracked files block task admission' {
        Write-Text (Join-Path $mainTree 'untracked.txt') 'synthetic'
        $result = Assert-AuditExit 1 'UNTRACKED_AUDIT'
        if ($result.Output -notmatch 'BLOCKED: current task worktree') { throw 'UNTRACKED_REASON_MISSING' }
        Remove-Item -LiteralPath (Join-Path $mainTree 'untracked.txt') -Force
    }
    Case 'ignored Visual Studio artifacts block task admission' {
        Write-Text (Join-Path $admin 'info/exclude') ('.vs/' + [Environment]::NewLine)
        Write-Text (Join-Path $mainTree '.vs/ProjectSettings.json') '{}'
        $result = Assert-AuditExit 1 'IGNORED_VS_AUDIT'
        if ($result.Output -notmatch 'ignored Visual Studio artifact') { throw 'IGNORED_VS_REASON_MISSING' }
        Remove-Item -LiteralPath (Join-Path $mainTree '.vs') -Recurse -Force
    }
    Case 'exact quarantine snapshot is detected as read-only' {
        $head = Invoke-Git $quarantineTree @('rev-parse','HEAD')
        $null = Write-QuarantineConfig -Path $quarantineTree -Head $head -Content ('quarantined' + [Environment]::NewLine)
        $result = Assert-AuditExit 0 'EXACT_QUARANTINE_AUDIT'
        if ($result.Output -notmatch 'QUARANTINED_READ_ONLY') { throw 'QUARANTINE_MARKER_MISSING' }
    }
    Case 'changed quarantine fingerprint blocks admission' {
        Write-Text (Join-Path $quarantineTree 'README.md') ('changed-after-quarantine' + [Environment]::NewLine)
        $result = Assert-AuditExit 1 'CHANGED_QUARANTINE_AUDIT'
        if ($result.Output -notmatch 'BLOCKED: registered dirty sibling worktree') { throw 'CHANGED_QUARANTINE_REASON_MISSING' }
        $null = Write-QuarantineConfig -Path $quarantineTree -Head (Invoke-Git $quarantineTree @('rev-parse','HEAD')) -Content ('quarantined' + [Environment]::NewLine)
    }
    Case 'commit mode permits staged changes but publish mode blocks them' {
        Write-Text (Join-Path $mainTree 'README.md') ('staged' + [Environment]::NewLine)
        Invoke-Git $mainTree @('add','README.md') | Out-Null
        $commit = Invoke-Audit -Mode 'Commit'
        if ($commit.ExitCode -ne 0 -or $commit.Output -notmatch 'STAGED_ONLY') { throw ('STAGED_COMMIT_MODE_FAILED:' + $commit.Output + $commit.Error) }

        Case 'hook Git environment is isolated when checking sibling worktrees' {
            $gitDir = Invoke-Git $mainTree @('rev-parse','--absolute-git-dir')
            $commonDir = Invoke-Git $mainTree @('rev-parse','--git-common-dir')
            if (-not [IO.Path]::IsPathRooted($commonDir)) { $commonDir = [IO.Path]::GetFullPath((Join-Path $mainTree $commonDir)) }
            $names = @('GIT_DIR','GIT_WORK_TREE','GIT_INDEX_FILE','GIT_COMMON_DIR','GIT_PREFIX','GIT_CONFIG_COUNT','GIT_CONFIG_KEY_0','GIT_CONFIG_VALUE_0')
            $saved = @{}
            foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name,'Process') }
            try {
                [Environment]::SetEnvironmentVariable('GIT_DIR',$gitDir,'Process')
                [Environment]::SetEnvironmentVariable('GIT_WORK_TREE',$mainTree,'Process')
                [Environment]::SetEnvironmentVariable('GIT_INDEX_FILE',(Join-Path $gitDir 'index'),'Process')
                [Environment]::SetEnvironmentVariable('GIT_COMMON_DIR',$commonDir,'Process')
                [Environment]::SetEnvironmentVariable('GIT_PREFIX','hook-prefix/','Process')
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_COUNT','1','Process')
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_KEY_0','core.bare','Process')
                [Environment]::SetEnvironmentVariable('GIT_CONFIG_VALUE_0','true','Process')
                $hookAudit = Invoke-Audit -Mode 'Commit'
                if ($hookAudit.ExitCode -ne 0 -or $hookAudit.Output -notmatch 'STAGED_ONLY') { throw ('HOOK_GIT_CONTEXT_LEAKED:' + $hookAudit.Output + $hookAudit.Error) }
            }
            finally {
                foreach ($name in $names) { if ($null -eq $saved[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') } }
            }
        }

        $publish = Invoke-Audit -Mode 'Publish'
        if ($publish.ExitCode -eq 0) { throw 'PUBLISH_ACCEPTED_STAGED_RESIDUE' }
        Invoke-Git $mainTree @('reset','--quiet','HEAD','--','README.md') | Out-Null
        Write-Text (Join-Path $mainTree 'README.md') ('base' + [Environment]::NewLine)
    }
    Case 'pre-commit hook refuses to commit the quarantined T-013 branch' {
        $fixtureScripts = Join-Path $quarantineTree 'scripts'
        $fixtureGitIdentity = Join-Path $fixtureScripts 'lib'
        $fixtureGithub = Join-Path $quarantineTree 'config/github'
        [IO.Directory]::CreateDirectory($fixtureGitIdentity) | Out-Null
        [IO.Directory]::CreateDirectory($fixtureGithub) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/verify-git-hook-context.ps1') -Destination (Join-Path $fixtureScripts 'verify-git-hook-context.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/lib/GitIdentity.psm1') -Destination (Join-Path $fixtureGitIdentity 'GitIdentity.psm1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Destination (Join-Path $fixtureGithub 'repository.json')
        Invoke-Git $admin @('config','core.hooksPath',$hooksPath) | Out-Null
        $repoPolicy = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json
        $policyLogin = [string]$repoPolicy.commitIdentity.login
        $policyEmail = [string]$repoPolicy.commitIdentity.userId + '+' + $policyLogin + '@users.noreply.github.com'
        Invoke-Git $quarantineTree @('config','--worktree','user.name',$policyLogin) | Out-Null
        Invoke-Git $quarantineTree @('config','--worktree','user.email',$policyEmail) | Out-Null
        Write-Text (Join-Path $quarantineTree 'README.md') ('staged-forbidden' + [Environment]::NewLine)
        Invoke-Git $quarantineTree @('add','README.md') | Out-Null
        $git = (Get-Command git -ErrorAction Stop).Source
        $result = Invoke-NativeProcess $git @('-C',$quarantineTree,'commit','-m','test: must be blocked') -HookProcess
        $hookText = [string]::Join([Environment]::NewLine,@($result.Output,$result.Error))
        if ($result.ExitCode -eq 0 -or $hookText -notmatch 'T-013 is a read-only recovery source') { throw ('T013_PRECOMMIT_GUARD_FAILED:' + $hookText) }
        Invoke-Git $quarantineTree @('reset','--quiet','HEAD','--','README.md') | Out-Null
        Remove-Item -LiteralPath (Join-Path $fixtureScripts 'verify-git-hook-context.ps1') -Force
        Remove-Item -LiteralPath (Join-Path $fixtureGitIdentity 'GitIdentity.psm1') -Force
        Remove-Item -LiteralPath (Join-Path $fixtureGithub 'repository.json') -Force
        Remove-Item -LiteralPath $fixtureGitIdentity -Force
        Remove-Item -LiteralPath $fixtureScripts -Force
        Remove-Item -LiteralPath $fixtureGithub -Force
        $null = Write-QuarantineConfig -Path $quarantineTree -Head (Invoke-Git $quarantineTree @('rev-parse','HEAD')) -Content ('quarantined' + [Environment]::NewLine)
    }
    Case 'publish mode refuses the quarantined T-013 recovery branch' {
        $result = Invoke-Audit -Mode 'Publish' -RepositoryRoot $quarantineTree
        if ($result.ExitCode -eq 0 -or $result.Output -notmatch 'T-013 is a read-only recovery source and cannot be published') {
            throw ('T013_PUBLISH_GUARD_FAILED:' + $result.Output + $result.Error)
        }
    }
    Case 'dirty sibling worktree blocks publish mode while exact quarantine remains allowed' {
        Remove-Item -LiteralPath (Join-Path $mainTree 'leftover.txt') -Force -ErrorAction SilentlyContinue
        $clean = Invoke-Audit -Mode 'Publish'
        if ($clean.ExitCode -ne 0 -or $clean.Output -notmatch 'QUARANTINED_READ_ONLY') { throw ('EXACT_QUARANTINE_PUBLISH_FAILED:' + $clean.Output + $clean.Error) }
        Write-Text (Join-Path $quarantineTree 'README.md') ('changed-after-recording' + [Environment]::NewLine)
        $dirty = Invoke-Audit -Mode 'Publish'
        if ($dirty.ExitCode -eq 0 -or $dirty.Output -notmatch 'BLOCKED: registered dirty sibling worktree') { throw ('DIRTY_SIBLING_PUBLISH_NOT_BLOCKED:' + $dirty.Output + $dirty.Error) }
        $null = Write-QuarantineConfig -Path $quarantineTree -Head (Invoke-Git $quarantineTree @('rev-parse','HEAD')) -Content ('quarantined' + [Environment]::NewLine)
    }
    Case 'commit and publish hooks invoke the global worktree audit' {
        $preCommitText = [IO.File]::ReadAllText((Join-Path $hooksPath 'pre-commit'))
        $prePushText = [IO.File]::ReadAllText((Join-Path $hooksPath 'pre-push'))
        if ($preCommitText -notmatch 'task-worktree-audit\.ps1.*-Mode Commit') { throw 'PRECOMMIT_AUDIT_WIRING_MISSING' }
        if ($prePushText -notmatch 'task-worktree-audit\.ps1.*-Mode Publish') { throw 'PREPUSH_AUDIT_WIRING_MISSING' }
    }
    Case 'non-ASCII quarantine paths match exact Git status' {
        $relative = 'данные/снимок.txt'
        Write-Text (Join-Path $quarantineTree 'README.md') ('base' + [Environment]::NewLine)
        Write-Text (Join-Path $quarantineTree $relative) ('quarantined unicode path' + [Environment]::NewLine)
        Invoke-Git $quarantineTree @('config','--worktree','core.quotepath','true') | Out-Null
        $head = Invoke-Git $quarantineTree @('rev-parse','HEAD')
        $null = Write-QuarantineConfig -Path $quarantineTree -Head $head -Content ('quarantined unicode path' + [Environment]::NewLine) -RelativePath $relative
        $result = Assert-AuditExit 0 'UNICODE_QUARANTINE_AUDIT'
        if ($result.Output -notmatch 'QUARANTINED_READ_ONLY') { throw ('UNICODE_QUARANTINE_MARKER_MISSING:' + $result.Output + $result.Error) }
    }
    Case 'real pre-commit hook validates commit indexes and repairs identity in bare admin' {
        $testTree = Join-Path $admin '.worktrees/T-019'
        $testBase = Invoke-Git $mainTree @('rev-parse','HEAD')
        Invoke-Git $admin @('worktree','add','--quiet','-b','task/T-019',$testTree,$testBase) | Out-Null
        Invoke-Git $testTree @('config','--worktree','core.bare','false') | Out-Null
        Invoke-Git $admin @('config','core.hooksPath',$hooksPath) | Out-Null

        $testScripts = Join-Path $testTree 'scripts'
        $testLib = Join-Path $testScripts 'lib'
        $testGithub = Join-Path $testTree 'config/github'
        $testGithubScripts = Join-Path $testScripts 'github'
        $testConfig = Join-Path $testTree 'config'
        $testHooks = Join-Path $testTree '.githooks'
        [IO.Directory]::CreateDirectory($testLib) | Out-Null
        [IO.Directory]::CreateDirectory($testGithub) | Out-Null
        [IO.Directory]::CreateDirectory($testGithubScripts) | Out-Null
        [IO.Directory]::CreateDirectory($testHooks) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot '.githooks/pre-commit') -Destination (Join-Path $testHooks 'pre-commit')
        Copy-Item -LiteralPath (Join-Path $repoRoot '.githooks/pre-push') -Destination (Join-Path $testHooks 'pre-push')
        Copy-Item -LiteralPath $scriptPath -Destination (Join-Path $testScripts 'task-worktree-audit.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/verify-git-hook-context.ps1') -Destination (Join-Path $testScripts 'verify-git-hook-context.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/verify-git-identity.ps1') -Destination (Join-Path $testScripts 'verify-git-identity.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/github/configure-local.ps1') -Destination (Join-Path $testGithubScripts 'configure-local.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/lib/GitIdentity.psm1') -Destination (Join-Path $testLib 'GitIdentity.psm1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Destination (Join-Path $testGithub 'repository.json')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'config/git-empty.config') -Destination (Join-Path $testConfig 'git-empty.config')
        Copy-Item -LiteralPath $configPath -Destination (Join-Path $testConfig 'worktree-quarantine.json')

        $policy = Get-Content -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Raw | ConvertFrom-Json
        $policyLogin = [string]$policy.commitIdentity.login
        $policyEmail = [string]$policy.commitIdentity.userId + '+' + $policyLogin + '@users.noreply.github.com'
        $originUrl = 'https://github.com/' + [string]$policy.repository + '.git'
        $originFetchBefore = Invoke-Git $admin @('remote','get-url','origin')
        $originPushBefore = Invoke-Git $admin @('remote','get-url','--push','origin')
        Invoke-Git $testTree @('config','--worktree','user.name',$policyLogin) | Out-Null
        Invoke-Git $testTree @('config','--worktree','user.email',$policyEmail) | Out-Null
        Invoke-Git $testTree @('config','--worktree','user.useConfigOnly','true') | Out-Null
        Invoke-Git $testTree @('config','--worktree','etalon.identity.userId',[string]$policy.commitIdentity.userId) | Out-Null
        Invoke-Git $testTree @('config','--worktree','etalon.identity.login',$policyLogin) | Out-Null

        $fixturePaths = @(
            'scripts/task-worktree-audit.ps1',
            'scripts/verify-git-hook-context.ps1',
            'scripts/verify-git-identity.ps1',
            'scripts/github/configure-local.ps1',
            'scripts/lib/GitIdentity.psm1',
            'config/github/repository.json',
            'config/git-empty.config',
            '.githooks/pre-commit',
            '.githooks/pre-push',
            'config/worktree-quarantine.json'
        )
        $stageArgs = @('add','--') + $fixturePaths
        Invoke-Git $testTree $stageArgs | Out-Null
        $emptyHooks = Join-Path $scratch 'empty-hooks-real-commit'
        [IO.Directory]::CreateDirectory($emptyHooks) | Out-Null
        Invoke-Git $testTree @('-c',('core.hooksPath=' + $emptyHooks),'commit','--quiet','-m','test: prepare real commit hook fixture') | Out-Null

        $oldAgent = $env:ETALON_AI_AGENT
        $oldIndex = $env:GIT_INDEX_FILE
        $oldPath = $env:Path
        $originTemporarilyChanged = $false
        $ghBin = Join-Path $scratch 'synthetic-gh'
        [IO.Directory]::CreateDirectory($ghBin) | Out-Null
        $ghShim = Join-Path $ghBin 'gh.cmd'
        $ghProfile = Join-Path $ghBin 'user.json'
        $ghProfileJson = [ordered]@{
            login = $policyLogin
            id = [long]$policy.commitIdentity.userId
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($ghProfile,$ghProfileJson + [Environment]::NewLine,$utf8)
        $ghLines = @(
            '@echo off',
            'if /I "%~1"=="api" if /I "%~2"=="user" (',
            '  type "%~dp0user.json"',
            '  exit /b 0',
            ')',
            'exit /b 2'
        )
        [IO.File]::WriteAllText($ghShim,([string]::Join([Environment]::NewLine,$ghLines) + [Environment]::NewLine),$utf8)
        $git = (Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        try {
            Invoke-Git $admin @('remote','set-url','origin',$originUrl) | Out-Null
            $originTemporarilyChanged = $true
            Invoke-Git $admin @('remote','set-url','--push','origin',$originUrl) | Out-Null
            $env:ETALON_AI_AGENT = 'Codex'
            $env:Path = $ghBin + ';' + $env:Path
            $resolvedGh = (Get-Command gh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
            if (-not [string]::Equals($resolvedGh,$ghShim,[StringComparison]::OrdinalIgnoreCase)) { throw 'SYNTHETIC_GH_SHIM_NOT_SELECTED' }
            $syntheticProfile = @(& $ghShim api user)
            $syntheticProfileExit = $LASTEXITCODE
            if ($syntheticProfileExit -ne 0 -or $syntheticProfile.Count -ne 1) { throw 'SYNTHETIC_GH_PROFILE_RESPONSE_INVALID' }
            try { $syntheticProfileObject = ConvertFrom-Json -InputObject ([string]$syntheticProfile[0]) -ErrorAction Stop } catch { throw 'SYNTHETIC_GH_PROFILE_JSON_INVALID' }
            if ([string]$syntheticProfileObject.login -cne $policyLogin -or [string]$syntheticProfileObject.id -cne [string]$policy.commitIdentity.userId) { throw 'SYNTHETIC_GH_PROFILE_POLICY_MISMATCH' }
            Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue

            Write-Text (Join-Path $testTree 'README.md') ('real commit -a content' + [Environment]::NewLine)
            $autoStage = Invoke-NativeProcess $git @('-C',$testTree,'commit','-a','-m','test: real commit-a hook') -HookProcess
            if ($autoStage.ExitCode -ne 0) { throw ('REAL_COMMIT_A_HOOK_FAILED:' + $autoStage.Output + $autoStage.Error) }

            Write-Text (Join-Path $testTree 'README.md') ('real pathspec content' + [Environment]::NewLine)
            $pathspec = Invoke-NativeProcess $git @('-C',$testTree,'commit','-m','test: real pathspec hook','--','README.md') -HookProcess
            if ($pathspec.ExitCode -ne 0) { throw ('REAL_PATHSPEC_HOOK_FAILED:' + $pathspec.Output + $pathspec.Error) }

            $remaining = Invoke-Git $testTree @('status','--porcelain=v2')
            if (-not [string]::IsNullOrWhiteSpace($remaining)) { throw ('REAL_HOOK_COMMIT_LEFT_RESIDUE:' + $remaining) }
            $identityOutput = Invoke-Git $testTree @('log','-2','--format=%ae%x09%ce')
            $identityLog = @($identityOutput -split '\r?\n')
            if ($identityLog.Count -ne 2) { throw ('REAL_HOOK_COMMIT_IDENTITY_COUNT_MISMATCH:' + $identityOutput) }
            foreach ($identityEntry in $identityLog) {
                $identityParts = $identityEntry.Split([char]9)
                if ($identityParts.Length -ne 2 -or $identityParts[0] -cne $policyEmail -or $identityParts[1] -cne $policyEmail) {
                    throw ('REAL_HOOK_COMMIT_IDENTITY_MISMATCH:' + $identityOutput)
                }
            }

            $outsideIndex = Join-Path $scratch 'untrusted.index'
            Write-Text $outsideIndex 'synthetic invalid index'
            $env:GIT_INDEX_FILE = $outsideIndex
            $rejected = Invoke-Audit -Mode 'Commit' -RepositoryRoot $testTree
            $rejectionText = [string]::Join([Environment]::NewLine,@($rejected.Output,$rejected.Error))
            if ($rejected.ExitCode -eq 0 -or $rejectionText -notmatch 'WORKTREE_AUDIT_HOOK_INDEX_OUTSIDE_WORKTREE') {
                throw ('UNTRUSTED_COMMIT_INDEX_NOT_REJECTED:' + $rejectionText)
            }

            Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
            $beforeRepairHead = Invoke-Git $testTree @('rev-parse','HEAD')
            Invoke-Git $testTree @('config','--worktree','user.name','Wrong Fixture') | Out-Null
            Invoke-Git $testTree @('config','--worktree','user.email','wrong@example.invalid') | Out-Null
            Write-Text (Join-Path $testTree 'README.md') ('identity repair fixture' + [Environment]::NewLine)
            Invoke-Git $testTree @('add','README.md') | Out-Null
            $repair = Invoke-NativeProcess $git @('-C',$testTree,'commit','-m','test: real identity repair hook') -HookProcess
            $repairText = [string]::Join([Environment]::NewLine,@($repair.Output,$repair.Error))
            $afterRepairHead = Invoke-Git $testTree @('rev-parse','HEAD')
            if ($repair.ExitCode -eq 0 -or $repairText -notmatch 'worktree identity repaired and verified' -or $afterRepairHead -cne $beforeRepairHead) {
                throw ('REAL_IDENTITY_REPAIR_DID_NOT_BLOCK_FIRST_ATTEMPT:' + $repairText)
            }
            $repairedName = Invoke-Git $testTree @('config','--worktree','--get','user.name')
            $repairedEmail = Invoke-Git $testTree @('config','--worktree','--get','user.email')
            if ($repairedName -cne $policyLogin -or $repairedEmail -cne $policyEmail) { throw 'REAL_IDENTITY_REPAIR_POLICY_MISMATCH' }

            $retry = Invoke-NativeProcess $git @('-C',$testTree,'commit','-m','test: real identity repair hook') -HookProcess
            if ($retry.ExitCode -ne 0) { throw ('REAL_IDENTITY_REPAIR_RETRY_FAILED:' + $retry.Output + $retry.Error) }
            $lastIdentity = Invoke-Git $testTree @('log','-1','--format=%an%x09%ae%x09%cn%x09%ce')
            $expectedLastIdentity = [string]::Join([char]9,@($policyLogin,$policyEmail,$policyLogin,$policyEmail))
            if ($lastIdentity -cne $expectedLastIdentity) { throw ('REAL_IDENTITY_REPAIR_COMMIT_IDENTITY_MISMATCH:' + $lastIdentity) }
            $finalStatus = Invoke-Git $testTree @('status','--porcelain=v2')
            if (-not [string]::IsNullOrWhiteSpace($finalStatus)) { throw ('REAL_IDENTITY_REPAIR_LEFT_RESIDUE:' + $finalStatus) }
        }
        finally {
            if ($originTemporarilyChanged) {
                Invoke-Git $admin @('remote','set-url','origin',$originFetchBefore) | Out-Null
                Invoke-Git $admin @('remote','set-url','--push','origin',$originPushBefore) | Out-Null
            }
            if ($null -eq $oldAgent) { Remove-Item Env:ETALON_AI_AGENT -ErrorAction SilentlyContinue } else { $env:ETALON_AI_AGENT = $oldAgent }
            if ($null -eq $oldIndex) { Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue } else { $env:GIT_INDEX_FILE = $oldIndex }
            $env:Path = $oldPath
        }
    }
    Case 'pre-push hook blocks publishing with untracked residue' {
        Write-Text (Join-Path $mainTree 'task.txt') 'committed task output'
        Invoke-Git $mainTree @('add','task.txt') | Out-Null
        $emptyHooks = Join-Path $scratch 'empty-hooks'
        [IO.Directory]::CreateDirectory($emptyHooks) | Out-Null
        Invoke-Git $mainTree @('-c',('core.hooksPath=' + $emptyHooks),'commit','--quiet','-m','test: create outgoing task commit') | Out-Null
        Write-Text (Join-Path $mainTree 'leftover.txt') 'uncommitted residue'
        $mainHookScripts = Join-Path $mainTree 'scripts'
        $mainHookGitIdentity = Join-Path $mainHookScripts 'lib'
        [IO.Directory]::CreateDirectory($mainHookGitIdentity) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/verify-git-hook-context.ps1') -Destination (Join-Path $mainHookScripts 'verify-git-hook-context.ps1')
        Copy-Item -LiteralPath (Join-Path $repoRoot 'scripts/lib/GitIdentity.psm1') -Destination (Join-Path $mainHookGitIdentity 'GitIdentity.psm1')
        $mainHookPolicy = Join-Path $mainTree 'config/github'
        [IO.Directory]::CreateDirectory($mainHookPolicy) | Out-Null
        Copy-Item -LiteralPath (Join-Path $repoRoot 'config/github/repository.json') -Destination (Join-Path $mainHookPolicy 'repository.json')
        $git = (Get-Command git -ErrorAction Stop).Source
        $result = Invoke-NativeProcess $git @('-C',$mainTree,'push','origin','task/T-018-worktree-guard') -HookProcess
        if ($result.ExitCode -eq 0 -or $result.Error -notmatch 'current worktree is not clean') { throw ('DIRTY_PREPUSH_GUARD_FAILED:' + $result.Error) }
        Remove-Item -LiteralPath (Join-Path $mainHookGitIdentity 'GitIdentity.psm1') -Force
        Remove-Item -LiteralPath (Join-Path $mainHookScripts 'verify-git-hook-context.ps1') -Force
        Remove-Item -LiteralPath (Join-Path $mainHookPolicy 'repository.json') -Force
        Remove-Item -LiteralPath $mainHookPolicy -Force
        Remove-Item -LiteralPath $mainHookGitIdentity -Force
        Remove-Item -LiteralPath $mainHookScripts -Force
    }

    if ($passed -ne 25) { throw ('TASK_WORKTREE_REGRESSION_COUNT_MISMATCH: expected 25, got ' + $passed) }
    Write-Output ('TASK-WORKTREE-REGRESSIONS: ' + $passed + ' passed, 0 failed')
}
finally {
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fullScratch = [IO.Path]::GetFullPath($scratch)
    if (-not $fullScratch.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'TASK_WORKTREE_FIXTURE_CLEANUP_PATH_INVALID' }
    if (Test-Path -LiteralPath $fullScratch) { Remove-Item -LiteralPath $fullScratch -Recurse -Force }
}
