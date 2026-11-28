#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RegistryPath,
    [ValidateRange(1024, 65535)][int]$Port = 8765
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false, $true)

Import-Module (Join-Path $PSScriptRoot 'lib/ProjectPeriod.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/ProjectProgress.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/ProjectRemainingWork.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/ProjectForecast.psm1')
Import-Module (Join-Path $PSScriptRoot 'lib/ProjectCost.psm1')

function Read-Field([string]$Card, [string]$Label) {
    $marker = if ($Label -eq 'Статус') { '(?:-[ \t]+)?' } else { '' }
    $match = [regex]::Match($Card, '(?im)^[ \t]*' + $marker + '(?:\*\*)?' + [regex]::Escape($Label) +
        '[ \t]*:(?:\*\*)?[ \t]*(?<value>[^\r\n]*)')
    $match.Groups['value'].Value.Trim().Trim('*')
}

function Assert-PlainPath([string]$Path, [bool]$Directory) {
    $cursor = Get-Item -LiteralPath $Path -Force
    if ($cursor.PSIsContainer -ne $Directory) { throw 'WRONG_PATH_TYPE' }
    while ($null -ne $cursor) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'REPARSE_POINT' }
        if ($cursor -is [IO.FileInfo]) { $cursor = $cursor.Directory }
        else { $cursor = $cursor.Parent }
    }
}

function Read-TransitionDate([string]$Card, [string]$Label) {
    Read-ObservedInstant (Read-Field $Card $Label)
}

function Read-ObservedInstant($value) {
    if ($value -isnot [string]) { return $null }
    $instant = [DateTimeOffset]::MinValue
    if ($value -cmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -and
        [DateTimeOffset]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$instant) -and $instant -le [DateTimeOffset]::UtcNow) {
        return $instant.ToUniversalTime().ToString('o')
    }
    return $null
}

function Read-Card([IO.FileInfo]$File, [string]$Source) {
    Assert-PlainPath $File.FullName $false
    $bytes = [IO.File]::ReadAllBytes($File.FullName)
    $card = $utf8.GetString($bytes).TrimStart([char]0xFEFF)
    $title = [regex]::Match($card, '(?m)^# (.+)').Groups[1].Value.Trim()
    $head = Read-Field $card 'PR_HEAD_SHA'
    $base = Read-Field $card 'PR_BASE_SHA'
    $ciHead = Read-Field $card 'CI_HEAD_SHA'
    $ciBase = Read-Field $card 'CI_BASE_SHA'
    $sha = '^[0-9a-f]{40}$'
    $binding = 'unknown'
    if (($head -match $sha -and $ciHead -match $sha -and $head -ne $ciHead) -or
        ($base -match $sha -and $ciBase -match $sha -and $base -ne $ciBase)) {
        $binding = 'previous'
    } elseif ($head -match $sha -and $base -match $sha -and $head -eq $ciHead -and $base -eq $ciBase) {
        $binding = 'matches'
    }
    $links = @([regex]::Matches($card, 'https://github\.com/[\w.-]+/[\w.-]+/(?:pull/[0-9]+|actions/runs/[0-9]+(?:/job/[0-9]+)?)(?![\w/?#-])') |
        ForEach-Object Value | Select-Object -Unique)
    $status = Read-Field $card 'Статус'
    $assignee = Read-Field $card 'Исполнитель'
    if (!$assignee) {
        $assignee = [regex]::Match($card, '(?im)\bИсполнитель(?: и координатор)?:(?:\*\*)?[ \t]*([^.\r\n·]+)').Groups[1].Value.Trim()
    }
    @{
        hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        title = $title
        status = [regex]::Match($status, '^[a-zA-Z][a-zA-Z0-9_-]*(?=[\s.;·]|$)').Value
        assignee = $assignee
        blocker = Read-Field $card 'Блокер'
        statusSince = Read-TransitionDate $card 'Статус с'
        blockedSince = Read-TransitionDate $card 'Блокировка с'
        nextAction = Read-Field $card 'Следующее действие'
        needsDecision = (Read-Field $card 'Решение владельца') -eq 'ожидается'
        source = $Source
        links = $links
        binding = $binding
        text = $card
    }
}

function Update-Projects {
    foreach ($project in $projects) {
        foreach ($source in $project.sources) {
            $source.error = $null
            try {
                $folder = Join-Path $source.path 'tasks'
                Assert-PlainPath $folder $true
                $files = @(Get-ChildItem -LiteralPath $folder -File -Filter 'T-*.md')
            } catch {
                $source.error = 'Папка задач недоступна'
                continue
            }
            $cards = @{}
            foreach ($file in $files) {
                if ($file.Name -cnotmatch '^(T-[0-9]{3,})(?:-[^.]+)?\.md$') { continue }
                $id = $Matches[1]
                try {
                    $cards[$file.Name] = @{ id = $id; version = Read-Card $file (Join-Path $source.path "tasks/$($file.Name)"); stale = $false }
                } catch {
                    $source.error = 'Некоторые карточки недоступны'
                    if ($source.cards.ContainsKey($file.Name)) {
                        $cards[$file.Name] = $source.cards[$file.Name]
                        $cards[$file.Name].stale = $true
                    } else {
                        $cards[$file.Name] = @{ id = $id; version = $null; stale = $true }
                    }
                }
            }
            $source.cards = $cards
            if (!$source.error) { $source.updated = [DateTimeOffset]::Now.ToString('o') }
        }
    }
}

