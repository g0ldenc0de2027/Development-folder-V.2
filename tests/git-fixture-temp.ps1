function Assert-GitFixtureTempRoot([string]$Root) {
    for ($directory = [IO.DirectoryInfo]::new($Root); $null -ne $directory; $directory = $directory.Parent) {
        $item = Get-Item -LiteralPath $directory.FullName -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Git fixture TempRoot must be an existing directory without reparse points: $Root"
        }
        $path = $directory.FullName
        if ((Test-Path -LiteralPath (Join-Path $path '.git')) -or
            ((Test-Path -LiteralPath (Join-Path $path 'HEAD') -PathType Leaf) -and
             (Test-Path -LiteralPath (Join-Path $path 'config') -PathType Leaf) -and
             (Test-Path -LiteralPath (Join-Path $path 'objects') -PathType Container) -and
             (Test-Path -LiteralPath (Join-Path $path 'refs') -PathType Container))) {
            throw "Git fixture TempRoot must be outside every Git repository: $Root"
        }
    }

    $savedGitEnvironment = @{}
    $savedLocale = $env:LC_ALL
    foreach ($name in @(Get-ChildItem Env: | Where-Object Name -like 'GIT_*' | ForEach-Object Name)) {
        $savedGitEnvironment[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
        Remove-Item -LiteralPath "Env:$name"
    }
    try {
        $env:GIT_CONFIG_NOSYSTEM = '1'
        $env:GIT_CONFIG_GLOBAL = Join-Path $PSScriptRoot '../config/git-empty.config'
        $env:LC_ALL = 'C'
        $discovery = @(& git --no-optional-locks -C $Root rev-parse --git-dir 2>&1)
        $discoveryExit = $LASTEXITCODE
        if ($discoveryExit -eq 0) {
            throw "Git fixture TempRoot must be outside every Git repository: $Root"
        }
        if ($discoveryExit -ne 128 -or ($discovery -join ' ') -notmatch '^fatal: not a git repository(?:\s|$)') {
            throw "Git fixture TempRoot could not be verified by Git: $Root"
        }
    } finally {
        Remove-Item Env:GIT_CONFIG_NOSYSTEM,Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue
        $env:LC_ALL = $savedLocale
        foreach ($name in $savedGitEnvironment.Keys) {
            [Environment]::SetEnvironmentVariable($name,$savedGitEnvironment[$name],'Process')
        }
    }
}

function New-GitFixtureTempDirectory([string]$Path) {
    $root = [IO.Path]::GetDirectoryName($Path)
    Assert-GitFixtureTempRoot $root
    $name = [IO.Path]::GetFileName($Path)
    New-Item -ItemType Directory -Path ([WildcardPattern]::Escape($root)) -Name $name -ErrorAction Stop | Out-Null
    try {
        [IO.File]::WriteAllText((Join-Path $Path '.fixture-owner'),$name)
    } catch {
        $markFailure = $_
        try {
            Assert-GitFixtureTempRoot $Path
            [IO.Directory]::Delete($Path, $false)
        } catch {
            throw "Could not mark the new Git fixture directory: $Path. $($markFailure.Exception.Message) Cleanup failed: $($_.Exception.Message)"
        }
        throw "Could not mark the new Git fixture directory: $Path. $($markFailure.Exception.Message)"
    }
}

function Remove-GitFixtureTempDirectory([string]$Path) {
    try {
        Assert-GitFixtureTempRoot $Path
        $marker = Get-Item -LiteralPath (Join-Path $Path '.fixture-owner') -Force -ErrorAction Stop
        $name = [IO.Path]::GetFileName($Path)
        if ($marker.PSIsContainer -or ($marker.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            [IO.File]::ReadAllText($marker.FullName) -cne $name) {
            throw 'Fixture ownership could not be verified'
        }
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        if (Test-Path -LiteralPath $Path -ErrorAction Stop) { throw 'Fixture directory still exists' }
    } catch {
        throw "Could not clean up the Git fixture directory: $Path. $($_.Exception.Message)"
    }
}
