#Requires -Version 7.6
[CmdletBinding()]
param(
    [ValidateSet('auto', 'developer', 'ci')]
    [string]$Mode = 'auto',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$version = $PSVersionTable.PSVersion
if ($version.Major -ne 7 -or $version.Minor -ne 6 -or $version -lt [version]'7.6.6') {
    throw "PowerShell 7.6.6 or newer in the 7.6 LTS line is required; found $version. Install the latest 7.6 servicing update."
}

$runtime = [System.Runtime.InteropServices.RuntimeInformation]
if (-not $runtime::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)) {
    throw 'The Development Folder V2 runtime is supported on Windows only.'
}
if ($runtime::OSArchitecture -ne [System.Runtime.InteropServices.Architecture]::X64) {
    throw 'The Development Folder V2 runtime requires x64 architecture.'
}

if ($Mode -eq 'auto') {
    if ($env:GITHUB_ACTIONS -eq 'true') {
        $Mode = 'ci'
    } else {
        $Mode = 'developer'
    }
}

$build = [Environment]::OSVersion.Version.Build
$productOptions = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name ProductType -ErrorAction Stop
$productType = [string]$productOptions.ProductType
switch ($Mode) {
    'developer' {
        if ($productType -ne 'WinNT' -or $build -lt 26200) {
            throw "Developer host must be Windows 11 x64 build 26200 or newer in an actively supported edition; found ProductType=$productType build=$build."
        }
    }
    'ci' {
        if ($env:GITHUB_ACTIONS -ne 'true' -or $productType -notin @('ServerNT', 'LanmanNT') -or $build -lt 26100) {
            throw "CI runtime must be GitHub Actions on Windows Server 2025 x64 (build 26100 or newer); found ProductType=$productType build=$build."
        }
    }
}

if (-not $Quiet) {
    Write-Output ("PASS: runtime mode={0}; PowerShell={1}; Windows build={2}; architecture={3}" -f $Mode, $version, $build, $runtime::OSArchitecture)
}
