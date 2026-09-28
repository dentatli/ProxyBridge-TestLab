Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ProcessAdapter.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProtocolWorker.psm1')
Import-Module (Join-Path $PSScriptRoot 'ProxyBridgeEvidence.psm1')

$script:ProtocolUtf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:MaxProtocolProcessTimeoutMs = 600000

function Get-ProtocolProperty {
    param($Object, [string]$Name, $Default = $null, [switch]$Required)
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    if ($Required) { throw "PROTOCOL_CONTRACT_MISSING_$($Name.ToUpperInvariant())" }
    return $Default
}

function Get-ProtocolEnvironmentValue {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment, [string]$Name)
    if (-not $Environment.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace([string]$Environment[$Name])) { throw "PROTOCOL_ENVIRONMENT_MISSING_$Name" }
    return [string]$Environment[$Name]
}

function Copy-ProtocolObject {
    param($Value)
    if ($null -eq $Value) { return [pscustomobject]@{} }
    return ($Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function New-ProtocolExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [Parameter(Mandatory)][string]$RunId,
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][string]$EvidenceDirectory,
        [Parameter(Mandatory)]$RuntimeContracts,
        [Parameter(Mandatory)][int]$OperationTimeoutCapMs,
        [Parameter(Mandatory)][int]$ProcessExitGraceMs,
        [int]$ActualPathTimeoutMs = 2000,
        [switch]$PlanningOnly
    )
    if ([string](Get-ProtocolProperty $Scenario 'executor_kind' 'native-client') -ne 'protocol-worker') { throw 'PROTOCOL_EXECUTOR_REQUIRED' }
    if ($Attempt -lt 1 -or $Attempt -gt 1000) { throw 'PROTOCOL_ATTEMPT_INVALID' }
    if ($OperationTimeoutCapMs -lt 1 -or $ProcessExitGraceMs -lt 1 -or $ActualPathTimeoutMs -lt 1) { throw 'PROTOCOL_TIMEOUT_INVALID' }
    $worker = Get-ProtocolProperty $Scenario 'protocol_worker' $null -Required
    $action = ([string](Get-ProtocolProperty $Scenario.client 'expected_action' $null -Required)).ToUpperInvariant()
    if (@('DIRECT','BLOCK','PROXY') -notcontains $action) { throw 'PROTOCOL_ACTION_INVALID' }
    $transport = ([string](Get-ProtocolProperty $worker 'transport' (Get-ProtocolProperty $Scenario.client 'protocol' '') )).ToUpperInvariant()
    if (@('TCP','UDP') -notcontains $transport) { throw 'PROTOCOL_TRANSPORT_INVALID' }
    $operationTimeoutMs = [Math]::Min([int]$Scenario.timeout_ms, $OperationTimeoutCapMs)
    if ($operationTimeoutMs -lt 1) { throw 'PROTOCOL_OPERATION_TIMEOUT_INVALID' }
    $processTimeoutMs = [long]$operationTimeoutMs + [long]$ProcessExitGraceMs
    if ($processTimeoutMs -le $operationTimeoutMs -or $processTimeoutMs -gt $script:MaxProtocolProcessTimeoutMs) { throw 'PROTOCOL_PROCESS_TIMEOUT_INVALID' }

    $attemptId = "attempt-$Attempt"
    $flowId = 'flow-1'
    $suffix = $(if ($Attempt -eq 1) { '' } else { "-attempt-$Attempt" })
    $parameters = Copy-ProtocolObject (Get-ProtocolProperty $worker 'parameters' $null -Required)
    $normalizedRemotePort = 0
    if (-not [int]::TryParse([string](Get-ProtocolProperty $parameters 'remote_port' ''), [ref]$normalizedRemotePort) -or $normalizedRemotePort -lt 1 -or $normalizedRemotePort -gt 65535) { throw 'PROTOCOL_REMOTE_PORT_INVALID' }
    $parameters.remote_port = $normalizedRemotePort
    $pluginId = [string](Get-ProtocolProperty $worker 'plugin_id' $null -Required)
    $isBrowser = $pluginId -eq 'browser-worker'
    $browserBasename = ''
    if ($isBrowser) {
        if ([string](Get-ProtocolProperty $worker 'protocol_family' '') -ne 'browser-web' -or $transport -ne 'TCP' -or [string](Get-ProtocolProperty $worker 'evidence_profile_id' '') -ne 'browser-session') { throw 'BROWSER_PROTOCOL_CONTRACT_INVALID' }
        if ($action -ne 'DIRECT') { throw 'BROWSER_ACTION_INVALID' }
        foreach ($identity in @($RunId,[string]$Scenario.scenario_id,$attemptId,$flowId)) {
            if ($identity -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') { throw 'BROWSER_ORIGIN_IDENTITY_INVALID' }
        }
        $browserExecutable = Get-ProtocolEnvironmentValue $Environment 'PB_BROWSER_EXE'
        $browserImageHash = (Get-ProtocolEnvironmentValue $Environment 'PB_EXPECTED_BROWSER_SHA256').ToLowerInvariant()
        $browserBasename = Get-ProtocolEnvironmentValue $Environment 'PB_BROWSER_APPLICATION_BASENAME'
        $browserIdentity = Get-ProtocolEnvironmentValue $Environment 'PB_BROWSER_APPLICATION_FULLPATH'
        $browserVersion = Get-ProtocolEnvironmentValue $Environment 'PB_BROWSER_VERSION'
        if ($browserImageHash -notmatch '^[0-9a-f]{64}$') { throw 'BROWSER_IMAGE_HASH_INVALID' }
        try {
            $browserExecutable = [System.IO.Path]::GetFullPath($browserExecutable)
            $browserIdentity = [System.IO.Path]::GetFullPath($browserIdentity)
        }
        catch { throw 'BROWSER_AUTOMATIC_IDENTITY_INVALID' }
        if (-not [string]::Equals($browserExecutable,$browserIdentity,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'BROWSER_AUTOMATIC_IDENTITY_MISMATCH' }
        if (-not [string]::Equals([System.IO.Path]::GetFileName($browserExecutable),$browserBasename,[System.StringComparison]::OrdinalIgnoreCase) -or $browserBasename -ne [System.IO.Path]::GetFileName($browserBasename)) { throw 'BROWSER_AUTOMATIC_BASENAME_MISMATCH' }
        $remoteHost = [string](Get-ProtocolProperty $parameters 'remote_host' $null -Required)
        $urlHost = $(if ($remoteHost.Contains(':')) { "[$remoteHost]" } else { $remoteHost })
        $originRoot = "/browser-origin/v1/runs/$RunId/scenarios/$([string]$Scenario.scenario_id)/attempts/$attemptId/flows/$flowId"
        $identityJson = '{"attempt_id":"' + $attemptId + '","flow_id":"' + $flowId + '","run_id":"' + $RunId + '","scenario_id":"' + [string]$Scenario.scenario_id + '"}'
        $downloadBody = "proxybridge-testlab-browser-download-v1`n$identityJson`n"
        $evidenceRoot = [System.IO.Path]::GetFullPath($EvidenceDirectory)
        $parameters = [pscustomobject][ordered]@{
            remote_host=$remoteHost;remote_port=$normalizedRemotePort
            browser_executable=$browserExecutable;expected_browser_sha256=$browserImageHash
            expected_browser_identity=$browserIdentity;expected_browser_version=$browserVersion;browser_arguments=@()
            target_url="http://$urlHost`:$normalizedRemotePort$originRoot/page"
            profile_dir=[System.IO.Path]::GetFullPath((Join-Path $evidenceRoot "browser-profile$suffix"))
            download_dir=[System.IO.Path]::GetFullPath((Join-Path $evidenceRoot "browser-downloads$suffix"))
            expected_content_sha256=(Get-ProtocolMockSha256 $downloadBody)
            expected_response_status=200;expected_negotiated_protocol='http/1.1';actual_path_timeout_ms=$ActualPathTimeoutMs
        }
    }
    $expected = Copy-ProtocolObject (Get-ProtocolProperty $worker 'expected' ([pscustomobject]@{}))
    $expected | Add-Member -NotePropertyName outcome -NotePropertyValue $(if ($action -eq 'BLOCK') { 'no-response' } else { 'response' }) -Force
    $workerPlan = New-ProtocolWorkerPlan -RunId $RunId -ScenarioId ([string]$Scenario.scenario_id) -AttemptId $attemptId -FlowId $flowId `
        -PluginId $pluginId -ProtocolFamily ([string](Get-ProtocolProperty $worker 'protocol_family' $null -Required)) `
        -Transport $transport -OperationTimeoutMs $operationTimeoutMs -Parameters $parameters -Expected $expected `
        -Capabilities @($Scenario.requires | ForEach-Object { [string]$_ }) -RuntimeContracts $RuntimeContracts

    if (-not (Test-Path -LiteralPath $EvidenceDirectory -PathType Container)) { $null = New-Item -ItemType Directory -Path $EvidenceDirectory -Force }
    $planPath = Join-Path $EvidenceDirectory ("protocol-worker-plan$suffix.json")
    $clientJsonlPath = Join-Path $EvidenceDirectory ("client$suffix.jsonl")
    $serverJsonlPath = Join-Path $EvidenceDirectory ("protocol-server$suffix.jsonl")
    Write-ProtocolWorkerPlan -Plan $workerPlan -Path $planPath -RuntimeContracts $RuntimeContracts

    $artifactDefinitions = @(
        @('python','PB_PROTOCOL_PYTHON_EXE','PB_EXPECTED_PROTOCOL_PYTHON_SHA256'),
        @('entrypoint','PB_PROTOCOL_WORKER_ENTRYPOINT','PB_EXPECTED_PROTOCOL_WORKER_SHA256'),
        @('manifest','PB_PROTOCOL_WORKER_MANIFEST','PB_EXPECTED_PROTOCOL_MANIFEST_SHA256'),
        @('evidence-contract','PB_PROTOCOL_EVIDENCE_CONTRACT','PB_EXPECTED_PROTOCOL_EVIDENCE_CONTRACT_SHA256'),
        @('ca','PB_PROTOCOL_CA_PEM','PB_EXPECTED_PROTOCOL_CA_SHA256')
    )
    $artifacts = [System.Collections.Generic.List[object]]::new()
    foreach ($definition in $artifactDefinitions) {
        $path = $(if ($Environment.ContainsKey($definition[1])) { [string]$Environment[$definition[1]] } elseif ($PlanningOnly) { "<automatic:$($definition[1])>" } else { throw "PROTOCOL_ENVIRONMENT_MISSING_$($definition[1])" })
        $hash = $(if ($Environment.ContainsKey($definition[2])) { [string]$Environment[$definition[2]] } elseif ($PlanningOnly) { ('0' * 64) } else { throw "PROTOCOL_ENVIRONMENT_MISSING_$($definition[2])" })
        $artifacts.Add([pscustomobject][ordered]@{ id=$definition[0]; path=$path; expected_sha256=$hash })
    }
    $byId = @{}
    foreach ($artifact in $artifacts) { $byId[[string]$artifact.id] = $artifact }
    $processPlan = [pscustomobject][ordered]@{
        executable=[string]$byId.python.path
        arguments=@('-I','-B',[string]$byId.entrypoint.path,'--plan',$planPath,'--output-jsonl',$clientJsonlPath,'--manifest',[string]$byId.manifest.path)
        process_timeout_ms=[int]$processTimeoutMs
        actual_path_timeout_ms=$ActualPathTimeoutMs
    }
    $remoteHost = [string](Get-ProtocolProperty $parameters 'remote_host' $null -Required)
    $remotePort = [int](Get-ProtocolProperty $parameters 'remote_port' 0 -Required)
    if ([string]::IsNullOrWhiteSpace($remoteHost) -or $remotePort -lt 1 -or $remotePort -gt 65535) { throw 'PROTOCOL_REMOTE_ENDPOINT_INVALID' }
    return [pscustomobject][ordered]@{
        schema_version=1; executor='protocol-worker'; scenario_id=[string]$Scenario.scenario_id; run_id=$RunId; attempt_id=$attemptId
        flow_id=$flowId; expected_action=$action; expected_outcome=$(if($action -eq 'BLOCK'){'no-response'}else{'response'})
        evidence_profile_id=[string](Get-ProtocolProperty $worker 'evidence_profile_id' $null -Required)
        expected_process=$(if($isBrowser){$browserBasename}elseif($PlanningOnly){'python.exe'}else{[System.IO.Path]::GetFileName([string]$byId.python.path)})
        remote_host=$remoteHost; remote_port=$remotePort; operation_timeout_ms=$operationTimeoutMs; process_timeout_ms=[int]$processTimeoutMs
        process_exit_grace_ms=$ProcessExitGraceMs; actual_path_timeout_ms=$ActualPathTimeoutMs
        timeout_budget_components=[pscustomobject][ordered]@{operation_count=1;operation_timeout_ms=$operationTimeoutMs;operation_budget_ms=$operationTimeoutMs;process_exit_grace_ms=$ProcessExitGraceMs;total_ms=[int]$processTimeoutMs;maximum_ms=$script:MaxProtocolProcessTimeoutMs}
        worker_plan=$workerPlan; worker_plan_path=$planPath; client_jsonl_path=$clientJsonlPath; server_jsonl_path=$serverJsonlPath
        evidence_contract_path=[string]$byId.'evidence-contract'.path; artifacts=$artifacts.ToArray(); process_plan=$processPlan
    }
}

function Invoke-ProtocolExecutionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)]$RuntimeContracts,
        [Parameter(Mandatory)]$ProcessAdapter,
        [switch]$AllowProductRuntime
    )
    if ([string]$Plan.executor -ne 'protocol-worker') { throw 'PROTOCOL_EXECUTION_PLAN_REQUIRED' }
    if ($null -eq $ProcessAdapter.PSObject.Properties['VerifyExecutable']) { throw 'PROTOCOL_ADAPTER_MISSING_VERIFY_EXECUTABLE' }
    $verifications = [System.Collections.Generic.List[object]]::new()
    foreach ($artifact in @($Plan.artifacts)) {
        if ([string]$artifact.expected_sha256 -notmatch '^[A-Fa-f0-9]{64}$') { throw "PROTOCOL_PRELAUNCH_HASH_INVALID_$($artifact.id)" }
        $verified = & $ProcessAdapter.VerifyExecutable ([string]$artifact.path) ([string]$artifact.expected_sha256)
        $verifications.Add([pscustomobject][ordered]@{id=[string]$artifact.id;path_verified=[bool]$verified.path_verified;hash_verified=[bool]$verified.hash_verified;status=[string]$verified.status})
        if (-not [bool]$verified.path_verified) { throw "PROTOCOL_PRELAUNCH_PATH_MISSING_$($artifact.id)" }
        if (-not [bool]$verified.hash_verified) { throw "PROTOCOL_PRELAUNCH_HASH_FAILED_$($artifact.id)" }
    }
    $processResult = Invoke-ProcessPlan -Plan $Plan.process_plan -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime
    $probeStatus = [string]$processResult.actual_path_probe_status
    $actualPathRequired = $probeStatus -ne 'PROCESS_EXITED'
    if ($probeStatus -eq 'QUERY_TIMEOUT') { throw 'PROTOCOL_PATH_QUERY_TIMEOUT' }
    if ($probeStatus -eq 'PATH_OBTAINED') {
        try {
            $expectedPath = [System.IO.Path]::GetFullPath([string]$Plan.process_plan.executable).TrimEnd('\')
            $actualPath = [System.IO.Path]::GetFullPath([string]$processResult.actual_path).TrimEnd('\')
            if (-not [string]::Equals($expectedPath,$actualPath,[System.StringComparison]::OrdinalIgnoreCase)) { throw 'PROTOCOL_PATH_VERIFICATION_FAILED' }
        }
        catch { if ($_.Exception.Message -eq 'PROTOCOL_PATH_VERIFICATION_FAILED') { throw }; throw 'PROTOCOL_PATH_VERIFICATION_FAILED' }
    }
    elseif ($probeStatus -ne 'PROCESS_EXITED') { throw 'PROTOCOL_PATH_PROBE_STATUS_INVALID' }

    $records = @()
    if (-not [bool]$processResult.timed_out -and (Test-Path -LiteralPath ([string]$Plan.client_jsonl_path) -PathType Leaf)) {
        $records = @(Read-ProtocolWorkerEvidence -Path ([string]$Plan.client_jsonl_path) -Plan $Plan.worker_plan -RuntimeContracts $RuntimeContracts -EvidenceContractPath ([string]$Plan.evidence_contract_path))
    }
    $stdout = ([string]$processResult.stdout).Trim()
    $stderr = ([string]$processResult.stderr).Trim()
    $stdoutValid = $stdout -match '^PROTOCOL_WORKER_OK records=([1-9][0-9]*)$' -and [int]$Matches[1] -eq $records.Count
    return [pscustomobject][ordered]@{
        exit_code=[int]$processResult.exit_code;timed_out=[bool]$processResult.timed_out;pid=[int]$processResult.pid
        actual_path=[string]$processResult.actual_path;actual_path_probe_status=$probeStatus
        actual_path_probe_attempts=[int]$processResult.actual_path_probe_attempts;actual_path_probe_elapsed_ms=[int]$processResult.actual_path_probe_elapsed_ms
        actual_path_required=[bool]$actualPathRequired;prelaunch_verified=(@($verifications|Where-Object{-not $_.path_verified -or -not $_.hash_verified}).Count -eq 0)
        artifact_verification=$verifications.ToArray();stdout_status_valid=$stdoutValid;stderr_empty=[string]::IsNullOrWhiteSpace($stderr)
        records=$records;raw_records=$records;canonical_records=$records;jsonl_path=[string]$Plan.client_jsonl_path
        run_mode=$(if([bool]$ProcessAdapter.is_mock){'mock'}else{'real'})
    }
}

function ConvertTo-ProtocolPosixSingleQuoted {
    param([Parameter(Mandatory)][string]$Value)
    $quote = [string][char]39
    return $quote + $Value.Replace($quote, ($quote + [string][char]92 + $quote + $quote)) + $quote
}

function Get-ProtocolSshBaseArguments {
    param([System.Collections.Generic.IDictionary[string, string]]$Environment)
    $hostName=Get-ProtocolEnvironmentValue $Environment 'PB_SSH_HOST';$userName=Get-ProtocolEnvironmentValue $Environment 'PB_SSH_USER'
    $keyPath=Get-ProtocolEnvironmentValue $Environment 'PB_SSH_KEY';$knownHosts=Get-ProtocolEnvironmentValue $Environment 'PB_SSH_KNOWN_HOSTS'
    if($hostName -notmatch '^[A-Za-z0-9][A-Za-z0-9._:-]*$'){throw 'PROTOCOL_SSH_HOST_INVALID'}
    if($userName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$'){throw 'PROTOCOL_SSH_USER_INVALID'}
    $port=0;if(-not [int]::TryParse((Get-ProtocolEnvironmentValue $Environment 'PB_SSH_PORT'),[ref]$port)-or $port-lt 1-or $port-gt 65535){throw 'PROTOCOL_SSH_PORT_INVALID'}
    return @('-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','StrictHostKeyChecking=yes','-o',("UserKnownHostsFile=$knownHosts"),'-p',[string]$port,'-i',$keyPath,("$userName@$hostName"))
}

function New-ProtocolLogCursorPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,[string]$SshExecutablePath='ssh.exe',[int]$TimeoutMs=10000)
    if($TimeoutMs-lt 1){throw 'PROTOCOL_SSH_TIMEOUT_INVALID'}
    $log=Get-ProtocolEnvironmentValue $Environment 'PB_VPS_PROTOCOL_LOG';$quoted=ConvertTo-ProtocolPosixSingleQuoted $log
    $inner="inode=`$(stat -c %i -- $quoted) && size=`$(stat -c %s -- $quoted) && printf 'INODE=%s\nOFFSET=%s\n' `"`$inode`" `"`$size`""
    $command="sudo -n -u proxybridge-testlab sh -c $(ConvertTo-ProtocolPosixSingleQuoted $inner)"
    return [pscustomobject][ordered]@{mode='protocol-log-cursor';process_plan=[pscustomobject][ordered]@{executable=$SshExecutablePath;arguments=@(Get-ProtocolSshBaseArguments $Environment)+@($command);timeout_ms=$TimeoutMs}}
}

function Invoke-ProtocolLogCursorPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$ProcessAdapter,[switch]$AllowProductRuntime)
    $result=Invoke-ProcessPlan -Plan $Plan.process_plan -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime
    if([bool]$result.timed_out){throw 'PROTOCOL_CURSOR_TIMEOUT'};if([int]$result.exit_code-ne 0){throw 'PROTOCOL_CURSOR_FAILED'}
    $values=@{};foreach($line in @(([string]$result.stdout)-split "`r?`n")){if($line-match '^(INODE|OFFSET)=([0-9]+)$'){$values[$Matches[1]]=$Matches[2]}}
    if(-not $values.ContainsKey('INODE')-or-not $values.ContainsKey('OFFSET')){throw 'PROTOCOL_CURSOR_OUTPUT_INVALID'}
    $offset=0L;if(-not [long]::TryParse([string]$values.OFFSET,[ref]$offset)-or $offset-lt 0){throw 'PROTOCOL_CURSOR_OFFSET_INVALID'}
    return [pscustomobject][ordered]@{inode=[string]$values.INODE;offset=$offset;captured_at_utc=[datetime]::UtcNow.ToString('o')}
}

function New-ProtocolServerCollectionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Collections.Generic.IDictionary[string, string]]$Environment,
        [Parameter(Mandatory)]$ExecutionPlan,
        [Parameter(Mandatory)]$Cursor,
        [string]$SshExecutablePath='ssh.exe',[int]$TimeoutMs=10000
    )
    if([string]$Cursor.inode-notmatch '^[0-9]+$'-or[long]$Cursor.offset-lt 0){throw 'PROTOCOL_CURSOR_INVALID'}
    $log=Get-ProtocolEnvironmentValue $Environment 'PB_VPS_PROTOCOL_LOG';$quotedLog=ConvertTo-ProtocolPosixSingleQuoted $log
    $quotedRun=ConvertTo-ProtocolPosixSingleQuoted ([string]$ExecutionPlan.run_id);$start=[long]$Cursor.offset+1
    $inner="inode=`$(stat -c %i -- $quotedLog) && [ `"`$inode`" = '$($Cursor.inode)' ] && size=`$(stat -c %s -- $quotedLog) && [ `"`$size`" -ge '$($Cursor.offset)' ] && tail -c +$start -- $quotedLog | grep -F -- $quotedRun; rc=`$?; if [ `$rc -eq 1 ]; then exit 0; else exit `$rc; fi"
    $command="sudo -n -u proxybridge-testlab sh -c $(ConvertTo-ProtocolPosixSingleQuoted $inner)"
    return [pscustomobject][ordered]@{mode='protocol-log-collection';output_path=[string]$ExecutionPlan.server_jsonl_path;process_plan=[pscustomobject][ordered]@{executable=$SshExecutablePath;arguments=@(Get-ProtocolSshBaseArguments $Environment)+@($command);timeout_ms=$TimeoutMs}}
}

function Read-BrowserServerEvidenceSet {
    param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$ExecutionPlan)
    if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'PROTOCOL_SERVER_EVIDENCE_MISSING'}
    $bytes=[System.IO.File]::ReadAllBytes($Path)
    if($bytes.Length-ge 3-and$bytes[0]-eq 0xEF-and$bytes[1]-eq 0xBB-and$bytes[2]-eq 0xBF){throw 'PROTOCOL_SERVER_EVIDENCE_BOM_FORBIDDEN'}
    $required=@('schema_version','run_id','scenario_id','attempt_id','flow_id','phase','sequence','event','resource','browser_session_id','request_path','content_sha256','content_length','result','timestamp_utc','monotonic_ms','process_id','socket_id','protocol_family','transport','local_ip','local_port','remote_ip','remote_port','negotiated_protocol','status_code')
    $records=[System.Collections.Generic.List[object]]::new()
    foreach($line in [System.IO.File]::ReadAllLines($Path,[System.Text.Encoding]::UTF8)){
        if([string]::IsNullOrWhiteSpace($line)){continue}
        try{$record=$line|ConvertFrom-Json}catch{throw 'PROTOCOL_SERVER_EVIDENCE_JSON_INVALID'}
        $identityMatches=$true
        foreach($field in @('run_id','scenario_id','attempt_id','flow_id')){
            if($null-eq$record.PSObject.Properties[$field]-or[string]$record.$field-ne[string]$ExecutionPlan.worker_plan.$field){$identityMatches=$false;break}
        }
        if(-not$identityMatches){continue}
        foreach($field in $required){if($null-eq$record.PSObject.Properties[$field]){throw "BROWSER_SERVER_EVIDENCE_FIELD_MISSING: $field"}}
        if([int]$record.schema_version-ne 1-or[string]$record.phase-ne'server'-or[string]$record.protocol_family-ne'browser-origin'-or[string]$record.transport-ne'TCP'){throw 'BROWSER_SERVER_EVIDENCE_CONTRACT_INVALID'}
        if([string]$record.content_sha256-notmatch'^[0-9a-fA-F]{64}$'){throw 'BROWSER_SERVER_EVIDENCE_HASH_INVALID'}
        $records.Add($record)
    }
    return $records.ToArray()
}

function Invoke-ProtocolServerCollectionPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)]$ExecutionPlan,[Parameter(Mandatory)]$RuntimeContracts,[Parameter(Mandatory)]$ProcessAdapter,[switch]$AllowProductRuntime)
    $result=Invoke-ProcessPlan -Plan $Plan.process_plan -ProcessAdapter $ProcessAdapter -AllowProductRuntime:$AllowProductRuntime
    if([bool]$result.timed_out){throw 'PROTOCOL_SERVER_COLLECTION_TIMEOUT'};if([int]$result.exit_code-ne 0){throw 'PROTOCOL_SERVER_COLLECTION_FAILED'}
    [System.IO.File]::WriteAllText([string]$Plan.output_path,[string]$result.stdout,$script:ProtocolUtf8NoBom)
    $records=$(if([string]$ExecutionPlan.evidence_profile_id-eq'browser-session'){
        @(Read-BrowserServerEvidenceSet -Path ([string]$Plan.output_path) -ExecutionPlan $ExecutionPlan)
    }else{
        @(Read-ProtocolServerEvidenceSet -Path ([string]$Plan.output_path) -Plan $ExecutionPlan.worker_plan -RuntimeContracts $RuntimeContracts -EvidenceContractPath ([string]$ExecutionPlan.evidence_contract_path))
    })
    return [pscustomobject][ordered]@{capture_complete=$true;records=$records;record_count=$records.Count;output_path=[string]$Plan.output_path;timed_out=$false;exit_code=[int]$result.exit_code}
}

