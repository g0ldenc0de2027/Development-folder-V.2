#Requires -Version 7.6
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$source=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Git hooks export repository-specific environment variables; never let fixture Git
# commands address the real worktree or index. This process is isolated from its parent.
foreach ($name in @(Get-ChildItem Env: | Where-Object Name -Like 'GIT_*' | ForEach-Object Name)) {
    Remove-Item -LiteralPath "Env:$name"
}
$env:GIT_CONFIG_NOSYSTEM = '1'
$env:GIT_CONFIG_GLOBAL = Join-Path $source 'config/git-empty.config'
$temp = [IO.Path]::GetFullPath($TempRoot)
for ($dir = [IO.DirectoryInfo]::new($temp); $null -ne $dir; $dir = $dir.Parent) {
    if ($dir.Exists -and ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'IDE cache TempRoot contains a reparse point'
    }
    if ((Test-Path -LiteralPath (Join-Path $dir.FullName '.git')) -or
        ((Test-Path -LiteralPath (Join-Path $dir.FullName 'HEAD') -PathType Leaf) -and
         (Test-Path -LiteralPath (Join-Path $dir.FullName 'objects') -PathType Container) -and
         (Test-Path -LiteralPath (Join-Path $dir.FullName 'refs') -PathType Container))) {
        throw 'IDE cache TempRoot must be outside every Git repository'
    }
}
if (-not [IO.Directory]::Exists($temp)) { throw 'IDE cache TempRoot must exist' }
$fixture = Join-Path $temp ('ide-cache-test-' + [guid]::NewGuid().ToString('N'))
if ([Text.Encoding]::UTF8.GetByteCount((Join-Path $fixture '.git')) -gt 200) {
    throw 'IDE cache fixture would exceed the Git for Windows GIT_DIR path budget'
}
$utf8=[Text.UTF8Encoding]::new($false)
try {
    $sourceIndex = & git -C $source rev-parse --path-format=absolute --git-path index
    if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve source index' }
    $sourceIndexHash = (Get-FileHash -LiteralPath $sourceIndex).Hash
    $sourceHead=(& git -C $source rev-parse --verify HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read source revision' }
    $sourceBranch=(& git -C $source symbolic-ref --quiet HEAD) -join [char]10
    $sourceStatus=(& git --no-optional-locks -C $source status --porcelain=v1 --untracked-files=all) -join [char]10
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source status' }
    & git clone --quiet --local --no-hardlinks --no-checkout --template= $source $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Fixture clone failed' }
    $mergeParent = & git -C $source rev-parse --verify --quiet MERGE_HEAD
    $head = $sourceHead
    if ($LASTEXITCODE -eq 0) { $head = $mergeParent.Trim() }
    & git -C $fixture checkout --quiet --detach $head
    if ($LASTEXITCODE -ne 0) { throw 'Fixture checkout failed' }
    foreach ($rel in @('.gitignore','scripts/ide-cache.ps1','scripts/quality-gate.ps1','tests/quality-gate-regressions.ps1',
        'spec/portfolio-kb-agent-workflow.md','specification-system/tz_state.md','docs/handoff.md')) {
        $to=Join-Path $fixture $rel
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $source $rel) -Destination $to -Force
    }
    $vs=Join-Path $fixture 'knowledge/.vs'
    [IO.Directory]::CreateDirectory($vs) | Out-Null
    $crlf=[string][char]13+[char]10
    [IO.File]::WriteAllText((Join-Path $vs 'ProjectSettings.json'),('{'+$crlf+'}'+$crlf),$utf8)
    & git -C $fixture check-ignore -q -- 'knowledge/.vs/ProjectSettings.json'
    if ($LASTEXITCODE -ne 0) { throw 'VS cache is not ignored' }
    . (Join-Path $fixture 'scripts/ide-cache.ps1')
    $excluded = @('knowledge/.vs','knowledge/temp','knowledge/.work','knowledge/.manus','knowledge/.worktrees')
    foreach ($relative in $excluded) {
        $dir = Join-Path $fixture $relative
        [IO.Directory]::CreateDirectory($dir) | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'invalid.ps1'),'function {',$utf8)
    }
    $similar = Join-Path $fixture 'knowledge/.vs-cache'
    [IO.Directory]::CreateDirectory($similar) | Out-Null
    [IO.File]::WriteAllText((Join-Path $similar 'valid.ps1'),("Write-Output 'fixture'" + [char]10),$utf8)
    $paths = @(Get-ProjectFiles $fixture | ForEach-Object {
        [IO.Path]::GetRelativePath($fixture,$_.FullName).Replace('\','/')
    })
    foreach ($relative in $excluded) {
        if (@($paths -like "$relative/*").Count -ne 0) { throw "Excluded directory enumerated: $relative" }
    }
    if ('knowledge/.vs-cache/valid.ps1' -notin $paths) { throw 'Similar directory was excluded' }
    $junction = Join-Path $fixture 'fixture-junction[probe]'
    New-Item -ItemType Junction -Path $junction -Target $similar | Out-Null
    try {
        $linkedPaths = @(Get-ProjectFiles $fixture | ForEach-Object FullName)
        $junctionPrefix = $junction + [IO.Path]::DirectorySeparatorChar
        if ($linkedPaths | Where-Object { $_.StartsWith($junctionPrefix, [StringComparison]::OrdinalIgnoreCase) }) {
            throw 'Source scan followed a junction'
        }
    } finally {
        [IO.Directory]::Delete($junction)
    }

    $projected = Join-Path $fixture 'fixture-projected'
    $projectedSource = Join-Path $projected 'probe.ps1'
    [IO.Directory]::CreateDirectory($projected) | Out-Null
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class V2ProjectedFixture {
    [DllImport("ProjectedFSLib.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
    public static extern int PrjMarkDirectoryAsPlaceholder(
        string root, IntPtr target, IntPtr version, ref Guid instance);
}
"@
        $instance = [guid]::NewGuid()
        $markResult = $null
        try {
            $markResult = [V2ProjectedFixture]::PrjMarkDirectoryAsPlaceholder(
                $projected, [IntPtr]::Zero, [IntPtr]::Zero, [ref]$instance)
        } catch {
            if ($_.Exception.InnerException -isnot [DllNotFoundException] -and
                $_.Exception.InnerException -isnot [EntryPointNotFoundException]) { throw }
        }
        if ($markResult -eq 0) {
            [IO.File]::WriteAllText($projectedSource, "Write-Output 'projfs'" + [char]10, $utf8)
            if ($projectedSource -notin @(Get-ProjectFiles $fixture | ForEach-Object FullName)) {
                throw 'Source scan skipped a ProjFS directory'
            }
            Write-Output 'PASS: source scan entered ProjFS and excluded a junction'
        } else {
            Write-Output ('NOT COVERED: ProjFS fixture unavailable (HRESULT {0})' -f $markResult)
        }
    } finally {
        [IO.File]::Delete($projectedSource)
        [IO.Directory]::Delete($projected)
    }

    $err=Join-Path $fixture 'fixture-stderr.txt'
    $result=@(& pwsh -NoLogo -NoProfile -File (Join-Path $fixture 'tests/quality-gate-regressions.ps1') 2>$err)
    if ($LASTEXITCODE -ne 0) { throw ('Ignored VS cache blocked hygiene: ' + [IO.File]::ReadAllText($err)) }
    $normal=Join-Path $fixture 'fixture-source.json'
    [IO.File]::WriteAllText($normal,('{'+$crlf+'}'+$crlf),$utf8)
    $result=@(& pwsh -NoLogo -NoProfile -File (Join-Path $fixture 'tests/quality-gate-regressions.ps1') 2>$err)
    if ($LASTEXITCODE -eq 0 -or -not ([IO.File]::ReadAllText($err).Contains('Expected LF-only'))) {
        throw 'Ordinary untracked file escaped hygiene'
    }
    [IO.File]::Delete($normal)
    & git -C $fixture add -f -- 'knowledge/.vs/ProjectSettings.json'
    if ($LASTEXITCODE -ne 0) { throw 'Could not stage tracked cache fixture' }
    $result=@(& pwsh -NoLogo -NoProfile -File (Join-Path $fixture 'tests/quality-gate-regressions.ps1') 2>$err)
    if ($LASTEXITCODE -eq 0 -or -not ([IO.File]::ReadAllText($err).Contains('Tracked .vs cache files are not permitted'))) {
        throw 'Tracked VS cache was not rejected'
    }
    $afterHead=(& git -C $source rev-parse --verify HEAD).Trim()
    $afterBranch=(& git -C $source symbolic-ref --quiet HEAD) -join [char]10
    $afterStatus=(& git --no-optional-locks -C $source status --porcelain=v1 --untracked-files=all) -join [char]10
    if ($LASTEXITCODE -ne 0 -or $afterHead -cne $sourceHead -or $afterBranch -cne $sourceBranch -or $afterStatus -cne $sourceStatus -or (Get-FileHash -LiteralPath $sourceIndex).Hash -cne $sourceIndexHash) { throw 'Source Git state changed during fixture' }
    Write-Output 'IDE-CACHE-REGRESSIONS: 3 passed'
} finally {
    $parent=[IO.Path]::GetFullPath($TempRoot).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    $resolved=[IO.Path]::GetFullPath($fixture)
    if ($resolved.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -cmatch '^ide-cache-test-[a-f0-9]{32}$' -and (Test-Path -LiteralPath $resolved)) {
        $item=Get-Item -LiteralPath $resolved -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Resolve-Path -LiteralPath $resolved).ProviderPath -cne $resolved) { throw 'Unsafe fixture cleanup root' }
        $links=@(Get-ChildItem -LiteralPath $resolved -Directory -Force -Recurse | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 })
        if ($links.Count -ne 0) { throw 'Unsafe fixture cleanup junction' }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
