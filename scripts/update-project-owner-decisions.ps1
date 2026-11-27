#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JournalPath,
    [Parameter(Mandatory)][string]$ProjectId,
    [Collections.IDictionary]$Decision,
    [Collections.IDictionary[]]$ConfirmedCoverage = @(),
    [Parameter(Mandatory)][object[]]$Baselines
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/ProjectDecisionJournal.psm1')
$file = Get-Item -LiteralPath $JournalPath -Force
$fields = 'projectId', 'eventId', 'itemId', 'scopeVersion', 'criteriaVersion', 'type', 'at', 'evidenceId'
if (!$PSBoundParameters.ContainsKey('Decision') -and !$ConfirmedCoverage.Count) {
    throw 'DECISION_JOURNAL_EMPTY_UPDATE'
}
$event = $null
if ($PSBoundParameters.ContainsKey('Decision')) {
    $event = [ordered]@{}
    foreach ($field in $fields) {
        if ($Decision[$field] -isnot [string]) { throw 'DECISION_JOURNAL_INVALID_EVENT' }
        $event[$field] = $Decision[$field]
    }
    if ($Decision.Count -ne $fields.Count) { throw 'DECISION_JOURNAL_INVALID_EVENT' }
}
$coverageFields = 'type', 'from', 'until'
foreach ($interval in $ConfirmedCoverage) {
    if ($interval.Count -ne $coverageFields.Count) { throw 'DECISION_JOURNAL_INVALID_COVERAGE' }
    foreach ($field in $coverageFields) {
        if ($interval[$field] -isnot [string]) { throw 'DECISION_JOURNAL_INVALID_COVERAGE' }
    }
}

$pathKey = [Text.Encoding]::UTF8.GetBytes($file.FullName.ToUpperInvariant())
$lockKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pathKey))
$mutex = [Threading.Mutex]::new($false, "Local\v2-decision-journal-$lockKey")
$locked = $false
try {
    try { $locked = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $locked = $true }
    if (!$locked) { throw 'DECISION_JOURNAL_WRITER_BUSY' }

    $snapshot = Read-ProjectDecisionJournal -Path $file.FullName -ProjectId $ProjectId -Baselines $Baselines
    $appendEvent = $null -ne $event
    if ($appendEvent) {
        foreach ($existing in $snapshot.document['events']) {
            if ($existing['eventId'] -cne $event['eventId']) { continue }
            foreach ($field in $fields) {
                if ($existing[$field] -cne $event[$field]) { throw 'DECISION_JOURNAL_ID_CONFLICT' }
            }
            $appendEvent = $false
            break
        }
    }
    $coverageChanged = $false
    foreach ($interval in $ConfirmedCoverage) {
        $known = $false
        foreach ($existing in $snapshot.document['coverage']) {
            if ($existing['type'] -ceq $interval['type'] -and $existing['from'] -ceq $interval['from'] -and
                $existing['until'] -ceq $interval['until']) {
                $known = $true
                break
            }
        }
        if (!$known) {
            $snapshot.document['coverage'] += $interval
            $coverageChanged = $true
        }
    }
    if (!$appendEvent -and !$coverageChanged) { return @{ published = $false; sha256 = $snapshot.sha256 } }
    if ($appendEvent) { $snapshot.document['events'] += $event }
    $temporary = Join-Path $file.DirectoryName ('.owner-decisions-' + [guid]::NewGuid().ToString('N'))
    try {
        $encoding = [Text.UTF8Encoding]::new($false, $true)
        $json = ($snapshot.document | ConvertTo-Json -Depth 16) + [char]10
        [IO.File]::WriteAllText($temporary, $json, $encoding)
        $updated = Read-ProjectDecisionJournal -Path $temporary -ProjectId $ProjectId -Baselines $Baselines
        $current = Read-ProjectDecisionJournal -Path $file.FullName -ProjectId $ProjectId -Baselines $Baselines
        if ($current.sha256 -cne $snapshot.sha256) { throw 'DECISION_JOURNAL_CHANGED' }
        [IO.File]::Replace($temporary, $file.FullName, [NullString]::Value)
        @{ published = $true; sha256 = $updated.sha256 }
    } finally {
        [IO.File]::Delete($temporary)
    }
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
