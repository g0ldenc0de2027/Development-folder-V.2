#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/lib/ProjectPeriod.psm1')
$zone = [TimeZoneInfo]::Utc
$start = [DateTimeOffset]'2026-11-27T08:00:00Z'
function New-DecisionEvent($EventId, $Type, $Hour, $ItemId) {
    $event = [pscustomobject]@{
        ProjectId = 'demo'; SourceId = 'owner-decision'; EventId = $EventId; TaskId = 'T-001'
        Type = $Type; At = $start.AddHours($Hour)
    }
    if ($ItemId) { $event | Add-Member -NotePropertyName ItemId -NotePropertyValue $ItemId }
    $event
}
$events = @(
    New-DecisionEvent 'a.1' accepted 0 'one'
    New-DecisionEvent 'a.2' accepted 1 'two'
    New-DecisionEvent 'r.2' acceptance_revoked 2 'two'
)
$before = Get-ProjectPeriod -TimeZone $zone -SnapshotAt $start.AddMinutes(90) -Days 1
$after = Get-ProjectPeriod -TimeZone $zone -SnapshotAt $start.AddHours(3) -Days 1
$old = Get-ProjectPeriodEvents -ProjectId demo -Period $before -Events $events
$new = Get-ProjectPeriodEvents -ProjectId demo -Period $after -Events $events
if ($old.totals.accepted -ne 2 -or $new.totals.accepted -ne 1 -or $new.totals.acceptance_revoked -ne 1) {
    throw 'One result overrode a different result of the same task'
}
$counted = @($new.events | Where-Object { $_.type -ceq 'accepted' -and $_.counted })
if ($counted.Count -ne 1 -or $counted[0].itemId -cne 'one' -or $counted[0].taskId -cne 'T-001') {
    throw 'Unexpected result identity or task reference'
}
$legacy = @(
    New-DecisionEvent 'a1' accepted 0 $null
    New-DecisionEvent 'r1' acceptance_revoked 2 $null
)
$oldFormat = Get-ProjectPeriodEvents -ProjectId demo -Period $after -Events $legacy
if ($oldFormat.totals.accepted -ne 0 -or $oldFormat.totals.acceptance_revoked -ne 1 -or
    $oldFormat.events[0].PSObject.Properties['itemId']) { throw 'Legacy behavior or output changed' }
$collision = @(
    New-DecisionEvent 'same' accepted 0 'one'
    New-DecisionEvent 'same' accepted 0 'two'
)
try {
    $null = Get-ProjectPeriodEvents -ProjectId demo -Period $after -Events $collision
    throw 'Different results shared the same event identity'
} catch {
    if ($_.Exception.Message -cne 'PROJECT_HISTORY_CONFLICTING_EVENT') { throw }
}
'PASS: distinct results, historical slice and legacy task aggregation'