function Test-ProtocolJsonInteger {
    param($Value,[long]$Minimum)
    if($null-eq$Value-or$Value-is[bool]){return $false}
    $isInteger=$Value-is[byte]-or$Value-is[sbyte]-or$Value-is[int16]-or$Value-is[uint16]-or$Value-is[int32]-or$Value-is[uint32]-or$Value-is[int64]-or$Value-is[uint64]
    return $isInteger-and[decimal]$Value-ge[decimal]$Minimum
}

function Test-BrowserProtocolScenarioAssertions {
    param($Scenario,$ExecutionPlan,$ClientResult,[object[]]$ServerRecords,[object[]]$ProxyBridgeRecords,$EvidenceContext,[string]$RunMode)
    $product=[System.Collections.Generic.List[string]]::new()
    $harness=[System.Collections.Generic.List[string]]::new()
    $missing=[System.Collections.Generic.List[string]]::new()
    $contamination=[System.Collections.Generic.List[string]]::new()
    if([bool]$ClientResult.timed_out){$harness.Add('browser worker timeout')}
    if(-not[bool]$ClientResult.prelaunch_verified){$harness.Add('browser controller prelaunch verification incomplete')}
    if(-not[bool]$ClientResult.stdout_status_valid){$harness.Add('browser worker status output invalid')}
    if(-not[bool]$ClientResult.stderr_empty){$harness.Add('browser worker stderr is not empty')}
    if([string]$ExecutionPlan.expected_action-ne'DIRECT'){$harness.Add('browser scenario action is not DIRECT')}

    $clientRecords=@($ClientResult.records)
    if($clientRecords.Count-ne 1){$harness.Add("browser client completion count actual=$($clientRecords.Count) expected=1")}
    $client=$(if($clientRecords.Count-eq 1){$clientRecords[0]}else{$null})
    $verifiedPids=[System.Collections.Generic.HashSet[int]]::new()
    $clientContractValid=$null-ne$client
    $cleanupVerified=$false
    if($null-ne$client){
        $requiredClient=@('run_id','scenario_id','attempt_id','flow_id','phase','sequence','event','process_id','protocol_family','transport','payload_sha256','result','browser_identity','browser_version','navigation_url_digest','negotiated_protocol','response_status','content_sha256','browser_executable_requested','browser_executable_observed','browser_image_sha256','browser_image_sha256_verified','browser_process_tree_pids','profile_id','actual_path_probe_status','actual_path_probe_attempts','actual_path_probe_elapsed_ms','process_tree_cleaned')
        foreach($field in $requiredClient){if($null-eq$client.PSObject.Properties[$field]){$harness.Add("browser client evidence field missing: $field");$clientContractValid=$false}}
    }
    if($clientContractValid){
        foreach($field in @('run_id','scenario_id','attempt_id','flow_id')){if([string]$client.$field-ne[string]$ExecutionPlan.worker_plan.$field){$contamination.Add("browser client identity mismatch: $field")}}
        if([string]$client.phase-ne'client'-or[int]$client.sequence-ne 1-or[string]$client.event-ne'BROWSER_CANARY_COMPLETED'-or[string]$client.protocol_family-ne'browser-web'-or[string]$client.transport-ne'TCP'){$harness.Add('browser client canonical completion invalid')}
        $parameters=$ExecutionPlan.worker_plan.parameters
        if([string]$client.browser_executable_requested-ne[string]$parameters.browser_executable){$contamination.Add('browser requested image evidence mismatch')}
        if([string]::IsNullOrWhiteSpace([string]$client.browser_executable_observed)){$harness.Add('browser observed image evidence missing')}
        else{
            try{
                $observed=[System.IO.Path]::GetFullPath([string]$client.browser_executable_observed)
                $requested=[System.IO.Path]::GetFullPath([string]$parameters.browser_executable)
                if(-not[string]::Equals($observed,$requested,[System.StringComparison]::OrdinalIgnoreCase)){$contamination.Add('browser observed image does not match requested image')}
                if(-not[string]::Equals([System.IO.Path]::GetFileName($observed),[string]$ExecutionPlan.expected_process,[System.StringComparison]::OrdinalIgnoreCase)){$contamination.Add('browser observed image basename does not match route rule')}
            }catch{$harness.Add('browser observed image path invalid')}
        }
        if([string]$client.browser_image_sha256-ne[string]$parameters.expected_browser_sha256){$contamination.Add('browser image hash identity mismatch')}
        $imageHashVerified=$client.browser_image_sha256_verified-is[bool]-and$client.browser_image_sha256_verified-eq$true
        if(-not$imageHashVerified){$harness.Add('browser image hash verification incomplete')}
        if([string]$client.browser_identity-ne[string]$parameters.expected_browser_identity){$contamination.Add('browser image identity mismatch')}
        if([string]$client.browser_version-ne[string]$parameters.expected_browser_version){$contamination.Add('browser version identity mismatch')}
        $expectedNavigationDigest=Get-ProtocolMockSha256 ([string]$parameters.target_url)
        if([string]$client.navigation_url_digest-notmatch'^[0-9a-f]{64}$'){$harness.Add('browser navigation URL digest invalid')}
        elseif([string]$client.navigation_url_digest-ne$expectedNavigationDigest){$contamination.Add('browser navigation URL identity mismatch')}
        $expectedProfileId=Get-ProtocolMockSha256 ([string]$parameters.profile_dir)
        if([string]$client.profile_id-notmatch'^[0-9a-f]{64}$'){$harness.Add('browser profile identity invalid')}
        elseif([string]$client.profile_id-ne$expectedProfileId){$contamination.Add('browser isolated profile identity mismatch')}
        if([string]$client.actual_path_probe_status-ne'PATH_OBTAINED'){$harness.Add('browser observed path probe status invalid')}
        if(-not(Test-ProtocolJsonInteger $client.actual_path_probe_attempts 1)){$harness.Add('browser observed path probe attempts invalid')}
        if(-not(Test-ProtocolJsonInteger $client.actual_path_probe_elapsed_ms 0)){$harness.Add('browser observed path probe elapsed invalid')}
        if([string]$client.content_sha256-ne[string]$parameters.expected_content_sha256-or[string]$client.payload_sha256-ne[string]$parameters.expected_content_sha256){$product.Add('browser download content mismatch')}
        if([int]$client.response_status-ne[int]$parameters.expected_response_status){$product.Add('browser response status mismatch')}
        if([string]$client.negotiated_protocol-ne[string]$parameters.expected_negotiated_protocol){$product.Add('browser negotiated protocol mismatch')}
        if([string]$client.result-ne'PASS'){$product.Add('browser client outcome mismatch')}
        $cleanupVerified=$client.process_tree_cleaned-is[bool]-and$client.process_tree_cleaned-eq$true
        if(-not$cleanupVerified){$harness.Add('browser process tree cleanup incomplete')}
        $rootPid=0
        if(-not[int]::TryParse([string]$client.process_id,[ref]$rootPid)-or$rootPid-lt 1){$harness.Add('browser root process id invalid')}
        foreach($value in @($client.browser_process_tree_pids)){
            $pidValue=0
            if(-not[int]::TryParse([string]$value,[ref]$pidValue)-or$pidValue-lt 1){$harness.Add('browser process tree pid invalid');continue}
            if(-not$verifiedPids.Add($pidValue)){$contamination.Add('duplicate browser process tree pid')}
        }
        if($verifiedPids.Count-eq 0-or($rootPid-gt 0-and-not$verifiedPids.Contains($rootPid))){$harness.Add('browser process tree does not contain its observed root')}
    }

    $serverCapture=[bool](Get-ProtocolProperty $EvidenceContext 'server_capture_complete' $false)
    $routeCapture=[bool](Get-ProtocolProperty $EvidenceContext 'channel_capture_completed' $false)
    if(-not$serverCapture){$missing.Add('complete browser origin capture')}
    if(-not$routeCapture){$missing.Add('complete browser route capture')}
    $requiredServer=@('run_id','scenario_id','attempt_id','flow_id','phase','sequence','event','resource','browser_session_id','request_path','content_sha256','content_length','result','timestamp_utc','process_id','protocol_family','transport','local_ip','local_port','remote_ip','remote_port','negotiated_protocol','status_code')
    $allServerContractsValid=$true
    $sessionSeparator=[string][char]31
    $expectedBrowserSessionId=Get-ProtocolMockSha256 (([string]$ExecutionPlan.run_id)+$sessionSeparator+([string]$ExecutionPlan.scenario_id)+$sessionSeparator+([string]$ExecutionPlan.attempt_id)+$sessionSeparator+([string]$ExecutionPlan.flow_id))
    foreach($server in @($ServerRecords)){
        $serverValid=$true
        foreach($field in $requiredServer){if($null-eq$server.PSObject.Properties[$field]){$harness.Add("browser server evidence field missing: $field");$serverValid=$false;$allServerContractsValid=$false}}
        if(-not$serverValid){continue}
        foreach($field in @('run_id','scenario_id','attempt_id','flow_id')){if([string]$server.$field-ne[string]$ExecutionPlan.worker_plan.$field){$contamination.Add("browser server identity mismatch: $field")}}
        if([string]$server.phase-ne'server'-or[string]$server.protocol_family-ne'browser-origin'-or[string]$server.transport-ne'TCP'-or[string]$server.result-ne'PASS'){$harness.Add('browser server canonical record invalid')}
        if([string]$server.content_sha256-notmatch'^[0-9a-f]{64}$'-or[string]$server.browser_session_id-notmatch'^[0-9a-f]{64}$'){$harness.Add('browser server digest invalid')}
        elseif([string]$server.browser_session_id-ne$expectedBrowserSessionId){$contamination.Add('browser origin identity-bound session mismatch')}
        if([string]$server.local_ip-ne[string]$ExecutionPlan.remote_host-or[int]$server.local_port-ne[int]$ExecutionPlan.remote_port){$contamination.Add('browser server destination identity mismatch')}
        if(-not(Test-ProtocolJsonInteger $server.remote_port 1)-or[decimal]$server.remote_port-gt 65535){$harness.Add('browser origin client port invalid');$allServerContractsValid=$false}
    }
    $pages=@($ServerRecords|Where-Object{$null-ne$_.PSObject.Properties['resource']-and[string]$_.resource-eq'page'})
    $downloads=@($ServerRecords|Where-Object{$null-ne$_.PSObject.Properties['resource']-and[string]$_.resource-eq'download'})
    if($pages.Count-eq 0){$missing.Add('browser origin page record')}elseif($pages.Count-gt 1){$contamination.Add('duplicate browser origin page records')}
    if($downloads.Count-eq 0){$missing.Add('browser origin download record')}elseif($downloads.Count-gt 1){$contamination.Add('duplicate browser origin download records')}
    if($ServerRecords.Count-gt 2-and($pages.Count-le 1-and$downloads.Count-le 1)){$contamination.Add('unexpected browser origin records')}
    $serverResourcesValid=$pages.Count-eq 1-and$downloads.Count-eq 1-and$allServerContractsValid
    $originConnectionsDistinct=$false
    if($serverResourcesValid){
        $page=$pages[0];$download=$downloads[0]
        $pagePath=[string]$ExecutionPlan.worker_plan.parameters.target_url
        $pagePath=([uri]$pagePath).AbsolutePath
        $downloadPath=$pagePath.Substring(0,$pagePath.LastIndexOf('/'))+'/download'
        if([int]$page.sequence-ne 1-or[int]$download.sequence-ne 2){$contamination.Add('browser origin deterministic sequences invalid')}
        if([string]$page.event-ne'BROWSER_ORIGIN_PAGE_SERVED'-or[string]$download.event-ne'BROWSER_ORIGIN_DOWNLOAD_SERVED'){$harness.Add('browser origin resource event invalid')}
        if([string]$page.request_path-ne$pagePath-or[string]$download.request_path-ne$downloadPath){$contamination.Add('browser origin request path identity mismatch')}
        if([string]$page.browser_session_id-ne[string]$download.browser_session_id){$contamination.Add('browser origin session identity mismatch')}
        if([int]$page.remote_port-eq[int]$download.remote_port){$missing.Add('two distinct browser origin TCP connections')}else{$originConnectionsDistinct=$true}
        if($clientContractValid){
            if([string]$download.content_sha256-ne[string]$client.content_sha256){$product.Add('browser download server content mismatch')}
            foreach($server in @($page,$download)){
                if([int]$server.status_code-ne[int]$client.response_status){$product.Add('browser origin response status mismatch')}
                if([string]$server.negotiated_protocol-ne[string]$client.negotiated_protocol){$product.Add('browser origin negotiated protocol mismatch')}
            }
        }
        $direct=[string](Get-ProtocolProperty $EvidenceContext 'direct_egress_ip' '')
        if([string]::IsNullOrWhiteSpace($direct)){$missing.Add('direct egress baseline')}
        else{foreach($server in @($page,$download)){if([string]$server.remote_ip-ne$direct){$product.Add('browser wrong direct egress')}}}
    }

    $start=Get-ProtocolProperty $EvidenceContext 'start_time_utc' ([datetime]::MinValue)
    $end=Get-ProtocolProperty $EvidenceContext 'end_time_utc' ([datetime]::MaxValue)
    $insideRoutes=[System.Collections.Generic.List[object]]::new()
    $outsideRoutes=[System.Collections.Generic.List[object]]::new()
    foreach($route in @($ProxyBridgeRecords)){
        if([string](Get-ProtocolProperty $route 'event' '')-notin @('ROUTE_DECISION','RELAY_ACCEPTED_REDIRECT')){continue}
        if(-not[string]::Equals([string](Get-ProtocolProperty $route 'process' ''),[string]$ExecutionPlan.expected_process,[System.StringComparison]::OrdinalIgnoreCase)){continue}
        if(-not[string]::Equals([string](Get-ProtocolProperty $route 'destination_ip' ''),[string]$ExecutionPlan.remote_host,[System.StringComparison]::OrdinalIgnoreCase)-or[int](Get-ProtocolProperty $route 'destination_port' 0)-ne[int]$ExecutionPlan.remote_port){continue}
        $observedText=[string](Get-ProtocolProperty $route 'observed_at_utc' '')
        if([string]::IsNullOrWhiteSpace($observedText)){$harness.Add('browser route timestamp missing');continue}
        try{$observed=[datetime]::Parse($observedText).ToUniversalTime()}catch{$harness.Add('browser route timestamp invalid');continue}
        if($observed-lt$start.ToUniversalTime()-or$observed-gt$end.ToUniversalTime()){continue}
        $routePid=0
        if(-not[int]::TryParse([string](Get-ProtocolProperty $route 'pid' 0),[ref]$routePid)-or$routePid-lt 1){$harness.Add('browser route pid invalid');continue}
        $canonicalRoute=[pscustomobject][ordered]@{
            process=[string](Get-ProtocolProperty $route 'process' '');pid=$routePid
            destination_ip=[string](Get-ProtocolProperty $route 'destination_ip' '');destination_port=[int](Get-ProtocolProperty $route 'destination_port' 0)
            action=[string](Get-ProtocolProperty $route 'action' '')
        }
        if($verifiedPids.Contains($routePid)){$insideRoutes.Add($canonicalRoute)}else{$outsideRoutes.Add($canonicalRoute)}
    }
    if($outsideRoutes.Count-gt 0){$contamination.Add('browser route pid is outside verified process tree')}
    $expectedRoutes=@($insideRoutes|Where-Object{[string]$_.action-eq[string]$ExecutionPlan.expected_action})
    $wrongRoutes=@($insideRoutes|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_.action)-and[string]$_.action-ne[string]$ExecutionPlan.expected_action})
    $routeValid=$expectedRoutes.Count-ge 1-and$wrongRoutes.Count-eq 0-and$outsideRoutes.Count-eq 0
    if($expectedRoutes.Count-gt 0-and$wrongRoutes.Count-gt 0){$contamination.Add('contradictory browser route records')}
    elseif($wrongRoutes.Count-gt 0){
        $externalWrongActionProof=$clientContractValid-and$serverCapture-and$serverResourcesValid-and$originConnectionsDistinct-and$routeCapture
        if($externalWrongActionProof){$product.Add('browser flow wrong ProxyBridge action')}else{$missing.Add('complete browser wrong-action proof')}
    }
    elseif($expectedRoutes.Count-eq 0){$missing.Add('browser expected-action route corroboration')}

    if(-not[bool]$ClientResult.timed_out-and[int]$ClientResult.exit_code-ne 0-and$product.Count-eq 0){$harness.Add("browser worker exit code $($ClientResult.exit_code)")}
    $outcome='PASS'
    if($contamination.Count-gt 0){$outcome='CONTAMINATED'}elseif($harness.Count-gt 0){$outcome='FAIL_HARNESS'}elseif($product.Count-gt 0){$outcome='FAIL_PRODUCT'}elseif($missing.Count-gt 0){$outcome='HOLD_AMBIGUOUS'}
    $errors=@($product)+@($harness)+@($missing)+@($contamination)
    $completeness=@(
        [pscustomobject][ordered]@{channel='client_plan';mandatory=$true;requested=$true;captured=$true;parsed=$true;validated=$true},
        [pscustomobject][ordered]@{channel='client_jsonl';mandatory=$true;requested=$true;captured=($clientRecords.Count-gt 0);parsed=($clientRecords.Count-gt 0);validated=($clientRecords.Count-eq 1-and$clientContractValid)},
        [pscustomobject][ordered]@{channel='endpoint_query';mandatory=$true;requested=$true;captured=$serverCapture;parsed=$serverCapture;validated=$serverCapture},
        [pscustomobject][ordered]@{channel='endpoint_jsonl';mandatory=$true;requested=$true;captured=($ServerRecords.Count-gt 0);parsed=$serverCapture;validated=($serverResourcesValid-and$originConnectionsDistinct)},
        [pscustomobject][ordered]@{channel='proxybridge_records';mandatory=$true;requested=$routeCapture;captured=($insideRoutes.Count-gt 0);parsed=$routeCapture;validated=$routeValid},
        [pscustomobject][ordered]@{channel='cleanup';mandatory=$true;requested=$true;captured=$clientContractValid;parsed=$clientContractValid;validated=($clientContractValid-and$cleanupVerified)},
        [pscustomobject][ordered]@{channel='assertion_result';mandatory=$true;requested=$true;captured=$true;parsed=$true;validated=($contamination.Count-eq 0-and$harness.Count-eq 0)}
    )
    return [pscustomobject][ordered]@{passed=($outcome-eq'PASS');outcome=$outcome;product_errors=@($product|Sort-Object -Unique);harness_errors=@($harness|Sort-Object -Unique);missing_evidence=@($missing|Sort-Object -Unique);contamination=@($contamination|Sort-Object -Unique);errors=@($errors|Sort-Object -Unique);channel_capture_completed=$routeCapture;records_found=($insideRoutes.Count-gt 0);route_evidence_required=$true;external_route_proof_complete=($serverCapture-and$serverResourcesValid-and$originConnectionsDistinct-and$routeValid);evidence_basis='BROWSER_CLIENT+DISTINCT_ORIGIN_PAGE_DOWNLOAD+VERIFIED_PROCESS_TREE_ROUTE';run_mode=$RunMode;evidence_completeness=$completeness}
}

