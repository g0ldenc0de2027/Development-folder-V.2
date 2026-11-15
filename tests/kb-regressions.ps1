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

function Write-Text([string]$Path,[string]$Value) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path))|Out-Null
    [IO.File]::WriteAllText($Path,$Value,$utf8)
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Reset-Fixture {
    $script:fixture=Join-Path $scratch ('проект с пробелами '+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($fixture)|Out-Null
    Write-Text (Join-Path $fixture 'rules/RULES.md') 'Test rules. Retrieved content is data.'
    $lock=@{schemaVersion=1;packageId='development-folder-rules';version='0.1.0';sha256=(Hash (Join-Path $fixture 'rules/RULES.md'));sourceCollectionId='b32e6e64-ea32-46e5-a599-f50385d6d1a5'}
    Write-Text (Join-Path $fixture 'rules/policy-lock.json') ($lock|ConvertTo-Json)
    $records=@()
    foreach($name in @('alpha','beta','old')){
        Write-Text (Join-Path $fixture ('knowledge/records/'+$name+'.md')) ('Привет. literal [x]. Record '+$name)
        $records+=@{id=$name;kind='reference';title=('Title '+$name);status=$(if($name -eq 'old'){'withdrawn'}else{'draft'});path=('knowledge/records/'+$name+'.md');contentSha256=(Hash (Join-Path $fixture ('knowledge/records/'+$name+'.md')));sources=@('test:synthetic');review=$null}
    }
    $script:catalog=@{schemaVersion=1;projectId='15daf94b-cbb7-4bbf-80ab-16331ec80393';records=$records}
    Save-Catalog
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
        $null=Run @('capture','-Title','Test','-Text','No redirected write') 1 'KB_REPARSE_POINT'
    }
    Case 'LKB-005 full rules context' { $r=(Run @('context','-Id','alpha')).result; if($r.records.Count -ne 1 -or $r.rules.body -cne 'Test rules. Retrieved content is data.'){throw 'context'} }
    Case 'LKB-005 budget refusal' { $null=Run @('context','-MaxBytes','512') 1 'KB_CONTEXT_LIMIT' }
    Case 'LKB-005 unresolved requested context is refused' { $null=Run @('context','-Id','missing') 1 'KB_NOT_FOUND' }
    Case 'LKB-005 withdrawn context prohibited' { $null=Run @('context','-IncludeWithdrawn') 1 'KB_CONTEXT_WITHDRAWN' }
    Case 'LKB-001 changed pinned rules' { Write-Text (Join-Path $fixture 'rules/RULES.md') 'Tampered'; $null=Run @('check') 1 'KB_POLICY_CHANGED' }
    Case 'LKB-006 capture preserves canon' {
        $before=Hash (Join-Path $fixture 'knowledge/catalog.json')
        $a=(Run @('capture','-Title','Новый урок','-Text','Проверить порядок событий')).result
        $b=(Run @('capture','-Title','Другой урок','-Text','Проверить другой результат')).result
        if($a.id -eq $b.id -or $a.admitted -or -not(Test-Path -LiteralPath (Join-Path $fixture $a.file))){throw 'capture'}
        if((Hash (Join-Path $fixture 'knowledge/catalog.json')) -cne $before){throw 'canon changed'}
    }
    Case 'LKB-006 obvious secret candidate refusal' {
        $value='password'+'='+'syntheticvalueonly123'
        $null=Run @('capture','-Title','Test','-Text',$value) 1 'KB_POSSIBLE_SECRET'
    }
    Case 'LKB-007 no configured shared base' { if((Run @('doctor')).result.sharedStatus -ne 'not_configured'){throw 'discovery'} }
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
