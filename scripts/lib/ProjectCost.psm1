Set-StrictMode -Version Latest

function Read-CostRange([object]$Range, [string]$Code) {
    if ($null -eq $Range) { return $null }
    if ($Range -isnot [array] -or $Range.Count -ne 3) { throw $Code }
    $values = foreach ($value in $Range) {
        if ($null -eq $value -or $value -isnot [ValueType] -or $value -is [bool] -or
            $value -is [char] -or $value -is [datetime] -or $value -is [datetimeoffset]) { throw $Code }
        try { [decimal]$amount = $value } catch { throw $Code }
        if ($amount -lt 0) { throw $Code }
        $amount
    }
    if ($values[0] -gt $values[1] -or $values[1] -gt $values[2]) { throw $Code }
    return ,$values
}

function Get-CostEstimate($Hours, [decimal]$Rate, $AiRub, $AiUsd, [decimal]$RubPerUsd, $SpentRub, $SpentUsd) {
    $laborRub = if ($null -ne $Hours) { @($Hours | ForEach-Object { $_ * $Rate }) }
    $rub = $null
    $usd = $null
    $needsExchangeRate = $false
    if ($null -ne $laborRub -and $null -ne $AiRub -and $null -ne $AiUsd -and
        $null -ne $SpentRub -and $null -ne $SpentUsd) {
        $nativeRub = for ($i = 0; $i -lt 3; $i++) { $SpentRub + $laborRub[$i] + $AiRub[$i] }
        $nativeUsd = @($AiUsd | ForEach-Object { $SpentUsd + $_ })
        if ($RubPerUsd -gt 0) {
            $rub = @(for ($i = 0; $i -lt 3; $i++) { $nativeRub[$i] + $nativeUsd[$i] * $RubPerUsd })
            $usd = @($rub | ForEach-Object { $_ / $RubPerUsd })
        } else {
            if ($nativeUsd[2] -eq 0) { $rub = $nativeRub }
            if ($nativeRub[2] -eq 0) { $usd = $nativeUsd }
            $needsExchangeRate = $null -eq $rub -or $null -eq $usd
        }
    }
    @{
        laborRub = $laborRub
        aiRub = $AiRub
        aiUsd = $AiUsd
        totalRub = $rub
        totalUsd = $usd
        missingInputs = @(
            if ($null -eq $Hours) { 'hours' }
            if ($null -eq $AiRub -or $null -eq $AiUsd) { 'ai' }
            if ($null -eq $SpentRub -or $null -eq $SpentUsd) { 'confirmedCost' }
            if ($needsExchangeRate) { 'exchangeRate' }
        )
    }
}

function Get-ProjectCost {
    [CmdletBinding()]
    param(
        [object]$PlanHours,
        [object]$PlanAiRub,
        [object]$PlanAiUsd,
        [decimal]$PlanRateRub = 1500,
        [decimal]$PlanRubPerUsd = 0,
        [object]$RemainingHours,
        [object]$RemainingAiRub,
        [object]$RemainingAiUsd,
        [decimal]$RateRub = 1500,
        [decimal]$RubPerUsd = 0,
        [Nullable[decimal]]$ConfirmedLaborRub,
        [Nullable[decimal]]$ConfirmedAiRub,
        [Nullable[decimal]]$ConfirmedAiUsd
    )

    if ($PlanRateRub -le 0 -or $RateRub -le 0 -or $PlanRubPerUsd -lt 0 -or $RubPerUsd -lt 0 -or
        (0 -gt $ConfirmedLaborRub -and $null -ne $ConfirmedLaborRub) -or
        (0 -gt $ConfirmedAiRub -and $null -ne $ConfirmedAiRub) -or
        (0 -gt $ConfirmedAiUsd -and $null -ne $ConfirmedAiUsd)) {
        throw 'PROJECT_COST_INVALID_INPUT'
    }
    $confirmedRub = if ($null -ne $ConfirmedLaborRub -and $null -ne $ConfirmedAiRub) {
        $ConfirmedLaborRub + $ConfirmedAiRub
    }
    $plan = Get-CostEstimate (Read-CostRange $PlanHours 'PROJECT_COST_INVALID_HOURS') $PlanRateRub `
        (Read-CostRange $PlanAiRub 'PROJECT_COST_INVALID_AI') (Read-CostRange $PlanAiUsd 'PROJECT_COST_INVALID_AI') `
        $PlanRubPerUsd 0 0
    $forecast = Get-CostEstimate (Read-CostRange $RemainingHours 'PROJECT_COST_INVALID_HOURS') $RateRub `
        (Read-CostRange $RemainingAiRub 'PROJECT_COST_INVALID_AI') (Read-CostRange $RemainingAiUsd 'PROJECT_COST_INVALID_AI') `
        $RubPerUsd $confirmedRub $ConfirmedAiUsd
    @{
        plan = $plan
        confirmed = @{ laborRub = $ConfirmedLaborRub; aiRub = $ConfirmedAiRub; aiUsd = $ConfirmedAiUsd }
        forecast = $forecast
    }
}

Export-ModuleMember -Function Get-ProjectCost