function Read-QueueCopy($Folder, $Id) {
    if (!$Folder) { return @{ state = 'unavailable' } }
    try {
        $path = Join-Path $Folder "$Id.md"
        $file = [IO.FileInfo]::new($path)
        $attributes = [IO.File]::GetAttributes($path)
        if ($attributes -band ([IO.FileAttributes]::Directory -bor [IO.FileAttributes]::ReparsePoint)) {
            throw 'INVALID_QUEUE_FILE'
        }
        if ($file.Length -gt 1048576) { throw 'QUEUE_FILE_TOO_LARGE' }
        $bytes = [IO.File]::ReadAllBytes($path)
        $text = $utf8.GetString($bytes).TrimStart([char]0xFEFF)
        if ([string]::IsNullOrWhiteSpace($text)) { throw 'EMPTY_QUEUE_FILE' }
        return @{ state = 'readable'; text = $text; hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)) }
    } catch [IO.FileNotFoundException] {
        return @{ state = 'missing' }
    } catch {
        return @{ state = 'unavailable' }
    }
}

function Update-Queue {
    if (!$queue) { return }
    $folders = @{}
    try {
        Assert-PlainPath $queue.path $true
        $folders.tasks = Join-Path $queue.path 'tasks'
        Assert-PlainPath $folders.tasks $true
        $files = @(Get-ChildItem -LiteralPath $folders.tasks -File -Filter '*.md' -Force)
    } catch {
        $queue.stale = $true
        return
    }
    foreach ($name in 'reports','accepted') {
        $path = Join-Path $queue.path $name
        try { Assert-PlainPath $path $true; $folders[$name] = $path } catch { $folders[$name] = $null }
    }
    $items = @{}
    foreach ($file in $files) {
        $id = $file.BaseName
        if ($id -cnotmatch '\A[A-Z0-9]+(?:-[A-Z0-9]+)*\z') { continue }
        $card = Read-QueueCopy $folders.tasks $id
        $report = Read-QueueCopy $folders.reports $id
        $accepted = Read-QueueCopy $folders.accepted $id
        $state = 'unknown'
        if ($card.state -eq 'readable') {
            if ($accepted.state -eq 'readable') { $state = 'accepted' }
            elseif ($accepted.state -eq 'missing' -and $report.state -eq 'readable') { $state = 'reported' }
            elseif ($accepted.state -eq 'missing' -and $report.state -eq 'missing') { $state = 'assigned' }
        }
        $comparison = 'unavailable'
        if ($report.state -eq 'readable' -and $accepted.state -eq 'readable') {
            $comparison = if ($report.hash -ceq $accepted.hash) { 'match' } else { 'conflict' }
        } elseif ($report.state -eq 'missing') { $comparison = 'missing' }
        $items[$id] = @{
            id = $id; state = $state; comparison = $comparison; cardState = $card.state
            assignee = if ($card.state -eq 'readable') { Read-Field $card.text 'Исполнитель' } else { '' }
            report = $report; accepted = $accepted
            lastKnown = if ($state -eq 'unknown' -and $queue.items.ContainsKey($id)) {
                $previous = $queue.items[$id]
                if ($previous.state -eq 'unknown') { $previous.lastKnown } else { @{ state = $previous.state; updated = $queue.updated } }
            } else { $null }
        }
    }
    $queue.items = $items
    $queue.stale = $false
    $queue.updated = [DateTimeOffset]::UtcNow.ToString('o')
}

function Get-AssignmentView($Item) {
    $view = $Item.Clone()
    foreach ($name in 'report','accepted') {
        $view[$name] = $Item[$name].Clone()
        $view[$name].Remove('text')
    }
    return $view
}

function Get-TrackerAction($Task, $Project, $Assignments) {
    $instruction = $Project.ownerActions[$Task.id]
    if ($instruction) {
        $missing = @($instruction.requires | Where-Object {
            $queue.stale -or !$queue.items.ContainsKey($_) -or
                $queue.items[$_].state -ne 'accepted' -or $queue.items[$_].comparison -ne 'match'
        })
        return @{ text = $instruction.text; blocked = [bool]$missing.Count; assignments = $missing }
    }
    $versions = @($Task.versions.Values | Where-Object { $_.sources.stale -contains $false })
    if (!$versions.Count -or @($versions | Where-Object status -NotIn 'merged','closed','accepted','done').Count -eq 0) { return }
    if ($versions.needsDecision -contains $true) { return @{ text = 'Получить решение владельца' } }
    if (!$queue.stale) {
        $conflicts = @($Assignments | Where-Object comparison -EQ 'conflict')
        if ($conflicts.Count) { return @{ text = 'Сверить версии отчёта'; assignments = @($conflicts.id) } }
    }
    if ($Project.bindings.ContainsKey($Task.id) -and ($queue.stale  -or
        @($Assignments | Where-Object { $_.state -eq 'unknown' -or ($_.accepted.state -eq 'readable' -and $_.report.state -eq 'unavailable') }).Count)) {
        return @{ text = 'Восстановить доступ к источнику'; assignments = $Project.bindings[$Task.id] }
    }
    if (@($versions | Where-Object blocker).Count) { return @{ text = 'Устранить блокер' } }
    $pending = @($Assignments | Where-Object state -EQ 'reported')
    if ($pending.Count) {
        $label = if ($pending.Count -eq 1) { 'Проверить отчёт' } else { "Проверить отчёты ($($pending.Count))" }
        return @{ text = $label; assignments = @($pending.id) }
    }
}

