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
    [IO.File]::WriteAllText($c, ('# T-001 — Другой проект' + [char]10 + '**Статус:** merged · **Исполнитель и координатор:** Kimi.'))
    [void](New-Item -ItemType Junction -Path $junction -Target (Join-Path $root 'other'))
    foreach ($folder in 'tasks','reports','accepted') {
        [void][IO.Directory]::CreateDirectory((Join-Path $root "queue/$folder"))
    }
    foreach ($accepted in 'readable','missing','unavailable') {
        foreach ($reported in 'readable','missing','unavailable') {
            $id = "CASE-$accepted-$reported".ToUpperInvariant()
            [IO.File]::WriteAllText((Join-Path $root "queue/tasks/$id.md"), 'Исполнитель: Codex')
            foreach ($pair in @(@('accepted',$accepted), @('reports',$reported))) {
                $file = Join-Path $root "queue/$($pair[0])/$id.md"
                if ($pair[1] -eq 'readable') { [IO.File]::WriteAllText($file, 'report <script>throw 1</script>') }
                if ($pair[1] -eq 'unavailable') { [IO.File]::WriteAllBytes($file, [byte[]]@(255)) }
            }
        }
    }
    [IO.File]::WriteAllText((Join-Path $root 'Проект А/tasks/T-002-test.md'), "# T-002`nСтатус: in_progress")
    [IO.File]::WriteAllText((Join-Path $root 'Проект А/tasks/T-003-test.md'), "# T-003`nСтатус: in_progress")
    [IO.File]::WriteAllText((Join-Path $root 'queue/tasks/SECOND-REPORT.md'), 'Исполнитель: Codex')
    [IO.File]::WriteAllText((Join-Path $root 'queue/reports/SECOND-REPORT.md'), 'second report')
    $history = Join-Path $root 'history.json'
    @'
{"schemaVersion":1,"projectId":"first","coverage":[{"type":"accepted","from":"2026-01-01T00:00:00Z","until":"2026-01-02T00:00:00Z"}],"events":[{"at":"2026-01-01T00:00:00Z","sourceId":"local","eventId":"e1","taskId":"T-001","type":"accepted"},{"at":"2026-01-01T00:00:00Z","sourceId":"local","eventId":"e1","taskId":"T-001","type":"accepted"}]}
'@ | Set-Content -LiteralPath $history -Encoding utf8
    $registry = Join-Path $root 'projects.json'
    @{
        queue = @{ id = 'pilot'; path = 'queue' }
        projects = @(
            @{ id = 'first'; name = 'Первый'; roots = @('Проект А', 'copy')
                historyPath = 'history.json'
                timeline = @{
                    timeZone = 'UTC'
                    startDate = '2026-11-20'
                    stages = @(@{ id = 'pilot'; name = 'Пилот'; plannedDate = '2026-11-26'; taskIds = @('T-001') })
                }
                bindings = @(
                    @{ taskId = 'T-001'; assignmentId = 'CASE-READABLE-READABLE' }
                    @{ taskId = 'T-002'; assignmentId = 'SECOND-REPORT' }
                    @{ taskId = 'T-002'; assignmentId = 'CASE-MISSING-READABLE' }
                )
                ownerActions = @(
                    @{ taskId = 'T-001'; text = 'Проверить результат'; requires = @('CASE-READABLE-READABLE') }
                    @{ taskId = 'T-003'; text = 'Проверить вручную'; requires = @() }
                )
            }
            @{ id = 'second'; name = 'Второй'; roots = @('other', 'linked') }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registry -Encoding utf8
    if ($V2Root) {
        $config = Get-Content -LiteralPath $registry -Raw | ConvertFrom-Json -AsHashtable
        $config.projects += @{ id = 'v2'; name = 'V2'; roots = @($V2Root) }
        $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registry -Encoding utf8
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
    $periodUri = $url + 'period?project=first&from=2026-01-01&through=2026-01-01'
    $period = Invoke-RestMethod $periodUri -TimeoutSec 10
    $wire = (Invoke-WebRequest $periodUri -TimeoutSec 10).Content | ConvertFrom-Json -DateKind String
    Assert-That ($wire.period.From -ceq '2026-01-01' -and $wire.period.Through -ceq '2026-01-01' -and
        $wire.period.TimeZone -ceq 'UTC' -and $wire.historyReadAt) 'PTR-VIS-013 serializes calendar dates and source freshness'
    Assert-That ($period.historyState -ceq 'readable' -and $period.report.totals.accepted -eq 1 -and
        $period.report.events.Count -eq 1 -and $period.report.events[0].day -ceq '2026-01-01') 'PTR-VIS-005 period counts deduplicated events at midnight'
    Assert-That (!$period.coverage.accepted.complete -and $period.coverage.accepted.gaps.Count -eq 1 -and
        $period.coverage.accepted.gaps[0].eventType -ceq 'acceptance_revoked' -and
        !$period.coverage.merged.complete -and $period.coverage.merged.gaps.Count -eq 1) 'PTR-VIS-005 distinguishes complete metric from missing history'
    $otherPeriod = Invoke-RestMethod ($url + 'period?project=second&days=3') -TimeoutSec 10
    Assert-That ($otherPeriod.historyState -ceq 'unconfigured' -and $null -eq $otherPeriod.report) 'PTR-VIS-005 history is isolated by project'
    $invalidPeriod = Invoke-WebRequest ($url + 'period?project=first&days=2') -SkipHttpErrorCheck -TimeoutSec 10
    Assert-That ($invalidPeriod.StatusCode -eq 400) 'PTR-VIS-005 unsupported period is refused'
    $offlineHistory = Join-Path $root 'history-offline.json'
    Move-Item -LiteralPath $history -Destination $offlineHistory
    $missingPeriod = Invoke-RestMethod $periodUri -TimeoutSec 10
    Assert-That ($missingPeriod.historyState -ceq 'unavailable' -and $null -eq $missingPeriod.report) 'PTR-VIS-005 missing history does not report zero'
    Move-Item -LiteralPath $offlineHistory -Destination $history
    $restoredPeriod = Invoke-RestMethod $periodUri -TimeoutSec 10
    Assert-That ($restoredPeriod.report.totals.accepted -eq 1) 'PTR-VIS-005 restored history does not duplicate events'
    $first = Invoke-RestMethod ($url + 'summary') -TimeoutSec 10
    Assert-That ($first[0].historyConfigured -and !$first[1].historyConfigured) 'PTR-VIS-005 summary distinguishes history configuration by project'
    Assert-That ($first.Count -eq (2 + [int][bool]$V2Root) -and $first[1].tasks[0].versions[0].status -eq 'merged') 'PTR-001 independent projects'
    $timeline = $first[0].timeline
    Assert-That ($timeline.startDate -ceq '2026-11-20' -and $timeline.timeZone -ceq 'UTC' -and
        $timeline.today -in @([DateTime]::UtcNow.ToString('yyyy-MM-dd'), [DateTime]::UtcNow.AddDays(-1).ToString('yyyy-MM-dd')) -and
        $timeline.stages -is [array] -and $timeline.stages.Count -eq 1 -and
        $timeline.stages[0].plannedDate -ceq '2026-11-26' -and $null -eq $timeline.stages[0].actualDate -and
        $timeline.stages[0].taskIds.Count -eq 1 -and $timeline.stages[0].taskIds[0] -ceq 'T-001' -and $null -eq $first[1].timeline) 'PTR-VIS-002 timeline and project isolation'
    if ($V2Root) {
        $expected = @(Get-ChildItem -LiteralPath (Join-Path $V2Root 'tasks') -File -Filter 'T-*.md' |
            Where-Object Name -CMatch '^T-[0-9]{3,}(?:-[^.]+)?\.md$').Count
        Assert-That ($expected -gt 0 -and $first[2].tasks.Count -eq $expected -and !$first[2].sources[0].error) 'PTR-001 real V2 checkout'
    }
    Assert-That ($first[1].tasks[0].versions[0].assignee -ceq 'Kimi') 'PTR-002 inline Markdown assignee'
    Assert-That ($first[1].tasks[0].versions[0].sources[0].path -ceq (Get-Item -LiteralPath $c).FullName) 'PTR-003 native source path'
    $version = $first[0].tasks[0].versions[0]
    Assert-That ($version.blocker -eq 'CI' -and $version.needsDecision -and $version.assignee -eq 'Codex' -and $version.status -eq 'in_progress') 'PTR-002 explicit fields'
    Assert-That ($first[0].tasks[0].versions.Count -eq 1 -and $version.sources.Count -eq 2) 'PTR-003 duplicate grouping'
    $card = Invoke-RestMethod ($url + "card?project=first&task=T-001&version=$($version.hash)") -TimeoutSec 10
    Assert-That ($card.text -ceq $sample) 'PTR-003 exact card text'
    Assert-That ($version.binding -eq 'previous' -and $first[1].tasks[0].versions[0].binding -eq 'unknown') 'PTR-004 evidence binding'
    Assert-That ($null -ne $first[1].sources[1].error) 'PTR-005 junction rejected'
    $linked = $first[0].tasks[0].assignments[0]
    Assert-That ($linked.state -eq 'accepted' -and $linked.comparison -eq 'match' -and !$first[0].tasks[0].action.blocked -and
        !$first[1].tasks[0].assignments.Count -and $first[0].unlinkedAssignments.Count -eq 7) 'T-101 binding, owner instruction and project isolation'
    $grouped = $first[0].tasks[1]
    Assert-That ($grouped.action.assignments.Count -eq 2 -and $grouped.action.assignments[0] -eq 'CASE-MISSING-READABLE' -and
        $grouped.action.assignments[1] -eq 'SECOND-REPORT') 'T-101 grouped review action in stable order'
    Assert-That (!$first[0].tasks[2].action.blocked) 'T-101 owner instruction without evidence condition'
    $all = @($first[0].unlinkedAssignments) + @($linked) + @($grouped.assignments | Where-Object id -Like 'CASE-*')
    foreach ($accepted in 'readable','missing','unavailable') {
        foreach ($reported in 'readable','missing','unavailable') {
            $item = $all | Where-Object id -EQ "CASE-$accepted-$reported"
            $expected = switch ("$accepted/$reported") {
                'missing/missing' { 'assigned' }
                'missing/readable' { 'reported' }
                default { if ($accepted -eq 'readable') { 'accepted' } else { 'unknown' } }
            }
            Assert-That ($item.state -eq $expected -and $item.accepted.state -eq $accepted -and $item.report.state -eq $reported) "T-101 copy matrix $accepted/$reported"
        }
    }
    $reportUri = $url + 'report?assignment=CASE-READABLE-READABLE&copy=accepted'
    $document = Invoke-RestMethod $reportUri -TimeoutSec 10
    Assert-That ($document.text -ceq 'report <script>throw 1</script>' -and $document.hash -ceq $linked.accepted.hash) 'T-101 exact report snapshot'
    [IO.File]::WriteAllText((Join-Path $root 'queue/reports/CASE-READABLE-READABLE.md'), 'different')
    $changed = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That ($changed[0].tasks[0].assignments[0].comparison -eq 'conflict' -and
        $changed[0].tasks[0].action.blocked -and $changed[0].tasks[0].action.text -eq 'Проверить результат') 'T-101 conflict blocks dependent owner instruction'
    $queueTasks = Join-Path $root 'queue/tasks'
    $originalTasks = Join-Path $root 'original-queue-tasks'
    Move-Item -LiteralPath $queueTasks -Destination $originalTasks
    try {
        [void][IO.Directory]::CreateDirectory($queueTasks)
        $empty = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
        Assert-That ($empty[0].unlinkedAssignments -is [array] -and $empty[0].unlinkedAssignments.Count -eq 0) 'T-101 empty unlinked assignments remain an array'
        Assert-That ($empty[0].tasks[0].action.blocked -and $empty[0].tasks[0].assignments[0].state -eq 'unknown' -and
            $empty[0].tasks[1].action.text -ceq 'Восстановить доступ к источнику') 'T-101 empty queue keeps missing bindings and blocks dependent instructions'
        [IO.File]::WriteAllText((Join-Path $queueTasks 'SINGLE.md'), '# Single assignment')
        $single = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
        Assert-That ($single[0].unlinkedAssignments -is [array] -and $single[0].unlinkedAssignments.Count -eq 1 -and
            $single[0].unlinkedAssignments[0].id -ceq 'SINGLE') 'T-101 singleton unlinked assignment remains an array'
    } finally {
        Move-Item -LiteralPath $queueTasks -Destination (Join-Path $root 'cardinality-queue-tasks')
        Move-Item -LiteralPath $originalTasks -Destination $queueTasks
    }
    $null = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Move-Item -LiteralPath (Join-Path $root 'queue') -Destination (Join-Path $root 'offline')
    $offline = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That ($offline[0].queue.stale -and $offline[0].queue.updated -and
        $offline[0].tasks[0].assignments[0].comparison -eq 'conflict' -and
        [IO.File]::ReadAllText((Join-Path $root 'offline/reports/CASE-READABLE-READABLE.md')) -ceq 'different') 'T-101 read-only stale snapshot'
    $wrong = Invoke-WebRequest ($origin + '/summary') -SkipHttpErrorCheck -TimeoutSec 10
    Assert-That ($wrong.StatusCode -eq 404) 'PTR-003 session isolation'
    [IO.File]::AppendAllText($b, ([char]10 + 'Следующее действие: повторить'))
    $refresh = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That ($refresh[0].tasks[0].versions.Count -eq 2) 'PTR-003 divergent versions'
    Move-Item -LiteralPath (Join-Path $root 'Проект А') -Destination (Join-Path $root 'moved')
    $stale = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That ($null -ne $stale[0].sources[0].error -and $stale[0].tasks[0].versions.sources.stale -contains $true) 'PTR-005 stale source retained'
    Assert-That ([IO.File]::ReadAllText((Join-Path $root 'moved/tasks/T-001-test.md')) -ceq $sample) 'PTR-005 source bytes unchanged'
    Move-Item -LiteralPath (Join-Path $root 'moved') -Destination (Join-Path $root 'Проект А')
    Move-Item -LiteralPath (Join-Path $root 'offline') -Destination (Join-Path $root 'queue')
    [IO.File]::WriteAllText((Join-Path $root 'queue/reports/CASE-READABLE-READABLE.md'), 'report <script>throw 1</script>')
    $restored = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{ Origin = $origin } -TimeoutSec 10
    Assert-That (!$restored[0].queue.stale -and $restored[0].tasks[0].assignments[0].comparison -eq 'match') 'T-101 queue recovered'
    Assert-That (!$restored[0].sources[0].error -and $restored[0].tasks[0].versions.Count -eq 2 -and
        $restored[0].tasks[0].versions.sources.stale -notcontains $true) 'PTR-005 source recovered'
} finally {
    if ($process) {
        if (!$process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
    if (Test-Path -LiteralPath $junction) { [IO.Directory]::Delete($junction) }
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
if (Test-Path -LiteralPath $root) { throw 'Cleanup failed' }
