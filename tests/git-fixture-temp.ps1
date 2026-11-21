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
}

function New-GitFixtureTempDirectory([string]$Path) {
    $root = [IO.Path]::GetDirectoryName($Path)
    Assert-GitFixtureTempRoot $root
    $name = [IO.Path]::GetFileName($Path)
    New-Item -ItemType Directory -Path $root -Name $name -ErrorAction Stop | Out-Null
    try {
        [IO.File]::WriteAllText((Join-Path $Path '.fixture-owner'),$name)
    } catch {
        throw "Could not mark the new Git fixture directory for cleanup: $Path. $($_.Exception.Message)"
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
