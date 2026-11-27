#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$HistoryPath,
    [Parameter(Mandatory)][ValidatePattern('\A[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\z')][string]$Repository,
    [Parameter(Mandatory)][ValidatePattern('\A[a-z0-9][a-z0-9-]{0,63}\z')][string]$ProjectId,
    [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/ProjectPeriod.psm1')

function Read-MergeInstant($Value) {
    $instant = [DateTimeOffset]::MinValue
    if ($Value -isnot [string] -or $Value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
        ![DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$instant)) {
        throw 'MERGE_HISTORY_INVALID_TIMESTAMP'
    }
    $instant.ToUniversalTime()
}

$resolved = Get-Item -LiteralPath $HistoryPath -Force
if ($resolved.PSIsContainer -or ($resolved.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    throw 'MERGE_HISTORY_INVALID_FILE'
}
$historyHash = (Get-FileHash -LiteralPath $resolved.FullName).Hash
$local = Read-ProjectHistory -Path $resolved.FullName -ProjectId $ProjectId
if ((Get-FileHash -LiteralPath $resolved.FullName).Hash -cne $historyHash) { throw 'MERGE_HISTORY_CHANGED' }
$map = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($event in $local.events) {
    if ($event.SourceId -cne 'github-pr' -or $event.Type -cne 'merged') { continue }
    if ($event.EventId -cnotmatch '\Apr-[1-9][0-9]*-merged\z' -or
        $event.TaskId -cnotmatch '\AT-[0-9]{3,}\z' -or !$map.TryAdd($event.EventId, $event)) {
        throw 'MERGE_HISTORY_INVALID_LOCAL_EVENT'
    }
}

$cutoff = [DateTimeOffset]::Parse([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture))
$output = & gh api --method GET --paginate --slurp "repos/$Repository/pulls?state=closed&base=main&per_page=100"
if ($LASTEXITCODE -ne 0) { throw 'MERGE_HISTORY_FETCH_FAILED' }
$pages = ConvertFrom-Json -InputObject ($output -join "`n") -AsHashtable -DateKind String -NoEnumerate
if ($pages -isnot [array] -or !$pages.Count) { throw 'MERGE_HISTORY_INVALID_PAGES' }

$seen = [Collections.Generic.HashSet[long]]::new()
$verified = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$additions = @(foreach ($page in $pages) {
    if ($page -isnot [array]) { throw 'MERGE_HISTORY_INVALID_PAGE' }
    foreach ($pull in $page) {
        if ($pull -isnot [Collections.IDictionary] -or $pull['number'] -isnot [long] -or $pull['number'] -le 0 -or
            !$seen.Add($pull['number']) -or $pull['state'] -cne 'closed' -or
            $pull['base']['ref'] -cne 'main' -or !$pull.Contains('merged_at')) { throw 'MERGE_HISTORY_INVALID_PULL' }
        if ($null -eq $pull['merged_at']) { continue }
        $at = Read-MergeInstant $pull['merged_at']
        if ($at -ge $cutoff) { continue }
        $eventId = 'pr-' + $pull['number'] + '-merged'
        $null = $verified.Add($eventId)
        if ($map.ContainsKey($eventId)) {
            if ($map[$eventId].At -ne $at) { throw 'MERGE_HISTORY_TIME_CONFLICT' }
            continue
        }
        if ($pull['head']['ref'] -cnotmatch '\Atask/(?<task>T-[0-9]{3,})(?:-[a-z0-9]+(?:-[a-z0-9]+)*)?\z') {
            throw 'MERGE_HISTORY_TASK_MAPPING_REQUIRED'
        }
        @{ sourceId = 'github-pr'; eventId = $eventId; type = 'merged'; at = $pull['merged_at']; taskId = $Matches.task }
    }
})
foreach ($event in $map.Values) {
    if ($event.At -lt $cutoff -and !$verified.Contains($event.EventId)) { throw 'MERGE_HISTORY_LOCAL_EVENT_NOT_FOUND' }
}
$published = $false
if ($Apply) {
    $directory = $resolved.Directory
    while ($null -ne $directory) {
        if ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'MERGE_HISTORY_INVALID_PARENT' }
        $directory = $directory.Parent
    }
    $pathKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
        [Text.Encoding]::UTF8.GetBytes($resolved.FullName.ToUpperInvariant())))
    $writer = [Threading.Mutex]::new($false, "Local\V2MergeHistory-$pathKey")
    $locked = $false
    try {
        try { $locked = $writer.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw 'MERGE_HISTORY_WRITER_BUSY' }
        if ((Get-FileHash -LiteralPath $resolved.FullName).Hash -cne $historyHash) { throw 'MERGE_HISTORY_CHANGED' }
        $document = Get-Content -LiteralPath $resolved.FullName -Raw | ConvertFrom-Json -AsHashtable -DateKind String
        $mergeCoverage = @($local.coverage | Where-Object { $_['type'] -ceq 'merged' })
        $from = $cutoff
        foreach ($interval in $mergeCoverage) {
            $start = Read-MergeInstant $interval['from']
            $end = Read-MergeInstant $interval['until']
            if ($start -ge $end -or $end -gt $cutoff) { throw 'MERGE_HISTORY_INVALID_COVERAGE' }
            if ($start -lt $from) { $from = $start }
        }
        foreach ($event in $map.Values) {
            if ($event.At -lt $from) { $from = $event.At }
        }
        foreach ($event in $additions) {
            $at = Read-MergeInstant $event.at
            if ($at -lt $from) { $from = $at }
        }
        $coverageAlreadyCurrent = $mergeCoverage.Count -eq 1 -and
            (Read-MergeInstant $mergeCoverage[0]['from']) -eq $from -and
            (Read-MergeInstant $mergeCoverage[0]['until']) -eq $cutoff
        if ($additions.Count -or ($from -lt $cutoff -and !$coverageAlreadyCurrent)) {
            $document['events'] += @($additions | Sort-Object { Read-MergeInstant $_.at }, eventId)
            $document['coverage'] = @($local.coverage | Where-Object { $_['type'] -cne 'merged' }) + @{
                type = 'merged'; from = $from.ToString('o'); until = $cutoff.ToString('o')
            }
            $temporary = Join-Path $resolved.DirectoryName ('.merge-history-' + [guid]::NewGuid().ToString('N'))
            try {
                $json = ($document | ConvertTo-Json -Depth 24) + [char]10
                [IO.File]::WriteAllText($temporary, $json, [Text.UTF8Encoding]::new($false, $true))
                $null = Read-ProjectHistory -Path $temporary -ProjectId $ProjectId
                $target = Get-Item -LiteralPath $resolved.FullName -Force
                if (($target.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
                    (Get-FileHash -LiteralPath $resolved.FullName).Hash -cne $historyHash) { throw 'MERGE_HISTORY_CHANGED' }
                [IO.File]::Replace($temporary, $resolved.FullName, [NullString]::Value)
                $published = $true
            } finally {
                [IO.File]::Delete($temporary)
            }
        }
    } finally {
        if ($locked) { $writer.ReleaseMutex() }
        $writer.Dispose()
    }
}

[ordered]@{
    projectId = $ProjectId
    published = $published
    repository = $Repository
    verifiedThroughExclusive = $cutoff.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    verifiedCount = $verified.Count
    additions = @($additions | Sort-Object { Read-MergeInstant $_.at }, eventId)
} | ConvertTo-Json -Depth 8 -Compress