function Read-EvidenceSnapshot($Project) {
    $path = $Project.evidencePath
    Assert-PlainPath $path $false
    $share = [IO.FileShare]::Read -bor [IO.FileShare]::Delete
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try {
        if ($stream.Length -gt 4MB) { throw 'EVIDENCE_SIZE_LIMIT' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes)
        if ($stream.ReadByte() -ne -1) { throw 'EVIDENCE_SIZE_CHANGED' }
    } finally { $stream.Dispose() }
    $data = $utf8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json -AsHashtable -DateKind String -Depth 16
    if ($data -isnot [Collections.IDictionary] -or $data['schemaVersion'] -ne 1 -or
        $data['projectId'] -cne $Project.id -or $data['tasks'] -isnot [array]) { throw 'INVALID_EVIDENCE' }
    $items = @{}
    $sha = '\A[0-9a-f]{40}\z'
    foreach ($row in $data['tasks']) {
        if ($row -isnot [Collections.IDictionary] -or $row['taskId'] -cnotmatch '\AT-[0-9]{3,}\z' -or
            $items.ContainsKey($row['taskId']) -or $row['headSha'] -cnotmatch $sha -or $row['baseSha'] -cnotmatch $sha) {
            throw 'INVALID_EVIDENCE_TASK'
        }
        $observed = Read-ObservedInstant $row['observedAt']
        if ($null -eq $observed) { throw 'INVALID_EVIDENCE_DATE' }
        $result = @{ headSha = $row['headSha']; baseSha = $row['baseSha']; observedAt = $observed; review = $null; ci = $null; mergeSha = $null; ownerAcceptance = $null }
        foreach ($kind in 'review','ci') {
            $fact = $row[$kind]
            if ($null -eq $fact) { continue }
            $allowed = if ($kind -eq 'review') { @('approved','changes_requested') } else { @('success','failure','pending') }
            if ($fact -isnot [Collections.IDictionary] -or $fact['status'] -cnotin $allowed -or
                $fact['headSha'] -cnotmatch $sha -or $fact['baseSha'] -cnotmatch $sha) { throw 'INVALID_EVIDENCE_FACT' }
            $view = @{
                status = $fact['status']; headSha = $fact['headSha']; baseSha = $fact['baseSha']
                current = $fact['headSha'] -ceq $result.headSha -and $fact['baseSha'] -ceq $result.baseSha
            }
            if ($kind -eq 'ci') {
                if ($fact['mergeResultSha'] -cnotmatch $sha -or $fact['parents'] -isnot [array] -or
                    $fact['parents'].Count -ne 2 -or $fact['parents'][0] -cne $fact['baseSha'] -or
                    $fact['parents'][1] -cne $fact['headSha']) { throw 'INVALID_EVIDENCE_CI' }
                $view.mergeResultSha = $fact['mergeResultSha']
            }
            $result[$kind] = $view
        }
        if ($null -ne $row['mergeSha']) {
            if ($row['mergeSha'] -cnotmatch $sha) { throw 'INVALID_EVIDENCE_MERGE' }
            $result.mergeSha = $row['mergeSha']
        }
        $decision = $row['ownerAcceptance']
        if ($null -ne $decision) {
            if ($decision -isnot [Collections.IDictionary] -or $decision['status'] -cnotin 'accepted','revoked') {
                throw 'INVALID_EVIDENCE_DECISION'
            }
            $decided = Read-ObservedInstant $decision['decidedAt']
            if ($null -eq $decided) { throw 'INVALID_EVIDENCE_DATE' }
            $result.ownerAcceptance = @{ status = $decision['status']; decidedAt = $decided }
        }
        $items.Add($row['taskId'], $result)
    }
    $items
}

function Update-Evidence {
    foreach ($project in $projects) {
        if (!$project.evidencePath) { continue }
        try {
            $project.evidence = Read-EvidenceSnapshot $project
            $project.evidenceState = 'readable'
        } catch {
            $project.evidenceState = if ($null -eq $project.evidence) { 'unavailable' } else { 'stale' }
        }
    }
}

function Test-DecisionFrame($Project, $Request, $Response) {
    if (!$Project.decisionsPath) { return $true }
    $frame = $Request.QueryString['frame']
    if ($frame -ceq $Project.decisionFrame) { return $true }
    $Response.StatusCode = if ($frame) { 409 } else { 400 }
    return $false
}

function Update-DecisionJournals {
    foreach ($project in $projects) {
        if (!$project.decisionsPath) { continue }
        $project.decisionFrame = [guid]::NewGuid().ToString('N')
        try {
            Assert-PlainPath $project.decisionsPath $false
            $candidate = Read-ProjectDecisionJournal -Path $project.decisionsPath -ProjectId $project.id -Baselines $project.progressInput.baselines
            $computed = Get-ProjectJournalProgress -Snapshot $candidate -ProjectId $project.id -Baselines $project.progressInput.baselines -AsOf $project.decisionAsOf
            $active = @($project.progressInput.baselines | Where-Object {
                (Read-ObservedInstant $_['approvedAt']) -le $project.decisionAsOf
            } | Select-Object -Last 1)
            $items = @(if ($active.Count) { $active[0]['items'] })
            $viewArgs = @{ Snapshot = $candidate; TaskByItem = $project.decisionTaskByItem; AsOf = $project.decisionAsOf; ActiveItems = $items }
            $project.decisionView = Get-ProjectDecisionView @viewArgs
            $project.decisionSnapshot = $candidate
            $project.decisionReadAt = [DateTimeOffset]::UtcNow
            $project.decisionState = 'readable'
            $project.weightedProgress = $computed
        } catch {
            $project.decisionState = if ($null -ne $project.decisionSnapshot) { 'stale' } else { 'unavailable' }
            if ($null -eq $project.decisionSnapshot) { $project.weightedProgress = @{ state = 'incomplete' } }
        }
        $project.dateForecast = Read-ProjectDateForecast $project.registryEntry $project.weightedProgress $project.timeline
    }
}

