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
$quarantineTree = Join-Path $admin '.worktrees/T-013'
$scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/task-worktree-audit.ps1'
$hooksPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.githooks'
$configPath = Join-Path $scratch 'quarantine.json'
$repoRoot = Split-Path $PSScriptRoot -Parent
$utf8 = [Text.UTF8Encoding]::new($false)
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
function Invoke-NativeProcess([string]$Executable,[string[]]$Arguments,[switch]$PreserveGitContext) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $Executable
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    if (-not $PreserveGitContext) {
        foreach ($name in @($start.Environment.Keys | Where-Object { ([string]$_).StartsWith('GIT_',[StringComparison]::OrdinalIgnoreCase) })) {
            $null = $start.Environment.Remove([string]$name)
        }
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $null = $process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return [pscustomobject]@{ ExitCode=$process.ExitCode; Output=$stdoutTask.Result; Error=$stderrTask.Result }
}
function Invoke-Audit([string]$Mode='Audit') {
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    return Invoke-NativeProcess $pwsh @('-NoLogo','-NoProfile','-File',$scriptPath,'-Mode',$Mode,'-RepositoryRoot',$mainTree,'-QuarantineConfigPath',$configPath) -PreserveGitContext
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
    $emptyConfig = @{schemaVersion=1;quarantines=@()} | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText($configPath,$emptyConfig,$utf8)

    Case 'production quarantine registry remains empty' {
        $productionConfig = Get-Content -LiteralPath (Join-Path $repoRoot 'config/worktree-quarantine.json') -Raw | ConvertFrom-Json
        if ($productionConfig.schemaVersion -ne 1 -or @($productionConfig.quarantines).Count -ne 0) { throw 'PRODUCTION_QUARANTINE_REGISTRY_MUST_BE_EMPTY' }
    }
    Case 'clean registered worktrees pass audit' {
        $result = Assert-AuditExit 0 'CLEAN_AUDIT'
        if ($result.Output -notmatch 'WORKTREE-AUDIT=PASS') { throw 'CLEAN_AUDIT_MARKER_MISSING' }
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
        $result = Invoke-NativeProcess $git @('-C',$quarantineTree,'commit','-m','test: must be blocked')
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
        $result = Invoke-NativeProcess $git @('-C',$mainTree,'push','origin','task/T-018-worktree-guard')
        if ($result.ExitCode -eq 0 -or $result.Error -notmatch 'current worktree is not clean') { throw ('DIRTY_PREPUSH_GUARD_FAILED:' + $result.Error) }
        Remove-Item -LiteralPath (Join-Path $mainHookGitIdentity 'GitIdentity.psm1') -Force
        Remove-Item -LiteralPath (Join-Path $mainHookScripts 'verify-git-hook-context.ps1') -Force
        Remove-Item -LiteralPath (Join-Path $mainHookPolicy 'repository.json') -Force
        Remove-Item -LiteralPath $mainHookPolicy -Force
        Remove-Item -LiteralPath $mainHookGitIdentity -Force
        Remove-Item -LiteralPath $mainHookScripts -Force
    }

    if ($passed -ne 19) { throw ('TASK_WORKTREE_REGRESSION_COUNT_MISMATCH: expected 19, got ' + $passed) }
    Write-Output ('TASK-WORKTREE-REGRESSIONS: ' + $passed + ' passed, 0 failed')
}
finally {
    $fullRoot = [IO.Path]::GetFullPath($root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fullScratch = [IO.Path]::GetFullPath($scratch)
    if (-not $fullScratch.StartsWith($fullRoot,[StringComparison]::OrdinalIgnoreCase)) { throw 'TASK_WORKTREE_FIXTURE_CLEANUP_PATH_INVALID' }
    if (Test-Path -LiteralPath $fullScratch) { Remove-Item -LiteralPath $fullScratch -Recurse -Force }
}
