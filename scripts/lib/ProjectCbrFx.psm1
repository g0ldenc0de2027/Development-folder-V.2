Set-StrictMode -Version Latest

$script:Invariant = [Globalization.CultureInfo]::InvariantCulture
$script:Moscow = [TimeZoneInfo]::FindSystemTimeZoneById('Russian Standard Time')
$script:CbrEndpoint = 'https://www.cbr.ru/scripts/XML_daily.asp'

function Get-CbrResponse([uri]$Uri, [Threading.CancellationToken]$CancellationToken, [int]$TimeoutMs = 8000) {
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $client = [Net.Http.HttpClient]::new($handler)
    $deadline = [Threading.CancellationTokenSource]::CreateLinkedTokenSource($CancellationToken)
    $deadline.CancelAfter($TimeoutMs)
    try {
        $response = $client.GetAsync($Uri, [Net.Http.HttpCompletionOption]::ResponseHeadersRead, $deadline.Token).GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -ne 200 -or $response.Content.Headers.ContentLength -gt 64KB) { throw 'CBR_FX_RESPONSE_REJECTED' }
            $stream = $response.Content.ReadAsStream($deadline.Token)
            $buffer = [byte[]]::new(64KB + 1)
            $length = 0
            while ($length -lt $buffer.Length) {
                $count = $stream.ReadAsync($buffer, $length, $buffer.Length - $length, $deadline.Token).GetAwaiter().GetResult()
                if (!$count) { break }
                $length += $count
            }
            if ($length -gt 64KB) { throw 'CBR_FX_RESPONSE_TOO_LARGE' }
            if (!$length) { throw 'CBR_FX_EMPTY_RESPONSE' }
            return ,([byte[]]$buffer[0..($length - 1)])
        } finally { $response.Dispose() }
    } finally {
        $deadline.Dispose()
        $client.Dispose()
    }
}

function ConvertFrom-CbrResponse([byte[]]$Bytes, [DateOnly]$RequestedDate) {
    [Text.Encoding]::RegisterProvider([Text.CodePagesEncodingProvider]::Instance)
    $settings = [Xml.XmlReaderSettings]::new()
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.MaxCharactersInDocument = 64KB
    $stream = [IO.MemoryStream]::new($Bytes, $false)
    try {
        $reader = [Xml.XmlReader]::Create($stream, $settings)
        try {
            $document = [Xml.XmlDocument]::new()
            $document.XmlResolver = $null
            $document.Load($reader)
        } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    $root = $document.SelectSingleNode('/ValCurs')
    if (!$root) { throw 'CBR_FX_INVALID_XML' }
    $effective = [DateOnly]::ParseExact($root.GetAttribute('Date'), 'dd.MM.yyyy', $script:Invariant)
    $usd = $root.SelectNodes("Valute[CharCode='USD']")
    if ($effective -gt $RequestedDate -or $usd.Count -ne 1) { throw 'CBR_FX_INVALID_QUOTE' }
    $nominal = [int]::Parse($usd[0].SelectSingleNode('Nominal').InnerText, [Globalization.NumberStyles]::None, $script:Invariant)
    $value = [decimal]::Parse($usd[0].SelectSingleNode('Value').InnerText.Replace(',', '.'),
        [Globalization.NumberStyles]::AllowDecimalPoint, $script:Invariant)
    if ($nominal -le 0 -or $value -le 0) { throw 'CBR_FX_INVALID_QUOTE' }
    @{
        schemaVersion = 1; source = 'cbr'; ratePerUsd = $value / $nominal
        effectiveDate = $effective.ToString('yyyy-MM-dd', $script:Invariant)
        fetchedAtUtc = [DateTimeOffset]::UtcNow.ToString('o', $script:Invariant)
    }
}

function Read-CbrCache([string]$Path, [DateOnly]$Today) {
    if (![IO.File]::Exists($Path)) { return $null }
    try {
        $file = Get-Item -LiteralPath $Path -Force
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 4KB) { return $null }
        $data = [IO.File]::ReadAllText($Path) | ConvertFrom-Json -AsHashtable -DateKind String
        if ($data.schemaVersion -ne 1 -or $data.source -cne 'cbr' -or $data.ratePerUsd -is [string] -or $data.ratePerUsd -le 0) { return $null }
        $date = [DateOnly]::ParseExact($data.effectiveDate, 'yyyy-MM-dd', $script:Invariant)
        $instant = [DateTimeOffset]::ParseExact($data.fetchedAtUtc, 'o', $script:Invariant)
        if ($date -gt $Today -or $instant -gt [DateTimeOffset]::UtcNow) { return $null }
        $data.ratePerUsd = [decimal]$data.ratePerUsd
        $data
    } catch { return $null }
}

function Update-CbrUsdRateSnapshot {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path, [Threading.CancellationToken]$CancellationToken)

    $today = [DateOnly]::FromDateTime([TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $script:Moscow).DateTime)
    $previous = Read-CbrCache $Path $today
    try {
        $uri = [uri]($script:CbrEndpoint + '?date_req=' + $today.ToString('dd/MM/yyyy', $script:Invariant))
        $rate = ConvertFrom-CbrResponse (Get-CbrResponse $uri $CancellationToken) $today
        $CancellationToken.ThrowIfCancellationRequested()
        $identity = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData(
            [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Path).ToUpperInvariant())))
        $mutex = [Threading.Mutex]::new($false, "Local\v2-usd-rub-$identity")
        $held = $false
        try {
            try { $held = $mutex.WaitOne(1000) } catch [Threading.AbandonedMutexException] { $held = $true }
            if (!$held) { throw 'CBR_FX_CACHE_BUSY' }
            $latest = Read-CbrCache $Path $today
            if ($latest -and $latest.effectiveDate -cgt $rate.effectiveDate) { $rate = $latest }
            else {
                $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
                if ($item -and ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint))) {
                    throw 'CBR_FX_CACHE_NOT_REGULAR'
                }
                $temporary = $Path + '.pending-' + [guid]::NewGuid().ToString('N')
                try {
                    [IO.File]::WriteAllText($temporary, ($rate | ConvertTo-Json -Compress) + [char]10)
                    [IO.File]::Move($temporary, $Path, $true)
                } finally { [IO.File]::Delete($temporary) }
            }
        } finally {
            if ($held) { $mutex.ReleaseMutex() }
            $mutex.Dispose()
        }
        @{ state = 'current'; snapshot = $rate }
    } catch {
        if ($previous) { @{ state = 'stale'; snapshot = $previous } }
        else { @{ state = 'unavailable' } }
    }
}

Export-ModuleMember -Function Update-CbrUsdRateSnapshot