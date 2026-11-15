#Requires -Version 7.4
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$source=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Git hooks export repository-specific environment variables; never let fixture Git
# commands address the real worktree or index. This process is isolated from its parent.
$localGitVariables=@(& git rev-parse --local-env-vars)
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate Git local environment variables' }
foreach ($name in $localGitVariables) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
$fixture=Join-Path ([IO.Path]::GetFullPath($TempRoot)) ('ide-cache-test-'+[guid]::NewGuid().ToString('N'))
$utf8=[Text.UTF8Encoding]::new($false)
try {
    $sourceHead=(& git -C $source rev-parse --verify HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot read source revision' }
    $sourceBranch=(& git -C $source symbolic-ref --quiet HEAD) -join [char]10
    $sourceStatus=(& git -C $source status --porcelain=v1 --untracked-files=all) -join [char]10
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source status' }
    & git clone --quiet --local --no-hardlinks --no-checkout $source $fixture
    if ($LASTEXITCODE -ne 0) { throw 'Fixture clone failed' }
    $head=(& git -C $source rev-parse HEAD).Trim()
    & git -C $fixture checkout --quiet --detach $head
    if ($LASTEXITCODE -ne 0) { throw 'Fixture checkout failed' }
    foreach ($rel in @('.gitignore','scripts/ide-cache.ps1','scripts/quality-gate.ps1','tests/quality-gate-regressions.ps1')) {
        $to=Join-Path $fixture $rel
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to)) | Out-Null
        Copy-Item -LiteralPath (Join-Path $source $rel) -Destination $to -Force
    }
    $vs=Join-Path $fixture 'knowledge/.vs'
    [IO.Directory]::CreateDirectory($vs) | Out-Null
    $crlf=[string][char]13+[char]10
    [IO.File]::WriteAllText((Join-Path $vs 'ProjectSettings.json'),('{'+$crlf+'}'+$crlf),$utf8)
    [IO.File]::WriteAllText((Join-Path $vs 'invalid.ps1'),'function {',$utf8)
    & git -C $fixture check-ignore -q -- 'knowledge/.vs/ProjectSettings.json'
    if ($LASTEXITCODE -ne 0) { throw 'VS cache is not ignored' }
    . (Join-Path $fixture 'scripts/ide-cache.ps1')
    $files=@(Get-ProjectFiles $fixture)
    if (@($files | Where-Object { $_.FullName.StartsWith($vs,[StringComparison]::OrdinalIgnoreCase) }).Count -ne 0) {
        throw 'Ignored cache was enumerated'
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
    $afterStatus=(& git -C $source status --porcelain=v1 --untracked-files=all) -join [char]10
    if ($LASTEXITCODE -ne 0 -or $afterHead -cne $sourceHead -or $afterBranch -cne $sourceBranch -or $afterStatus -cne $sourceStatus) { throw 'Source Git state changed during fixture' }
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