function Get-Summary {
    foreach ($project in $projects) {
        $tasks = @{}
        foreach ($source in $project.sources) {
            foreach ($name in $source.cards.Keys) {
                $record = $source.cards[$name]
                if (!$tasks.ContainsKey($record.id)) {
                    $tasks[$record.id] = @{ id = $record.id; versions = @{}; unreadable = @() }
                }
                $task = $tasks[$record.id]
                if ($null -eq $record.version) {
                    $task.unreadable += Join-Path $source.path "tasks/$name"
                    continue
                }
                $version = $record.version
                if (!$task.versions.ContainsKey($version.hash)) {
                    $view = $version.Clone()
                    $view.Remove('text')
                    $view.Remove('source')
                    $view.sources = @()
                    $task.versions[$version.hash] = $view
                }
                $task.versions[$version.hash].sources += @{
                    path = $version.source
                    stale = $record.stale -or $source.error -eq 'Папка задач недоступна'
                }
            }
        }
        $summary = @{
            id = $project.id
            name = $project.name
            historyConfigured = [bool]$project.historyPath
            dateForecast = $project.dateForecast
            weightedProgress = $project.weightedProgress
            cost = if ($project.cost.ContainsKey('exchange') -and $project.cost.exchange.ContainsKey('forecast') -and $project.cost.exchange.forecast.source -ceq 'cbr') {
                Read-ProjectCostSnapshot $project.registryEntry $fxState.latest
            } else { $project.cost }
            timeline = if ($project.timeline) {
                @{
                    startDate = $project.timeline.startDate
                    timeZone = $project.timeline.zone.Id
                    today = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $project.timeline.zone).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                    stages = $project.timeline.stages
                }
            } else { $null }
            sources = @($project.sources | ForEach-Object { @{ path = $_.path; error = $_.error; updated = $_.updated } })
            queue = if ($queue) { @{ id = $queue.id; stale = $queue.stale; updated = $queue.updated } } else { $null }
            unlinkedAssignments = @(if ($queue) { $queue.items.Values | Where-Object { !$boundAssignments.Contains($_.id) } | Sort-Object id | ForEach-Object { Get-AssignmentView $_ } })
            tasks = @($tasks.Values | Sort-Object { $_.id.Length }, id | ForEach-Object {
                $task = $_
                $assignments = @(foreach ($assignmentId in $project.bindings[$task.id]) {
                    if ($queue.items.ContainsKey($assignmentId)) { Get-AssignmentView $queue.items[$assignmentId] }
                    else { @{ id = $assignmentId; state = 'unknown'; comparison = 'unavailable' } }
                })
                @{
                    id = $task.id; unreadable = $task.unreadable; versions = @($task.versions.Values | Sort-Object hash)
                    evidence = if ($project.evidencePath) {
                        @{ state = $project.evidenceState; record = if ($null -ne $project.evidence) { $project.evidence[$task.id] } }
                    }
                    assignments = $assignments
                    action = if ($queue) { Get-TrackerAction $task $project $assignments } else { $null }
                }
            })
        }
        if ($project.decisionsPath) {
            $summary.frame = $project.decisionFrame
            $summary.journal = @{
                state = $project.decisionState
                readAt = $project.decisionReadAt
                unmappedCount = if ($null -ne $project.decisionView) { $project.decisionView.unmappedItems.Count } else { 0 }
                generation = if ($null -ne $project.decisionSnapshot) { $project.decisionSnapshot.sha256 }
            }
        }
        $summary
    }
}

function Read-ProjectTimeline($Entry) {
    if (!$Entry.Contains('timeline')) { return $null }
    $timeline = $Entry.timeline
    if ($timeline -isnot [Collections.IDictionary] -or $timeline.timeZone -isnot [string] -or
        !$timeline.timeZone.Trim() -or $timeline.stages -isnot [array]) { throw 'INVALID_PROJECT_TIMELINE' }
    try { $zone = [TimeZoneInfo]::FindSystemTimeZoneById($timeline.timeZone) }
    catch { throw 'INVALID_PROJECT_TIME_ZONE' }
    $stageIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $stages = @(foreach ($stage in $timeline.stages) {
        if ($stage -isnot [Collections.IDictionary] -or $stage.id -isnot [string] -or
            $stage.id -cnotmatch '\A[a-z0-9][a-z0-9-]{0,63}\z' -or !$stageIds.Add($stage.id) -or
            $stage.name -isnot [string] -or !$stage.name.Trim() -or $stage.taskIds -isnot [array]) {
            throw 'INVALID_PROJECT_STAGE'
        }
        $taskIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($id in $stage.taskIds) {
            if ($id -isnot [string] -or $id -cnotmatch '\AT-[0-9]{3,}\z' -or !$taskIds.Add($id)) {
                throw 'INVALID_STAGE_TASK_ID'
            }
        }
        @{
            id = $stage.id
            name = $stage.name
            plannedDate = Read-TimelineDate $stage['plannedDate']
            actualDate = Read-TimelineDate $stage['actualDate']
            taskIds = $stage.taskIds
        }
    })
    @{ startDate = Read-TimelineDate $timeline['startDate']; zone = $zone; stages = $stages }
}

function Read-TimelineDate($Value) {
    if ($null -eq $Value) { return $null }
    $date = [DateOnly]::MinValue
    if ($Value -isnot [string] -or ![DateOnly]::TryParseExact($Value, 'yyyy-MM-dd',
        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date)) {
        throw 'INVALID_PROJECT_TIMELINE_DATE'
    }
    return $Value
}

function Get-RemainingWorkView($Project, $Period, $Zone, $History) {
    $data = $Project.progressInput
    if ($null -eq $data) { return @{ state = 'unconfigured'; points = @() } }
    if ($null -eq $History) { return @{ state = 'incomplete'; points = @() } }
    if ($Project.decisionsPath) {
        # A coverage gap at the current cutoff can coexist with verified earlier points.
        if ($null -eq $Project.decisionSnapshot) { return @{ state = 'incomplete'; points = @() } }
        $cutoff = $Project.decisionAsOf
    } else {
        if ($Project.weightedProgress.state -cne 'available') {
            return @{ state = 'incomplete'; points = @() }
        }
        $cutoff = $Project.weightedProgress.asOf
    }
    if ($cutoff -gt $Period.SnapshotAt) { $cutoff = $Period.SnapshotAt }
    $lastDate = [DateOnly]::FromDateTime([TimeZoneInfo]::ConvertTime($cutoff, $Zone).DateTime)
    if ($lastDate -gt $Period.Through) { $lastDate = $Period.Through }
    if ($lastDate -lt $Period.From) { return @{ state = 'before_period'; points = @() } }
    $intervals = @($History.coverage | Where-Object { $_.type -cin 'accepted', 'acceptance_revoked' })
    $decisions = @(if ($Project.decisionsPath) { $Project.decisionSnapshot.document.events } else { $data.decisions })
    Get-ProjectRemainingWork -ProjectId $Project.id -From $Period.From -Through $lastDate -SnapshotAt $cutoff -TimeZone $Zone -Baselines $data.baselines -Decisions $decisions -Coverage $intervals -Checkpoint $data['checkpoint']
}

