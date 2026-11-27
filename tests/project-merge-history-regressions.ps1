#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scriptPath = Join-Path $PSScriptRoot '../scripts/sync-project-merge-history.ps1'
$history = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($history, '{"schemaVersion":1,"projectId":"demo","events":[{"sourceId":"owner","eventId":"a","taskId":"T-001","type":"accepted","at":"2026-11-01T01:00:00Z"}],"coverage":[]}')
    $mock = @{}
    $mock.response = '[[{"number":1,"state":"closed","base":{"ref":"main"},"head":{"ref":"task/T-001-demo"},"merged_at":"2026-11-01T00:00:00Z"}],[{"number":2,"state":"closed","base":{"ref":"main"},"head":{"ref":"task/T-002-demo"},"merged_at":"2026-11-02T00:00:00Z"}],[]]'
    $mock.exitCode = 0
    $mock.change = $false
    Set-Item -LiteralPath Function:gh -Value ({
        if ($mock.change) { [IO.File]::AppendAllText($history, [string][char]10) }
        $global:LASTEXITCODE = $mock.exitCode
        $mock.response
    }.GetNewClosure())
    $inputs = @{ HistoryPath = $history; ProjectId = 'demo'; Repository = 'demo/example' }
    $before = (Get-FileHash -LiteralPath $history).Hash
    $plan = & $scriptPath @inputs | ConvertFrom-Json
    if ($plan.published -or $plan.additions.Count -ne 2 -or (Get-FileHash -LiteralPath $history).Hash -cne $before) {
        throw 'Read-only plan modified history or omitted an event'
    }
    'PASS: PTR-VIS-005 paginated read-only plan preserves history'
    $applied = & $scriptPath @inputs -Apply | ConvertFrom-Json
    $actual = Get-Content -LiteralPath $history -Raw | ConvertFrom-Json -DateKind String
    if (!$applied.published -or $actual.events.Count -ne 3 -or $actual.events[0].eventId -cne 'a' -or
        $actual.events[1].eventId -cne 'pr-1-merged' -or $actual.events[2].eventId -cne 'pr-2-merged' -or $actual.coverage[0].type -cne 'merged') {
        throw 'Atomic publication did not preserve and extend history'
    }
    'PASS: PTR-VIS-005 atomic publication preserves owner decision'
    $repeated = & $scriptPath @inputs -Apply | ConvertFrom-Json
    if ($repeated.additions.Count -or (Get-Content -LiteralPath $history -Raw | ConvertFrom-Json).events.Count -ne 3) {
        throw 'Repeated import duplicated events'
    }
    'PASS: PTR-VIS-005 repeated import is idempotent'

    function Assert-Refusal([string]$Expected, [string]$Hash) {
        try {
            $null = & $scriptPath @inputs -Apply
            throw 'Expected import to fail'
        } catch {
            if ($_.Exception.Message -cne $Expected) { throw }
        }
        if ((Get-FileHash -LiteralPath $history).Hash -cne $Hash) { throw 'Refusal changed the expected history bytes' }
        "PASS: PTR-VIS-005 $Expected"
    }
    $stable = (Get-FileHash -LiteralPath $history).Hash
    $mock.exitCode = 1
    Assert-Refusal 'MERGE_HISTORY_FETCH_FAILED' $stable
    $mock.exitCode = 0
    $saved = $mock.response
    $mock.response = $saved.Replace('2026-11-02T00:00:00Z', '2026-11-02T00:00:01Z')
    Assert-Refusal 'MERGE_HISTORY_TIME_CONFLICT' $stable
    $mock.response = $saved.Replace('"number":2', '"number":1')
    Assert-Refusal 'MERGE_HISTORY_INVALID_PULL' $stable
    $mock.response = $saved
    $mock.change = $true
    $changed = [IO.File]::ReadAllText($history) + [char]10
    $replacementHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($changed)))
    Assert-Refusal 'MERGE_HISTORY_CHANGED' $replacementHash
} finally {
    [IO.File]::Delete($history)
}
