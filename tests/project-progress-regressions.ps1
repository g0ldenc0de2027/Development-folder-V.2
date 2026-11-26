#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/lib/ProjectProgress.psm1') -Force

function Item($Id, $Weight, $Criteria = 'v1') { @{ id = $Id; weight = $Weight; criteriaVersion = $Criteria } }
function Baseline($Version, $Previous, $At, $Items) {
    @{ projectId = 'demo'; version = $Version; previousVersion = $Previous; approvedAt = $At; items = $Items }
}
function Decision($EventId, $Id, $Version, $At, $Type = 'accepted') {
    @{ projectId = 'demo'; eventId = $EventId; itemId = $Id; scopeVersion = $Version; at = $At;
        type = $Type; criteriaVersion = 'v1'; evidenceId = 'synthetic' }
}
function Assert-Snapshot($Name, $Expected, $At, $Baselines, $Decisions) {
    $result = Get-ProjectProgress -ProjectId demo -AsOf $At -Baselines $Baselines -Decisions $Decisions
    $actual = if ($result.state -ceq 'available') { [string]::Format([Globalization.CultureInfo]::InvariantCulture, "{0:G29}/{1:G29}", $result.percent, $result.remainingWeight) } else { $result.state }
    if ($actual -ne $Expected) { throw "FAIL: $Name ($actual)" }
    "PASS: $Name"
}

$b1 = Baseline first $null '2026-11-01T00:00:00Z' @((Item A 12), (Item B 8))
$b2 = Baseline expanded first '2026-11-04T00:00:00Z' @((Item A 12), (Item B 8), (Item C 5))
$accepted = Decision event-one A first '2026-11-02T00:00:00Z'
$revoked = Decision event-two A expanded '2026-11-06T00:00:00Z' acceptance_revoked
$historic = '2026-11-03T00:00:00Z'
$current = '2026-11-05T00:00:00Z'
Assert-Snapshot 'PRG-002 missing baseline' 'not_assessed' $current @() @()
Assert-Snapshot 'PRG-003 approved empty acceptance history' '0/20' $historic @($b1) @()
Assert-Snapshot 'PRG-004 historical version' '60/8' $historic @($b1, $b2) @($accepted, $revoked)
Assert-Snapshot 'PRG-004 expanded scope' '48/13' $current @($b1, $b2) @($accepted, $revoked)
Assert-Snapshot 'PRG-004 acceptance revoked' '0/25' '2026-11-07T00:00:00Z' @($b1, $b2) @($revoked, $accepted)
$changed = Baseline changed first '2026-11-04T00:00:00Z' @((Item A 12 v2), (Item B 8))
Assert-Snapshot 'PRG-004 changed criteria require acceptance' '0/20' $current @($b1, $changed) @($accepted)
$removed = Baseline removed first '2026-11-04T00:00:00Z' @((Item A 12))
Assert-Snapshot 'PRG-004 removed outstanding scope' '100/0' $current @($b1, $removed) @($accepted)
$reweighted = Baseline reweighted first '2026-11-04T00:00:00Z' @((Item A 12), (Item B 12))
Assert-Snapshot 'PRG-004 reweighted scope' '50/12' $current @($b1, $reweighted) @($accepted)
$almost = Baseline almost first '2026-11-04T00:00:00Z' @((Item A 9999), (Item B 1))
Assert-Snapshot 'PRG-009 positive remainder below rounding threshold' '99.9/1' $current @($b1, $almost) @($accepted)

$barely = Baseline barely first '2026-11-04T00:00:00Z' @((Item A 1), (Item B 2000))
Assert-Snapshot 'PRG-009 positive acceptance below rounding threshold' '0.1/2000' $current @($b1, $barely) @($accepted)

$foreign = $accepted.Clone()
$foreign.projectId = 'different'
try {
    $null = Get-ProjectProgress -ProjectId demo -AsOf $current -Baselines @($b1) -Decisions @($foreign)
    throw 'Unexpected cross-project acceptance.'
} catch {
    if ($_.Exception.Message -cne 'PROJECT_PROGRESS_INVALID_DECISION') { throw }
}
'PASS: PRG-001 rejects cross-project acceptance'
