[CmdletBinding()]
param([string]$TempRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$validator = Join-Path $repoRoot 'scripts/verify-pr-merge-result.ps1'
$workflow = Get-Content -LiteralPath (Join-Path $repoRoot '.github/workflows/quality-gate.yml') -Raw
$qualityGate = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts/quality-gate.ps1') -Raw
$workflowBaseExpr = '$' + '{{ github.event.pull_request.base.sha }}'
$workflowHeadExpr = '$' + '{{ github.event.pull_request.head.sha }}'
$workflowTestExpr = '$' + '{{ github.sha }}'
if (
    $workflow -notmatch '(?m)^\s*-\s*name:\s*Verify exact pull request merge-result\s*$' -or

    -not $workflow.Contains('PR_BASE_SHA: ' + $workflowBaseExpr) -or
    -not $workflow.Contains('PR_HEAD_SHA: ' + $workflowHeadExpr) -or
    -not $workflow.Contains('EVENT_TEST_SHA: ' + $workflowTestExpr) -or
    -not $workflow.Contains('scripts/verify-pr-merge-result.ps1') -or
    -not $workflow.Contains('if ($env:GITHUB_EVENT_NAME -eq ''pull_request'')') -or
    -not $workflow.Contains('NOT APPLICABLE: current event is not pull_request') -or
    $workflow -match '(?im)^\s*pull_request_target\s*:'
) {
    throw 'Workflow must run the exact merge-result assertion only for pull_request with payload base/head and github.sha'
}
$verifyStepPosition = $workflow.IndexOf('      - name: Verify exact pull request merge-result', [StringComparison]::Ordinal)
$gateStepPosition = $workflow.IndexOf('      - name: Run quality gate and record tested revisions', [StringComparison]::Ordinal)
if ($verifyStepPosition -lt 0 -or $gateStepPosition -lt 0 -or $verifyStepPosition -ge $gateStepPosition) {
    throw 'PR merge-result assertion must run before the main quality gate'
}
if (
    -not $qualityGate.Contains('tests/pr-merge-result-regressions.ps1') -or
    -not $qualityGate.Contains('NOT APPLICABLE: hosted PR merge-result assertion requires pull_request event')
) {
    throw 'Quality gate must run tuple regressions and mark hosted assertion not applicable outside pull_request'
}
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw 'PR merge-result validator is missing'
}

$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
if ([string]::IsNullOrWhiteSpace($TempRoot)) {
    $tempParent = $systemTemp
} else {
    $tempParent = [IO.Path]::GetFullPath($TempRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $tempPrefix = $systemTemp + [IO.Path]::DirectorySeparatorChar
    if (
        -not $tempParent.Equals($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
        -not $tempParent.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw 'Regression TempRoot must be inside the system temporary directory'
    }
}
if (-not [IO.Directory]::Exists($tempParent)) {
    throw 'Regression TempRoot is unavailable'
}
$fixtureRoot = Join-Path $tempParent ('pr-merge-result-' + [guid]::NewGuid().ToString('N'))
if (Test-Path -LiteralPath $fixtureRoot) {
    throw 'Regression fixture path already exists'
}

$oldEnvironment = @{}
foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
    if (([string]$entry.Key).StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase)) {
        $oldEnvironment[$entry.Key] = $entry.Value
    }
}
$passed = 0
$fixtureRepo = Join-Path $fixtureRoot 'synthetic.git'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-GitFixture {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = @(& git -C $fixtureRepo @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        $detail = ($output -join ' ') -replace [regex]::Escape($fixtureRepo), '<fixture>'
        throw ("Synthetic Git fixture command failed: {0}, exit {1}, details: {2}" -f $Arguments[0], $exitCode, $detail)
    }
    return ($output -join '').Trim()
}

function New-FixtureCommit {
    param([string[]]$Parents, [Parameter(Mandatory)][string]$Message)
    $arguments = [Collections.Generic.List[string]]::new()
    $null = $arguments.Add('commit-tree')
    $null = $arguments.Add($script:fixtureTree)
    foreach ($parent in $Parents) {
        $null = $arguments.Add('-p')
        $null = $arguments.Add($parent)
    }
    $null = $arguments.Add('-m')
    $null = $arguments.Add($Message)
    $uniqueParents = @($Parents | Select-Object -Unique)
    if ($uniqueParents.Count -ne $Parents.Count) {
        throw 'Synthetic commit fixture received duplicate parents'
    }
    $commit = Invoke-GitFixture -Arguments $arguments.ToArray()
    if ($commit -notmatch '^[0-9a-f]{40}$') {
        throw 'Synthetic commit fixture did not return exactly one SHA-1'
    }
    return $commit
}

function Set-FixtureHead {
    param([Parameter(Mandatory)][string]$Sha)
    $null = Invoke-GitFixture -Arguments @('update-ref', 'refs/heads/main', $Sha)
}

function Invoke-ValidatorCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$ShouldPass,
        [Parameter(Mandatory)][string]$Base,
        [Parameter(Mandatory)][string]$Head,
        [Parameter(Mandatory)][string]$Test
    )
    $output = @(& $pwsh -NoLogo -NoProfile -File $validator -RepositoryRoot $fixtureRepo -BaseSha $Base -HeadSha $Head -TestSha $Test 2>&1)
    $exitCode = $LASTEXITCODE
    if ($ShouldPass -and $exitCode -ne 0) {
        throw "Expected validator success for case: $Name"
    }
    if (-not $ShouldPass -and $exitCode -eq 0) {
        throw "Expected validator rejection for case: $Name"
    }
    $script:passed++
}

