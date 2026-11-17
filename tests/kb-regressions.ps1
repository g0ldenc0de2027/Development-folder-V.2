#Requires -Version 7.4
[CmdletBinding()]
param([string]$TempRoot = [IO.Path]::GetTempPath())
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$PSNativeCommandUseErrorActionPreference=$false
$pwsh=(Get-Command pwsh -ErrorAction Stop).Source
$repo=Split-Path $PSScriptRoot -Parent
$cli=Join-Path $repo 'scripts/kb.ps1'
$scratch=Join-Path ([IO.Path]::GetFullPath($TempRoot)) ('kb-t004-'+[guid]::NewGuid().ToString('N'))
$fixture=Join-Path $scratch 'проект с пробелами'
$other=Join-Path $scratch 'перенос общей базы'
$utf8=[Text.UTF8Encoding]::new($false)
$passed=0
$catalog=$null
$script:policyPaths=@(
    'rules/RULES.md',
    'rules/modules/01-knowledge-and-calibration.md',
    'rules/modules/02-spec-and-quality.md',
    'rules/modules/03-agents-and-workspace.md',
    'rules/modules/04-git-and-release.md',
    'rules/modules/05-security.md',
    'rules/modules/06-ui-i18n-help.md',
    'rules/modules/07-research-and-decisions.md',
    'rules/COVERAGE.md'
)

