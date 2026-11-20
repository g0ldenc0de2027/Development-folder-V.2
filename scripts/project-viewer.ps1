#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RegistryPath,
    [ValidateRange(1024, 65535)][int]$Port = 8765
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false, $true)

function Read-Field([string]$Card, [string]$Label) {
    $match = [regex]::Match($Card, '(?im)^[ \t]*(?:\*\*)?' + [regex]::Escape($Label) +
        '[ \t]*:(?:\*\*)?[ \t]*(?<value>[^\r\n]*)')
    $match.Groups['value'].Value.Trim().Trim('*')
}

function Assert-PlainPath([string]$Path, [bool]$Directory) {
    $cursor = Get-Item -LiteralPath $Path -Force
    if ($cursor.PSIsContainer -ne $Directory) { throw 'WRONG_PATH_TYPE' }
    while ($null -ne $cursor) {
        if ($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'REPARSE_POINT' }
        if ($cursor -is [IO.FileInfo]) { $cursor = $cursor.Directory }
        else { $cursor = $cursor.Parent }
    }
}

function Read-Card([IO.FileInfo]$File, [string]$Source) {
    Assert-PlainPath $File.FullName $false
    $bytes = [IO.File]::ReadAllBytes($File.FullName)
    $card = $utf8.GetString($bytes).TrimStart([char]0xFEFF)
    $title = [regex]::Match($card, '(?m)^# (.+)').Groups[1].Value.Trim()
    $head = Read-Field $card 'PR_HEAD_SHA'
    $base = Read-Field $card 'PR_BASE_SHA'
    $ciHead = Read-Field $card 'CI_HEAD_SHA'
    $ciBase = Read-Field $card 'CI_BASE_SHA'
    $sha = '^[0-9a-f]{40}$'
    $binding = 'unknown'
    if (($head -match $sha -and $ciHead -match $sha -and $head -ne $ciHead) -or
        ($base -match $sha -and $ciBase -match $sha -and $base -ne $ciBase)) {
        $binding = 'previous'
    } elseif ($head -match $sha -and $base -match $sha -and $head -eq $ciHead -and $base -eq $ciBase) {
        $binding = 'matches'
    }
    $links = @([regex]::Matches($card, 'https://github\.com/[\w.-]+/[\w.-]+/(?:pull/[0-9]+|actions/runs/[0-9]+(?:/job/[0-9]+)?)(?![\w/?#-])') |
        ForEach-Object Value | Select-Object -Unique)
    $status = Read-Field $card 'Статус'
    $assignee = Read-Field $card 'Исполнитель'
    if (!$assignee) {
        $assignee = [regex]::Match($card, '(?im)\bИсполнитель(?: и координатор)?:[ \t]*([^.\r\n·]+)').Groups[1].Value.Trim()
    }
    @{
        hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
        title = $title
        status = [regex]::Match($status, '^[a-zA-Z][a-zA-Z0-9_-]*(?=[\s.;·]|$)').Value
        assignee = $assignee
        blocker = Read-Field $card 'Блокер'
        nextAction = Read-Field $card 'Следующее действие'
        needsDecision = (Read-Field $card 'Решение владельца') -eq 'ожидается'
        source = $Source
        links = $links
        binding = $binding
        text = $card
    }
}

function Update-Projects {
    foreach ($project in $projects) {
        foreach ($source in $project.sources) {
            $source.error = $null
            try {
                $folder = Join-Path $source.path 'tasks'
                Assert-PlainPath $folder $true
                $files = @(Get-ChildItem -LiteralPath $folder -File -Filter 'T-*.md')
            } catch {
                $source.error = 'Папка задач недоступна'
                continue
            }
            $cards = @{}
            foreach ($file in $files) {
                if ($file.Name -cnotmatch '^(T-[0-9]{3,})(?:-[^.]+)?\.md$') { continue }
                $id = $Matches[1]
                try {
                    $cards[$file.Name] = @{ id = $id; version = Read-Card $file (Join-Path $source.path "tasks/$($file.Name)"); stale = $false }
                } catch {
                    $source.error = 'Некоторые карточки недоступны'
                    if ($source.cards.ContainsKey($file.Name)) {
                        $cards[$file.Name] = $source.cards[$file.Name]
                        $cards[$file.Name].stale = $true
                    } else {
                        $cards[$file.Name] = @{ id = $id; version = $null; stale = $true }
                    }
                }
            }
            $source.cards = $cards
            if (!$source.error) { $source.updated = [DateTimeOffset]::Now.ToString('o') }
        }
    }
}