function Read-WeightedProgress($Entry) {
    if (!$Entry.Contains('progress')) { return @{ state = 'unconfigured' } }
    try {
        $data = $Entry.progress
        if ($data -isnot [Collections.IDictionary] -or $data.schemaVersion -cne 1 -or
            $data.baselines -isnot [array] -or $data.decisions -isnot [array] -or
            $data.decisionsComplete -isnot [bool]) { throw 'INVALID_PROGRESS_SNAPSHOT' }
        if (!$data.decisionsComplete) { return @{ state = 'incomplete' } }
        $asOf = Read-ObservedInstant $data.asOf
        if ($null -eq $asOf) { throw 'INVALID_PROGRESS_CUTOFF' }
        Get-ProjectProgress -ProjectId $Entry.id -AsOf $asOf -Baselines $data.baselines -Decisions $data.decisions
    } catch {
        @{ state = 'invalid' }
    }
}

function Read-ProjectDateForecast($Entry, $Progress, $Timeline) {
    if (!$Entry.Contains('forecast')) { return @{ state = 'not_assessed'; reason = 'configuration_unavailable' } }
    if ($Progress.state -cne 'available') { return @{ state = 'not_assessed'; reason = 'scope_unavailable' } }
    try {
        $config = $Entry['forecast']
        if ($config -isnot [Collections.IDictionary] -or
            ($config['schemaVersion'] -isnot [int] -and $config['schemaVersion'] -isnot [long]) -or
            $config['schemaVersion'] -ne 1) {
            throw 'FORECAST_INVALID_CONFIGURATION'
        }
        if ($config['scopeVersion'] -cne $Progress.scopeVersion) {
            return @{ state = 'not_assessed'; reason = 'scope_version_mismatch' }
        }
        $zone = if ($Timeline) { $Timeline.zone } else { [TimeZoneInfo]::Utc }
        $date = [DateOnly]::FromDateTime([TimeZoneInfo]::ConvertTime($Progress.asOf, $zone).DateTime)
        $arguments = @{ AsOf = $date; RemainingWeight = $Progress.remainingWeight }
        foreach ($name in 'UnitsPerDayLow','UnitsPerDayHigh','WorkDays','DaysOff','PlanFinish','NotBefore','CompletedAt','UnresolvedBlocker') {
            $key = $name.Substring(0,1).ToLowerInvariant() + $name.Substring(1)
            if (!$config.Contains($key) -or $null -eq $config[$key]) { continue }
            $value = $config[$key]
            switch ($name) {
                { $_ -in 'UnitsPerDayLow','UnitsPerDayHigh' } {
                    if ($value -isnot [long] -and $value -isnot [double] -and $value -isnot [decimal]) {
                        throw 'FORECAST_INVALID_PACE'
                    }
                }
                'WorkDays' {
                    $dayNames = [Enum]::GetNames([DayOfWeek])
                    if ($value -isnot [array] -or @($value | Where-Object { $_ -isnot [string] -or $_ -cnotin $dayNames }).Count) {
                        throw 'FORECAST_INVALID_WORK_DAYS'
                    }
                }
                'DaysOff' {
                    if ($value -isnot [array]) { throw 'FORECAST_INVALID_DAYS_OFF' }
                    $value = @($value | ForEach-Object {
                        [DateOnly]::ParseExact((Read-TimelineDate $_), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                    })
                }
                { $_ -in 'PlanFinish','NotBefore','CompletedAt' } {
                    $value = [DateOnly]::ParseExact((Read-TimelineDate $value), 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                }
            }
            $arguments[$name] = $value
        }
        if ($arguments.ContainsKey('UnresolvedBlocker') -and $arguments.UnresolvedBlocker -isnot [bool]) {
            throw 'FORECAST_INVALID_BLOCKER'
        }
        $forecast = Get-ProjectDateForecast @arguments
        foreach ($field in 'asOf','planFinish','earliest','latest','completedAt') {
            if ($null -ne $forecast[$field]) {
                $forecast[$field] = $forecast[$field].ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            }
        }
        $forecast
    } catch {
        @{ state = 'not_assessed'; reason = 'invalid_configuration' }
    }
}

function Read-ProjectCostSnapshot($Entry, $Fx = $null) {
    if (!$Entry.Contains('cost')) { return @{ state = 'unconfigured' } }
    try {
        $cost = $Entry.cost
        if ($cost -isnot [Collections.IDictionary]) { throw 'INVALID_COST_SNAPSHOT' }
        $schemaVersion = $cost['schemaVersion']
        if (($schemaVersion -isnot [int] -and $schemaVersion -isnot [long]) -or $schemaVersion -ne 1) {
            throw 'INVALID_COST_SNAPSHOT'
        }
        $date = Read-TimelineDate $cost.asOf
        $scope = $cost.scopeVersion
        if ($scope -isnot [string] -or $scope -cnotmatch '\A[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}\z') { throw 'INVALID_COST_SCOPE' }

        $inputs = @{}
        foreach ($name in 'PlanHours','PlanAiRub','PlanAiUsd','RemainingHours','RemainingAiRub','RemainingAiUsd',
            'PlanRateRub','PlanRubPerUsd','RateRub','RubPerUsd','ConfirmedLaborRub','ConfirmedAiRub','ConfirmedAiUsd') {
            $key = $name.Substring(0,1).ToLowerInvariant() + $name.Substring(1)
            if (!$cost.Contains($key) -or $null -eq $cost[$key]) { continue }
            $value = $cost[$key]
            if ($name -match 'RateRub|RubPerUsd|Confirmed' -and $value -isnot [long] -and
                $value -isnot [double] -and $value -isnot [decimal]) { throw 'INVALID_COST_VALUE' }
            $inputs[$name] = $value
        }
        $mode = $cost['exchangeRateMode']
        if ($null -ne $mode -and $mode -cnotin @('manual', 'cbr')) { throw 'INVALID_COST_FX_MODE' }
        $exchange = @{}
        foreach ($kind in 'plan', 'forecast') {
            $parameter = if ($kind -ceq 'plan') { 'PlanRubPerUsd' } else { 'RubPerUsd' }
            $dateKey = if ($kind -ceq 'plan') { 'planExchangeRateDate' } else { 'exchangeRateDate' }
            if ($inputs.ContainsKey($parameter) -and $inputs[$parameter] -gt 0) {
                $exchange[$kind] = @{
                    rubPerUsd = $inputs[$parameter]
                    effectiveDate = Read-TimelineDate $cost[$dateKey]
                    source = 'manual'
                }
            }
        }
        if (!$exchange.ContainsKey('forecast') -and $mode -ceq 'cbr') {
            $exchange.forecast = @{ source = 'cbr'; state = 'unavailable' }
            if ($null -ne $Fx -and $Fx.state -cin @('current', 'stale')) {
                $inputs.RubPerUsd = $Fx.snapshot.ratePerUsd
                $exchange.forecast = @{
                    source = 'cbr'; state = $Fx.state; rubPerUsd = $inputs.RubPerUsd
                    effectiveDate = $Fx.snapshot.effectiveDate
                }
            }
        }
        $result = Get-ProjectCost @inputs
        @{ state = 'available'; asOf = $date; scopeVersion = $scope; values = $result; exchange = $exchange }
    } catch {
        @{ state = 'invalid' }
    }
}

$registryFile = Get-Item -LiteralPath $RegistryPath
$registry = [IO.File]::ReadAllText($registryFile.FullName, $utf8) | ConvertFrom-Json -AsHashtable -DateKind String
$queue = $null
if ($registry.Contains('queue')) {
    $entry = $registry.queue
    if ($entry -isnot [System.Collections.IDictionary] -or $entry.id -cnotmatch '\A[a-z0-9][a-z0-9-]{0,63}\z' -or
        $entry.path -isnot [string] -or !$entry.path.Trim() -or $entry.path -match '^[\\/]{2}') { throw 'INVALID_QUEUE_REGISTRY' }
    $path = [IO.Path]::GetFullPath($entry.path, $registryFile.DirectoryName)
    if ($path -notmatch '^[A-Za-z]:[\\/]') { throw 'QUEUE_ROOT_MUST_BE_LOCAL' }
    $queue = @{ id = $entry.id; path = $path; items = @{}; stale = $true; updated = $null }
}
$boundAssignments = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$projects = @(foreach ($entry in $registry.projects) {
    if ($entry.id -isnot [string] -or $entry.id -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or
        !$ids.Add($entry.id) -or $entry.name -isnot [string] -or !$entry.name.Trim() -or
        $entry.roots -isnot [array] -or !$entry.roots.Count) { throw 'INVALID_PROJECT_REGISTRY' }
    $bindings = @{}
    $ownerActions = @{}
    if (($entry.Contains('bindings') -or $entry.Contains('ownerActions')) -and !$queue) { throw 'QUEUE_NOT_CONFIGURED' }
    foreach ($binding in $entry['bindings']) {
        if ($binding.taskId -cnotmatch '\AT-[0-9]{3,}\z' -or $binding.assignmentId -cnotmatch '\A[A-Z0-9]+(?:-[A-Z0-9]+)*\z' -or
            !$boundAssignments.Add($binding.assignmentId)) { throw 'INVALID_TASK_ASSIGNMENT_BINDING' }
        $bindings[$binding.taskId] = @($bindings[$binding.taskId] | Where-Object { $_ }) + $binding.assignmentId
    }
    foreach ($action in $entry['ownerActions']) {
        if ($action.taskId -cnotmatch '\AT-[0-9]{3,}\z' -or $ownerActions.ContainsKey($action.taskId) -or
            $action.text -isnot [string] -or !$action.text.Trim() -or $action.requires -isnot [array]) { throw 'INVALID_OWNER_ACTION' }
        foreach ($required in $action.requires) {
            if ($required -isnot [string] -or $required -cnotin $bindings[$action.taskId]) { throw 'UNKNOWN_REQUIRED_ASSIGNMENT' }
        }
        $ownerActions[$action.taskId] = $action
    }
    foreach ($taskId in @($bindings.Keys)) { $bindings[$taskId] = @($bindings[$taskId] | Sort-Object -CaseSensitive) }
    $decisionsPath = $null
    $decisionAsOf = $null
    if ($entry.Contains('decisionsPath')) {
        $relative = $entry['decisionsPath']
        $inputProgress = $entry['progress']
        if ($relative -isnot [string] -or !$relative.Trim() -or [IO.Path]::IsPathRooted($relative) -or
            $inputProgress -isnot [Collections.IDictionary] -or $inputProgress['baselines'] -isnot [array]) {
            throw 'INVALID_PROJECT_DECISION_JOURNAL'
        }
        $decisionsPath = [IO.Path]::GetFullPath($relative, $registryFile.DirectoryName)
        $decisionAsOf = Read-ObservedInstant $inputProgress['asOf']
        if ($decisionsPath -notmatch '^[A-Za-z]:[\\/]' -or $null -eq $decisionAsOf) {
            throw 'INVALID_PROJECT_DECISION_JOURNAL'
        }
    }
    $progress = if ($decisionsPath) { @{ state = 'incomplete' } } else { Read-WeightedProgress $entry }
    $timeline = Read-ProjectTimeline $entry
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    @{
        id = $entry.id
        name = $entry.name
        timeline = $timeline
        weightedProgress = $progress
        progressInput = $entry['progress']
        registryEntry = $entry
        decisionsPath = $decisionsPath
        decisionAsOf = $decisionAsOf
        decisionSnapshot = $null
        decisionView = $null
        decisionTaskByItem = if ($entry.Contains('decisionTaskByItem')) { $entry['decisionTaskByItem'] } else { @{} }
        decisionFrame = $null
        decisionReadAt = $null
        decisionState = 'unavailable'
        dateForecast = Read-ProjectDateForecast $entry $progress $timeline
        cost = Read-ProjectCostSnapshot $entry
        historyPath = if ($entry.Contains('historyPath')) {
            $history = $entry['historyPath']
            if ($history -isnot [string] -or !$history.Trim() -or [IO.Path]::IsPathRooted($history)) {
                throw 'INVALID_PROJECT_HISTORY_PATH'
            }
            $resolved = [IO.Path]::GetFullPath($history, $registryFile.DirectoryName)
            if ($resolved -notmatch '^[A-Za-z]:[\\/]') { throw 'INVALID_PROJECT_HISTORY_PATH' }
            $resolved
        } else { $null }
        evidencePath = if ($entry.Contains('evidenceSnapshotPath')) {
            $path = $entry['evidenceSnapshotPath']
            if ($path -isnot [string] -or !$path.Trim() -or [IO.Path]::IsPathRooted($path)) { throw 'INVALID_PROJECT_EVIDENCE_PATH' }
            $resolved = [IO.Path]::GetFullPath($path, $registryFile.DirectoryName)
            if ($resolved -notmatch '^[A-Za-z]:[\\/]') { throw 'INVALID_PROJECT_EVIDENCE_PATH' }
            $resolved
        }
        evidence = $null
        evidenceState = 'unavailable'
        bindings = $bindings
        ownerActions = $ownerActions
        sources = @(foreach ($root in $entry.roots) {
            if ($root -isnot [string] -or !$root.Trim()) { throw 'INVALID_PROJECT_ROOT' }
            $path = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($root, $registryFile.DirectoryName))
            if ($paths.Add($path)) { @{ path = $path; cards = @{}; error = $null; updated = $null } }
        })
    }
})
if (!$projects.Count) { throw 'EMPTY_PROJECT_REGISTRY' }

if ($projects | Where-Object decisionsPath) {
    Import-Module (Join-Path $PSScriptRoot 'lib/ProjectDecisionJournal.psm1')
    Import-Module (Join-Path $PSScriptRoot 'lib/ProjectDecisionView.psm1')
}
$page = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'project-viewer.html'), $utf8)
$origin = "http://127.0.0.1:$Port"
$key = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
$prefix = "/$key/"
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("$origin/")
$fxState = [hashtable]::Synchronized(@{ latest = $null })
$fxWorker = $null
$fxCancel = $null
$fxPending = $null
try {
    if ($projects | Where-Object { $_.cost.ContainsKey('exchange') -and $_.cost.exchange.ContainsKey('forecast') -and
            $_.cost.exchange.forecast.source -ceq 'cbr' }) {
        $fxCancel = [Threading.CancellationTokenSource]::new()
        $fxWorker = [PowerShell]::Create()
        $fxModule = Join-Path $PSScriptRoot 'lib/ProjectCbrFx.psm1'
        $fxPath = $registryFile.FullName + '.usd-rub.json'
        $null = $fxWorker.AddScript({
            param($Module, $Path, $State, $Token)
            $ErrorActionPreference = 'Stop'
            Import-Module -Name $Module
            do {
                $State.latest = Update-CbrUsdRateSnapshot -Path $Path -CancellationToken $Token
            } while (!$Token.WaitHandle.WaitOne([TimeSpan]::FromHours(1)))
        }).AddArgument($fxModule).AddArgument($fxPath).AddArgument($fxState).AddArgument($fxCancel.Token)
        $fxPending = $fxWorker.BeginInvoke()
    }
    Update-Projects
    Update-Queue
    Update-Evidence
    Update-DecisionJournals
    $listener.Start()
    Write-Output "$origin$prefix"
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        try {
            $response.Headers['Cache-Control'] = 'no-store'
            $response.Headers['X-Content-Type-Options'] = 'nosniff'
            $response.Headers['Referrer-Policy'] = 'no-referrer'
            $response.Headers['Content-Security-Policy'] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
            $path = $request.Url.AbsolutePath
            $method = $request.HttpMethod
            if ($request.UserHostName -cne "127.0.0.1:$Port" -or !$path.StartsWith($prefix, [StringComparison]::Ordinal)) {
                $response.StatusCode = 404
                continue
            }
            $route = $path.Substring($prefix.Length)
            $response.ContentType = 'application/json; charset=utf-8'
            if ($method -eq 'GET' -and !$route) {
                $response.ContentType = 'text/html; charset=utf-8'
                $body = $page
            } elseif (($method -eq 'GET' -and $route -eq 'summary') -or
                ($method -eq 'POST' -and $route -eq 'refresh' -and $request.Headers['Origin'] -ceq $origin)) {
                if ($method -eq 'POST') { Update-Projects; Update-Queue; Update-Evidence; Update-DecisionJournals }
                $body = ConvertTo-Json -InputObject @(Get-Summary) -Depth 10 -Compress
            } elseif ($method -eq 'GET' -and $route -eq 'period') {
                $project = $projects | Where-Object { $_.id -ceq $request.QueryString['project'] }
                if (!$project) { $response.StatusCode = 404; continue }
                if (!(Test-DecisionFrame $project $request $response)) { continue }
                $zone = if ($project.timeline) { $project.timeline.zone } else { [TimeZoneInfo]::Utc }
                $args = @{TimeZone = $zone; SnapshotAt = [DateTimeOffset]::UtcNow}
                try {
                    $from = $request.QueryString['from']
                    $through = $request.QueryString['through']
                    $days = $request.QueryString['days']
                    if ($null -ne $from -or $null -ne $through) {
                        if ($null -ne $days) { throw 'PROJECT_PERIOD_MIXED_FILTERS' }
                        $culture = [Globalization.CultureInfo]::InvariantCulture
                        $args.From = [DateOnly]::ParseExact($from, 'yyyy-MM-dd', $culture)
                        $args.Through = [DateOnly]::ParseExact($through, 'yyyy-MM-dd', $culture)
                    } elseif ($null -ne $days) {
                        if ($days -cnotin '1','3','7','30') { throw 'PROJECT_PERIOD_INVALID_DAYS' }
                        $args.Days = [int]$days
                    }
                    $period = Get-ProjectPeriod @args
                } catch {
                    $response.StatusCode = 400
                    continue
                }
                $state = 'unconfigured'
                $history = @{ events = @(); coverage = @() }
                $result = $null
                $coverage = $null
                if ($project.historyPath) {
                    try {
                        Assert-PlainPath $project.historyPath $false
                        $history = Read-ProjectHistory -Path $project.historyPath -ProjectId $project.id
                        $result = Get-ProjectPeriodEvents -ProjectId $project.id -Period $period -Events $history.events
                        $coverage = Get-ProjectHistoryCoverage $period $history.coverage @($result.totals.Keys)
                        $state = 'readable'
                    } catch {
                        $result = $null
                        $state = 'unavailable'
                    }
                }
                if ($project.decisionsPath) {
                    $events = @($history.events | Where-Object Type -CNotIn 'accepted','acceptance_revoked')
                    $intervals = @($history.coverage | Where-Object type -CNotIn 'accepted','acceptance_revoked')
                    if ($null -ne $project.decisionView) {
                        $events += @($project.decisionView.eventHistory)
                        if (!$project.decisionView.unmappedItems.Count) { $intervals += @($project.decisionView.coverage) }
                        $state = 'readable'
                    }
                    $history = @{ events = $events; coverage = $intervals }
                    if ($state -ceq 'readable') {
                        $result = Get-ProjectPeriodEvents -ProjectId $project.id -Period $period -Events $events
                        $coverage = Get-ProjectHistoryCoverage $period $intervals @($result.totals.Keys)
                    }
                }
                try {
                    $remainingWork = Get-RemainingWorkView $project $period $zone $(if ($state -ceq 'readable') { $history })
                } catch {
                    $remainingWork = @{ state = 'invalid'; points = @() }
                }
                $periodView = @{
                    From = $period.From.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                    Through = $period.Through.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
                    StartUtc = $period.StartUtc
                    EndUtc = $period.EndUtc
                    SnapshotAt = $period.SnapshotAt
                    TimeZone = $period.TimeZone
                }
                $sourceFreshness = @{
                    tasks = @(foreach ($source in $project.sources) {
                        @{ updated = $source.updated; stale = [bool]$source.error }
                    })
                    queue = if ($queue) { @{ updated = $queue.updated; stale = $queue.stale } } else { $null }
                }
                $periodResponse = @{ projectId = $project.id; sourceFreshness = $sourceFreshness; period = $periodView; historyState = $state; report = $result; coverage = $coverage; remainingWork = $remainingWork; historyReadAt = if ($state -ceq 'readable') { [DateTimeOffset]::UtcNow } else { $null } }
                if ($project.decisionsPath) {
                    $periodResponse.frame = $project.decisionFrame
                    $periodResponse.journalState = $project.decisionState
                    $periodResponse.journalReadAt = $project.decisionReadAt
                    $periodResponse.journalGeneration = if ($null -ne $project.decisionSnapshot) { $project.decisionSnapshot.sha256 }
                }
                $body = $periodResponse | ConvertTo-Json -Depth 10 -Compress
            } elseif ($method -eq 'GET' -and $route -eq 'report' -and $queue) {
                $id = $request.QueryString['assignment']
                $kind = $request.QueryString['copy']
                if (!$id -or $kind -cnotin 'report','accepted' -or !$queue.items.ContainsKey($id) -or
                    $queue.items[$id][$kind].state -ne 'readable') { $response.StatusCode = 404; continue }
                $body = @{ text = $queue.items[$id][$kind].text; hash = $queue.items[$id][$kind].hash } | ConvertTo-Json -Compress
            } elseif ($method -eq 'GET' -and $route -eq 'card') {
                $project = $projects | Where-Object { $_.id -ceq $request.QueryString['project'] }
                if ($null -eq $project) { $response.StatusCode = 404; continue }
                if (!(Test-DecisionFrame $project $request $response)) { continue }
                $record = foreach ($source in $project.sources) {
                    $source.cards.Values | Where-Object {
                        $_.id -ceq $request.QueryString['task'] -and $null -ne $_.version -and
                            $_.version.hash -ceq $request.QueryString['version']
                    }
                }
                $first = @($record | Select-Object -First 1)
                if (!$first.Count) { $response.StatusCode = 404; continue }
                $cardResponse = @{ text = $first[0].version.text }
                if ($project.decisionsPath) {
                    $cardResponse.frame = $project.decisionFrame
                    $cardResponse.journalGeneration = if ($null -ne $project.decisionSnapshot) { $project.decisionSnapshot.sha256 }
                    $cardResponse.ownerDecisions = @(if ($null -ne $project.decisionView) {
                        $project.decisionView.acceptanceByItem.Values | Where-Object taskId -CEQ $request.QueryString['task'] |
                            Sort-Object itemId -CaseSensitive | Select-Object -Property itemId, status, decidedAt
                    })
                }
                $body = $cardResponse | ConvertTo-Json -Depth 8 -Compress
            } else { $response.StatusCode = 404; continue }
            $bytes = $utf8.GetBytes($body)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            if ($response.OutputStream.CanWrite) { $response.StatusCode = 500 }
        } finally {
            $response.Close()
        }
    }
} finally {
    $listener.Close()
    if ($fxWorker) {
        $fxCancel.Cancel()
        try {
            if ($fxPending -and $fxPending.AsyncWaitHandle.WaitOne(5000)) {
                $null = $fxWorker.EndInvoke($fxPending)
            } else { $fxWorker.Stop() }
        } finally {
            $fxWorker.Dispose()
            $fxCancel.Dispose()
        }
    }
}
