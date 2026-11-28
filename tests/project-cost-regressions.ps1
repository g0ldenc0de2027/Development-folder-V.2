#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot '../scripts/lib/ProjectCost.psm1') -Force

function Assert-Equal($Actual, $Expected, [string]$Name) {
    if (($Actual -join ',') -cne ($Expected -join ',')) { throw "FAIL: $Name -> $Actual" }
    Write-Output "PASS: $Name"
}

$zero = @(0, 0, 0)
$example = Get-ProjectCost -PlanHours @(40, 50, 60) -PlanAiRub @(5000, 5000, 5000) -PlanAiUsd $zero -PlanRubPerUsd 100
Assert-Equal $example.plan.totalRub @(65000, 80000, 95000) 'PRG-013 planned RUB'
Assert-Equal $example.plan.totalUsd @(650, 800, 950) 'PRG-014 planned USD'
if ($null -ne $example.forecast.totalRub -or 'confirmedCost' -cnotin $example.forecast.missingInputs) {
    throw 'Missing forecast must remain unknown.'
}
$forecast = Get-ProjectCost -RemainingHours @(20, 25, 30) -RemainingAiRub $zero -RemainingAiUsd @(10, 15, 20) `
    -RubPerUsd 90 -ConfirmedLaborRub 15000 -ConfirmedAiRub 2700 -ConfirmedAiUsd 0
Assert-Equal $forecast.forecast.totalRub @(48600, 56550, 64500) 'PRG-013 forecast RUB including confirmed spend'
$override = Get-ProjectCost -PlanHours @(1, 1, 1) -PlanAiRub $zero -PlanAiUsd $zero `
    -RemainingHours @(1, 1, 1) -RemainingAiRub $zero -RemainingAiUsd $zero -RateRub 2000 `
    -ConfirmedLaborRub 0 -ConfirmedAiRub 0 -ConfirmedAiUsd 0
Assert-Equal $override.plan.totalRub @(1500, 1500, 1500) 'PRG-015 historical rate preserved'
Assert-Equal $override.forecast.totalRub @(2000, 2000, 2000) 'PRG-015 project rate override'
if ($null -ne $override.forecast.totalUsd) { throw 'Missing FX must suppress USD conversion.' }
$mixed = Get-ProjectCost -PlanHours @(1, 1, 1) -PlanAiRub $zero -PlanAiUsd @(1, 1, 1)
if ($null -ne $mixed.plan.totalRub -or $null -ne $mixed.plan.totalUsd -or $mixed.plan.aiUsd[0] -ne 1) {
    throw 'Missing FX must preserve source amounts and suppress the mixed total.'
}
foreach ($bad in @(
    @{ PlanHours = @(1, 3, 2) },
    @{ PlanHours = @(-1, 0, 1) },
    @{ PlanHours = @('1', '2', '3') },
    @{ PlanAiUsd = @(1, 2) },
    @{ RateRub = 0 },
    @{ RubPerUsd = -1 },
    @{ ConfirmedAiUsd = -1 }
)) {
    try {
        $null = Get-ProjectCost @bad
        throw 'Invalid input accepted.'
    } catch {
        if ($_.Exception.Message -cnotlike 'PROJECT_COST_INVALID_*') { throw }
    }
}
Write-Output 'PASS: unavailable FX, missing inputs and invalid input boundaries'

$zeroForecast = Get-ProjectCost -RemainingHours $zero -RemainingAiRub $zero -RemainingAiUsd $zero `
    -ConfirmedLaborRub 0 -ConfirmedAiRub 0 -ConfirmedAiUsd 0
Assert-Equal $zeroForecast.forecast.totalRub $zero 'PRG-014 zero RUB without exchange rate'
Assert-Equal $zeroForecast.forecast.totalUsd $zero 'PRG-014 zero USD without exchange rate'
if ('exchangeRate' -cin $zeroForecast.forecast.missingInputs) { throw 'Zero totals do not require FX.' }

$mixedFx = Get-ProjectCost -RemainingHours $zero -RemainingAiRub $zero -RemainingAiUsd $zero `
    -RubPerUsd 82.1265 -ConfirmedLaborRub 360000 -ConfirmedAiRub 0 -ConfirmedAiUsd 200
Assert-Equal ([math]::Round($mixedFx.forecast.totalRub[0], 2)) 376425.30 'PRG-016 confirmed 240h x 1500 RUB + 200 USD at 82.1265'
Assert-Equal ([math]::Round($mixedFx.forecast.totalUsd[0], 2)) 4583.48 'PRG-016 mixed total in USD at 82.1265'
Assert-Equal $mixedFx.confirmed.aiUsd @(200) 'PRG-016 source USD preserved with FX'
$mixedNoFx = Get-ProjectCost -RemainingHours $zero -RemainingAiRub $zero -RemainingAiUsd $zero `
    -ConfirmedLaborRub 360000 -ConfirmedAiRub 0 -ConfirmedAiUsd 200
Assert-Equal $mixedNoFx.confirmed.aiUsd @(200) 'PRG-016 source USD preserved without FX'
if ($null -ne $mixedNoFx.forecast.totalRub -or $null -ne $mixedNoFx.forecast.totalUsd -or
    'exchangeRate' -cnotin $mixedNoFx.forecast.missingInputs) {
    throw 'Mixed confirmed cost without FX must remain unknown.'
}
Write-Output 'PASS: mixed confirmed RUB/USD totals and source USD preservation'
