Set-StrictMode -Version Latest

function Get-ProjectPeriod {
    param(
        [Parameter(Mandatory)][TimeZoneInfo]$TimeZone,
        [Parameter(Mandatory)][DateTimeOffset]$SnapshotAt,
        [ValidateSet(1, 3, 7, 30)][int]$Days = 1,
        [Nullable[DateOnly]]$From,
        [Nullable[DateOnly]]$Through
    )

    $today = [DateOnly]::FromDateTime([TimeZoneInfo]::ConvertTime($SnapshotAt, $TimeZone).DateTime)
    if (($null -eq $From) -ne ($null -eq $Through)) { throw 'PROJECT_PERIOD_NEEDS_BOTH_DATES' }
    if ($null -eq $From) {
        $From = $today.AddDays(1 - $Days)
        $Through = $today
    }
    if ($From -gt $Through -or $Through -gt $today) { throw 'PROJECT_PERIOD_INVALID_RANGE' }
    $start = ConvertTo-ProjectDayBoundary $From $TimeZone
    $end = if ($Through -eq $today) { $SnapshotAt.ToUniversalTime() }
           else { ConvertTo-ProjectDayBoundary $Through.AddDays(1) $TimeZone }
    [pscustomobject]@{
        From = $From
        Through = $Through
        StartUtc = $start
        EndUtc = $end
        SnapshotAt = $SnapshotAt.ToUniversalTime()
        TimeZone = $TimeZone.Id
    }
}

function ConvertTo-ProjectDayBoundary([DateOnly]$Date, [TimeZoneInfo]$TimeZone) {
    $local = $Date.ToDateTime([TimeOnly]::MinValue)
    # В некоторых часовых поясах смещение меняется в полночь.
    while ($TimeZone.IsInvalidTime($local)) { $local = $local.AddMinutes(1) }
    $offset = if ($TimeZone.IsAmbiguousTime($local)) {
        $TimeZone.GetAmbiguousTimeOffsets($local) | Sort-Object -Descending | Select-Object -First 1
    } else { $TimeZone.GetUtcOffset($local) }
    [DateTimeOffset]::new($local, $offset).ToUniversalTime()
}

function Get-ProjectPeriodEvents {
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)]$Period,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Events
    )

    $knownTypes = @('started', 'reported', 'reviewed', 'merged', 'added', 'accepted', 'acceptance_revoked')
    $unique = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $counted = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($event in $Events) {
        if ($event.ProjectId -cne $ProjectId) { continue }
        if ($event.SourceId -cnotmatch '\A[a-z0-9][a-z0-9_-]{0,63}\z' -or
            $event.EventId -cnotmatch '\A[a-zA-Z0-9][a-zA-Z0-9_-]{0,127}\z' -or
            $event.TaskId -cnotmatch '\AT-[0-9]{3,}\z' -or
            $event.Type -cnotin $knownTypes -or $event.At -isnot [DateTimeOffset]) {
            throw 'PROJECT_HISTORY_INVALID_EVENT'
        }
        $key = $event.SourceId + '/' + $event.EventId
        $row = [pscustomobject]@{
            SourceId = $event.SourceId
            EventId = $event.EventId
            TaskId = $event.TaskId
            Type = $event.Type
            At = $event.At.ToUniversalTime()
        }
        if ($unique.ContainsKey($key)) {
            $previous = $unique[$key]
            if ($previous.TaskId -cne $row.TaskId -or $previous.Type -cne $row.Type -or $previous.At -ne $row.At) {
                throw 'PROJECT_HISTORY_CONFLICTING_EVENT'
            }
            continue
        }
        $unique.Add($key, $row)
        if ($row.At -ge $Period.EndUtc -or $row.Type -cnotin 'accepted', 'acceptance_revoked') { continue }
        $previous = $counted[$row.TaskId]
        if (!$previous -or $row.At -gt $previous.At -or
            ($row.At -eq $previous.At -and (
                ($row.Type -ceq 'acceptance_revoked' -and $previous.Type -cne 'acceptance_revoked') -or
                ($row.Type -ceq $previous.Type -and [StringComparer]::Ordinal.Compare($key, ($previous.SourceId + '/' + $previous.EventId)) -lt 0)))) {
            $counted[$row.TaskId] = $row
        }
    }

    $zone = [TimeZoneInfo]::FindSystemTimeZoneById($Period.TimeZone)
    $rows = @(foreach ($row in ($unique.Values | Sort-Object At, SourceId, EventId -CaseSensitive)) {
        if ($row.At -lt $Period.StartUtc -or $row.At -ge $Period.EndUtc) { continue }
        $last = $counted[$row.TaskId]
        $included = $row.Type -cne 'accepted' -or ($last.SourceId -ceq $row.SourceId -and $last.EventId -ceq $row.EventId)
        [pscustomobject]@{
            sourceId = $row.SourceId
            eventId = $row.EventId
            taskId = $row.TaskId
            type = $row.Type
            at = $row.At
            day = [TimeZoneInfo]::ConvertTime($row.At, $zone).ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
            counted = $included
        }
    })
    $totals = [ordered]@{}
    foreach ($type in $knownTypes) { $totals[$type] = 0 }
    $days = [ordered]@{}
    foreach ($row in $rows) {
        if (!$row.counted) { continue }
        $totals[$row.type]++
        if (!$days.Contains($row.day)) { $days[$row.day] = [ordered]@{} }
        if (!$days[$row.day].Contains($row.type)) { $days[$row.day][$row.type] = 0 }
        $days[$row.day][$row.type]++
    }
    [pscustomobject]@{
        projectId = $ProjectId
        totals = $totals
        days = $days
        events = $rows
    }
}