function Test-ProtocolScenarioAssertions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Scenario,[Parameter(Mandatory)]$ExecutionPlan,[Parameter(Mandatory)]$ClientResult,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ServerRecords,[Parameter(Mandatory)][AllowEmptyCollection()][object[]]$ProxyBridgeRecords,
        $EvidenceContext,[ValidateSet('mock','real')][string]$RunMode='mock'
    )
    if([string]$ExecutionPlan.evidence_profile_id-eq'browser-session'){
        return Test-BrowserProtocolScenarioAssertions -Scenario $Scenario -ExecutionPlan $ExecutionPlan -ClientResult $ClientResult -ServerRecords $ServerRecords -ProxyBridgeRecords $ProxyBridgeRecords -EvidenceContext $EvidenceContext -RunMode $RunMode
    }
    $product=[System.Collections.Generic.List[string]]::new();$harness=[System.Collections.Generic.List[string]]::new()
    $missing=[System.Collections.Generic.List[string]]::new();$contamination=[System.Collections.Generic.List[string]]::new()
    if([bool]$ClientResult.timed_out){$harness.Add('protocol worker timeout')}
    if(-not [bool]$ClientResult.prelaunch_verified){$harness.Add('protocol prelaunch verification incomplete')}
    if(-not [bool]$ClientResult.stdout_status_valid){$harness.Add('protocol worker status output invalid')}
    if(-not [bool]$ClientResult.stderr_empty){$harness.Add('protocol worker stderr is not empty')}
    $clientRecords=@($ClientResult.records)
    if($clientRecords.Count-ne 1){$harness.Add("protocol client record count actual=$($clientRecords.Count) expected=1")}
    if(-not [bool](Get-ProtocolProperty $EvidenceContext 'server_capture_complete' $false)){$missing.Add('complete protocol server capture')}
    if($ServerRecords.Count-gt 1){$contamination.Add('duplicate exact protocol server records')}
    $client=$(if($clientRecords.Count-eq 1){$clientRecords[0]}else{$null});$server=$(if($ServerRecords.Count-eq 1){$ServerRecords[0]}else{$null})
    $routeValid=$false;$wrongRoute=$false;$routeRecords=@();$expectedRoute=@();$contradictory=@()
    if($null-ne $client){
        foreach($field in @('run_id','scenario_id','attempt_id','flow_id')){if([string]$client.$field-ne[string]$ExecutionPlan.worker_plan.$field){$contamination.Add("protocol client identity mismatch: $field")}}
        $trafficPid=[int]$client.process_id
        $childTrafficAllowed=[string]$ExecutionPlan.evidence_profile_id-eq'failure-injection'
        if(-not $childTrafficAllowed-and$trafficPid-ne[int]$ClientResult.pid){$contamination.Add('protocol client process identity mismatch')}
        $start=Get-ProtocolProperty $EvidenceContext 'start_time_utc' ([datetime]::MinValue);$end=Get-ProtocolProperty $EvidenceContext 'end_time_utc' ([datetime]::MaxValue)
        $routeRecords=@(Find-ProxyBridgeFlowEvidence -Records $ProxyBridgeRecords -Process ([string]$ExecutionPlan.expected_process) -Pid $trafficPid -DestinationIp ([string]$ExecutionPlan.remote_host) -DestinationPort ([int]$ExecutionPlan.remote_port) -StartTimeUtc $start -EndTimeUtc $end)
        $expectedRoute=@($routeRecords|Where-Object{[string]$_.action-eq[string]$ExecutionPlan.expected_action})
        $contradictory=@($routeRecords|Where-Object{-not[string]::IsNullOrWhiteSpace([string]$_.action)-and[string]$_.action-ne[string]$ExecutionPlan.expected_action})
        if($expectedRoute.Count-gt 0-and$contradictory.Count-gt 0){$contamination.Add('contradictory protocol route records')}
        elseif($contradictory.Count-gt 0){$wrongRoute=$true;$product.Add('protocol flow wrong ProxyBridge action')}
        elseif($expectedRoute.Count-eq 0){$missing.Add('protocol flow exact internal route decision')}
        else{$routeValid=$true}
    }
    $serverValid=$null-ne $server
    if($serverValid){
        foreach($field in @('run_id','scenario_id','attempt_id','flow_id')){if([string]$server.$field-ne[string]$ExecutionPlan.worker_plan.$field){$contamination.Add("protocol server identity mismatch: $field")}}
        if($null-ne $client-and[string]$client.payload_sha256-ne[string]$server.payload_sha256){$product.Add('protocol payload correlation mismatch')}
        if([string]$server.result-ne'PASS'){$harness.Add('protocol server result invalid')}
    }
    $expectedAction=[string]$ExecutionPlan.expected_action
    if($expectedAction-eq'BLOCK'){
        if($null-ne $client){
            $noResponse=$null-ne $client.PSObject.Properties['no_response_observed']-and[bool]$client.no_response_observed
            if([string]$client.result-ne'PASS'-or-not $noResponse){
                if($serverValid-or$wrongRoute-or$routeValid){$product.Add('protocol BLOCK produced an unexpected client response or outcome')}else{$missing.Add('protocol BLOCK no-response proof')}
            }
        }
        if($ServerRecords.Count-gt 0){$product.Add('protocol BLOCK leaked to the server')}
    }
    else{
        if(-not $serverValid){$missing.Add('exact protocol server record')}
        if($null-ne $client-and[string]$client.result-ne'PASS'){
            if($serverValid-or$wrongRoute){$product.Add('protocol client outcome mismatch')}else{$missing.Add('complete external evidence for protocol client failure')}
        }
        if($null-ne $client-and$serverValid){
            $profile=[string]$ExecutionPlan.evidence_profile_id
            $compareFields=switch($profile){
                'dns-transaction'{@('dns_transport','query_name','query_type','response_code','answer_digest')}
                'tls-session'{@('tls_version','cipher_suite','server_name','alpn','peer_certificate_sha256')}
                'http1-transaction'{@('method','authority','path_digest','request_body_sha256','status_code','response_body_sha256')}
                'http2-transaction'{@('alpn','stream_id','method','status_code','request_body_sha256','response_body_sha256','end_stream','flow_control_complete')}
                'rpc-transaction'{@('rpc_protocol','service','method','request_sha256','response_sha256','application_status')}
                'websocket-transaction'{@('upgrade_status','subprotocol','message_type','message_sha256','echo_sha256','close_code')}
                'quic-http3-transaction'{@('quic_version','alpn','stream_id','handshake_complete','status_code','response_body_sha256','migration_status')}
                'file-transfer'{@('file_protocol','operation','content_sha256','transferred_bytes','control_status','data_channel_status')}
                'mail-transaction'{@('mail_protocol','session_id','operation','message_sha256','protocol_status','mailbox_state_digest')}
                'messaging-transaction'{@('messaging_protocol','namespace','topic_digest','delivery_mode','message_sha256','acknowledged')}
                'time-transaction'{@('time_protocol','request_id','stratum','server_receive_utc','server_transmit_utc')}
                'multi-peer-transaction'{@('peer_id','peer_count','channel_id','message_sha256','delivery_set_digest')}
                'stun-turn-transaction'{@('ice_protocol','transaction_id','method','mapped_address_digest','relay_address_digest','integrity_verified')}
                'rtp-media-session'{@('ssrc','payload_type','packet_count','sequence_gap_count','jitter_ms','rtcp_status','media_digest')}
                'udp-registration-session'{@('registration_id','registration_sent','server_initiated','message_sha256')}
                'failure-injection'{@('injector_id','target_identity','injection_started_utc','injection_verified','expected_failure_signature','rollback_verified')}
                default{@()}
            }
            foreach($field in $compareFields){if([string]$client.$field-ne[string]$server.$field){$product.Add("protocol $field mismatch")}}
            $direct=[string](Get-ProtocolProperty $EvidenceContext 'direct_egress_ip' '');$proxy=[string](Get-ProtocolProperty $EvidenceContext 'proxy_egress_ip' '')
            if($expectedAction-eq'DIRECT'){
                if([string]::IsNullOrWhiteSpace($direct)){$missing.Add('direct egress baseline')}
                elseif([string]$server.remote_ip-ne$direct){$product.Add('protocol wrong direct egress')}
            }elseif($expectedAction-eq'PROXY'){
                if(-not[string]::IsNullOrWhiteSpace($proxy)-and[string]$server.remote_ip-ne$proxy){$product.Add('protocol wrong proxy egress')}
                elseif(-not[string]::IsNullOrWhiteSpace($direct)-and[string]$server.remote_ip-eq$direct){$product.Add('protocol direct egress leak')}
                elseif([string]::IsNullOrWhiteSpace($proxy)-and[string]::IsNullOrWhiteSpace($direct)){$missing.Add('proxy egress discriminator')}
            }
        }
    }
    if(-not[bool]$ClientResult.timed_out-and[int]$ClientResult.exit_code-ne 0-and$product.Count-eq 0){$harness.Add("protocol worker exit code $($ClientResult.exit_code)")}
    $outcome='PASS';if($contamination.Count-gt 0){$outcome='CONTAMINATED'}elseif($harness.Count-gt 0){$outcome='FAIL_HARNESS'}elseif($product.Count-gt 0){$outcome='FAIL_PRODUCT'}elseif($missing.Count-gt 0){$outcome='HOLD_AMBIGUOUS'}
    $errors=@($product)+@($harness)+@($missing)+@($contamination)
    $serverCapture=[bool](Get-ProtocolProperty $EvidenceContext 'server_capture_complete' $false)
    $routeCapture=[bool](Get-ProtocolProperty $EvidenceContext 'channel_capture_completed' $false)
    $completeness=@(
        [pscustomobject][ordered]@{channel='client_plan';mandatory=$true;requested=$true;captured=$true;parsed=$true;validated=$true},
        [pscustomobject][ordered]@{channel='client_jsonl';mandatory=$true;requested=$true;captured=($clientRecords.Count-gt 0);parsed=($clientRecords.Count-gt 0);validated=($clientRecords.Count-eq 1)},
        [pscustomobject][ordered]@{channel='endpoint_query';mandatory=$true;requested=$true;captured=$serverCapture;parsed=$serverCapture;validated=$serverCapture},
        [pscustomobject][ordered]@{channel='endpoint_jsonl';mandatory=($expectedAction-ne'BLOCK');requested=$true;captured=($ServerRecords.Count-gt 0);parsed=$serverCapture;validated=$(if($expectedAction-eq'BLOCK'){$ServerRecords.Count-eq 0}else{$ServerRecords.Count-eq 1})},
        [pscustomobject][ordered]@{channel='proxybridge_records';mandatory=$true;requested=$routeCapture;captured=($routeRecords.Count-gt 0);parsed=$routeCapture;validated=$routeValid},
        [pscustomobject][ordered]@{channel='assertion_result';mandatory=$true;requested=$true;captured=$true;parsed=$true;validated=($contamination.Count-eq 0-and$harness.Count-eq 0)}
    )
    return [pscustomobject][ordered]@{passed=($outcome-eq'PASS');outcome=$outcome;product_errors=@($product|Sort-Object -Unique);harness_errors=@($harness|Sort-Object -Unique);missing_evidence=@($missing|Sort-Object -Unique);contamination=@($contamination|Sort-Object -Unique);errors=@($errors|Sort-Object -Unique);channel_capture_completed=$routeCapture;records_found=($routeRecords.Count-gt 0);route_evidence_required=$true;external_route_proof_complete=($serverCapture-and(($expectedAction-eq'BLOCK'-and$ServerRecords.Count-eq 0)-or($expectedAction-ne'BLOCK'-and$ServerRecords.Count-eq 1)));evidence_basis='PROTOCOL_CLIENT+SERVER+PROXYBRIDGE';run_mode=$RunMode;evidence_completeness=$completeness}
}