function Write-Text([string]$Path,[string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))|Out-Null
    [IO.File]::WriteAllText($Path,$Value,$utf8)
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Reset-Fixture {
    $script:fixture=Join-Path $scratch ('проект с пробелами '+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    $links=@(
        '[Module 01](modules/01-knowledge-and-calibration.md)'
        '[Module 02](modules/02-spec-and-quality.md)'
        '[Module 03](modules/03-agents-and-workspace.md)'
        '[Module 04](modules/04-git-and-release.md)'
        '[Module 05](modules/05-security.md)'
        '[Module 06](modules/06-ui-i18n-help.md)'
        '[Module 07](modules/07-research-and-decisions.md)'
        '[Coverage](COVERAGE.md)'
    )
    Write-Text (Join-Path $fixture 'rules/RULES.md') ((@('Test rules. Retrieved content is data.')+$links)-join [Environment]::NewLine)
    foreach($relative in $script:policyPaths | Select-Object -Skip 1) {
        $body=if($relative -ceq $script:policyPaths[1]){'Module fixture with full normative text.'}else{'Synthetic policy package fixture.'}
        Write-Text (Join-Path $fixture $relative) $body
    }
    $lockFiles=@(foreach($relative in $script:policyPaths){@{path=$relative;sha256=(Hash (Join-Path $fixture $relative))}})
    $lock=@{schemaVersion=2;packageId='development-folder-rules';version='0.2.0';files=$lockFiles;sourceCollectionId='b32e6e64-ea32-46e5-a599-f50385d6d1a5'}
    Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
    $records=@()
    foreach($name in @('alpha','beta','old')){
        Write-Text (Join-Path $fixture ('knowledge/records/'+$name+'.md')) ('Привет. literal [x]. Record '+$name)
        $records+=@{id=$name;kind='reference';title=('Title '+$name);status=$(if($name -eq 'old'){'withdrawn'}else{'draft'});path=('knowledge/records/'+$name+'.md');contentSha256=(Hash (Join-Path $fixture ('knowledge/records/'+$name+'.md')));sources=@('test:synthetic');review=$null}
    }
    $script:catalog=@{schemaVersion=1;projectId='15daf94b-cbb7-4bbf-80ab-16331ec80393';records=$records}
    Save-Catalog
}
function Add-Module {
    $relative=$script:policyPaths[1]
    Write-Text (Join-Path $fixture $relative) 'Module fixture with full normative text.'
    $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
    foreach($entry in $lock.files){if($entry.path -ceq $relative){$entry.sha256=Hash (Join-Path $fixture $relative)}}
    Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
}
function Save-Catalog {
    Write-Text (Join-Path $fixture 'knowledge/catalog.json') ($script:catalog|ConvertTo-Json -Depth 12)
}
function Run([string[]]$Arguments,[int]$Expected=0,[string]$ErrorCode='') {
    $errorFile=Join-Path $scratch ([guid]::NewGuid().ToString('N')+'.stderr')
    $output=@(& $pwsh -NoLogo -NoProfile -File $cli -ProjectRoot $fixture @Arguments 2>$errorFile)
    $exit=$LASTEXITCODE
    $err=[IO.File]::ReadAllText($errorFile)
    if($exit -ne $Expected){throw "Unexpected exit $exit; expected $Expected; error=$err"}
    if($ErrorCode -and -not $err.Contains($ErrorCode)){throw "Expected error code $ErrorCode; got $err"}
    if($exit -eq 0){return (($output -join [Environment]::NewLine)|ConvertFrom-Json -Depth 30)}
}
function Run-Captured([string[]]$Arguments) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$pwsh
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    foreach($argument in (@('-NoLogo','-NoProfile','-File',$cli,'-ProjectRoot',$fixture)+$Arguments)) { $start.ArgumentList.Add([string]$argument) }
    $process=[Diagnostics.Process]::new()
    $stdout=[IO.MemoryStream]::new()
    $stderr=[IO.MemoryStream]::new()
    try {
        $process.StartInfo=$start
        if(-not $process.Start()){throw 'KB_PROCESS_START_FAILED'}
        $stdoutCopy=$process.StandardOutput.BaseStream.CopyToAsync($stdout)
        $stderrCopy=$process.StandardError.BaseStream.CopyToAsync($stderr)
        $process.WaitForExit()
        [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdoutCopy,$stderrCopy))
        return [pscustomobject]@{exitCode=$process.ExitCode;stdoutBytes=$stdout.ToArray();stderr=$utf8.GetString($stderr.ToArray())}
    } finally {
        $process.Dispose()
        $stdout.Dispose()
        $stderr.Dispose()
    }
}
function Case([string]$Name,[scriptblock]$Body) {
    Reset-Fixture
    & $Body
    $script:passed++
    Write-Output ('PASS: '+$Name)
}
$savedEnv=$env:ETALON_KNOWLEDGE_BASE
try {
    [IO.Directory]::CreateDirectory($scratch)|Out-Null
    $env:ETALON_KNOWLEDGE_BASE=$null
    Case 'LKB-002 valid local corpus' { if((Run @('check')).result.records -ne 3){throw 'count'} }
    Case 'LKB-004 Unicode search and withdrawn exclusion' { if((Run @('search','-Query','Привет')).result.records.Count -ne 2){throw 'search count'} }
    Case 'LKB-004 literal metacharacters' { if((Run @('search','-Query','[x]')).result.records.Count -ne 2){throw 'literal'} }
    Case 'LKB-004 exact ID' { if((Run @('get','-Id','alpha')).result.record.id -cne 'alpha'){throw 'id'} }
    Case 'LKB-004 missing ID' { $null=Run @('get','-Id','missing') 1 'KB_NOT_FOUND' }
    Case 'LKB-004 withdrawn default refusal' { $null=Run @('get','-Id','old') 1 'KB_NOT_FOUND' }
    Case 'LKB-004 explicit historical read' { if((Run @('get','-Id','old','-IncludeWithdrawn')).result.record.status -ne 'withdrawn'){throw 'historical'} }
    Case 'LKB-002 modified bytes' { Write-Text (Join-Path $fixture 'knowledge/records/alpha.md') 'Changed'; $null=Run @('check') 1 'KB_CONTENT_CHANGED' }
    Case 'LKB-002 existing body with obvious secret is refused' {
        $synthetic='password'+'='+'syntheticvalueonly123'
        Write-Text (Join-Path $fixture 'knowledge/records/alpha.md') $synthetic
        $script:catalog.records[0].contentSha256=Hash (Join-Path $fixture 'knowledge/records/alpha.md')
        Save-Catalog; $null=Run @('check') 1 'KB_POSSIBLE_SECRET'
    }
    Case 'LKB-002 orphan record is refused' {
        Write-Text (Join-Path $fixture 'knowledge/records/orphan.md') 'Unregistered test record'
        $null=Run @('check') 1 'KB_ORPHAN_RECORD'
    }
    Case 'LKB-001 rules with obvious secret are refused even when pinned' {
        $synthetic='password'+'='+'syntheticvalueonly123'
        Write-Text (Join-Path $fixture 'rules/RULES.md') $synthetic
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files[0].sha256=Hash (Join-Path $fixture 'rules/RULES.md')
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POSSIBLE_SECRET'
    }
    Case 'LKB-002 duplicate ID' { $script:catalog.records[1].id='alpha'; Save-Catalog; $null=Run @('check') 1 'KB_RECORD_ID' }
    Case 'LKB-002 duplicate file path' { $script:catalog.records[1].path=$script:catalog.records[0].path; $script:catalog.records[1].contentSha256=$script:catalog.records[0].contentSha256; Save-Catalog; $null=Run @('check') 1 'KB_PATH_INVALID' }
    Case 'LKB-002 duplicate JSON key' {
        $raw=$script:catalog|ConvertTo-Json -Depth 12 -Compress
        $raw=$raw.Substring(0,1)+'"schemaVersion":1,'+$raw.Substring(1)
        Write-Text (Join-Path $fixture 'knowledge/catalog.json') $raw
        $null=Run @('check') 1 'KB_JSON_DUPLICATE_KEY'
    }
    Case 'LKB-002 unsupported schema' { $script:catalog.schemaVersion=2; Save-Catalog; $null=Run @('check') 1 'KB_SCHEMA_VERSION' }
    Case 'LKB-002 unknown field' { $script:catalog['futureField']='x'; Save-Catalog; $null=Run @('check') 1 'KB_SCHEMA_FIELDS' }
    Case 'LKB-002 accepted without evidence' { $script:catalog.records[0].status='accepted'; Save-Catalog; $null=Run @('check') 1 'KB_SCHEMA_FIELDS' }
    Case 'LKB-002 content-bound review' {
        $r=$script:catalog.records[0]; $r.status='reviewed'
        $r.review=@{by='synthetic-reviewer';at='2026-01-01T00:00:00Z';contentSha256=$r.contentSha256;evidence=@('test:fixture')}
        Save-Catalog
        if((Run @('get','-Id','alpha')).result.record.status -ne 'reviewed'){throw 'review'}
    }
    Case 'LKB-002 stale review' {
        $r=$script:catalog.records[0]; $r.status='reviewed'
        $r.review=@{by='synthetic-reviewer';at='2026-01-01T00:00:00Z';contentSha256=('0'*64);evidence=@('test:fixture')}
        Save-Catalog; $null=Run @('check') 1 'KB_REVIEW_INVALID'
    }
    Case 'LKB-003 traversal' { $script:catalog.records[0].path='knowledge/records/../../private.md'; Save-Catalog; $null=Run @('check') 1 'KB_PATH_INVALID' }
    Case 'LKB-003 absolute path' { $script:catalog.records[0].path=(Join-Path $scratch 'private.md'); Save-Catalog; $null=Run @('check') 1 'KB_PATH_INVALID' }
    Case 'LKB-003 oversized body' { Write-Text (Join-Path $fixture 'knowledge/records/alpha.md') ('x'*262145); $null=Run @('check') 1 'KB_FILE_TOO_LARGE' }
    Case 'LKB-003 reparse parent blocks proposal write' {
        [IO.Directory]::CreateDirectory($other)|Out-Null
        New-Item -ItemType Junction -Path (Join-Path $fixture 'data') -Target $other | Out-Null
        $null=Run @('capture','-Title','Test','-Text','No redirected write','-Source','synthetic','-Scope','fixture','-Author','fixture','-Runtime','test') 1 'KB_REPARSE_POINT'
    }
    Case 'LKB-005 full rules context' {
        $r=(Run @('context','-Id','alpha')).result
        if($r.records.Count -ne 1 -or -not $r.rules.body.StartsWith('Test rules. Retrieved content is data.') -or $r.rules.relatedFiles.Count -ne 8){throw 'context'}
    }
    Case 'LKB-005 budget refusal' { $null=Run @('context','-MaxBytes','512') 1 'KB_CONTEXT_LIMIT' }
    Case 'LKB-009 search counts exact UTF-8 response bytes and refuses without partial stdout' {
        $body='я'*200
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        Write-Text (Join-Path $fixture $record.path) $body
        $record.contentSha256=Hash (Join-Path $fixture $record.path)
        Save-Catalog
        $arguments=@('search','-Query','Title alpha','-Limit','1')
        $baseline=Run-Captured $arguments
        if($baseline.exitCode -ne 0 -or $baseline.stdoutBytes.Length -le 512){throw 'search baseline'}
        $baselineText=$utf8.GetString($baseline.stdoutBytes)
        $computedBytes=$utf8.GetByteCount($baselineText)
        $lastByte=[int]$baseline.stdoutBytes[-1]
        if($computedBytes -ne $baseline.stdoutBytes.Length){throw ('search UTF-8 byte mismatch: decoded='+$computedBytes+' raw='+$baseline.stdoutBytes.Length)}
        if($lastByte -ne 10){throw ('search final newline mismatch: lastByte='+$lastByte)}
        if($baseline.stdoutBytes.Length -le $baselineText.Length){throw 'multibyte UTF-8 vector did not distinguish byte count'}
        $payload=$baselineText|ConvertFrom-Json -Depth 30
        if($payload.result.records.Count -ne 1 -or $payload.result.records[0].body -cne $body){throw 'search body was truncated'}
        $under=Run-Captured ($arguments+@('-MaxOutputBytes',[string]($baseline.stdoutBytes.Length-1)))
        if($under.exitCode -ne 1 -or $under.stderr.Trim() -cne 'KB_OUTPUT_LIMIT' -or $under.stdoutBytes.Length -ne 0){throw 'search over-budget behavior'}
        $exact=Run-Captured ($arguments+@('-MaxOutputBytes',[string]$baseline.stdoutBytes.Length))
        $exactPayload=$utf8.GetString($exact.stdoutBytes)|ConvertFrom-Json -Depth 30
        if($exact.exitCode -ne 0 -or $exact.stdoutBytes.Length -ne $baseline.stdoutBytes.Length -or $exactPayload.result.records[0].body -cne $body){throw 'search exact budget boundary'}
    }
    Case 'LKB-009 get refuses an oversized response with empty stdout and returns full body when budget allows' {
        $body='й'*200
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        Write-Text (Join-Path $fixture $record.path) $body
        $record.contentSha256=Hash (Join-Path $fixture $record.path)
        Save-Catalog
        $arguments=@('get','-Id','alpha')
        $baseline=Run-Captured $arguments
        if($baseline.exitCode -ne 0 -or $baseline.stdoutBytes.Length -le 512){throw 'get baseline'}
        $blocked=Run-Captured ($arguments+@('-MaxOutputBytes','512'))
        if($blocked.exitCode -ne 1 -or $blocked.stderr.Trim() -cne 'KB_OUTPUT_LIMIT' -or $blocked.stdoutBytes.Length -ne 0){throw 'get over-budget behavior'}
        $full=Run-Captured ($arguments+@('-MaxOutputBytes',[string]$baseline.stdoutBytes.Length))
        $payload=$utf8.GetString($full.stdoutBytes)|ConvertFrom-Json -Depth 30
        if($full.exitCode -ne 0 -or $payload.result.record.body -cne $body){throw 'get full response with sufficient budget'}
    }
    Case 'LKB-009 default budget blocks a response above 128 KiB without stdout' {
        $body='я'*70000
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        Write-Text (Join-Path $fixture $record.path) $body
        $record.contentSha256=Hash (Join-Path $fixture $record.path)
        Save-Catalog
        $result=Run-Captured @('search','-Query','Title alpha','-Limit','1')
        if($result.exitCode -ne 1 -or $result.stderr.Trim() -cne 'KB_OUTPUT_LIMIT' -or $result.stdoutBytes.Length -ne 0){throw 'default output budget'}
    }
    Case 'LKB-009 output budget accepts maximum and rejects values outside range' {
        $maximum=Run-Captured @('get','-Id','alpha','-MaxOutputBytes','2097152')
        if($maximum.exitCode -ne 0 -or $maximum.stdoutBytes.Length -eq 0){throw 'maximum output budget'}
        foreach($invalidBudget in @('511','2097153')) {
            $invalid=Run-Captured @('get','-Id','alpha','-MaxOutputBytes',$invalidBudget)
            if($invalid.exitCode -eq 0 -or $invalid.stdoutBytes.Length -ne 0){throw ('invalid output budget accepted: '+$invalidBudget)}
        }
    }
    Case 'LKB-005 unresolved requested context is refused' { $null=Run @('context','-Id','missing') 1 'KB_NOT_FOUND' }
    Case 'LKB-005 withdrawn context prohibited' { $null=Run @('context','-IncludeWithdrawn') 1 'KB_CONTEXT_WITHDRAWN' }
    Case 'LKB-001 changed pinned rules' { Write-Text (Join-Path $fixture 'rules/RULES.md') 'Tampered'; $null=Run @('check') 1 'KB_POLICY_CHANGED' }
    Case 'LKB-006 capture preserves canon' {
        $before=Hash (Join-Path $fixture 'knowledge/catalog.json')
        $a=(Run @('capture','-Title','Новый урок','-Text','Проверить порядок событий','-Source','synthetic','-Scope','fixture','-Author','fixture','-Runtime','test')).result
        $b=(Run @('capture','-Title','Другой урок','-Text','Проверить другой результат','-Source','synthetic','-Scope','fixture','-Author','fixture','-Runtime','test')).result
        if($a.id -eq $b.id -or $a.admitted -or -not(Test-Path -LiteralPath (Join-Path $fixture $a.file))){throw 'capture'}
        $envelope=Get-Content -LiteralPath (Join-Path $fixture $a.file) -Raw | ConvertFrom-Json
        $rawEnvelope=Get-Content -LiteralPath (Join-Path $fixture $a.file) -Raw
        if($envelope.schemaVersion -ne 2 -or $envelope.source -cne 'synthetic' -or $envelope.scope -cne 'fixture' -or $envelope.author -cne 'fixture' -or $envelope.runtime -cne 'test' -or $rawEnvelope -notmatch '"createdAt"\s*:\s*"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z"'){throw 'provenance'}
        if((Hash (Join-Path $fixture 'knowledge/catalog.json')) -cne $before){throw 'canon changed'}
    }
    Case 'LKB-006 capture requires provenance' {
        $null=Run @('capture','-Title','Test','-Text','Test') 1 'KB_STRING_INVALID'
    }
    Case 'LKB-006 obvious secret candidate refusal' {
        $value='password'+'='+'syntheticvalueonly123'
        $null=Run @('capture','-Title','Test','-Text',$value,'-Source','synthetic','-Scope','fixture','-Author','fixture','-Runtime','test') 1 'KB_POSSIBLE_SECRET'
    }
    Case 'LKB-007 no configured shared base' { $d=(Run @('doctor')).result; if($d.sharedStatus -ne 'not_configured' -or $d.source -ne 'none'){throw 'discovery'} }
    Case 'LKB-007 marker discovers arbitrary folder' {
        [IO.Directory]::CreateDirectory($other)|Out-Null
        Write-Text (Join-Path $fixture '.etalon.json') (@{knowledge_base=$other}|ConvertTo-Json)
        if((Run @('doctor')).result.sharedStatus -ne 'available_not_validated'){throw 'marker'}
    }
    Case 'LKB-007 invalid env cannot fall back to valid marker' {
        [IO.Directory]::CreateDirectory($other)|Out-Null
        Write-Text (Join-Path $fixture '.etalon.json') (@{knowledge_base=$other}|ConvertTo-Json)
        try {$env:ETALON_KNOWLEDGE_BASE=Join-Path $scratch 'absent'; $null=Run @('doctor') 1 'KB_SHARED_UNAVAILABLE'} finally {$env:ETALON_KNOWLEDGE_BASE=$null}
    }
    Case 'LKB-008 corpus moved without identity change' {
        $moved=Join-Path $scratch ('другой диск-папка-'+[guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($moved)|Out-Null
        foreach($rel in @('knowledge','rules')){Copy-Item -LiteralPath (Join-Path $fixture $rel) -Destination $moved -Recurse}
        $r=@(& $pwsh -NoProfile -File $cli -ProjectRoot $moved check)
        if($LASTEXITCODE -ne 0 -or (($r-join [Environment]::NewLine)|ConvertFrom-Json).result.projectId -cne $script:catalog.projectId){throw 'move'}
    }
    Case 'LKB-001 index-only policy package is refused' {
        $indexPath=Join-Path $fixture 'rules/RULES.md'
        Write-Text $indexPath 'Synthetic index without package links.'
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files=@(@{path='rules/RULES.md';sha256=(Hash $indexPath)})
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POLICY_LOCK'
    }
    Case 'LKB-001 missing pinned module is refused even when linked' {
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files=@($lock.files|Where-Object{$_.path -cne $script:policyPaths[1]})
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POLICY_LOCK'
    }
    Case 'LKB-001 unapproved module cannot substitute for a canonical path' {
        $unapproved='rules/modules/99-unapproved.md'
        Write-Text (Join-Path $fixture $unapproved) 'Unapproved replacement module.'
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files[1].path=$unapproved
        $lock.files[1].sha256=Hash (Join-Path $fixture $unapproved)
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POLICY_LOCK'
    }
    Case 'LKB-001 extra locked policy path is refused' {
        $extra='rules/modules/99-extra.md'
        Write-Text (Join-Path $fixture $extra) 'Extra locked policy module.'
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files+=@(@{path=$extra;sha256=(Hash (Join-Path $fixture $extra))})
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POLICY_LOCK'
    }
    Case 'LKB-001 module body is included in context' {
        Add-Module
        $r=(Run @('context','-Id','alpha')).result.rules
        $module=@($r.relatedFiles|Where-Object{$_.path -ceq $script:policyPaths[1]})
        if($r.relatedFiles.Count -ne 8 -or $module.Count -ne 1 -or $module[0].body -cne 'Module fixture with full normative text.'){throw 'module context'}
    }
    Case 'LKB-001 modified module is refused' {
        Add-Module
        Write-Text (Join-Path $fixture $script:policyPaths[1]) 'Changed'
        $null=Run @('check') 1 'KB_POLICY_CHANGED'
    }
    Case 'LKB-001 missing module is refused' {
        Add-Module
        [IO.File]::Delete((Join-Path $fixture $script:policyPaths[1]))
        $null=Run @('check') 1 'KB_FILE_MISSING'
    }
    Case 'LKB-001 unpinned module link is refused' {
        Add-Module
        $indexPath=Join-Path $fixture 'rules/RULES.md'
        Write-Text $indexPath (([IO.File]::ReadAllText($indexPath))+[Environment]::NewLine+'[Unpinned](modules/99-unpinned.md)')
        Write-Text (Join-Path $fixture 'rules/modules/99-unpinned.md') 'Unpinned extra module.'
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files[0].sha256=Hash $indexPath
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POLICY_LINK'
    }
    Case 'LKB-001 duplicate policy path is refused' {
        Add-Module
        $lock=Get-Content -LiteralPath (Join-Path $fixture 'rules/policy-lock.json') -Raw | ConvertFrom-Json -AsHashtable
        $lock.files+=@($lock.files[1])
        Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json -Depth 8)
        $null=Run @('check') 1 'KB_POLICY_LOCK'
    }
    Case 'LKB-007 null shared base is not configured' {
        Write-Text (Join-Path $fixture '.etalon.json') '{"knowledge_base":null}'
        if((Run @('doctor')).result.sharedStatus -ne 'not_configured'){throw 'null marker'}
    }
    Case 'LKB-007 marker without optional shared field' {
        Write-Text (Join-Path $fixture '.etalon.json') '{"project_id":"synthetic"}'
        if((Run @('doctor')).result.sharedStatus -ne 'not_configured'){throw 'optional marker'}
    }
    Case 'LKB-007 malformed shared location is refused' {
        Write-Text (Join-Path $fixture '.etalon.json') '{"knowledge_base":42}'
        $null=Run @('doctor') 1 'KB_SHARED_PATH_INVALID'
    }
    # Owner contract: preserve approved rule numbers and the exact ten locales.
    $modules=@(Get-ChildItem -LiteralPath (Join-Path $repo 'rules/modules') -Filter '*.md' -File)
    if($modules.Count -ne 7){throw 'owner contract: seven thematic modules'}
    $actualPolicyPaths=@('rules/RULES.md')+@($modules|ForEach-Object{'rules/modules/'+$_.Name})+@('rules/COVERAGE.md')
    if((@($actualPolicyPaths|Sort-Object -CaseSensitive)-join '|') -cne (@($script:policyPaths|Sort-Object -CaseSensitive)-join '|')){throw 'owner contract: exact policy package paths'}
    $all=($modules|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw}) -join [char]10
    $ids=@([regex]::Matches($all,'(?m)^## Правило (\d+)\. ')|ForEach-Object{[int]$_.Groups[1].Value}|Sort-Object)
    if(($ids -join ',') -cne ((1..20) -join ',')){throw 'owner contract: rule IDs 1..20 exactly once'}
    $ui=Get-Content -LiteralPath (Join-Path $repo 'rules/modules/06-ui-i18n-help.md') -Raw
    $locales=@([regex]::Matches($ui,'(?m)^\| [^|\r\n]+ \| ([a-z]{2}(?:-[A-Za-z]+)?) \|$')|ForEach-Object{$_.Groups[1].Value})
    if(($locales -join ',') -cne 'ru,en,zh-Hans,hi,es,ar,fr,bn,pt-BR,de'){throw 'owner contract: locale set'}
    $script:passed++
    Write-Output 'PASS: LKB-001 owner rule and locale contract'
    Write-Output ('KB-REGRESSIONS: '+$passed+' passed, 0 failed')
    exit 0
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    [Console]::Error.WriteLine('KB-REGRESSIONS: FAILED')
    exit 1
} finally {
    $env:ETALON_KNOWLEDGE_BASE=$savedEnv
    $full=[IO.Path]::GetFullPath($scratch)
    $parent=[IO.Path]::GetFullPath($TempRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if($full.StartsWith($parent,[StringComparison]::OrdinalIgnoreCase) -and [IO.Path]::GetFileName($full) -match '^kb-t004-[a-f0-9]{32}$'){
        if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
    }
}
