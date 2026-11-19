# Enumerate source files without descending into workspace caches.
function Get-ProjectFiles([string]$Root) {
    $tracked = @(& git -C $Root ls-files -- ':(icase,glob)**/.vs/**')
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect tracked IDE cache paths' }
    if ($tracked.Count -gt 0) { throw 'Tracked .vs cache files are not permitted' }
    $directories = [Collections.Generic.Stack[string]]::new()
    $directories.Push($Root)
    while ($directories.Count -gt 0) {
        $dir = $directories.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $dir -Force) {
            if ($item.PSIsContainer) {
                if ($item.Name -iin @('.git','.worktrees','.work','.manus','temp','.vs')) { continue }
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                $directories.Push($item.FullName)
            } else { $item }
        }
    }
}