try {
    New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
    $globalConfig = Join-Path $fixtureRoot 'empty.gitconfig'
    [IO.File]::WriteAllText($globalConfig, '', [Text.UTF8Encoding]::new($false))
    foreach ($name in $oldEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $null, 'Process')
    }
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_GLOBAL', $globalConfig, 'Process')
    [Environment]::SetEnvironmentVariable('GIT_CONFIG_NOSYSTEM', '1', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_AUTHOR_NAME', 'Synthetic Regression', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_AUTHOR_EMAIL', 'regression@example.invalid', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_NAME', 'Synthetic Regression', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_EMAIL', 'regression@example.invalid', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE', '2001-01-01T00:00:00Z', 'Process')
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE', '2001-01-01T00:00:00Z', 'Process')

    New-Item -ItemType Directory -Path $fixtureRepo | Out-Null
    $null = Invoke-GitFixture -Arguments @('init', '--quiet', '--bare', '--initial-branch=main')
    $blobText = 'synthetic content'
    $blobOutput = @($blobText | & git -C $fixtureRepo hash-object -w --stdin)
    if ($LASTEXITCODE -ne 0) { throw 'Could not create synthetic blob' }
    $blob = ($blobOutput -join '').Trim()
    $treeLine = '100644 blob ' + $blob + [char]9 + 'fixture.txt'
    $treeOutput = @($treeLine | & git -C $fixtureRepo mktree)
    if ($LASTEXITCODE -ne 0) { throw 'Could not create synthetic tree' }
    $script:fixtureTree = ($treeOutput -join '').Trim()

    $base = New-FixtureCommit -Parents @() -Message 'base'
    $head = New-FixtureCommit -Parents @($base) -Message 'head'
    $extra = New-FixtureCommit -Parents @($base) -Message 'extra'
    $good = New-FixtureCommit -Parents @($base, $head) -Message 'good'
    $reversed = New-FixtureCommit -Parents @($head, $base) -Message 'reversed'
    $octopus = New-FixtureCommit -Parents @($base, $head, $extra) -Message 'octopus'
    $null = Invoke-GitFixture -Arguments @('symbolic-ref', 'HEAD', 'refs/heads/main')

    Set-FixtureHead -Sha $good
    Invoke-ValidatorCase -Name 'exact tuple' -ShouldPass $true -Base $base -Head $head -Test $good
    Set-FixtureHead -Sha $reversed
    Invoke-ValidatorCase -Name 'reversed parents' -ShouldPass $false -Base $base -Head $head -Test $reversed
    Set-FixtureHead -Sha $head
    Invoke-ValidatorCase -Name 'single parent' -ShouldPass $false -Base $base -Head $head -Test $head
    Set-FixtureHead -Sha $octopus
    Invoke-ValidatorCase -Name 'three parents' -ShouldPass $false -Base $base -Head $head -Test $octopus
    Set-FixtureHead -Sha $good
    Invoke-ValidatorCase -Name 'wrong base' -ShouldPass $false -Base $extra -Head $head -Test $good
    Invoke-ValidatorCase -Name 'wrong head' -ShouldPass $false -Base $base -Head $extra -Test $good
    Set-FixtureHead -Sha $base
    Invoke-ValidatorCase -Name 'checkout mismatch' -ShouldPass $false -Base $base -Head $head -Test $good
    Set-FixtureHead -Sha $good
    Invoke-ValidatorCase -Name 'malformed base SHA' -ShouldPass $false -Base 'not-a-sha' -Head $head -Test $good
    Invoke-ValidatorCase -Name 'malformed head SHA' -ShouldPass $false -Base $base -Head 'not-a-sha' -Test $good
    Invoke-ValidatorCase -Name 'malformed test SHA' -ShouldPass $false -Base $base -Head $head -Test 'not-a-sha'
    Invoke-ValidatorCase -Name 'missing commit' -ShouldPass $false -Base $base -Head $head -Test ('0' * 40)
    Invoke-ValidatorCase -Name 'non-commit object' -ShouldPass $false -Base $base -Head $head -Test $script:fixtureTree

    Write-Output ("PR-MERGE-RESULT-REGRESSIONS: {0} passed, 0 failed" -f $passed)
} finally {
    foreach ($entry in [Environment]::GetEnvironmentVariables('Process').GetEnumerator()) {
        if (([string]$entry.Key).StartsWith('GIT_', [StringComparison]::OrdinalIgnoreCase)) {
            [Environment]::SetEnvironmentVariable($entry.Key, $null, 'Process')
        }
    }
    foreach ($name in $oldEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $oldEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $fixtureRoot) {
        $fixtureRootFull = [IO.Path]::GetFullPath($fixtureRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
        $allowedPrefix = [IO.Path]::GetFullPath($tempParent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (
            -not $fixtureRootFull.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            $fixtureRootFull.Equals([IO.Path]::GetFullPath($tempParent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
        ) {
            throw 'Refusing to remove a fixture outside its unique temporary directory'
        }
        $fixtureItem = Get-Item -LiteralPath $fixtureRootFull -Force
        if (($fixtureItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Refusing to remove a reparse-point fixture'
        }
        Remove-Item -LiteralPath $fixtureRootFull -Recurse -Force
    }
}
