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
    [IO.File]::WriteAllText($c, ('# T-001 — Другой проект' + [char]10 + '- **Статус:** merged · **Исполнитель и координатор:** Kimi.'))
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
    $evidenceFile = Join-Path $root 'evidence.json'
    $evidenceHead = 'a' * 40
    $evidenceBase = 'b' * 40
    $evidenceCi = @{
        status = 'success'; headSha = $evidenceHead; baseSha = $evidenceBase
        mergeResultSha = 'c' * 40; parents = @($evidenceBase, $evidenceHead)
    }
    $evidenceRow = @{
        taskId = 'T-001'; headSha = $evidenceHead; baseSha = $evidenceBase
        observedAt = '2026-01-01T00:00:00Z'; ci = $evidenceCi
        review = @{status = 'approved'; headSha = $evidenceHead; baseSha = $evidenceBase}
        mergeSha = 'd' * 40
    }
    $evidence = @{schemaVersion = 1; projectId = 'first'; tasks = @($evidenceRow)}
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8
    $registry = Join-Path $root 'projects.json'
    @{
        queue = @{ id = 'pilot'; path = 'queue' }
        projects = @(
            @{ id = 'first'; name = 'Первый'; roots = @('Проект А', 'copy')
                progress = @{
                    schemaVersion = 1; asOf = '2026-01-03T00:00:00Z'; decisionsComplete = $true
                    baselines = @(@{ projectId = 'first'; version = 'v1'; approvedAt = '2026-01-01T00:00:00Z'
                        items = @(@{id = 'A'; criteriaVersion = 'v1'; weight = 3}, @{id = 'B'; criteriaVersion = 'v1'; weight = 5})
                    })
                    decisions = @(@{projectId = 'first'; eventId = 'accept-a'; itemId = 'A'; scopeVersion = 'v1'
                        criteriaVersion = 'v1'; at = '2026-01-02T00:00:00Z'; type = 'accepted'; evidenceId = 'synthetic'})
                }
                forecast = @{
                    schemaVersion = 1; scopeVersion = 'v1'; unitsPerDayLow = 1; unitsPerDayHigh = 2
                    workDays = @('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday')
                    planFinish = '2026-01-08'
                }
                cost = @{
                    schemaVersion = 1; asOf = '2026-11-26'; scopeVersion = 'v1'
                    planHours = @(40, 50, 60); planAiRub = @(5000, 5000, 5000); planAiUsd = @(0, 0, 0); planRubPerUsd = 100; planExchangeRateDate = '2026-01-01'; rubPerUsd = 80; exchangeRateDate = '2026-01-02'
                }
                historyPath = 'history.json'
                evidenceSnapshotPath = 'evidence.json'
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
    $badVersions = @($true, '1', [double]1)
    $config = Get-Content -LiteralPath $registry -Raw | ConvertFrom-Json -AsHashtable
    for ($i = 0; $i -lt $badVersions.Count; $i++) {
        $cost = $config.projects[0].cost.Clone()
        $cost.schemaVersion = $badVersions[$i]
        $forecast = $config.projects[0].forecast.Clone()
        $forecast.schemaVersion = $badVersions[$i]
        $config.projects += @{ id = "bad-cost-$i"; name = "Снимок $i"; roots = @('other'); cost = $cost; forecast = $forecast }
        $config.projects[-1].progress = $config.projects[0].progress | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable
        $config.projects[-1].progress.baselines[0].projectId = "bad-cost-$i"
        $config.projects[-1].progress.decisions[0].projectId = "bad-cost-$i"
    }
    $invalidProgress = $config.projects[0].progress | ConvertTo-Json -Depth 8 | ConvertFrom-Json -AsHashtable
    $invalidProgress.schemaVersion = '1'
    $invalidProgress.baselines[0].projectId = 'bad-progress'
    $invalidProgress.decisions[0].projectId = 'bad-progress'
    $config.projects += @{ id = 'bad-progress'; name = 'Invalid progress'; roots = @('other'); progress = $invalidProgress }
    $journalFixture = Join-Path $root 'owner-journal.json'
    $journalBaseline = @{ projectId = 'journal'; version = 'v1'; approvedAt = '2026-01-01T00:00:00Z'
        items = @(@{ id = 'result-a'; criteriaVersion = 'v1'; weight = 3 }, @{ id = 'result-b'; criteriaVersion = 'v1'; weight = 2 }) }
    $journalEvent = @{ projectId = 'journal'; eventId = 'a.1'; itemId = 'result-a'; scopeVersion = 'v1'; criteriaVersion = 'v1'
        type = 'accepted'; at = '2026-01-01T06:00:00Z'; evidenceId = 'synthetic' }
    $journalDocument = @{ schemaVersion = 1; projectId = 'journal'; events = @($journalEvent); coverage = @(foreach ($type in 'accepted','acceptance_revoked') {
        @{ type = $type; from = '2026-01-01T00:00:00Z'; until = '2026-01-02T00:00:00Z' }
    }) }
    [IO.File]::WriteAllText($journalFixture, ($journalDocument | ConvertTo-Json -Depth 8))
    $config.projects += @{
        id = 'journal'; name = 'Журнал'; roots = @('other'); decisionsPath = 'owner-journal.json'; historyPath = 'journal-activity.json'
        decisionTaskByItem = @{ 'result-a' = 'T-001'; 'result-b' = 'T-001' }
        progress = @{ schemaVersion = 1; asOf = '2026-01-01T08:00:00Z'; baselines = @($journalBaseline) }
    }
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registry -Encoding utf8
    $gapFixture = Join-Path $root 'gap.json'
    $gapBaseline = $journalBaseline.Clone()
    $gapBaseline.projectId = 'gap'
    $gapExpanded = @{projectId='gap';version='v2';previousVersion='v1';approvedAt='2026-01-02T06:00:00Z'
        reason='Добавлен отчёт';items=$gapBaseline.items + @(@{id='result-c';criteriaVersion='v1';weight=1})}
    $gap = @{schemaVersion=1;projectId='gap';events=@();coverage=$journalDocument.coverage.Clone()}
    [IO.File]::WriteAllText($gapFixture, ($gap | ConvertTo-Json -Depth 8))
    $config.projects += @{id='gap';name='Gap';roots=@('other');decisionsPath='gap.json';progress=@{schemaVersion=1;asOf='2026-01-02T08:00:00Z';baselines=@($gapBaseline,$gapExpanded)}}
    $config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registry -Encoding utf8
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
    $journalSummary = (Invoke-RestMethod ($url + 'summary') -TimeoutSec 10) | Where-Object id -CEQ 'journal'
    Assert-That ($journalSummary.weightedProgress.percent -eq 60 -and $journalSummary.journal.state -ceq 'readable' -and
        $journalSummary.journal.PSObject.Properties.Name -notcontains 'path') 'PRG-003 loads a confirmed journal snapshot without a path'
    $frame = $journalSummary.frame
    $periodPath = $url + 'period?project=journal&from=2026-01-01&through=2026-01-01'
    $journalPeriod = Invoke-RestMethod ($periodPath + "&frame=$frame") -TimeoutSec 10
    Assert-That ($journalPeriod.report.totals.accepted -eq 1 -and $journalPeriod.journalGeneration -ceq $journalSummary.journal.generation) 'PRG-003 projects journal history from the summary snapshot'
    Assert-That ($journalPeriod.historyState -ceq 'partial' -and $journalPeriod.journalState -ceq 'readable' -and
        $journalPeriod.coverage.accepted.complete -and !$journalPeriod.coverage.merged.complete) 'PTR-VIS-005 unavailable activity history preserves confirmed journal metrics with a partial status'
    $cardVersion = $journalSummary.tasks[0].versions[0].hash
    $journalCard = Invoke-RestMethod ($url + "card?project=journal&task=T-001&version=$cardVersion&frame=$frame") -TimeoutSec 10
    Assert-That ($journalCard.ownerDecisions[0].status -ceq 'accepted' -and
        $journalCard.ownerDecisions[0].itemId -ceq 'result-a') 'PRG-003 projects acceptance onto the bound task version'
    $lateDecision = $journalEvent.Clone()
    $lateDecision.eventId = 'r.1'; $lateDecision.type = 'acceptance_revoked'; $lateDecision.at = '2026-01-01T07:00:00Z'
    $journalDocument.events += $lateDecision
    [IO.File]::WriteAllText($journalFixture, ($journalDocument | ConvertTo-Json -Depth 8))
    $unchanged = Invoke-RestMethod ($periodPath + "&frame=$frame") -TimeoutSec 10
    Assert-That ($unchanged.journalGeneration -ceq $journalSummary.journal.generation -and $unchanged.report.totals.accepted -eq 1) 'PRG-003 preserves the displayed frame before refresh'
    $nextFrame = (Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin=$origin} -TimeoutSec 10) | Where-Object id -CEQ 'journal'
    $oldFrame = Invoke-WebRequest ($periodPath + "&frame=$frame") -SkipHttpErrorCheck -TimeoutSec 10
    Assert-That ($oldFrame.StatusCode -eq 409 -and $nextFrame.weightedProgress.percent -eq 0 -and
        $nextFrame.journal.generation -cne $journalSummary.journal.generation) 'PRG-003 changes all projections together and refuses obsolete frame'
    $gapSummary = (Invoke-RestMethod ($url + 'summary') -TimeoutSec 10) | Where-Object id -CEQ 'gap'
    $gapPath = $url + 'period?project=gap&from=2026-01-01&through=2026-01-02&frame='
    $points = (Invoke-RestMethod ($gapPath + $gapSummary.frame) -TimeoutSec 10).remainingWork.points
    Assert-That ($gapSummary.weightedProgress.state -ceq 'incomplete' -and $points.Count -eq 2 -and
        $points[0].remainingWeight -eq 5 -and $points[1].state -ceq 'incomplete' -and $points[1].scopeChanged -and $points[1].scopeChanges[0].reason -ceq 'Добавлен отчёт') 'PRG-008 HTTP preserves confirmed points before gap'
    foreach ($interval in $gap.coverage) { $interval.until = '2026-01-03T00:00:00Z' }
    [IO.File]::WriteAllText($gapFixture, ($gap | ConvertTo-Json -Depth 8))
    $gapSummary = (Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin=$origin} -TimeoutSec 10) | Where-Object id -CEQ 'gap'
    $points = (Invoke-RestMethod ($gapPath + $gapSummary.frame) -TimeoutSec 10).remainingWork.points
    Assert-That ($points[0].remainingWeight -eq 5 -and $points[1].remainingWeight -eq 6 -and $points[1].scopeChanged) 'PRG-008 HTTP restores points after gap backfill'
    [IO.File]::Delete($journalFixture)
    $staleJournal = (Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin=$origin} -TimeoutSec 10) | Where-Object id -CEQ 'journal'
    Assert-That ($staleJournal.journal.state -ceq 'stale' -and
        $staleJournal.journal.generation -ceq $nextFrame.journal.generation) 'PRG-003 retains the previous journal when the source is unavailable'
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
    $historyBytes = [IO.File]::ReadAllText($history)
    $completeHistory = $historyBytes | ConvertFrom-Json -AsHashtable -DateKind String
    Assert-That ($period.remainingWork.points.Count -eq 1 -and
        $period.remainingWork.points[0].state -ceq 'incomplete' -and
        $null -eq $period.remainingWork.points[0].PSObject.Properties['remainingWeight']) 'PRG-008 refuses cumulative weight where revocation coverage is missing'
    $completeHistory.coverage += @{ type = 'acceptance_revoked'; from = '2026-01-01T00:00:00Z'; until = '2026-01-02T00:00:00Z' }
    try {
        [IO.File]::WriteAllText($history, ($completeHistory | ConvertTo-Json -Depth 6))
        $completePeriod = Invoke-RestMethod $periodUri -TimeoutSec 10
        Assert-That ($completePeriod.coverage.accepted.complete -and $completePeriod.coverage.accepted.gaps.Count -eq 0 -and
            $completePeriod.report.totals.accepted -eq 1) 'PTR-VIS-005 acceptance coverage includes revocations'
        $point = $completePeriod.remainingWork.points[0]
        Assert-That ($point.state -ceq 'available' -and $point.date -ceq '2026-01-01' -and
            $point.totalWeight -eq 8 -and $point.remainingWeight -eq 8 -and
            $point.acceptedWeight -eq 0) 'PRG-003 restores confirmed weight independently of merged or accepted event count'
    } finally {
        [IO.File]::WriteAllText($history, $historyBytes)
    }
    Assert-That ($wire.sourceFreshness.tasks.Count -eq 2 -and $wire.sourceFreshness.tasks[0].updated -and
        !$wire.sourceFreshness.tasks[0].stale -and
        $wire.sourceFreshness.tasks[0].PSObject.Properties.Name -notcontains 'path' -and
        $wire.sourceFreshness.queue.updated) 'PTR-VIS-013 source freshness excludes paths'
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
    $validHistoryJson = [IO.File]::ReadAllText($history)
    try {
        foreach ($version in 'true', '"1"', '1.0', '[1]') {
            $invalidHistoryJson = $validHistoryJson -replace '("schemaVersion"\s*:\s*)1', ('${1}' + $version)
            [IO.File]::WriteAllText($history, $invalidHistoryJson)
            $invalidPeriod = Invoke-RestMethod $periodUri -TimeoutSec 10
            Assert-That ($invalidPeriod.historyState -ceq 'unavailable' -and $null -eq $invalidPeriod.report) "T-154 history rejects schemaVersion $version"
        }
    } finally {
        [IO.File]::WriteAllText($history, $validHistoryJson)
    }
    $first = Invoke-RestMethod ($url + 'summary') -TimeoutSec 10
    Assert-That ($first[0].weightedProgress.state -ceq 'available' -and $first[0].weightedProgress.percent -eq 37.5 -and
        $first[0].weightedProgress.remainingWeight -eq 5 -and $first[1].weightedProgress.state -ceq 'unconfigured') 'PRG-003 weighted progress is isolated by project'
    $forecast = $first[0].dateForecast
    Assert-That ($forecast.state -ceq 'available' -and $forecast.method -ceq 'scenario' -and
        $forecast.asOf -ceq '2026-01-03' -and $forecast.earliest -ceq '2026-01-07' -and
        $forecast.latest -ceq '2026-01-09' -and $forecast.earliestDeltaDays -eq -1 -and
        $forecast.latestDeltaDays -eq 1) 'PRG-007 scenario range and plan deltas reach the project summary'
    Assert-That ($first[1].dateForecast.state -ceq 'not_assessed' -and
        $first[1].dateForecast.reason -ceq 'configuration_unavailable') 'PRG-008 forecast settings are isolated by project'
    $invalidProgress = $first | Where-Object id -CEQ 'bad-progress'
    Assert-That ($invalidProgress.weightedProgress.state -ceq 'invalid') 'T-154 progress rejects a string schema version'
    $invalidCosts = @($first | Where-Object id -Like 'bad-cost-*')
    Assert-That ($invalidCosts.Count -eq 3 -and @($invalidCosts | Where-Object { $_.cost.state -cne 'invalid' }).Count -eq 0) 'PRG-014 rejects boolean, string and floating-point JSON schema versions'
    Assert-That (@($invalidCosts | Where-Object { $_.dateForecast.reason -cne 'invalid_configuration' }).Count -eq 0) 'PRG-011 forecast rejects non-integer schema versions'
    Assert-That ($first[0].cost.state -ceq 'available' -and $first[0].cost.asOf -ceq '2026-11-26' -and
        $first[0].cost.values.plan.totalRub[1] -eq 80000 -and $first[0].cost.values.plan.totalUsd[1] -eq 800 -and
        $null -eq $first[0].cost.values.forecast.totalRub -and $first[1].cost.state -ceq 'unconfigured') 'PRG-012 cost snapshot is isolated by project'
    $rates = $first[0].cost.exchange
    Assert-That ($rates.plan.rubPerUsd -eq 100 -and $rates.plan.effectiveDate -ceq '2026-01-01' -and
        $rates.plan.source -ceq 'manual' -and $rates.forecast.rubPerUsd -eq 80 -and
        $rates.forecast.effectiveDate -ceq '2026-01-02' -and $rates.forecast.source -ceq 'manual') 'PRG-014 HTTP exposes independent plan and forecast rates'
    $view = $first[0].tasks[0].evidence
    $validEvidenceJson = [IO.File]::ReadAllText($evidenceFile)
    try {
        foreach ($version in 'true', '"1"', '1.0', '[1]') {
            $invalidEvidenceJson = $validEvidenceJson -replace '("schemaVersion"\s*:\s*)1', ('${1}' + $version)
            [IO.File]::WriteAllText($evidenceFile, $invalidEvidenceJson)
            $invalidEvidence = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin = $origin} -TimeoutSec 10
            $candidate = $invalidEvidence[0].tasks[0].evidence
            Assert-That ($candidate.state -ceq 'stale' -and $candidate.record.headSha -ceq $view.record.headSha) "T-154 evidence rejects schemaVersion $version"
        }
    } finally {
        [IO.File]::WriteAllText($evidenceFile, $validEvidenceJson)
    }
    Assert-That ($view.state -ceq 'readable' -and $view.record.ci.current -and $view.record.review.current -and
        !$view.record.ownerAcceptance -and $view.record.mergeSha -and !$first[1].tasks[0].evidence -and
        (($view | ConvertTo-Json -Depth 8) -notmatch 'evidence\.json')) 'PTR-VIS-007 isolated evidence and independent acceptance'
    $evidenceRow.baseSha = 'e' * 40
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8
    $changedEvidence = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin = $origin} -TimeoutSec 10
    Assert-That (!$changedEvidence[0].tasks[0].evidence.record.ci.current -and
        !$changedEvidence[0].tasks[0].evidence.record.review.current) 'PTR-VIS-007 base change marks evidence historical'
    $evidenceRow.baseSha = $evidenceBase
    $evidenceRow.headSha = 'e' * 40
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8
    $changedEvidence = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin = $origin} -TimeoutSec 10
    Assert-That (!$changedEvidence[0].tasks[0].evidence.record.ci.current -and
        !$changedEvidence[0].tasks[0].evidence.record.review.current) 'PTR-VIS-007 head change marks evidence historical'
    $evidenceCi.parents = @($evidenceHead, $evidenceBase)
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8
    $staleEvidence = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin = $origin} -TimeoutSec 10
    Assert-That ($staleEvidence[0].tasks[0].evidence.state -ceq 'stale' -and
        $staleEvidence[0].tasks[0].evidence.record.baseSha -ceq $evidenceBase) 'PTR-VIS-007 invalid parents keep last snapshot'
    $evidenceCi.parents = @($evidenceBase, $evidenceHead)
    $evidenceRow.headSha = $evidenceHead
    $evidenceRow.ownerAcceptance = @{status = 'accepted'; decidedAt = '2026-01-01T01:00:00Z'}
    $evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidenceFile -Encoding utf8
    $recovered = Invoke-RestMethod ($url + 'refresh') -Method Post -Headers @{Origin = $origin} -TimeoutSec 10
    Assert-That ($recovered[0].tasks[0].evidence.state -ceq 'readable' -and
        $recovered[0].tasks[0].evidence.record.ownerAcceptance.status -ceq 'accepted') 'PTR-VIS-007 recovery and explicit acceptance'
    Assert-That ($first[0].historyConfigured -and !$first[1].historyConfigured) 'PTR-VIS-005 summary distinguishes history configuration by project'
    Assert-That ($first.Count -eq (5 + [int][bool]$V2Root + $badVersions.Count) -and $first[1].tasks[0].versions[0].status -eq 'merged') 'PTR-001 independent projects'
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
    Assert-That ($first[1].tasks[0].versions[0].assignee -ceq 'Kimi' -and $first[1].tasks[0].versions[0].status -ceq 'merged') 'PTR-002 Markdown list status and inline assignee'
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