function Read-ProjectHistory {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ProjectId)

    $stream = [IO.File]::OpenRead($Path)
    try {
        if ($stream.Length -gt 4MB) { throw 'PROJECT_HISTORY_TOO_LARGE' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes)
        if ($stream.ReadByte() -ne -1) { throw 'PROJECT_HISTORY_CHANGED' }
    } finally {
        $stream.Dispose()
    }

    $encoding = [Text.UTF8Encoding]::new($false, $true)
    $json = $encoding.GetString($bytes).TrimStart([char]0xFEFF)
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.AllowDuplicateProperties = $false
    $document = [Text.Json.JsonDocument]::Parse($json, $options)
    $document.Dispose()
    $data = ConvertFrom-Json -InputObject $json -AsHashtable -DateKind String
    if ($data -isnot [Collections.IDictionary] -or $data['schemaVersion'] -cne 1 -or
        $data['projectId'] -cne $ProjectId -or $data['events'] -isnot [array]) {
        throw 'PROJECT_HISTORY_INVALID_DOCUMENT'
    }
    $events = @(foreach ($item in $data['events']) {
        if ($item -isnot [Collections.IDictionary]) { throw 'PROJECT_HISTORY_INVALID_EVENT' }
        $time = $item['at']
        $at = [DateTimeOffset]::MinValue
        if ($time -isnot [string] -or $time -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
            ![DateTimeOffset]::TryParse($time, [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$at)) { throw 'PROJECT_HISTORY_INVALID_TIMESTAMP' }
        foreach ($field in 'sourceId', 'eventId', 'taskId', 'type') {
            if ($item[$field] -isnot [string]) { throw 'PROJECT_HISTORY_INVALID_EVENT' }
        }
        [pscustomobject]@{
            ProjectId = $ProjectId
            SourceId = $item['sourceId']
            EventId = $item['eventId']
            TaskId = $item['taskId']
            Type = $item['type']
            At = $at.ToUniversalTime()
        }
    })
    $coverage = $data['coverage']
    if ($null -eq $coverage) { $coverage = @() }
    if ($coverage -isnot [array]) { throw 'PROJECT_HISTORY_INVALID_COVERAGE' }
    @{ events = $events; coverage = $coverage }
}

function Get-ProjectHistoryCoverage($Period, [object[]]$Coverage, [string[]]$Types) {
    $intervals = @{}
    foreach ($type in $Types) { $intervals[$type] = [Collections.Generic.List[object]]::new() }
    foreach ($item in $Coverage) {
        if ($item -isnot [Collections.IDictionary] -or $item['type'] -cnotin $Types) {
            throw 'PROJECT_HISTORY_INVALID_COVERAGE'
        }
        $dates = @(foreach ($key in 'from', 'until') {
            $value = $item[$key]
            $at = [DateTimeOffset]::MinValue
            if ($value -isnot [string] -or $value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
                ![DateTimeOffset]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture,
                    [Globalization.DateTimeStyles]::None, [ref]$at)) { throw 'PROJECT_HISTORY_INVALID_COVERAGE' }
            $at.ToUniversalTime()
        })
        if ($dates[0] -ge $dates[1]) { throw 'PROJECT_HISTORY_INVALID_COVERAGE' }
        $intervals[$item['type']].Add(@{ start = $dates[0]; end = $dates[1] })
    }
    $result = [ordered]@{}
    foreach ($type in $Types) {
        $cursor = $Period.StartUtc
        $gaps = @(foreach ($interval in ($intervals[$type] | Sort-Object { $_.start })) {
            if ($interval.end -le $cursor) { continue }
            if ($interval.start -ge $Period.EndUtc) { break }
            if ($interval.start -gt $cursor) { @{ from = $cursor; until = $interval.start } }
            $cursor = $interval.end
        }
        if ($cursor -lt $Period.EndUtc) { @{ from = $cursor; until = $Period.EndUtc } })
        $result[$type] = @{ complete = $gaps.Count -eq 0; gaps = $gaps }
    }
    $result
}

Export-ModuleMember -Function Get-ProjectPeriod, Get-ProjectPeriodEvents, Read-ProjectHistory, Get-ProjectHistoryCoverage
