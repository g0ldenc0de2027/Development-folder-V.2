#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/lib/ProjectForecast.psm1') -Force

$options = @{
    AsOf = [DateOnly]::new(2026,11,26)
    PlanFinish = [DateOnly]::new(2026,12,8)
    WorkDays = @('Monday','Tuesday','Wednesday','Thursday','Friday')
}

function Assert-That([bool]$Condition, [string]$Name) {
    if (!$Condition) { throw "FAIL: $Name" }
    "PASS: $Name"
}

$initial = Get-ProjectDateForecast @options -RemainingWeight 8 -UnitsPerDayLow 1 -UnitsPerDayHigh 2
Assert-That ($initial.state -ceq 'available' -and $initial.method -ceq 'scenario' -and
    $initial.earliest -eq [DateOnly]::new(2026,12,2) -and $initial.latest -eq [DateOnly]::new(2026,12,8)) 'PRG-007 original workload'

$expanded = Get-ProjectDateForecast @options -RemainingWeight 13 -UnitsPerDayLow 1 -UnitsPerDayHigh 2
Assert-That ($expanded.earliest -eq [DateOnly]::new(2026,12,7) -and $expanded.latest -eq [DateOnly]::new(2026,12,15) -and
    $expanded.earliestDeltaDays -eq -1 -and $expanded.latestDeltaDays -eq 7 -and
    $expanded.planFinish -eq $initial.planFinish) 'PRG-007 scope expansion preserves original plan'

$adjusted = Get-ProjectDateForecast @options -RemainingWeight 13 -UnitsPerDayLow 1.3 -UnitsPerDayHigh 2.6 -DaysOff @([DateOnly]::new(2026,11,30))
Assert-That ($adjusted.earliest -eq [DateOnly]::new(2026,12,4) -and $adjusted.latest -eq [DateOnly]::new(2026,12,11)) 'PRG-007 changed pace and holiday'

$delayed = Get-ProjectDateForecast @options -RemainingWeight 2 -UnitsPerDayLow 1 -UnitsPerDayHigh 2 -NotBefore ([DateOnly]::new(2026,11,29))
Assert-That ($delayed.earliest -eq [DateOnly]::new(2026,11,30) -and $delayed.latest -eq [DateOnly]::new(2026,12,1)) 'PRG-007 dependency and weekend'

Assert-That ((Get-ProjectDateForecast @options).reason -ceq 'scope_unavailable') 'PRG-007 missing scope'
Assert-That ((Get-ProjectDateForecast @options -RemainingWeight 1).reason -ceq 'pace_unavailable') 'PRG-007 missing pace'
Assert-That ((Get-ProjectDateForecast -AsOf $options.AsOf -RemainingWeight 1).reason -ceq 'calendar_unavailable') 'PRG-007 missing calendar'
Assert-That ((Get-ProjectDateForecast @options -RemainingWeight 1 -UnitsPerDayLow 0 -UnitsPerDayHigh 1).reason -ceq 'capacity_zero') 'PRG-007 zero capacity'
Assert-That ((Get-ProjectDateForecast @options -RemainingWeight 1 -UnresolvedBlocker).reason -ceq 'blocker_unresolved') 'PRG-007 blocker without date'
Assert-That ((Get-ProjectDateForecast @options -RemainingWeight 9000 -UnitsPerDayLow 1 -UnitsPerDayHigh 2).reason -ceq 'horizon_exceeded') 'PRG-007 bounded date horizon'
Assert-That ((Get-ProjectDateForecast @options -RemainingWeight 0).reason -ceq 'completion_date_unavailable') 'PRG-007 no false completion date'
Assert-That ((Get-ProjectDateForecast @options -RemainingWeight 0 -CompletedAt $options.AsOf).state -ceq 'completed') 'PRG-007 evidenced completion'

$previous = $options + @{RemainingWeight = 8; UnitsPerDayLow = 1; UnitsPerDayHigh = 2}
$current = $options + @{RemainingWeight = 13; UnitsPerDayLow = 1.3; UnitsPerDayHigh = 2.6; DaysOff = @([DateOnly]::new(2026,11,30))}
$change = Compare-ProjectDateForecast -Previous $previous -Current $current -ScopeWeightDelta 5
Assert-That ($change.totalDays.earliest -eq 2 -and $change.totalDays.latest -eq 3 -and
    $change.scopeDays.earliest -eq 5 -and $change.scopeDays.latest -eq 7 -and
    $change.otherDays.earliest -eq -3 -and $change.otherDays.latest -eq -4) 'PRG-007 explains the shift by scope and remaining assumptions'
Assert-That ($previous.RemainingWeight -eq 8) 'PRG-008 preserves the prior inputs'
$withoutScope = Compare-ProjectDateForecast -Previous $previous -Current $current
Assert-That ($withoutScope.totalDays.latest -eq 3 -and $null -eq $withoutScope.scopeDays -and
    $null -eq $withoutScope.otherDays) 'PRG-008 no attribution without confirmed scope delta'
$withoutForecast = Compare-ProjectDateForecast -Previous $previous -Current ($current + @{UnresolvedBlocker = $true})
Assert-That ($withoutForecast.after.reason -ceq 'blocker_unresolved' -and $null -eq $withoutForecast.totalDays) 'PRG-008 no delta without comparable dates'
