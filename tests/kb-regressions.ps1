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
function Run-Captured([string[]]$Arguments,[string]$Root=$fixture,[System.Collections.IDictionary]$Environment=@{}) {
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=$pwsh
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    foreach($name in $Environment.Keys){$start.Environment[[string]$name]=[string]$Environment[$name]}
    foreach($argument in (@('-NoLogo','-NoProfile','-File',$cli,'-ProjectRoot',$Root)+$Arguments)) { $start.ArgumentList.Add([string]$argument) }
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
    Case 'LKB-010 compact uses the same matching and preserves order and status' {
        foreach($options in @(@(),@('-Limit','1'),@('-IncludeWithdrawn'))){
            $arguments=@('SEARCH','-Query','Привет')+$options
            $full=(Run $arguments).result
            $small=(Run ($arguments+@('-Compact'))).result
            if($small.representation -cne 'compact' -or $small.projectId -cne $full.projectId -or
               $small.totalMatches -ne $full.totalMatches -or $small.returned -ne $full.returned -or
               $small.truncated -ne $full.truncated -or ($small.records.id -join '|') -cne ($full.records.id -join '|')){
                throw 'compact selection differs'
            }
            foreach($record in $small.records){
                if((($record.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'contentSha256,id,kind,status,title'){
                    throw 'compact fields differ'
                }
                $readback=(Run (@('get','-Id',$record.id)+@($options|Where-Object {$_ -eq '-IncludeWithdrawn'}))).result.record
                foreach($field in 'id','kind','title','status','contentSha256'){
                    if($record.$field -cne $readback.$field){throw "compact readback differs: $field"}
                }
            }
        }
        $empty=(Run @('search','-Compact','-Query','absent-test-token')).result
        if($empty.records.Count -ne 0 -or $empty.totalMatches -ne 0 -or $empty.truncated){throw 'compact empty result'}
    }
    Case 'LKB-010 compact obeys the byte boundary and fails closed' {
        $arguments=@('search','-Compact','-Query','Привет')
        $baseline=Run-Captured $arguments
        if($baseline.exitCode -ne 0 -or $baseline.stdoutBytes.Length -le 512){throw 'compact baseline'}
        $exact=Run-Captured ($arguments+@('-MaxOutputBytes',[string]$baseline.stdoutBytes.Length))
        $under=Run-Captured ($arguments+@('-MaxOutputBytes',[string]($baseline.stdoutBytes.Length-1)))
        if($exact.exitCode -ne 0 -or $exact.stdoutBytes.Length -ne $baseline.stdoutBytes.Length -or
           $under.exitCode -ne 1 -or $under.stdoutBytes.Length -ne 0 -or $under.stderr.Trim() -cne 'KB_OUTPUT_LIMIT'){
            throw 'compact budget differs'
        }
        $null=Run @('get','-Compact','-Id','alpha') 1 'KB_COMPACT_SEARCH_ONLY'
        Write-Text (Join-Path $fixture 'knowledge/records/alpha.md') 'Changed'
        $null=Run $arguments 1 'KB_CONTENT_CHANGED'
    }
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
    Case 'LKB-003 record path rejects a trailing slash or newline' {
        foreach ($suffix in '/', [string][char]10) {
            $script:catalog.records[0].path='knowledge/records/local-first.md'+$suffix
            Save-Catalog
            $result=Run-Captured @('check')
            if ($result.exitCode -ne 1 -or $result.stderr.Trim() -cne 'KB_PATH_INVALID' -or $result.stdoutBytes.Length -ne 0) { throw 'Unexpected invalid path result' }
        }
    }
    Case 'LKB-003 project root below a reparse ancestor is refused' {
        $alias=Join-Path $scratch ('project-parent-link-'+[guid]::NewGuid().ToString('N'))
        New-Item -ItemType Junction -Path $alias -Target $scratch | Out-Null
        $aliasRoot=Join-Path $alias (Split-Path -Leaf $fixture)
        $result=Run-Captured @('check') $aliasRoot
        if($result.exitCode -ne 1 -or -not $result.stderr.Contains('KB_REPARSE_POINT') -or $result.stdoutBytes.Length -ne 0){throw 'reparse ancestor refusal'}
    }
    Case 'LKB-003 hard-linked metadata and policy files are refused before output' {
        foreach ($relative in @('knowledge/catalog.json','rules/policy-lock.json','rules/RULES.md')) {
            $file = Join-Path $fixture $relative
            $outside = Join-Path $scratch ('metadata-outside-' + [guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $file -Destination $outside
            Remove-Item -LiteralPath $file
            try {
                New-Item -ItemType HardLink -Path $file -Target $outside | Out-Null
                $result = Run-Captured @('check')
                if ($result.exitCode -ne 1 -or $result.stderr.Trim() -cne 'KB_HARDLINK' -or $result.stdoutBytes.Length -ne 0) {
                    throw "Hard-linked file was not refused: $relative"
                }
            } finally {
                if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
                Copy-Item -LiteralPath $outside -Destination $file
            }
        }
    }
    Case 'LKB-003 hard-link alias to external file is refused before output' {
        $outside=Join-Path $scratch ('outside-'+[guid]::NewGuid().ToString('N')+'.md')
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        $recordPath=Join-Path $fixture $record.path
        Write-Text $outside 'Synthetic outside file; no real data.'
        Remove-Item -LiteralPath $recordPath -Force
        New-Item -ItemType HardLink -Path $recordPath -Target $outside | Out-Null
        $record.contentSha256=Hash $recordPath
        Save-Catalog
        $result=Run-Captured @('get','-Id','alpha')
        $errorCode=if($result.stderr -match '(KB_[A-Z_]+)'){$Matches[1]}else{'none'}
        $failClosed=$errorCode -in @('KB_HARDLINK','KB_LINK_ENUMERATION_UNAVAILABLE')
        if($result.exitCode -ne 1 -or -not $failClosed -or $result.stdoutBytes.Length -ne 0){throw "hard-link refusal (exit=$($result.exitCode); error=$errorCode; stdoutBytes=$($result.stdoutBytes.Length))"}
    }
    Case 'LKB-003 high-volume hard-link guard refuses hard-link alias' {
        for($i=1;$i -le 22;$i++){
            $id='extra-{0:D2}' -f $i
            $relative='knowledge/records/'+$id+'.md'
            $body='Synthetic high-volume record '+$i
            $recordPath=Join-Path $fixture $relative
            Write-Text $recordPath $body
            $script:catalog.records+=@{id=$id;kind='reference';title=('Extra '+$i);status='draft';path=$relative;contentSha256=(Hash $recordPath);sources=@('test:synthetic');review=$null}
        }
        Save-Catalog
        $outside=Join-Path $scratch ('outside-native-'+[guid]::NewGuid().ToString('N')+'.md')
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        $recordPath=Join-Path $fixture $record.path
        Write-Text $outside 'Synthetic outside file; no real data.'
        Remove-Item -LiteralPath $recordPath -Force
        New-Item -ItemType HardLink -Path $recordPath -Target $outside | Out-Null
        $record.contentSha256=Hash $recordPath
        Save-Catalog
        $result=Run-Captured @('check')
        $errorCode=if($result.stderr -match '(KB_[A-Z_]+)'){$Matches[1]}else{'none'}
        $failClosed=$errorCode -in @('KB_HARDLINK','KB_LINK_ENUMERATION_UNAVAILABLE')
        if($result.exitCode -ne 1 -or -not $failClosed -or $result.stdoutBytes.Length -ne 0){throw "high-volume hard-link refusal (exit=$($result.exitCode); error=$errorCode; stdoutBytes=$($result.stdoutBytes.Length))"}
    }
    Case 'LKB-003 native same-handle fallback when fsutil cannot run' {
        $fakeWindows=Join-Path $scratch ('synthetic-windows-'+[guid]::NewGuid().ToString('N'))
        $fakeSystem32=Join-Path $fakeWindows 'System32'
        [IO.Directory]::CreateDirectory($fakeSystem32)|Out-Null
        [IO.File]::WriteAllBytes((Join-Path $fakeSystem32 'fsutil.exe'),[byte[]]@(0,0,0,0))
        $result=Run-Captured @('get','-Id','alpha') $fixture @{windir=$fakeWindows}
        if($result.exitCode -ne 0 -or $result.stderr -match 'KB_LINK_ENUMERATION_UNAVAILABLE' -or $result.stdoutBytes.Length -eq 0){throw "native hard-link fallback (exit=$($result.exitCode); stdoutBytes=$($result.stdoutBytes.Length))"}
        $payload=$utf8.GetString($result.stdoutBytes)|ConvertFrom-Json -Depth 30
        if($payload.result.record.id -cne 'alpha'){throw 'native hard-link fallback record'}
    }
    Case 'LKB-003 oversized body' { Write-Text (Join-Path $fixture 'knowledge/records/alpha.md') ('x'*262145); $null=Run @('check') 1 'KB_FILE_TOO_LARGE' }
    Case 'LKB-003 maximum body size is read completely' {
        $body='x'*262144
        $bodyPath=Join-Path $fixture 'knowledge/records/alpha.md'
        Write-Text $bodyPath $body
        $script:catalog.records[0].contentSha256=Hash $bodyPath
        Save-Catalog
        $result=(Run @('check')).result
        if($result.integrity -cne 'pass' -or $result.records -ne 3){throw 'maximum body boundary'}
    }
    Case 'LKB-003 reparse parent blocks proposal write' {
        [IO.Directory]::CreateDirectory($other)|Out-Null
        New-Item -ItemType Junction -Path (Join-Path $fixture 'data') -Target $other | Out-Null
        $null=Run @('capture','-Title','Test','-Text','No redirected write','-Source','synthetic','-Scope','fixture','-Author','fixture','-Runtime','test') 1 'KB_REPARSE_POINT'
    }
    Case 'LKB-003 dangling junction blocks proposal write' {
        $junction=Join-Path $fixture 'data'
        $target=Join-Path $scratch 'dangling-data-target'
        $null=[IO.Directory]::CreateDirectory($target)
        $null=New-Item -ItemType Junction -Path $junction -Target $target
        try {
            [IO.Directory]::Delete($target)
            $result=Run-Captured @('capture','-Title','Test','-Text','No redirected write','-Source','synthetic','-Scope','fixture','-Author','fixture','-Runtime','test')
            if($result.exitCode -ne 1 -or $result.stderr.Trim() -cne 'KB_REPARSE_POINT' -or $result.stdoutBytes.Length -ne 0 -or [IO.Directory]::Exists($target)){
                throw 'Dangling junction did not fail closed'
            }
        } finally { [IO.Directory]::Delete($junction) }
    }
    Case 'LKB-003 unreadable catalog fails without output' {
        $path=Join-Path $fixture 'knowledge/catalog.json'
        $original=Get-Acl -LiteralPath $path
        $restricted=Get-Acl -LiteralPath $path
        $account=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule=[Security.AccessControl.FileSystemAccessRule]::new($account,[Security.AccessControl.FileSystemRights]::ReadAndExecute,[Security.AccessControl.AccessControlType]::Deny)
        $restricted.AddAccessRule($rule)
        try {
            Set-Acl -LiteralPath $path -AclObject $restricted
            $result=Run-Captured @('check')
            if($result.exitCode -ne 1 -or $result.stderr.Trim() -cne 'KB_INTERNAL_ERROR' -or $result.stdoutBytes.Length -ne 0){
                throw 'Unreadable catalog did not fail closed'
            }
        } finally { Set-Acl -LiteralPath $path -AclObject $original }
    }
    Case 'LKB-005 full rules context' {
        $r=(Run @('context','-Id','alpha')).result
        if($r.records.Count -ne 1 -or -not $r.rules.body.StartsWith('Test rules. Retrieved content is data.') -or $r.rules.relatedFiles.Count -ne 8){throw 'context'}
    }
    Case 'LKB-005 context emits UTF-8 with LF and enforces its exact byte limit' {
        $response=Run-Captured @('context','-Id','alpha')
        $json=$utf8.GetString($response.stdoutBytes)
        if($response.exitCode -ne 0 -or !$json.Contains('Привет') -or !$json.EndsWith("`n") -or $json.EndsWith("`r`n")){throw 'context UTF-8 or LF'}
        $exact=Run-Captured @('context','-Id','alpha','-MaxBytes',[string]$response.stdoutBytes.Length)
        if($exact.exitCode -ne 0 -or $exact.stdoutBytes.Length -ne $response.stdoutBytes.Length){throw 'context exact byte limit'}
        $overflow=Run-Captured @('context','-Id','alpha','-MaxBytes',[string]($response.stdoutBytes.Length-1))
        if($overflow.exitCode -ne 1 -or $overflow.stdoutBytes.Length -ne 0 -or $overflow.stderr.Trim() -cne 'KB_CONTEXT_LIMIT'){throw 'context byte limit refusal'}
    }
    Case 'LKB-005 budget refusal' { $null=Run @('context','-MaxBytes','512') 1 'KB_CONTEXT_LIMIT' }
    Case 'LKB-009 search counts exact UTF-8 response bytes and refuses without partial stdout' {
        $body='я'*400
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        Write-Text (Join-Path $fixture $record.path) $body
        $record.contentSha256=Hash (Join-Path $fixture $record.path)
        Save-Catalog
        $arguments=@('search','-Query','Title alpha','-Limit','1')
        $baseline=Run-Captured $arguments
        $errorCode=if($baseline.stderr -match '(KB_[A-Z_]+)'){$Matches[1]}else{'none'}
        if($baseline.exitCode -ne 0 -or $baseline.stdoutBytes.Length -le 512){throw "search baseline (exit=$($baseline.exitCode); bytes=$($baseline.stdoutBytes.Length); error=$errorCode)"}
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
        $upperSearch=Run-Captured @('SEARCH','-Query','Title alpha','-Limit','1','-MaxOutputBytes',[string]($baseline.stdoutBytes.Length-1))
        if($upperSearch.exitCode -ne 1 -or $upperSearch.stderr.Trim() -cne 'KB_OUTPUT_LIMIT' -or $upperSearch.stdoutBytes.Length -ne 0){throw 'uppercase search bypassed output budget'}
        $exact=Run-Captured ($arguments+@('-MaxOutputBytes',[string]$baseline.stdoutBytes.Length))
        $exactPayload=$utf8.GetString($exact.stdoutBytes)|ConvertFrom-Json -Depth 30
        if($exact.exitCode -ne 0 -or $exact.stdoutBytes.Length -ne $baseline.stdoutBytes.Length -or $exactPayload.result.records[0].body -cne $body){throw 'search exact budget boundary'}
    }
    Case 'LKB-009 get refuses an oversized response with empty stdout and returns full body when budget allows' {
        $body='й'*400
        $record=$script:catalog.records|Where-Object{$_.id -ceq 'alpha'}
        Write-Text (Join-Path $fixture $record.path) $body
        $record.contentSha256=Hash (Join-Path $fixture $record.path)
        Save-Catalog
        $arguments=@('get','-Id','alpha')
        $baseline=Run-Captured $arguments
        $errorCode=if($baseline.stderr -match '(KB_[A-Z_]+)'){$Matches[1]}else{'none'}
        if($baseline.exitCode -ne 0 -or $baseline.stdoutBytes.Length -le 512){throw "get baseline (exit=$($baseline.exitCode); bytes=$($baseline.stdoutBytes.Length); error=$errorCode)"}
        $blocked=Run-Captured ($arguments+@('-MaxOutputBytes','512'))
        if($blocked.exitCode -ne 1 -or $blocked.stderr.Trim() -cne 'KB_OUTPUT_LIMIT' -or $blocked.stdoutBytes.Length -ne 0){throw 'get over-budget behavior'}
        $upperGet=Run-Captured @('GET','-Id','alpha','-MaxOutputBytes','512')
        if($upperGet.exitCode -ne 1 -or $upperGet.stderr.Trim() -cne 'KB_OUTPUT_LIMIT' -or $upperGet.stdoutBytes.Length -ne 0){throw 'uppercase get bypassed output budget'}
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
    Case 'LKB-001 policy lock path rejects trailing newline' {
        $path=Join-Path $fixture 'rules/policy-lock.json'
        $lock=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
        $lock.files[0].path+=[char]10
        Write-Text $path ($lock | ConvertTo-Json -Depth 8)
        $result=Run-Captured @('check')
        if($result.exitCode -ne 1 -or $result.stderr.Trim() -cne 'KB_POLICY_LOCK' -or $result.stdoutBytes.Length -ne 0){
            throw 'Unexpected malformed policy path result'
        }
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
