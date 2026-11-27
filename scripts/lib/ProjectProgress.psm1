Set-StrictMode -Version Latest

function Get-ProgressInstant($Value) {
    $instant = [DateTimeOffset]::MinValue
    if ($Value -isnot [string] -or $Value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
        ![DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$instant)) {
        throw 'PROJECT_PROGRESS_INVALID_TIMESTAMP'
    }
    $instant
}

function Assert-ProgressId($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z') {
        throw 'PROJECT_PROGRESS_INVALID_ID'
    }
}

function Get-ProjectProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][DateTimeOffset]$AsOf,
        [object[]]$Baselines = @(),
        [object[]]$Decisions = @()
    )

    Assert-ProgressId $ProjectId
    $versions = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $active = $null
    $previous = $null
    foreach ($baseline in $Baselines) {
        if ($baseline -isnot [Collections.IDictionary] -or $baseline['projectId'] -cne $ProjectId -or
            $baseline['items'] -isnot [array]) { throw 'PROJECT_PROGRESS_INVALID_BASELINE' }
        $version = $baseline['version']
        Assert-ProgressId $version
        $at = Get-ProgressInstant $baseline['approvedAt']
        if ($versions.ContainsKey($version) -or
            ($previous -and ($at -le $previous.at -or $baseline['previousVersion'] -cne $previous.version)) -or
            (!$previous -and $null -ne $baseline['previousVersion'])) { throw 'PROJECT_PROGRESS_INVALID_BASELINE_CHAIN' }

        $items = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        foreach ($item in $baseline['items']) {
            if ($item -isnot [Collections.IDictionary]) { throw 'PROJECT_PROGRESS_INVALID_ITEM' }
            $id = $item['id']
            $criteria = $item['criteriaVersion']
            Assert-ProgressId $id
            Assert-ProgressId $criteria
            $weight = $item['weight']
            if (($weight -isnot [int] -and $weight -isnot [long] -and $weight -isnot [decimal] -and
                $weight -isnot [double]) -or $items.ContainsKey($id)) { throw 'PROJECT_PROGRESS_INVALID_WEIGHT' }
            try { $weight = [decimal]$weight } catch { throw 'PROJECT_PROGRESS_INVALID_WEIGHT' }
            if ($weight -le 0) { throw 'PROJECT_PROGRESS_INVALID_WEIGHT' }
            $items.Add($id, @{ weight = $weight; criteriaVersion = $criteria })
        }
        if ($previous) { $previous.until = $at }
        $previous = @{ version = $version; at = $at; until = $null; items = $items }
        $versions.Add($version, $previous)
        if ($at -le $AsOf) { $active = $previous }
    }

    $effective = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $times = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($decision in $Decisions) {
        if ($decision -isnot [Collections.IDictionary] -or $decision['projectId'] -cne $ProjectId -or
            $decision['type'] -cnotin @('accepted', 'acceptance_revoked') -or
            $decision['evidenceId'] -isnot [string] -or [string]::IsNullOrWhiteSpace($decision['evidenceId'])) {
            throw 'PROJECT_PROGRESS_INVALID_DECISION'
        }
        $eventId = $decision['eventId']
        $id = $decision['itemId']
        $version = $decision['scopeVersion']
        $criteria = $decision['criteriaVersion']
        Assert-ProgressId $eventId
        Assert-ProgressId $id
        Assert-ProgressId $version
        Assert-ProgressId $criteria
        $at = Get-ProgressInstant $decision['at']
        if (!$ids.Add($eventId) -or !$versions.ContainsKey($version) -or $at -lt $versions[$version].at -or
            ($versions[$version].until -and $at -ge $versions[$version].until) -or
            !$versions[$version].items.ContainsKey($id) -or
            $versions[$version].items[$id].criteriaVersion -cne $criteria) {
            throw 'PROJECT_PROGRESS_INVALID_DECISION'
        }
        # IDs may contain dots and hyphens but never the separator.
        $key = "$id/$criteria"
        if (!$times.Add("$key/$($at.UtcTicks)")) { throw 'PROJECT_PROGRESS_AMBIGUOUS_DECISION' }
        if ($at -gt $AsOf) { continue }
        if (!$effective.ContainsKey($key) -or $at -gt $effective[$key].at) {
            $effective[$key] = @{ at = $at; type = $decision['type'] }
        }
    }

    if (!$active -or !$active.items.Count) {
        return @{ state = 'not_assessed'; projectId = $ProjectId; asOf = $AsOf }
    }

    [decimal]$total = 0
    [decimal]$accepted = 0
    foreach ($id in $active.items.Keys) {
        $item = $active.items[$id]
        $total += $item.weight
        $key = "$id/$($item.criteriaVersion)"
        if ($effective.ContainsKey($key) -and $effective[$key].type -ceq 'accepted') { $accepted += $item.weight }
    }
    $percent = [Math]::Round(100 * ($accepted / $total), 1, [MidpointRounding]::AwayFromZero)
    if ($accepted -gt 0 -and $percent -eq 0) { $percent = [decimal]0.1 }
    if ($accepted -lt $total -and $percent -eq 100) { $percent = [decimal]99.9 }
    @{
        state = 'available'
        projectId = $ProjectId
        asOf = $AsOf
        scopeVersion = $active.version
        totalWeight = $total
        acceptedWeight = $accepted
        remainingWeight = $total - $accepted
        percent = $percent
    }
}

Export-ModuleMember -Function Get-ProjectProgress