function Get-Summary {
    foreach ($project in $projects) {
        $tasks = @{}
        foreach ($source in $project.sources) {
            foreach ($name in $source.cards.Keys) {
                $record = $source.cards[$name]
                if (!$tasks.ContainsKey($record.id)) {
                    $tasks[$record.id] = @{ id = $record.id; versions = @{}; unreadable = @() }
                }
                $task = $tasks[$record.id]
                if ($null -eq $record.version) {
                    $task.unreadable += Join-Path $source.path "tasks/$name"
                    continue
                }
                $version = $record.version
                if (!$task.versions.ContainsKey($version.hash)) {
                    $view = $version.Clone()
                    $view.Remove('text')
                    $view.Remove('source')
                    $view.sources = @()
                    $task.versions[$version.hash] = $view
                }
                $task.versions[$version.hash].sources += @{
                    path = $version.source
                    stale = $record.stale -or $source.error -eq 'Папка задач недоступна'
                }
            }
        }
        @{
            id = $project.id
            name = $project.name
            sources = @($project.sources | ForEach-Object { @{ path = $_.path; error = $_.error; updated = $_.updated } })
            tasks = @($tasks.Values | Sort-Object { $_.id.Length }, id | ForEach-Object {
                @{ id = $_.id; unreadable = $_.unreadable; versions = @($_.versions.Values | Sort-Object hash) }
            })
        }
    }
}

$registryFile = Get-Item -LiteralPath $RegistryPath
$registry = [IO.File]::ReadAllText($registryFile.FullName, $utf8) | ConvertFrom-Json -AsHashtable
$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$projects = @(foreach ($entry in $registry.projects) {
    if ($entry.id -isnot [string] -or $entry.id -cnotmatch '^[a-z0-9][a-z0-9-]{0,63}$' -or
        !$ids.Add($entry.id) -or $entry.name -isnot [string] -or !$entry.name.Trim() -or
        $entry.roots -isnot [array] -or !$entry.roots.Count) { throw 'INVALID_PROJECT_REGISTRY' }
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    @{
        id = $entry.id
        name = $entry.name
        sources = @(foreach ($root in $entry.roots) {
            if ($root -isnot [string] -or !$root.Trim()) { throw 'INVALID_PROJECT_ROOT' }
            $path = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($root, $registryFile.DirectoryName))
            if ($paths.Add($path)) { @{ path = $path; cards = @{}; error = $null; updated = $null } }
        })
    }
})
if (!$projects.Count) { throw 'EMPTY_PROJECT_REGISTRY' }

$page = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'project-viewer.html'), $utf8)
$origin = "http://127.0.0.1:$Port"
$key = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
$prefix = "/$key/"
$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("$origin/")
try {
    Update-Projects
    $listener.Start()
    Write-Output "$origin$prefix"
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        try {
            $response.Headers['Cache-Control'] = 'no-store'
            $response.Headers['X-Content-Type-Options'] = 'nosniff'
            $response.Headers['Referrer-Policy'] = 'no-referrer'
            $response.Headers['Content-Security-Policy'] = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
            $path = $request.Url.AbsolutePath
            $method = $request.HttpMethod
            if ($request.UserHostName -cne "127.0.0.1:$Port" -or !$path.StartsWith($prefix, [StringComparison]::Ordinal)) {
                $response.StatusCode = 404
                continue
            }
            $route = $path.Substring($prefix.Length)
            $response.ContentType = 'application/json; charset=utf-8'
            if ($method -eq 'GET' -and !$route) {
                $response.ContentType = 'text/html; charset=utf-8'
                $body = $page
            } elseif (($method -eq 'GET' -and $route -eq 'summary') -or
                ($method -eq 'POST' -and $route -eq 'refresh' -and $request.Headers['Origin'] -ceq $origin)) {
                if ($method -eq 'POST') { Update-Projects }
                $body = ConvertTo-Json -InputObject @(Get-Summary) -Depth 10 -Compress
            } elseif ($method -eq 'GET' -and $route -eq 'card') {
                $project = $projects | Where-Object { $_.id -ceq $request.QueryString['project'] }
                if ($null -eq $project) { $response.StatusCode = 404; continue }
                $record = foreach ($source in $project.sources) {
                    $source.cards.Values | Where-Object {
                        $_.id -ceq $request.QueryString['task'] -and $null -ne $_.version -and
                            $_.version.hash -ceq $request.QueryString['version']
                    }
                }
                $first = @($record | Select-Object -First 1)
                if (!$first.Count) { $response.StatusCode = 404; continue }
                $body = @{ text = $first[0].version.text } | ConvertTo-Json -Compress
            } else { $response.StatusCode = 404; continue }
            $bytes = $utf8.GetBytes($body)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } catch {
            if ($response.OutputStream.CanWrite) { $response.StatusCode = 500 }
        } finally {
            $response.Close()
        }
    }
} finally {
    $listener.Close()
}
