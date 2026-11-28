#Requires -Version 7.6
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$parent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$root = Join-Path $parent ('project-fx-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$process = $null
try {
    $module = Import-Module (Join-Path $PSScriptRoot '../scripts/lib/ProjectCbrFx.psm1') -PassThru
    $typeFixture = Join-Path $root 'cache-types.json'
    $today = [DateOnly]::FromDateTime([DateTime]::UtcNow)
    $sample = '{"schemaVersion":VERSION,"source":"cbr","ratePerUsd":RATE,"effectiveDate":"2026-01-01","fetchedAtUtc":"2026-01-01T00:00:00.0000000+00:00"}'
    foreach ($version in 'true', '"1"', '1.0', '[1]') {
        [IO.File]::WriteAllText($typeFixture, $sample.Replace('VERSION', $version).Replace('RATE', '80'))
        if ($null -ne (& $module { param($Path, $Today) Read-CbrCache $Path $Today } $typeFixture $today)) {
            throw "T-154 cache accepted schemaVersion $version"
        }
    }
    foreach ($rate in 'true', '"80"', '[80]', 'null', '0', '-1') {
        [IO.File]::WriteAllText($typeFixture, $sample.Replace('VERSION', '1').Replace('RATE', $rate))
        if ($null -ne (& $module { param($Path, $Today) Read-CbrCache $Path $Today } $typeFixture $today)) {
            throw "T-154 cache accepted ratePerUsd $rate"
        }
    }
    [IO.File]::WriteAllText($typeFixture, $sample.Replace('VERSION', '1').Replace('RATE', '80.25'))
    $typedCache = & $module { param($Path, $Today) Read-CbrCache $Path $Today } $typeFixture $today
    if ($typedCache.ratePerUsd -ne [decimal]80.25) { throw 'T-154 cache rejected a decimal rate' }

    $server = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $server.Start()
    $address = "http://127.0.0.1:$($server.LocalEndpoint.Port)/"
    $date = [DateTimeOffset]::UtcNow.ToOffset([TimeSpan]::FromHours(3)).ToString('dd.MM.yyyy', [Globalization.CultureInfo]::InvariantCulture)
    $publisher = [PowerShell]::Create()
    $null = $publisher.AddScript({
        param($Listener, $Date)
        foreach ($slow in @($false, $true)) {
            $socket = $Listener.AcceptTcpClient()
            try {
                $stream = $socket.GetStream()
                $buffer = [byte[]]::new(2048)
                $null = $stream.Read($buffer, 0, $buffer.Length)
                $xml = "<ValCurs Date='$Date'><Valute><CharCode>USD</CharCode><Nominal>10</Nominal><Value>800,0000</Value></Valute></ValCurs>"
                $body = [Text.Encoding]::ASCII.GetBytes($xml)
                $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n")
                $stream.Write($header, 0, $header.Length)
                $stream.Write($body, 0, $(if ($slow) { 1 } else { $body.Length }))
                $stream.Flush()
                if ($slow) { Start-Sleep -Seconds 4 }
            } finally { $socket.Dispose() }
        }
    }).AddArgument($server).AddArgument($date)
    try {
        $publish = $publisher.BeginInvoke()
        & $module { param($Address) $script:CbrEndpoint = $Address } $address
        $cache = Join-Path $root 'actual-provider-cache.json'
        $first = Update-CbrUsdRateSnapshot -Path $cache -CancellationToken ([Threading.CancellationToken]::None)
        if ($first.state -cne 'current' -or $first.snapshot.ratePerUsd -ne 80) { throw 'PRG-014 valid provider response did not populate cache' }
        $hash = (Get-FileHash -LiteralPath $cache).Hash
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $bodyTimedOut = $false
        try {
            $null = & $module { param($Address) Get-CbrResponse ([uri]$Address) ([Threading.CancellationToken]::None) 750 } $address
        } catch {
            $exception = $_.Exception
            while ($exception) {
                if ($exception -is [OperationCanceledException]) { $bodyTimedOut = $true; break }
                $exception = $exception.InnerException
            }
        }
        if (!$bodyTimedOut -or $watch.Elapsed.TotalSeconds -gt 3) { throw 'PRG-014 deadline did not cover body' }
        $cancelled = [Threading.CancellationToken]::new($true)
        $stale = Update-CbrUsdRateSnapshot -Path $cache -CancellationToken $cancelled
        $empty = Update-CbrUsdRateSnapshot -Path (Join-Path $root 'absent-cache.json') -CancellationToken $cancelled
        if ($stale.state -cne 'stale' -or $stale.snapshot.ratePerUsd -ne 80 -or
            $empty.state -cne 'unavailable' -or (Get-FileHash -LiteralPath $cache).Hash -cne $hash) {
            throw 'PRG-014 provider altered cache after cancellation'
        }
        'PASS: PRG-014 real transport limits body time and preserves last validated cache'
    } finally {
        $server.Stop()
        $publisher.Stop()
        $publisher.Dispose()
    }
    $scripts = Join-Path $root 'scripts'
    $lib = Join-Path $scripts 'lib'
    [void][IO.Directory]::CreateDirectory($lib)
    [void][IO.Directory]::CreateDirectory((Join-Path $root 'project/tasks'))
    $source = Join-Path $PSScriptRoot '../scripts'
    foreach ($name in 'project-viewer.ps1', 'project-viewer.html') {
        [IO.File]::Copy((Join-Path $source $name), (Join-Path $scripts $name))
    }
    foreach ($name in 'ProjectPeriod', 'ProjectProgress', 'ProjectRemainingWork', 'ProjectForecast', 'ProjectCost') {
        [IO.File]::Copy((Join-Path $source "lib/$name.psm1"), (Join-Path $lib "$name.psm1"))
    }
    $fixture = @"
function Update-CbrUsdRateSnapshot {
    param([string]`$Path, [Threading.CancellationToken]`$CancellationToken)
    while (![IO.File]::Exists("`$Path.ready")) {
        if (`$CancellationToken.WaitHandle.WaitOne(20)) { return @{state='unavailable'} }
    }
    @{state='current'; snapshot=@{ratePerUsd=[decimal]80;effectiveDate='2026-11-27'}}
}
"@
    [IO.File]::WriteAllText((Join-Path $lib 'ProjectCbrFx.psm1'), $fixture)
    $registry = Join-Path $root 'registry.json'
    $cost = @{
        schemaVersion=1; asOf='2026-11-27'; scopeVersion='v1'; exchangeRateMode='cbr'
        planHours=@(50,50,50); planAiRub=@(5000,5000,5000); planAiUsd=@(0,0,0); planRubPerUsd=100
        remainingHours=@(50,50,50); remainingAiRub=@(5000,5000,5000); remainingAiUsd=@(0,0,0)
        confirmedLaborRub=0; confirmedAiRub=0; confirmedAiUsd=0
    }
    $manual = $cost.Clone()
    $manual.rubPerUsd = 125
    $config = @{projects=@(
        @{id='automatic';name='Automatic';roots=@('project');cost=$cost}
        @{id='manual';name='Manual';roots=@('project');cost=$manual}
    )}
    [IO.File]::WriteAllText($registry, ($config | ConvertTo-Json -Depth 8))
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = $probe.LocalEndpoint.Port
    $probe.Stop()
    $info = [Diagnostics.ProcessStartInfo]::new((Get-Process -Id $PID).Path)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($arg in @('-NoLogo','-NoProfile','-File',(Join-Path $scripts 'project-viewer.ps1'),'-RegistryPath',$registry,'-Port',"$port")) {
        $info.ArgumentList.Add($arg)
    }
    $process = [Diagnostics.Process]::Start($info)
    $read = $process.StandardOutput.ReadLineAsync()
    if (!$read.Wait(15000) -or !$read.Result) { throw 'FX test viewer startup failed' }
    $url = $read.Result
    $projects = Invoke-RestMethod ($url + 'summary') -TimeoutSec 4
    $auto = $projects | Where-Object id -CEQ 'automatic'
    if ($auto.cost.exchange.forecast.state -cne 'unavailable' -or $auto.cost.values.forecast.totalRub[1] -ne 80000 -or
        $null -ne $auto.cost.values.forecast.totalUsd) { throw 'PRG-014 expected native amount during slow fetch' }
    'PASS: PRG-014 requests remain available while FX is pending'
    [IO.File]::WriteAllText("$registry.usd-rub.json.ready", '')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $projects = Invoke-RestMethod ($url + 'summary') -TimeoutSec 4
        $auto = $projects | Where-Object id -CEQ 'automatic'
        if ($auto.cost.exchange.forecast.state -ceq 'current') { break }
        Start-Sleep -Milliseconds 50
    } while ($clock.Elapsed.TotalSeconds -lt 5)
    $fixed = $projects | Where-Object id -CEQ 'manual'
    if ($auto.cost.exchange.forecast.state -cne 'current' -or $auto.cost.values.forecast.totalUsd[1] -ne 1000 -or
        $auto.cost.values.plan.totalUsd[1] -ne 800 -or $fixed.cost.values.forecast.totalUsd[1] -ne 640 -or
        $fixed.cost.exchange.forecast.source -cne 'manual') { throw 'PRG-014 invalid FX projection after recovery' }
    'PASS: PRG-014 automatic forecast recovers while plan and manual quote stay pinned'
} finally {
    if ($process) {
        if (!$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
    if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($root)) -cne [IO.Path]::TrimEndingDirectorySeparator($parent)) {
        throw 'Unexpected fixture location'
    }
    [IO.Directory]::Delete($root, $true)
}
