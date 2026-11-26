Set-StrictMode -Version Latest

function Get-ProjectDateForecast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][DateOnly]$AsOf,
        [Nullable[decimal]]$RemainingWeight,
        [Nullable[decimal]]$UnitsPerDayLow,
        [Nullable[decimal]]$UnitsPerDayHigh,
        [DayOfWeek[]]$WorkDays = @(),
        [DateOnly[]]$DaysOff = @(),
        [Nullable[DateOnly]]$PlanFinish,
        [Nullable[DateOnly]]$NotBefore,
        [Nullable[DateOnly]]$CompletedAt,
        [switch]$UnresolvedBlocker
    )

    $result = @{
        state = 'not_assessed'
        reason = $null
        method = 'scenario'
        asOf = $AsOf
        planFinish = $PlanFinish
    }

    if (($null -ne $RemainingWeight -and $RemainingWeight -lt 0) -or
        ($null -ne $UnitsPerDayLow -and $UnitsPerDayLow -lt 0) -or
        ($null -ne $UnitsPerDayHigh -and $UnitsPerDayHigh -lt 0) -or
        ($null -ne $UnitsPerDayLow -and $null -ne $UnitsPerDayHigh -and $UnitsPerDayLow -gt $UnitsPerDayHigh) -or
        ($null -ne $CompletedAt -and ($CompletedAt -gt $AsOf -or $RemainingWeight -ne 0))) {
        throw 'PROJECT_FORECAST_INVALID_INPUT'
    }

    if ($null -eq $RemainingWeight) { $result.reason = 'scope_unavailable'; return $result }
    if ($RemainingWeight -eq 0) {
        if ($null -eq $CompletedAt) { $result.reason = 'completion_date_unavailable'; return $result }
        $result.state = 'completed'
        $result.completedAt = $CompletedAt
        return $result
    }
    if ($UnresolvedBlocker) { $result.reason = 'blocker_unresolved'; return $result }
    if (!$WorkDays.Count) { $result.reason = 'calendar_unavailable'; return $result }
    if ($null -eq $UnitsPerDayLow -or $null -eq $UnitsPerDayHigh) { $result.reason = 'pace_unavailable'; return $result }
    if ($UnitsPerDayLow -eq 0) { $result.reason = 'capacity_zero'; return $result }

    $horizon = [Math]::Min(3660, [DateOnly]::MaxValue.DayNumber - $AsOf.DayNumber)
    if ($RemainingWeight / [Math]::Max(1, $horizon) -gt $UnitsPerDayLow) {
        $result.reason = 'horizon_exceeded'
        return $result
    }

    $fastDays = [Math]::Ceiling($RemainingWeight / $UnitsPerDayHigh)
    $slowDays = [Math]::Ceiling($RemainingWeight / $UnitsPerDayLow)
    $fastDays = [Math]::Max([decimal]1, $fastDays)
    $slowDays = [Math]::Max([decimal]1, $slowDays)
    $excluded = [Collections.Generic.HashSet[DateOnly]]::new()
    foreach ($date in $DaysOff) { [void]$excluded.Add($date) }
    $count = 0
    $earliest = $null
    $latest = $null
    for ($day = 1; $day -le $horizon; $day++) {
        $date = $AsOf.AddDays($day)
        if ($date.DayOfWeek -cnotin $WorkDays -or $excluded.Contains($date) -or
            ($null -ne $NotBefore -and $date -lt $NotBefore)) { continue }
        $count++
        if ($count -eq $fastDays) { $earliest = $date }
        if ($count -eq $slowDays) { $latest = $date; break }
    }
    if ($null -eq $latest) { $result.reason = 'horizon_exceeded'; return $result }

    $result.state = 'available'
    $result.earliest = $earliest
    $result.latest = $latest
    if ($null -ne $PlanFinish) {
        $result.earliestDeltaDays = $earliest.DayNumber - $PlanFinish.DayNumber
        $result.latestDeltaDays = $latest.DayNumber - $PlanFinish.DayNumber
    }
    $result
}

function Compare-ProjectDateForecast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Previous,
        [Parameter(Mandatory)][hashtable]$Current,
        [Nullable[decimal]]$ScopeWeightDelta
    )

    $before = Get-ProjectDateForecast @Previous
    $after = Get-ProjectDateForecast @Current
    $comparison = @{ before = $before; after = $after; totalDays = $null; scopeDays = $null; otherDays = $null }
    if ($before.state -cne 'available' -or $after.state -cne 'available') { return $comparison }

    $comparison.totalDays = @{
        earliest = $after.earliest.DayNumber - $before.earliest.DayNumber
        latest = $after.latest.DayNumber - $before.latest.DayNumber
    }
    if ($null -eq $ScopeWeightDelta) { return $comparison }
    $scopeOnlyInputs = $Previous.Clone()
    $scopeOnlyInputs.RemainingWeight += $ScopeWeightDelta
    if ($scopeOnlyInputs.RemainingWeight -le 0) { return $comparison }

    $scopeOnly = Get-ProjectDateForecast @scopeOnlyInputs
    if ($scopeOnly.state -cne 'available') { return $comparison }
    $comparison.scopeDays = @{
        earliest = $scopeOnly.earliest.DayNumber - $before.earliest.DayNumber
        latest = $scopeOnly.latest.DayNumber - $before.latest.DayNumber
    }
    $comparison.otherDays = @{
        earliest = $after.earliest.DayNumber - $scopeOnly.earliest.DayNumber
        latest = $after.latest.DayNumber - $scopeOnly.latest.DayNumber
    }
    $comparison
}

Export-ModuleMember -Function Get-ProjectDateForecast, Compare-ProjectDateForecast
