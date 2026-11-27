#Requires -Version 7.6
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProjectPeriod.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProjectProgress.psm1')

function Get-RemainingWorkInputHash {
    param([string]$ProjectId, [DateTimeOffset]$AsOf, [object[]]$Baselines, [object[]]$Decisions)
    $previousBaselines = @(foreach ($baseline in $Baselines) {
        if ([DateTimeOffset]$baseline['approvedAt'] -gt $AsOf) { continue }
        [ordered]@{
            projectId = $baseline['projectId']; version = $baseline['version']
            previousVersion = $baseline['previousVersion']; approvedAt = $baseline['approvedAt']
            items = @(foreach ($item in ($baseline['items'] | Sort-Object { $_['id'] } -CaseSensitive)) {
                [ordered]@{ id = $item['id']; weight = [decimal]$item['weight']; criteriaVersion = $item['criteriaVersion'] }
            })
        }
    })
    $previousDecisions = @(foreach ($decision in ($Decisions | Sort-Object { $_['eventId'] } -CaseSensitive)) {
        if ([DateTimeOffset]$decision['at'] -gt $AsOf) { continue }
        [ordered]@{
            projectId = $decision['projectId']; eventId = $decision['eventId']; itemId = $decision['itemId']
            scopeVersion = $decision['scopeVersion']; type = $decision['type']; criteriaVersion = $decision['criteriaVersion']
            evidenceId = $decision['evidenceId']; at = $decision['at']
        }
    })
    $json = [ordered]@{ v = 1; projectId = $ProjectId; asOf = $AsOf.ToUniversalTime().ToString('o')
        baselines = $previousBaselines; decisions = $previousDecisions } | ConvertTo-Json -Depth 8 -Compress
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($json)))
}

function Get-ProjectRemainingWork {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][DateOnly]$From,
        [Parameter(Mandatory)][DateOnly]$Through,
        [Parameter(Mandatory)][DateTimeOffset]$SnapshotAt,
        [Parameter(Mandatory)][TimeZoneInfo]$TimeZone,
        [object[]]$Baselines = @(),
        [object[]]$Decisions = @(),
        [object[]]$Coverage = @(),
        [Collections.IDictionary]$Checkpoint
    )

    $period = Get-ProjectPeriod -From $From -Through $Through -SnapshotAt $SnapshotAt -TimeZone $TimeZone
    if ($Through.DayNumber - $From.DayNumber -ge 90) { return @{ state = 'range_too_large'; points = @() } }
    if (!$Baselines.Count) { return @{ state = 'unconfigured'; points = @() } }

    $origin = [DateTimeOffset]::Parse($Baselines[0]['approvedAt'], [Globalization.CultureInfo]::InvariantCulture)
    $verifiedAt = $null
    if ($null -ne $Checkpoint) {
        $checkpointAt = [DateTimeOffset]::MinValue
        if ($Checkpoint['asOf'] -isnot [string] -or $Checkpoint['asOf'] -cnotmatch '(Z|[+-]\d{2}:\d{2})$' -or
            ![DateTimeOffset]::TryParse($Checkpoint['asOf'], [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None, [ref]$checkpointAt) -or $checkpointAt -lt $origin -or
            $Checkpoint['evidenceId'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Checkpoint['evidenceId']) -or
            $Checkpoint['inputSha256'] -cnotmatch '\A[A-F0-9]{64}\z') { throw 'INVALID_REMAINING_WORK_CHECKPOINT' }
        if ($checkpointAt -le $SnapshotAt) {
            $hash = Get-RemainingWorkInputHash -ProjectId $ProjectId -AsOf $checkpointAt -Baselines $Baselines -Decisions $Decisions
            if ($hash -cne $Checkpoint['inputSha256']) { throw 'STALE_REMAINING_WORK_CHECKPOINT' }
            $verifiedAt = $checkpointAt
        }
    }
    $types = @('accepted', 'acceptance_revoked')
    $changeTicks = @(
        foreach ($baseline in $Baselines) { ([DateTimeOffset]$baseline['approvedAt']).UtcTicks }
        foreach ($decision in $Decisions) { ([DateTimeOffset]$decision['at']).UtcTicks }
    ) | Sort-Object -Unique
    $changeTicks = @($changeTicks)
    $changeIndex = 0
    $snapshot = $null
    $previousVersion = $null
    $points = @(for ($day = $period.From; $day -le $period.Through; $day = $day.AddDays(1)) {
        $dayPeriod = Get-ProjectPeriod -From $day -Through $day -SnapshotAt $SnapshotAt -TimeZone $TimeZone
        $endTicks = $dayPeriod.EndUtc.UtcTicks
        $previousIndex = $changeIndex
        while ($changeIndex -lt $changeTicks.Count -and $changeTicks[$changeIndex] -lt $endTicks) {
            $changeIndex++
        }
        if ($null -eq $snapshot -or $changeIndex -ne $previousIndex) {
            $snapshot = Get-ProjectProgress -ProjectId $ProjectId -AsOf $dayPeriod.EndUtc.AddTicks(-1) -Baselines $Baselines -Decisions $Decisions
        }
        $point = @{ date = $day.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture); state = $snapshot.state }
        if ($snapshot.state -ceq 'available') {
            $point.scopeVersion = $snapshot.scopeVersion
            $point.scopeChanged = $null -ne $previousVersion -and $previousVersion -cne $snapshot.scopeVersion
            $previousVersion = $snapshot.scopeVersion
            $point.totalWeight = $snapshot.totalWeight
            $cumulative = @{StartUtc = $origin.ToUniversalTime(); EndUtc = $dayPeriod.EndUtc}
            if ($null -ne $verifiedAt -and $verifiedAt -lt $dayPeriod.EndUtc) {
                $cumulative.StartUtc = $verifiedAt.AddTicks(1).ToUniversalTime()
            }
            $confirmed = $cumulative.StartUtc -ge $cumulative.EndUtc -or
                (Get-ProjectHistoryCoverage $cumulative $Coverage $types).accepted.complete
            if ($confirmed) {
                $point.acceptedWeight = $snapshot.acceptedWeight
                $point.remainingWeight = $snapshot.remainingWeight
            } else {
                $point.state = 'incomplete'
            }
        }
        $point
    })
    @{ state = 'available'; points = $points }
}

Export-ModuleMember -Function Get-ProjectRemainingWork, Get-RemainingWorkInputHash
