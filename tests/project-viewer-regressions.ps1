#Requires -Version 7.6
param([string]$TempRoot = [IO.Path]::GetTempPath(), [string]$V2Root)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-That([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    Write-Host "PASS: $Name"
}

$temp = [IO.Path]::GetFullPath($TempRoot)
$ancestor = Get-Item -LiteralPath $temp
while ($ancestor) {
    if ($ancestor -isnot [IO.DirectoryInfo] -or ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
        (Test-Path -LiteralPath (Join-Path $ancestor.FullName '.git')) -or
        ((Test-Path -LiteralPath (Join-Path $ancestor.FullName 'HEAD')) -and
         (Test-Path -LiteralPath (Join-Path $ancestor.FullName 'objects')))) {
        throw 'Test root must be outside Git repositories and reparse points'
    }
    $ancestor = $ancestor.Parent
}
$root = Join-Path $temp ('ptr-' + [guid]::NewGuid().ToString('N'))
$process = $null
$junction = Join-Path $root 'linked'
if ((Test-Path -LiteralPath $root) -or
    ![IO.Path]::GetFullPath($root).StartsWith([IO.Path]::TrimEndingDirectorySeparator($temp) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Unexpected test root'
}
try {
    foreach ($folder in @('Проект А', 'copy', 'other')) {
        [void][IO.Directory]::CreateDirectory((Join-Path $root "$folder/tasks"))
    }
    $a = Join-Path $root 'Проект А/tasks/T-001-test.md'
    $b = Join-Path $root 'copy/tasks/T-001-test.md'
    $c = Join-Path $root 'other/tasks/T-001-test.md'
    $head = 'a' * 40
    $old = 'b' * 40
    $sample = @"
# T-001 — Кириллица
Статус: in_progress. Исполнитель: Codex.
Блокер: CI
Решение владельца: ожидается
PR_HEAD_SHA: $head
CI_HEAD_SHA: $old
<script>throw 1</script>
"@
    [IO.File]::WriteAllText($a, $sample)
    [IO.File]::WriteAllText($b, $sample)
    [IO.File]::WriteAllText($c, ('# T-001 — Другой проект' + [char]10 + '**Статус:** merged'))
    [void](New-Item -ItemType Junction -Path $junction -Target (Join-Path $root 'other'))
    $registry = Join-Path $root 'projects.json'
    @{
        projects = @(
            @{ id = 'first'; name = 'Первый'; roots = @('Проект А', 'copy') }
            @{ id = 'second'; name = 'Второй'; roots = @('other', 'linked') }
        )
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $registry -Encoding utf8
    if ($V2Root) {
        $config = Get-Content -LiteralPath $registry -Raw | ConvertFrom-Json -AsHashtable
        $config.projects += @{ id = 'v2'; name = 'V2'; roots = @($V2Root) }
        $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $registry -Encoding utf8
    }
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = $probe.LocalEndpoint.Port
    $probe.Stop()
    $start = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $script = Join-Path $PSScriptRoot '../scripts/project-viewer.ps1'
    foreach ($argument in @('-NoLogo', '-NoProfile', '-File', $script, '-RegistryPath', $registry, '-Port', "$port")) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($start)
    $pending = $process.StandardOutput.ReadLineAsync()
    if (!$pending.Wait(15000)) { throw 'Viewer startup timed out' }
    $url = $pending.Result
    if (!$url) { throw ($process.StandardError.ReadToEnd()) }
    $origin = "http://127.0.0.1:$port"
    $first = Invoke-RestMethod ($url + 'summary') -TimeoutSec 10
    Assert-That ($first.Count -eq (2 + [int][bool]$V2Root) -and $first[1].tasks[0].versions[0].status -eq 'merged') 'PTR-001 independent projects'
    if ($V2Root) {
        $expected = @(Get-ChildItem -LiteralPath (Join-Path $V2Root 'tasks') -File -Filter 'T-*.md' |
            Where-Object Name -CMatch '^T-[0-9]{3,}(?:-[^.]+)?\.md$').Count
        Assert-That ($expected -gt 0 -and $first[2].tasks.Count -eq $expected -and !$first[2].sources[0].error) 'PTR-001 real V2 checkout'
    }
    $version = $first[0].tasks[0].versions[0]
    Assert-That ($version.blocker -eq 'CI' -and $version.needsDecision -and $version.assignee -eq 'Codex' -and $version.status -eq 'in_progress') 'PTR-002 explicit fields'
    Assert-That ($first[0].tasks[0].versions.Count -eq 1 -and $version.sources.Count -eq 2) 'PTR-003 duplicate grouping'
    $card = Invoke-RestMethod ($url + "card?project=first&task=T-001&version=$($version.hash)") -TimeoutSec 10
    Assert-That ($card.text -ceq $sample) 'PTR-003 exact card text'
    Assert-That ($version.binding -eq 'previous' -and $first[1].tasks[0].versions[0].binding -eq 'unknown') 'PTR-004 evidence binding'
    Assert-That ($null -ne $first[1].sources[1].error) 'PTR-005 junction rejected'
    $wrong = Invoke-WebRequest ($origin + '/summary') -SkipHttpErrorCheck -TimeoutSec 10
    Assert-That ($wrong.StatusCode -eq 404) 'PTR-003 session isolation'
    [IO.File]::AppendAllText($b, ([char]10 + 'Следующее действие: повторить'))
    $refresh = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That ($refresh[0].tasks[0].versions.Count -eq 2) 'PTR-003 divergent versions'
    Move-Item -LiteralPath (Join-Path $root 'Проект А') -Destination (Join-Path $root 'moved')
    $stale = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That ($null -ne $stale[0].sources[0].error -and $stale[0].tasks[0].versions.sources.stale -contains $true) 'PTR-005 stale source retained'
    Assert-That ([IO.File]::ReadAllText((Join-Path $root 'moved/tasks/T-001-test.md')) -ceq $sample) 'PTR-005 source bytes unchanged'
} finally {
    if ($process) {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
    if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if (Test-Path -LiteralPath $root) { throw 'Cleanup failed' }
