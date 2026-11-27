#Requires -Version 7.6
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'scripts/lib/ProjectDecisionJournal.psm1')
Import-Module (Join-Path $root 'scripts/lib/ProjectProgress.psm1')
Import-Module (Join-Path $root 'scripts/lib/ProjectPeriod.psm1')
$writer = Join-Path $root 'scripts/update-project-owner-decisions.ps1'
$directory = [IO.Directory]::CreateTempSubdirectory('decision-journal-')
$path = Join-Path $directory.FullName 'decisions.json'

function Assert-Journal($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

try {
    [IO.File]::WriteAllText($path, '{"schemaVersion":1,"projectId":"demo","events":[],"coverage":[]}')
    $baselines = @(@{
        projectId = 'demo'; version = 'v1'; approvedAt = '2026-11-27T08:00:00Z'
        items = @(@{ id = 'one'; criteriaVersion = 'v1'; weight = 3 }, @{ id = 'two'; criteriaVersion = 'v1'; weight = 2 },
                  @{ id = 'three'; criteriaVersion = 'v1'; weight = 3 })
    })
    $inputArgs = @{ JournalPath = $path; ProjectId = 'demo'; Baselines = $baselines }
    $event = @{
        projectId = 'demo'; eventId = 'd1'; itemId = 'one'; scopeVersion = 'v1'; criteriaVersion = 'v1'
        type = 'accepted'; at = '2026-11-27T09:00:00Z'; evidenceId = 'synthetic-one'
    }
    $first = & $writer @inputArgs -Decision $event
    Assert-Journal ($first.published -and $first.sha256 -ceq (Get-FileHash -LiteralPath $path).Hash) 'First publication failed'
    $retry = & $writer @inputArgs -Decision $event
    Assert-Journal (!$retry.published -and $retry.sha256 -ceq $first.sha256) 'Duplicate changed snapshot'
    $different = $event.Clone()
    $different.evidenceId = 'different'
    try {
        $null = & $writer @inputArgs -Decision $different
        throw 'Conflicting duplicate accepted'
    } catch {
        if ($_.Exception.Message -cne 'DECISION_JOURNAL_ID_CONFLICT') { throw }
    }
    Assert-Journal ((Get-FileHash -LiteralPath $path).Hash -ceq $first.sha256) 'Conflict changed snapshot'

    $candidate = $event.Clone()
    $candidate.eventId = 'busy'
    $candidate.at = '2026-11-27T09:15:00Z'
    $candidate.itemId = 'two'
    $pathKey = [Text.Encoding]::UTF8.GetBytes((Get-Item -LiteralPath $path).FullName.ToUpperInvariant())
    $lockKey = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($pathKey))
    $mutex = [Threading.Mutex]::new($false, "Local\v2-decision-journal-$lockKey")
    $job = $null
    $locked = $mutex.WaitOne(0)
    try {
        Assert-Journal $locked 'Fixture could not acquire mutex'
        $job = Start-Job -ArgumentList $writer, $inputArgs, $candidate -ScriptBlock {
            param($CommandPath, $Inputs, $Event)
            $ErrorActionPreference = 'Stop'
            try { $null = & $CommandPath @Inputs -Decision $Event }
            catch { return $_.Exception.Message }
            'UNEXPECTED_SUCCESS'
        }
        Assert-Journal ($null -ne (Wait-Job -Job $job -Timeout 20)) 'Contending writer timed out'
        Assert-Journal ((Receive-Job -Job $job) -ceq 'DECISION_JOURNAL_WRITER_BUSY') 'Contending writer was not refused'
        Assert-Journal ((Get-FileHash -LiteralPath $path).Hash -ceq $first.sha256) 'Contention changed snapshot'
    } finally {
        if ($job) { Remove-Job -Job $job -Force }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }

    $reader = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $replaceFailed = $false
        try { $null = & $writer @inputArgs -Decision $candidate }
        catch [IO.IOException] { $replaceFailed = $true }
        Assert-Journal $replaceFailed 'Replacement unexpectedly bypassed read handle'
        Assert-Journal ((Get-FileHash -LiteralPath $path).Hash -ceq $first.sha256) 'Failed replacement changed snapshot'
        Assert-Journal (@($directory.GetFiles()).Count -eq 1) 'Failure left staged file'
    } finally {
        $reader.Dispose()
    }

    $second = $event.Clone()
    $second.eventId = 'd2'; $second.itemId = 'two'; $second.at = '2026-11-27T10:00:00Z'
    $third = $event.Clone()
    $third.eventId = 'd3'; $third.itemId = 'three'; $third.at = '2026-11-27T11:00:00Z'
    $revoke = $second.Clone()
    $revoke.eventId = 'd4'; $revoke.type = 'acceptance_revoked'; $revoke.at = '2026-11-27T12:00:00Z'
    foreach ($next in $second, $third, $revoke) {
        Assert-Journal ((& $writer @inputArgs -Decision $next).published) 'New decision was not published'
    }
    $coverage = @(
        @{ type = 'accepted'; from = '2026-11-27T08:00:00Z'; until = '2026-11-27T13:00:00Z' },
        @{ type = 'acceptance_revoked'; from = '2026-11-27T08:00:00Z'; until = '2026-11-27T13:00:00Z' }
    )
    $coverageWrite = & $writer @inputArgs -ConfirmedCoverage $coverage
    Assert-Journal $coverageWrite.published 'Coverage-only update was omitted'
    $coverageRetry = & $writer @inputArgs -ConfirmedCoverage $coverage
    Assert-Journal (!$coverageRetry.published -and $coverageRetry.sha256 -ceq $coverageWrite.sha256) 'Coverage retry changed snapshot'
    $bad = @{ type = 'accepted'; from = '2026-11-27T13:00:00Z'; until = '2026-11-27T12:00:00Z' }
    try {
        $null = & $writer @inputArgs -Decision $candidate -ConfirmedCoverage @($bad)
        throw 'Invalid combined update accepted'
    } catch {
        if ($_.Exception.Message -cne 'DECISION_JOURNAL_INVALID_COVERAGE') { throw }
    }
    Assert-Journal ((Get-FileHash -LiteralPath $path).Hash -ceq $coverageWrite.sha256) 'Invalid coverage published part of the update'
    $snapshot = Read-ProjectDecisionJournal -Path $path -ProjectId demo -Baselines $baselines
    Assert-Journal ($snapshot.document.events.Count -eq 4) 'Decision missing'
    foreach ($slice in @(
        @{ at = '2026-11-27T09:30:00Z'; expected = 37.5 },
        @{ at = '2026-11-27T10:30:00Z'; expected = 62.5 },
        @{ at = '2026-11-27T11:30:00Z'; expected = 100 },
        @{ at = '2026-11-27T12:30:00Z'; expected = 75 }
    )) {
        $progress = Get-ProjectProgress -ProjectId demo -AsOf ([DateTimeOffset]$slice.at) -Baselines $baselines -Decisions $snapshot.document.events
        Assert-Journal ($progress.percent -eq $slice.expected) "Wrong progress at $($slice.at)"
    }
    $late = $event.Clone()
    $late.eventId = 'late'; $late.at = '2026-11-27T15:00:00Z'
    Assert-Journal ((& $writer @inputArgs -Decision $late).published) 'Known event outside the verified window was lost'
    $snapshot = Read-ProjectDecisionJournal -Path $path -ProjectId demo -Baselines $baselines
    Assert-Journal ($snapshot.document.events.Count -eq 5) 'Partial journal lost its known event'
    $types = 'accepted', 'acceptance_revoked'
    $window = @{ StartUtc = [DateTimeOffset]'2026-11-27T08:00:00Z'; EndUtc = [DateTimeOffset]'2026-11-27T13:00:00Z' }
    $coverageView = Get-ProjectHistoryCoverage -Period $window -Coverage $snapshot.document.coverage -Types $types
    Assert-Journal $coverageView.accepted.complete 'An event outside the period invalidated documented coverage'
    $window.EndUtc = [DateTimeOffset]'2026-11-27T16:00:00Z'
    $coverageView = Get-ProjectHistoryCoverage -Period $window -Coverage $snapshot.document.coverage -Types $types
    Assert-Journal (!$coverageView.accepted.complete -and $coverageView.accepted.gaps.Count -eq 2) 'Known events outside coverage hid an unverified tail'
    $valid = Get-ProjectJournalProgress -Snapshot $snapshot -ProjectId demo -Baselines $baselines -AsOf ([DateTimeOffset]'2026-11-27T12:30:00Z')
    Assert-Journal ($valid.state -ceq 'available' -and $valid.percent -eq 75) 'Verified history did not produce weight'
    $atEnd = Get-ProjectJournalProgress -Snapshot $snapshot -ProjectId demo -Baselines $baselines -AsOf ([DateTimeOffset]'2026-11-27T13:00:00Z')
    Assert-Journal ($atEnd.state -ceq 'incomplete' -and !$atEnd.ContainsKey('percent')) 'Inclusive cutoff counted unverified instant'
    $afterGap = Get-ProjectJournalProgress -Snapshot $snapshot -ProjectId demo -Baselines $baselines -AsOf ([DateTimeOffset]'2026-11-27T16:00:00Z')
    Assert-Journal ($afterGap.state -ceq 'incomplete' -and !$afterGap.ContainsKey('percent')) 'Known decision hid a gap in weighted progress'
    Assert-Journal (@($directory.GetFiles()).Count -eq 1) 'Unexpected staged files'
    'PASS: publish, replay, conflict, writer contention, replacement failure, revoke and cleanup'
} finally {
    [IO.File]::Delete($path)
    $directory.Delete()
}
