#Requires -Version 7.6
[CmdletBinding()]
param(
    [ValidateSet('auto', 'developer', 'ci')]
    [string]$Mode = 'auto',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$policyPath = Join-Path $repoRoot 'config/runtime-support.json'
$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
if ($policy.schemaVersion -ne 1) {
    throw 'Unsupported runtime support policy schema.'
}

$version = $PSVersionTable.PSVersion
$powerShellPolicy = $policy.powerShell
$minimumPowerShell = [version]$powerShellPolicy.minimumVersion
$preRelease = [string]$PSVersionTable['Prerelease']
if (
    $version.Major -ne [int]$powerShellPolicy.major -or
    $version.Minor -ne [int]$powerShellPolicy.minor -or
    $version -lt $minimumPowerShell -or
    $preRelease
) {
    throw "PowerShell $minimumPowerShell or newer stable servicing update in the $($powerShellPolicy.major).$($powerShellPolicy.minor) $($powerShellPolicy.channel) line is required; found $version."
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

$productOptions = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\ProductOptions' -Name ProductType -ErrorAction Stop
$productType = [string]$productOptions.ProductType
switch ($Mode) {
    'developer' {
        $osVersion = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name DisplayVersion, CurrentBuildNumber, UBR, BuildBranch, InstallationType -ErrorAction Stop
        $displayVersion = [string]$osVersion.DisplayVersion
        $build = [int]$osVersion.CurrentBuildNumber
        $updateBuildRevision = [int]$osVersion.UBR
        $buildBranch = [string]$osVersion.BuildBranch
        $installationType = [string]$osVersion.InstallationType
        $supportedRelease = @($policy.developerHost.supportedWindowsReleases | Where-Object {
            [string]$_.displayVersion -eq $displayVersion -and [int]$_.build -eq $build
        })
        if (
            $productType -ne [string]$policy.developerHost.productType -or
            $installationType -ne [string]$policy.developerHost.installationType -or
            $buildBranch -ne [string]$policy.developerHost.releaseBranch -or
            $supportedRelease.Count -ne 1
        ) {
            $allowed = @($policy.developerHost.supportedWindowsReleases | ForEach-Object { "$($_.displayVersion) build $($_.build)" }) -join ' or '
            throw "Developer host must match the GA Windows 11 x64 allowlist ($allowed) on branch $($policy.developerHost.releaseBranch); found ProductType=$productType InstallationType=$installationType DisplayVersion=$displayVersion build=$build branch=$buildBranch."
        }
    }
    'ci' {
        $osVersion = Get-ItemProperty -LiteralPath 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name CurrentBuildNumber -ErrorAction Stop
        $build = [int]$osVersion.CurrentBuildNumber
        if (
            $env:GITHUB_ACTIONS -ne 'true' -or
            $productType -ne [string]$policy.ci.productType -or
            $build -ne [int]$policy.ci.build
        ) {
            throw "CI runtime must be $($policy.ci.provider) on Windows Server 2025 x64 ($($policy.ci.runner), build $($policy.ci.build)); found ProductType=$productType build=$build."
        }
    }
}

if (-not $Quiet) {
    if ($Mode -eq 'developer') {
        Write-Output ("PASS: runtime mode={0}; PowerShell={1}; OS=Windows 11 {2}; build={3}.{4}; branch={5}; architecture={6}" -f $Mode, $version, $displayVersion, $build, $updateBuildRevision, $buildBranch, $runtime::OSArchitecture)
    } else {
        Write-Output ("PASS: runtime mode={0}; PowerShell={1}; OS=Windows Server 2025; build={2}; architecture={3}" -f $Mode, $version, $build, $runtime::OSArchitecture)
    }
}
