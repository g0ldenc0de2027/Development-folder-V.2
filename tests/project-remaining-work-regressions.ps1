#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/lib/ProjectRemainingWork.psm1') -Force

function Item($Id, $Weight) { @{ id = $Id; weight = $Weight; criteriaVersion = 'v1' } }
function Decision($EventId, $ItemId, $Scope, $Type, $At) {
    @{ projectId = 'demo'; eventId = $EventId; itemId = $ItemId; scopeVersion = $Scope
       type = $Type; criteriaVersion = 'v1'; evidenceId = 'synthetic'; at = $At }
}
function Coverage($From, $Until) {
    foreach ($type in 'accepted', 'acceptance_revoked') { @{ type = $type; from = $From; until = $Until } }
}
function Assert-That([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    "PASS: $Name"
}

$items = @((Item A 4), (Item B 6), (Item C 10))
$first = @{ projectId = 'demo'; version = 'v1'; approvedAt = '2026-11-20T00:00:00Z'; items = $items }
$expanded = @{ projectId = 'demo'; version = 'v2'; previousVersion = 'v1'; approvedAt = '2026-11-24T09:00:00Z'; items = $items + @((Item D 5)) }
$early = @((Decision a A v1 accepted '2026-11-21T12:00:00Z'), (Decision b B v1 accepted '2026-11-22T12:00:00Z'))
$later = $early + @((Decision r B v1 acceptance_revoked '2026-11-23T12:00:00Z'), (Decision c C v2 accepted '2026-11-25T12:00:00Z'))
$initial = @(Coverage '2026-11-20T00:00:00Z' '2026-11-24T00:00:00Z')
$resumed = @(Coverage '2026-11-25T00:00:00Z' '2026-11-26T00:00:00Z')
$filled = @(Coverage '2026-11-24T00:00:00Z' '2026-11-25T00:00:00Z')
$period = @{ ProjectId = 'demo'; From = '2026-11-20'; Through = '2026-11-22'; SnapshotAt = '2026-11-23T00:00:00Z'; TimeZone = [TimeZoneInfo]::Utc }

$old = Get-ProjectRemainingWork @period -Baselines @($first) -Decisions $early -Coverage $initial
$replay = Get-ProjectRemainingWork @period -Baselines @($first, $expanded) -Decisions $later -Coverage ($initial + $resumed)
Assert-That (($old.points.remainingWeight -join ',') -ceq '20,16,10' -and
    ($replay.points.remainingWeight -join ',') -ceq '20,16,10') 'PRG-004 later decisions and scope do not rewrite old points'
$period.Through = '2026-11-25'
$period.SnapshotAt = '2026-11-26T00:00:00Z'
$gap = Get-ProjectRemainingWork @period -Baselines @($first, $expanded) -Decisions $later -Coverage ($initial + $resumed)
Assert-That ($gap.points[3].remainingWeight -eq 16 -and $gap.points[4].scopeChanged -and
    $gap.points[4].totalWeight -eq 25 -and $gap.points[4].state -ceq 'incomplete' -and
    $gap.points[5].state -ceq 'incomplete' -and !$gap.points[5].ContainsKey('remainingWeight')) 'PRG-008 gap persists after source resumes'
$complete = Get-ProjectRemainingWork @period -Baselines @($first, $expanded) -Decisions $later -Coverage ($initial + $resumed + $filled)
Assert-That (($complete.points.remainingWeight -join ',') -ceq '20,16,10,16,21,11') 'PRG-003 restores cumulative weight after backfill'

$verifiedAt = [DateTimeOffset]'2026-11-25T00:00:00Z'
$pin = @{ asOf = $verifiedAt.ToString('o'); evidenceId = 'synthetic-checkpoint'
    inputSha256 = Get-RemainingWorkInputHash -ProjectId demo -AsOf $verifiedAt -Baselines @($first, $expanded) -Decisions $later }
$verified = Get-ProjectRemainingWork @period -Baselines @($first, $expanded) -Decisions $later -Coverage ($initial + $resumed) -Checkpoint $pin
Assert-That ($verified.points[4].state -ceq 'incomplete' -and $verified.points[5].remainingWeight -eq 11) 'PRG-008 checkpoint resumes confirmed points without hiding an older gap'
$pin.inputSha256 = 'A' * 64
try {
    $null = Get-ProjectRemainingWork @period -Baselines @($first, $expanded) -Decisions $later -Coverage ($initial + $resumed) -Checkpoint $pin
    throw 'Expected rejection'
} catch {
    if ($_.Exception.Message -cne 'STALE_REMAINING_WORK_CHECKPOINT') { throw }
    'PASS: PRG-008 changed checkpoint evidence cannot confirm history'
}

$moscow = [TimeZoneInfo]::FindSystemTimeZoneById('Russian Standard Time')
$boundary = Decision midnight A v1 accepted '2026-11-21T00:00:00+03:00'
$bounds = @(Coverage '2026-11-20T00:00:00Z' '2026-11-23T00:00:00Z')
$daily = Get-ProjectRemainingWork -ProjectId demo -From '2026-11-20' -Through '2026-11-22' -SnapshotAt '2026-11-22T21:00:00Z' -TimeZone $moscow -Baselines @($first) -Decisions @($boundary) -Coverage $bounds
Assert-That (($daily.points.remainingWeight -join ',') -ceq '20,16,16') 'PRG-008 local midnight changes exactly the following point'

$expanded.reason = 'Добавлен отчёт по остатку'
$third = @{ projectId = 'demo'; version = 'v3'; previousVersion = 'v2'
    approvedAt = '2026-11-24T14:00:00Z'; items = $items + @((Item D 5), (Item E 2)) }
$changes = Get-ProjectRemainingWork -ProjectId demo -From '2026-11-24' -Through '2026-11-24' -SnapshotAt '2026-11-25T00:00:00Z' -TimeZone ([TimeZoneInfo]::Utc) -Baselines @($first, $expanded, $third)
$point = $changes.points[0]
Assert-That ($point.state -ceq 'incomplete' -and $point.scopeChanged -and $point.scopeChanges.Count -eq 2 -and
    $point.scopeChanges[0].previousScopeVersion -ceq 'v1' -and $point.scopeChanges[0].scopeVersion -ceq 'v2' -and
    $point.scopeChanges[0].weightDelta -eq 5 -and $point.scopeChanges[0].reason -ceq 'Добавлен отчёт по остатку' -and
    $point.scopeChanges[1].weightDelta -eq 2 -and $null -eq $point.scopeChanges[1].reason) 'PRG-004 explains multiple scope changes starting on the first day despite missing acceptance coverage'


$exact = [DateTimeOffset]'2026-11-20T12:00:00Z'
$exactDecision = Decision at-cutoff A v1 accepted $exact.ToString('o')
$laterDecision = Decision after-cutoff B v1 accepted $exact.AddTicks(1).ToString('o')
$current = @{ ProjectId = 'demo'; From = '2026-11-20'; Through = '2026-11-20'
    SnapshotAt = $exact; TimeZone = [TimeZoneInfo]::Utc
    Baselines = @($first); Decisions = @($exactDecision, $laterDecision) }
$confirmed = Get-ProjectRemainingWork @current -Coverage @(Coverage $first.approvedAt $exact.AddTicks(1).ToString('o'))
Assert-That ($confirmed.points[0].acceptedWeight -eq 4 -and $confirmed.points[0].remainingWeight -eq 16) 'PRG-008 includes the exact snapshot tick and excludes the next tick'
$unconfirmed = Get-ProjectRemainingWork @current -Coverage @(Coverage $first.approvedAt $exact.ToString('o'))
Assert-That ($unconfirmed.points[0].state -ceq 'incomplete' -and !$unconfirmed.points[0].ContainsKey('acceptedWeight')) 'PRG-008 requires coverage of the exact snapshot tick'

$atMidnight = Get-ProjectRemainingWork -ProjectId demo -From '2026-11-20' -Through '2026-11-21' -SnapshotAt $boundary.at -TimeZone $moscow -Baselines @($first) -Decisions @($boundary) -Coverage $bounds
Assert-That (($atMidnight.points.remainingWeight -join ',') -ceq '20,16') 'PRG-008 a midnight snapshot includes the decision on the new day only'