function Get-ProtocolMockSha256 {
    param([string]$Value)
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($Value)
    $hasher=[System.Security.Cryptography.SHA256]::Create()
    try{return ([System.BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}
    finally{$hasher.Dispose();[array]::Clear($bytes,0,$bytes.Length)}
}

function Add-ProtocolMockProfileFields {
    param($Record,$ExecutionPlan,[bool]$NoResponse)
    $parameters=$ExecutionPlan.worker_plan.parameters;$expected=$ExecutionPlan.worker_plan.expected
    switch([string]$ExecutionPlan.evidence_profile_id){
        'dns-transaction'{
            $answers=@(Get-ProtocolProperty $expected 'answers' @()|ForEach-Object{[string]$_}|Sort-Object)
            foreach($pair in (([ordered]@{dns_transport=[string]$parameters.dns_transport;query_id=1234;query_name=[string]$parameters.query_name;query_type=$(if([string]$parameters.query_type-eq'A'){1}else{28});response_code=$(if($NoResponse){-1}else{[int](Get-ProtocolProperty $expected 'response_code' 0)});answer_digest=(Get-ProtocolMockSha256 ($answers-join "`n"));truncated=$false;dnssec_status=$(if($NoResponse){'NOT_OBSERVED'}else{'NOT_REQUESTED'});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'tls-session'{
            foreach($pair in (([ordered]@{tls_version=$(if($NoResponse){''}else{'TLSv1.3'});cipher_suite=$(if($NoResponse){''}else{'TLS_AES_256_GCM_SHA384'});server_name=[string]$parameters.server_name;alpn=$(if($NoResponse){''}else{'pb-test/1'});peer_certificate_sha256=$(if($NoResponse){Get-ProtocolMockSha256 ''}else{('c'*64)-join''});resumed=$false;shutdown_status=$(if($NoResponse){'NOT_OBSERVED'}else{'GRACEFUL'});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'http1-transaction'{
            $path=[string](Get-ProtocolProperty $parameters 'path' '/probe')
            foreach($pair in (([ordered]@{method='POST';authority=[string]$parameters.authority;path_digest=(Get-ProtocolMockSha256 $path);request_body_sha256=[string]$Record.payload_sha256;status_code=$(if($NoResponse){0}else{[int](Get-ProtocolProperty $expected 'status_code' 200)});response_body_sha256=$(if($NoResponse){Get-ProtocolMockSha256 ''}else{('d'*64)-join''});connection_reused=$false;no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'http2-transaction'{
            foreach($pair in (([ordered]@{alpn=$(if($NoResponse){''}else{'h2'});stream_id=$(if($NoResponse){0}else{1});method='POST';status_code=$(if($NoResponse){0}else{[int](Get-ProtocolProperty $expected 'status_code' 200)});request_body_sha256=[string]$Record.payload_sha256;response_body_sha256=$(if($NoResponse){Get-ProtocolMockSha256 ''}else{('e'*64)-join''});end_stream=(-not $NoResponse);flow_control_complete=(-not $NoResponse);no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'rpc-transaction'{
            foreach($pair in (([ordered]@{rpc_protocol='grpc';service=[string]$parameters.service;method=[string]$parameters.method;request_sha256=[string]$Record.payload_sha256;response_sha256=$(if($NoResponse){Get-ProtocolMockSha256 ''}else{[string]$Record.payload_sha256});application_status=$(if($NoResponse){'NOT_OBSERVED'}else{'0'});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'websocket-transaction'{
            foreach($pair in (([ordered]@{upgrade_status=$(if($NoResponse){0}else{101});subprotocol=[string](Get-ProtocolProperty $parameters 'subprotocol' 'pb-test.v1');message_type='binary';message_sha256=[string]$Record.payload_sha256;echo_sha256=$(if($NoResponse){Get-ProtocolMockSha256 ''}else{[string]$Record.payload_sha256});close_code=$(if($NoResponse){0}else{1000});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'quic-http3-transaction'{
            foreach($pair in (([ordered]@{quic_version=$(if($NoResponse){''}else{'0x00000001'});alpn=$(if($NoResponse){''}else{'h3'});connection_id_digest=$(Get-ProtocolMockSha256 ([string]$ExecutionPlan.flow_id));stream_id=$(if($NoResponse){0}else{0});handshake_complete=(-not $NoResponse);status_code=$(if($NoResponse){0}else{200});response_body_sha256=$(if($NoResponse){Get-ProtocolMockSha256 ''}else{('f'*64)-join''});migration_status=$(if($NoResponse){'NOT_OBSERVED'}else{'NOT_ATTEMPTED'});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'file-transfer'{
            $secure=[bool](Get-ProtocolProperty $parameters 'use_tls' $false)
            foreach($pair in (([ordered]@{file_protocol=$(if($secure){'FTPS'}else{'FTP'});operation='UPLOAD';content_sha256=[string]$Record.payload_sha256;transferred_bytes=$(if($NoResponse){0}else{[int]$Record.bytes});control_status=$(if($NoResponse){'NOT_OBSERVED'}else{'221'});data_channel_status=$(if($NoResponse){'NOT_OBSERVED'}elseif($secure){'TLS_PROTECTED'}else{'CLEAR'});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'mail-transaction'{
            $mail=[string]$parameters.mail_protocol;$operation=$(if($mail-like'SMTP*'){'SEND'}elseif($mail-like'IMAP*'){'APPEND'}else{'RETRIEVE'})
            foreach($pair in (([ordered]@{mail_protocol=$mail;session_id=[string]$ExecutionPlan.flow_id;operation=$operation;message_sha256=[string]$Record.payload_sha256;protocol_status=$(if($NoResponse){'NOT_OBSERVED'}elseif($mail-like'SMTP*'){'250'}else{'OK'});mailbox_state_digest=(Get-ProtocolMockSha256 (([string]$ExecutionPlan.flow_id)+'|stored'));no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'messaging-transaction'{
            $protocol=[string](Get-ProtocolProperty $parameters 'messaging_protocol' $(if([string]$ExecutionPlan.worker_plan.plugin_id-eq'protocol-irc'){$(if([bool](Get-ProtocolProperty $parameters 'use_tls' $false)){'IRCS'}else{'IRC'})}else{''}))
            $isIrc=$protocol-like'IRC*';$isMqtt=$protocol-like'MQTT*';$namespace=$(if($isIrc){'#testlab'}elseif($isMqtt){'testlab'}else{'/'})
            foreach($pair in (([ordered]@{messaging_protocol=$protocol;namespace=$namespace;topic_digest=(Get-ProtocolMockSha256 $(if($isIrc){'#testlab'}else{[string]$ExecutionPlan.flow_id}));delivery_mode=$(if($NoResponse){'NOT_OBSERVED'}elseif($isIrc){'SERVER_NOTICE'}elseif($isMqtt){'QOS1'}else{'CONFIRM'});message_sha256=[string]$Record.payload_sha256;acknowledged=(-not $NoResponse);no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'time-transaction'{
            foreach($pair in (([ordered]@{time_protocol='NTPv4';request_id=(Get-ProtocolMockSha256 ([string]$ExecutionPlan.flow_id)).Substring(0,16);stratum=$(if($NoResponse){0}else{2});server_receive_utc=$(if($NoResponse){''}else{'1'});server_transmit_utc=$(if($NoResponse){''}else{'1'});round_trip_ms=$(if($NoResponse){100}else{1});no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'multi-peer-transaction'{
            foreach($pair in (([ordered]@{peer_id='peer-a';peer_count=2;channel_id=[string]$ExecutionPlan.flow_id;message_sha256=[string]$Record.payload_sha256;delivery_set_digest=(Get-ProtocolMockSha256 "peer-a`npeer-b");no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'stun-turn-transaction'{
            $ice=[string](Get-ProtocolProperty $parameters 'ice_protocol' 'STUN');$method=$(if($ice-eq'TURN'){'ALLOCATE'}else{'BINDING'})
            foreach($pair in (([ordered]@{ice_protocol=$ice;transaction_id=(Get-ProtocolMockSha256 ([string]$ExecutionPlan.flow_id)).Substring(0,24);method=$method;mapped_address_digest=$(Get-ProtocolMockSha256 $(if($NoResponse){''}else{'mapped'}));relay_address_digest=$(Get-ProtocolMockSha256 $(if($NoResponse-or$ice-ne'TURN'){''}else{'relay'}));integrity_verified=(-not $NoResponse);no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'rtp-media-session'{
            $count=[int](Get-ProtocolProperty $parameters 'packet_count' 12)
            foreach($pair in (([ordered]@{ssrc=123456;payload_type=111;packet_count=$count;sequence_gap_count=$(if($NoResponse){$count}else{0});jitter_ms=0;rtcp_status=$(if($NoResponse){'NOT_OBSERVED'}else{'RECEIVER_REPORT'});media_digest=[string]$Record.payload_sha256;no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'udp-registration-session'{
            foreach($pair in (([ordered]@{registration_id=(Get-ProtocolMockSha256 ([string]$ExecutionPlan.flow_id)).Substring(0,24);registration_sent=$true;server_initiated=(-not $NoResponse);message_sha256=[string]$Record.payload_sha256;nat_mapping_digest=(Get-ProtocolMockSha256 $(if($NoResponse){''}else{'mapping'}));no_response_observed=$NoResponse}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        'failure-injection'{
            foreach($pair in (([ordered]@{injector_id='client-process-controller';target_identity=(Get-ProtocolMockSha256 'fixture-child');injection_started_utc='2030-01-01T00:00:00.000Z';injection_verified=(-not $NoResponse);expected_failure_signature='CLIENT_PROCESS_TERMINATED';rollback_verified=$true}).GetEnumerator())){$Record|Add-Member -NotePropertyName $pair.Key -NotePropertyValue $pair.Value}
        }
        default{throw 'PROTOCOL_MOCK_PROFILE_UNSUPPORTED'}
    }
}

function Invoke-MockBrowserProtocolScenario {
    param($Scenario,$ExecutionPlan,[string]$FixtureRoot)
    $fixturePath=Join-Path (Join-Path $FixtureRoot 'protocol') 'browser-direct.json'
    if(-not(Test-Path -LiteralPath $fixturePath -PathType Leaf)){throw 'PROTOCOL_MOCK_FIXTURE_MISSING'}
    try{$fixture=Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{throw 'PROTOCOL_MOCK_FIXTURE_INVALID'}
    if([int]$fixture.schema_version-ne 1-or[string]$fixture.expected_action-ne'DIRECT'-or[string]$ExecutionPlan.expected_action-ne'DIRECT'){throw 'PROTOCOL_MOCK_FIXTURE_CONTRACT_MISMATCH'}
    if([int]$fixture.route_decision_count-ne 2-or(@($fixture.server_resources)-join ',')-ne'page,download'){throw 'PROTOCOL_MOCK_FIXTURE_CONTRACT_MISMATCH'}
    $parameters=$ExecutionPlan.worker_plan.parameters
    $rootPid=6100;$childPid=6101
    $contentHash=[string]$parameters.expected_content_sha256
    $targetUrl=[string]$parameters.target_url
    $client=[pscustomobject][ordered]@{
        schema_version=1;run_id=[string]$ExecutionPlan.run_id;scenario_id=[string]$ExecutionPlan.scenario_id;attempt_id=[string]$ExecutionPlan.attempt_id;flow_id=[string]$ExecutionPlan.flow_id
        phase='client';sequence=1;event='BROWSER_CANARY_COMPLETED';timestamp_utc='2030-01-01T00:00:03.000Z';monotonic_ms=30
        process_id=$rootPid;socket_id=0;protocol_family='browser-web';transport='TCP';local_ip='';local_port=0;remote_ip='';remote_port=0
        payload_sha256=$contentHash;bytes=64;result=[string]$fixture.client_result
        browser_identity=[string]$parameters.expected_browser_identity;browser_version=[string]$parameters.expected_browser_version
        navigation_url_digest=(Get-ProtocolMockSha256 $targetUrl);negotiated_protocol=[string]$parameters.expected_negotiated_protocol
        response_status=[int]$parameters.expected_response_status;content_sha256=$contentHash
        browser_executable_requested=[string]$parameters.browser_executable;browser_executable_observed=[string]$parameters.browser_executable
        browser_image_sha256=[string]$parameters.expected_browser_sha256;browser_image_sha256_verified=$true
        browser_process_tree_pids=@($rootPid,$childPid);profile_id=(Get-ProtocolMockSha256 ([string]$parameters.profile_dir))
        actual_path_probe_status='PATH_OBTAINED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=1;process_tree_cleaned=$true
    }
    $pagePath=([uri]$targetUrl).AbsolutePath
    $downloadPath=$pagePath.Substring(0,$pagePath.LastIndexOf('/'))+'/download'
    $separator=[string][char]31
    $sessionId=Get-ProtocolMockSha256 (([string]$ExecutionPlan.run_id)+$separator+([string]$ExecutionPlan.scenario_id)+$separator+([string]$ExecutionPlan.attempt_id)+$separator+([string]$ExecutionPlan.flow_id))
    $egress=$(if([string]$fixture.server_egress-eq'direct'){'192.0.2.50'}elseif([string]$fixture.server_egress-eq'proxy'){'198.51.100.50'}else{throw 'PROTOCOL_MOCK_EGRESS_INVALID'})
    $serverRecords=[System.Collections.Generic.List[object]]::new()
    foreach($resource in @('page','download')){
        $sequence=$(if($resource-eq'page'){1}else{2})
        $requestPath=$(if($resource-eq'page'){$pagePath}else{$downloadPath})
        $hash=$(if($resource-eq'download'){$contentHash}else{Get-ProtocolMockSha256 ("browser-page|$sessionId")})
        $serverRecords.Add([pscustomobject][ordered]@{
            schema_version=1;run_id=[string]$ExecutionPlan.run_id;scenario_id=[string]$ExecutionPlan.scenario_id;attempt_id=[string]$ExecutionPlan.attempt_id;flow_id=[string]$ExecutionPlan.flow_id
            phase='server';sequence=$sequence;event=$(if($resource-eq'page'){'BROWSER_ORIGIN_PAGE_SERVED'}else{'BROWSER_ORIGIN_DOWNLOAD_SERVED'})
            resource=$resource;browser_session_id=$sessionId;request_path=$requestPath;content_sha256=$hash;content_length=128;result='PASS'
            timestamp_utc="2030-01-01T00:00:0$sequence.000Z";monotonic_ms=$sequence;process_id=5000;socket_id=0;protocol_family='browser-origin';transport='TCP'
            local_ip=[string]$ExecutionPlan.remote_host;local_port=[int]$ExecutionPlan.remote_port;remote_ip=$egress;remote_port=(51000+$sequence)
            secure=$false;negotiated_protocol=[string]$parameters.expected_negotiated_protocol;status_code=[int]$parameters.expected_response_status
        })
    }
    $routeLines=@(
        "2030-01-01T00:00:01Z $($ExecutionPlan.expected_process) ($rootPid) -> $($ExecutionPlan.remote_host):$($ExecutionPlan.remote_port) via $($fixture.route_text)",
        "2030-01-01T00:00:02Z $($ExecutionPlan.expected_process) ($rootPid) -> $($ExecutionPlan.remote_host):$($ExecutionPlan.remote_port) via $($fixture.route_text)"
    )
    $routes=@(ConvertFrom-ProxyBridgeTextLines -Lines $routeLines -DefaultTimestampUtc ([datetime]'2030-01-01T00:00:00Z'))
    [System.IO.File]::WriteAllText([string]$ExecutionPlan.client_jsonl_path,(($client|ConvertTo-Json -Compress -Depth 20)+[Environment]::NewLine),$script:ProtocolUtf8NoBom)
    $serverText=(@($serverRecords|ForEach-Object{$_|ConvertTo-Json -Compress -Depth 20})-join[Environment]::NewLine)+[Environment]::NewLine
    [System.IO.File]::WriteAllText([string]$ExecutionPlan.server_jsonl_path,$serverText,$script:ProtocolUtf8NoBom)
    $result=[pscustomobject][ordered]@{exit_code=0;timed_out=$false;pid=4242;actual_path=[string]$ExecutionPlan.process_plan.executable;actual_path_probe_status='PATH_OBTAINED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=1;actual_path_required=$true;prelaunch_verified=$true;artifact_verification=@();stdout_status_valid=$true;stderr_empty=$true;records=@($client);raw_records=@($client);canonical_records=@($client);jsonl_path=[string]$ExecutionPlan.client_jsonl_path;run_mode='mock'}
    $context=[pscustomobject]@{server_capture_complete=$true;channel_capture_completed=$true;direct_egress_ip='192.0.2.50';proxy_egress_ip='198.51.100.50';start_time_utc=[datetime]'2029-12-31T23:59:00Z';end_time_utc=[datetime]'2030-01-01T00:01:00Z'}
    return [pscustomobject][ordered]@{client_result=$result;server_records=@($serverRecords.ToArray());proxybridge_records=$routes;evidence_context=$context}
}

function Invoke-MockProtocolScenario {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Scenario,[Parameter(Mandatory)]$ExecutionPlan,[Parameter(Mandatory)][string]$FixtureRoot)
    if([string]$ExecutionPlan.evidence_profile_id-eq'browser-session'){
        return Invoke-MockBrowserProtocolScenario -Scenario $Scenario -ExecutionPlan $ExecutionPlan -FixtureRoot $FixtureRoot
    }
    $fixturePath=Join-Path (Join-Path $FixtureRoot 'protocol') (([string]$ExecutionPlan.expected_action).ToLowerInvariant()+'.json')
    if(-not(Test-Path -LiteralPath $fixturePath -PathType Leaf)){throw 'PROTOCOL_MOCK_FIXTURE_MISSING'}
    try{$fixture=Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8|ConvertFrom-Json}catch{throw 'PROTOCOL_MOCK_FIXTURE_INVALID'}
    if([int]$fixture.schema_version-ne 1-or[string]$fixture.expected_action-ne[string]$ExecutionPlan.expected_action){throw 'PROTOCOL_MOCK_FIXTURE_CONTRACT_MISMATCH'}
    $noResponse=[bool]$fixture.no_response_observed;$payload=Get-ProtocolMockSha256 ("$($ExecutionPlan.run_id)|$($ExecutionPlan.scenario_id)|$($ExecutionPlan.attempt_id)|$($ExecutionPlan.flow_id)")
    $client=[pscustomobject][ordered]@{schema_version=1;run_id=[string]$ExecutionPlan.run_id;scenario_id=[string]$ExecutionPlan.scenario_id;attempt_id=[string]$ExecutionPlan.attempt_id;flow_id=[string]$ExecutionPlan.flow_id;phase='client';sequence=1;event=$(if($noResponse){'PROTOCOL_NO_RESPONSE_OBSERVED'}else{'PROTOCOL_TRANSACTION_COMPLETED'});timestamp_utc='2030-01-01T00:00:00.000Z';monotonic_ms=10;process_id=4242;socket_id=7001;protocol_family=[string]$ExecutionPlan.worker_plan.protocol_family;transport=[string]$ExecutionPlan.worker_plan.transport;local_ip='192.0.2.20';local_port=32000;remote_ip=$(if($noResponse){''}else{[string]$ExecutionPlan.remote_host});remote_port=[int]$ExecutionPlan.remote_port;payload_sha256=$payload;bytes=128;result=[string]$fixture.client_result}
    Add-ProtocolMockProfileFields -Record $client -ExecutionPlan $ExecutionPlan -NoResponse $noResponse
    $serverRecords=[System.Collections.Generic.List[object]]::new()
    if([int]$fixture.server_record_count-eq 1){
        $egress=$(if([string]$fixture.server_egress-eq'direct'){'192.0.2.50'}elseif([string]$fixture.server_egress-eq'proxy'){'198.51.100.50'}else{throw 'PROTOCOL_MOCK_EGRESS_INVALID'})
        $server=$client|Select-Object *;$server.phase='server';$server.event='PROTOCOL_REQUEST_RECEIVED';$server.process_id=5000;$server.socket_id=0;$server.local_ip=[string]$ExecutionPlan.remote_host;$server.local_port=[int]$ExecutionPlan.remote_port;$server.remote_ip=$egress;$server.remote_port=51000;$server.result='PASS';$server.no_response_observed=$false
        $serverRecords.Add($server)
    }elseif([int]$fixture.server_record_count-ne 0){throw 'PROTOCOL_MOCK_SERVER_COUNT_INVALID'}
    $routeText="2030-01-01T00:00:00Z $($ExecutionPlan.expected_process) (4242) -> $($ExecutionPlan.remote_host):$($ExecutionPlan.remote_port) via $($fixture.route_text)"
    $routes=@(ConvertFrom-ProxyBridgeTextLines -Lines @($routeText) -DefaultTimestampUtc ([datetime]'2030-01-01T00:00:00Z'))
    [System.IO.File]::WriteAllText([string]$ExecutionPlan.client_jsonl_path,(($client|ConvertTo-Json -Compress -Depth 20)+[Environment]::NewLine),$script:ProtocolUtf8NoBom)
    $serverText=$(if($serverRecords.Count){(($serverRecords[0]|ConvertTo-Json -Compress -Depth 20)+[Environment]::NewLine)}else{''})
    [System.IO.File]::WriteAllText([string]$ExecutionPlan.server_jsonl_path,$serverText,$script:ProtocolUtf8NoBom)
    $result=[pscustomobject][ordered]@{exit_code=0;timed_out=$false;pid=4242;actual_path=[string]$ExecutionPlan.process_plan.executable;actual_path_probe_status='PATH_OBTAINED';actual_path_probe_attempts=1;actual_path_probe_elapsed_ms=1;actual_path_required=$true;prelaunch_verified=$true;artifact_verification=@();stdout_status_valid=$true;stderr_empty=$true;records=@($client);raw_records=@($client);canonical_records=@($client);jsonl_path=[string]$ExecutionPlan.client_jsonl_path;run_mode='mock'}
    $context=[pscustomobject]@{server_capture_complete=$true;channel_capture_completed=$true;direct_egress_ip='192.0.2.50';proxy_egress_ip='198.51.100.50';start_time_utc=[datetime]'2029-12-31T23:59:00Z';end_time_utc=[datetime]'2030-01-01T00:01:00Z'}
    return [pscustomobject][ordered]@{client_result=$result;server_records=@($serverRecords.ToArray());proxybridge_records=$routes;evidence_context=$context}
}

Export-ModuleMember -Function New-ProtocolExecutionPlan, Invoke-ProtocolExecutionPlan, New-ProtocolLogCursorPlan, Invoke-ProtocolLogCursorPlan, New-ProtocolServerCollectionPlan, Invoke-ProtocolServerCollectionPlan, Test-ProtocolScenarioAssertions, Invoke-MockProtocolScenario
