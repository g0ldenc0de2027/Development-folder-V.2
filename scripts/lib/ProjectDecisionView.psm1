Set-StrictMode -Version Latest

function Get-ProjectDecisionView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Snapshot,
        [Parameter(Mandatory)][Collections.IDictionary]$TaskByItem,
        [Parameter(Mandatory)][DateTimeOffset]$AsOf,
        [object[]]$ActiveItems = @()
    )
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $history = [Collections.Generic.List[object]]::new()
    $unmapped = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $activeCriteria = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    $latest = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($item in $ActiveItems) { $activeCriteria.Add($item['id'],$item['criteriaVersion']) }
    foreach ($decision in $Snapshot.document.events) {
        $item = $decision['itemId']
        $instant = [DateTimeOffset]::Parse($decision['at'],[Globalization.CultureInfo]::InvariantCulture)
        $task = $TaskByItem[$item]
        if ($task -isnot [string] -or $task -cnotmatch '\AT-[0-9]{3,}\z') {
            $null = $unmapped.Add($item)
            continue
        }
        $history.Add([pscustomobject]@{
            ProjectId = $decision['projectId']
            SourceId = 'owner-decision'
            EventId = $decision['eventId']
            TaskId = $task
            ItemId = $item
            Type = $decision['type']
            At = $instant.ToUniversalTime()
        })
        if ($instant -gt $AsOf) { continue }
        if (!$activeCriteria.ContainsKey($item) -or $activeCriteria[$item] -cne $decision['criteriaVersion']) { continue }
        if ($latest.ContainsKey($item) -and $latest[$item].decidedAt -gt $instant) { continue }
        $latest[$item] = @{
            itemId = $item
            taskId = $task
            eventId = $decision['eventId']
            status = if ($decision['type'] -ceq 'accepted') { 'accepted' } else { 'revoked' }
            decidedAt = $instant
            evidenceId = $decision['evidenceId']
        }
    }
    @{
        revision = $Snapshot.sha256
        decisions = $Snapshot.document.events
        coverage = $Snapshot.document.coverage
        eventHistory = $history.ToArray()
        acceptanceByItem = $latest
        unmappedItems = @($unmapped | Sort-Object -CaseSensitive)
    }
}

Export-ModuleMember -Function Get-ProjectDecisionView
