# Accept only the Windows ProjFS directory tag. Unknown tags and failed queries stay excluded.
function Test-ProjectedDirectory([string]$Path) {
    if (-not $IsWindows) { return $false }
    if (-not ('V2.ProjectedDirectory' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace V2 {
    public static class ProjectedDirectory {
        [StructLayout(LayoutKind.Sequential)]
        private struct TagInfo {
            public uint Attributes;
            public uint ReparseTag;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFile(
            string path, uint access, uint share, IntPtr security,
            uint creation, uint flags, IntPtr template);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool GetFileInformationByHandleEx(
            SafeFileHandle handle, int infoClass, out TagInfo info, uint size);

        public static bool IsProjected(string path) {
            const uint OpenExisting = 3;
            const uint OpenDirectoryWithoutFollowingLink = 0x02200000;
            const int FileAttributeTagInfo = 9;
            const uint DirectoryReparseAttributes = 0x410;
            const uint ProjFsTag = 0x9000001c;
            using (var handle = CreateFile(path, 0, 7, IntPtr.Zero, OpenExisting,
                                          OpenDirectoryWithoutFollowingLink, IntPtr.Zero)) {
                return !handle.IsInvalid &&
                    GetFileInformationByHandleEx(handle, FileAttributeTagInfo, out var info, 8) &&
                    (info.Attributes & DirectoryReparseAttributes) == DirectoryReparseAttributes &&
                    info.ReparseTag == ProjFsTag;
            }
        }
    }
}
"@
    }
    return [V2.ProjectedDirectory]::IsProjected($Path)
}

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
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -and
                    -not (Test-ProjectedDirectory $item.FullName)) { continue }
                $directories.Push($item.FullName)
            } elseif (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                $item
            }
        }
    }
}

function Get-ProjectPowerShellFiles([string]$Root) {
    Get-ProjectFiles $Root | Where-Object { $_.Extension -iin @('.ps1', '.psm1', '.psd1') }
}
