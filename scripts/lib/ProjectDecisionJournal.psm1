Set-StrictMode -Version Latest
Import-Module (Join-Path $PSScriptRoot 'ProjectProgress.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProjectPeriod.psm1')

function Get-DecisionJournalInstant($Value) {
    $instant = [DateTimeOffset]::MinValue
    if ($Value -isnot [string] -or $Value -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})\z' -or
        ![DateTimeOffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None, [ref]$instant)) { throw 'DECISION_JOURNAL_INVALID_TIMESTAMP' }
    $instant
}

function Read-ProjectDecisionJournal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ProjectId,
        [object[]]$Baselines = @()
    )

    $file = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'DECISION_JOURNAL_INVALID_FILE'
    }
    # Разрешаем атомарную замену имени, пока запрос дочитывает открытый снимок.
    $share = [IO.FileShare]::Read -bor [IO.FileShare]::Delete
    $stream = [IO.File]::Open($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try {
        if ($stream.Length -gt 4MB) { throw 'DECISION_JOURNAL_TOO_LARGE' }
        $bytes = [byte[]]::new([int]$stream.Length)
        $stream.ReadExactly($bytes)
    } finally {
        $stream.Dispose()
    }

    $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($json.StartsWith([char]0xFEFF)) { $json = $json.Substring(1) }
    $options = [Text.Json.JsonDocumentOptions]::new()
    $options.AllowDuplicateProperties = $false
    [Text.Json.JsonDocument]::Parse($json, $options).Dispose()
    $data = ConvertFrom-Json -InputObject $json -AsHashtable -DateKind String -ErrorAction Stop
    if ($data -isnot [Collections.IDictionary] -or
        ($data['schemaVersion'] -isnot [long] -and $data['schemaVersion'] -isnot [int]) -or
        $data['schemaVersion'] -ne 1 -or $data['projectId'] -isnot [string] -or
        $data['projectId'] -cne $ProjectId -or $data['events'] -isnot [array] -or $data['coverage'] -isnot [array]) {
        throw 'DECISION_JOURNAL_INVALID_DOCUMENT'
    }

    $null = Get-ProjectProgress -ProjectId $ProjectId -AsOf ([DateTimeOffset]::MaxValue) -Baselines $Baselines -Decisions $data['events']
    foreach ($interval in $data['coverage']) {
        if ($interval -isnot [Collections.IDictionary] -or $interval['type'] -isnot [string] -or
            $interval['type'] -cnotin @('accepted', 'acceptance_revoked') -or
            (Get-DecisionJournalInstant $interval['from']) -ge (Get-DecisionJournalInstant $interval['until'])) {
            throw 'DECISION_JOURNAL_INVALID_COVERAGE'
        }
    }

    @{
        document = $data
        sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    }
}

function Get-ProjectJournalProgress {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Collections.IDictionary]$Snapshot,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][DateTimeOffset]$AsOf,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Baselines
    )

    $data = $Snapshot.document
    if ($data['projectId'] -cne $ProjectId) { throw 'DECISION_JOURNAL_INVALID_DOCUMENT' }
    $progress = Get-ProjectProgress -ProjectId $ProjectId -AsOf $AsOf -Baselines $Baselines -Decisions $data['events']
    if ($progress.state -cne 'available') { return $progress }

    # Включительный срез требует покрытия до следующего тика полуоткрытого интервала.
    if ($AsOf -eq [DateTimeOffset]::MaxValue) { throw 'DECISION_JOURNAL_INVALID_TIMESTAMP' }
    $window = @{
        StartUtc = (Get-DecisionJournalInstant $Baselines[0]['approvedAt']).ToUniversalTime()
        EndUtc = $AsOf.ToUniversalTime().AddTicks(1)
    }
    $types = 'accepted', 'acceptance_revoked'
    $coverage = Get-ProjectHistoryCoverage -Period $window -Coverage $data['coverage'] -Types $types
    if (!$coverage.accepted.complete) {
        return @{ state = 'incomplete'; projectId = $ProjectId; asOf = $AsOf; gaps = $coverage.accepted.gaps }
    }
    $progress
}

Export-ModuleMember -Function Read-ProjectDecisionJournal, Get-ProjectJournalProgress
