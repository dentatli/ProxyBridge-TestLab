[CmdletBinding()]
param(
    [ValidateSet('Deploy','Inspect','Start','Status','Stop','Collect')][string]$Phase='Inspect',
    [string]$ConnectionFile='',
    [string]$RunId='',
    [int]$Port=54122,
    [long]$TransferBytes=524288,
    [int]$MaxConnections=1024,
    [int]$MaxTotalConnections=1200,
    [int]$MaxDurationSeconds=720,
    [string]$EvidenceDirectory=''
)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
function Read-LinuxReceiverJson([string]$Text) {
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {return ($Text | ConvertFrom-Json -DateKind String)}
    return ($Text | ConvertFrom-Json)
}
if (-not $ConnectionFile) {
    $ConnectionFile=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'ProxyBridge-TestLab/config/linux-receiver-connection.json'
}
$connectionItem=Get-Item -LiteralPath $ConnectionFile
if ($connectionItem.Length -gt 16384 -or ($connectionItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'LINUX_RECEIVER_CONNECTION_FILE_INVALID'}
$connection=Read-LinuxReceiverJson (Get-Content -LiteralPath $ConnectionFile -Raw)
$hostIp=$null;$sourceIp=$null
if ($connection.schema_version -ne 1 -or $connection.username -cne 'root' -or
    -not [Net.IPAddress]::TryParse([string]$connection.host,[ref]$hostIp) -or $hostIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    -not [Net.IPAddress]::TryParse([string]$connection.allowed_source,[ref]$sourceIp) -or $sourceIp.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork -or
    [int]$connection.port -notin 1..65535 -or $connection.host_key_fingerprint -notmatch '^SHA256:[A-Za-z0-9+/]{43}$' -or
    $connection.trust_method -notin @('user-authorized-observed-ssh-key','independently-verified-host-key')) {throw 'LINUX_RECEIVER_CONNECTION_INVALID'}
foreach ($path in @($connection.private_key_path,$connection.known_hosts_path)) {
    $item=Get-Item -LiteralPath $path
    if (-not $item.Length -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {throw 'LINUX_RECEIVER_SSH_FILE_INVALID'}
}
$ssh=(Get-Command ssh.exe -ErrorAction Stop).Source
$fingerprints=@(& ssh-keygen.exe -lf $connection.known_hosts_path)
if ($LASTEXITCODE -ne 0 -or -not @($fingerprints | Where-Object {$_ -like ('* '+$connection.host_key_fingerprint+' *')}).Count) {throw 'LINUX_RECEIVER_HOST_KEY_BINDING_DIFFERS'}
$receiverPath=Join-Path $root 'src/pb_cts_push_receiver.py'
$controlPath=Join-Path $root 'src/pb_linux_cts_control.py'
$receiverHash=(Get-FileHash -LiteralPath $receiverPath).Hash.ToLowerInvariant()
$controlHash=(Get-FileHash -LiteralPath $controlPath).Hash.ToLowerInvariant()
$request=[ordered]@{schema_version=1;phase=$Phase;receiver_sha256=$receiverHash}
if ($Phase -eq 'Deploy') {$request.receiver_base64=[Convert]::ToBase64String([IO.File]::ReadAllBytes($receiverPath))}
if ($Phase -in @('Start','Status','Stop','Collect')) {
    if ($RunId -cnotmatch '^[a-z0-9][a-z0-9-]{0,55}$') {throw 'LINUX_RECEIVER_RUN_ID_INVALID'}
    $request.run_id=$RunId
}
if ($Phase -eq 'Start') {
    if ($Port -lt 1024 -or $Port -gt 65535 -or $TransferBytes -lt 1 -or $TransferBytes -gt 8GB -or
        $MaxConnections -lt 1 -or $MaxConnections -gt 1024 -or $MaxTotalConnections -lt $MaxConnections -or $MaxTotalConnections -gt 4096 -or
        $MaxDurationSeconds -lt 1 -or $MaxDurationSeconds -gt 1800) {throw 'LINUX_RECEIVER_START_BOUND_INVALID'}
    $request.bind_ipv4=$hostIp.ToString();$request.allowed_source=$sourceIp.ToString();$request.port=$Port
    $request.transfer_bytes=$TransferBytes;$request.max_connections=$MaxConnections
    $request.max_total_connections=$MaxTotalConnections;$request.max_duration_seconds=$MaxDurationSeconds
}
if ($Phase -eq 'Collect') {
    if (-not $EvidenceDirectory -or (Test-Path -LiteralPath $EvidenceDirectory)) {throw 'LINUX_RECEIVER_COLLECTION_REQUIRES_FRESH_DIRECTORY'}
}
$remoteCode='exec(__import__("base64").b64decode("'+[Convert]::ToBase64String([IO.File]::ReadAllBytes($controlPath))+'"))'
$arguments=@('-T','-F','NUL','-o','BatchMode=yes','-o','IdentitiesOnly=yes','-o','PreferredAuthentications=publickey',
    '-o','PasswordAuthentication=no','-o','KbdInteractiveAuthentication=no','-o','ForwardAgent=no',
    '-o','ClearAllForwardings=yes','-o','PermitLocalCommand=no','-o','StrictHostKeyChecking=yes',
    '-o',('UserKnownHostsFile='+$connection.known_hosts_path),'-o','GlobalKnownHostsFile=NUL',
    '-o','ConnectTimeout=8','-o','ConnectionAttempts=1','-o','HostKeyAlgorithms=ssh-ed25519',
    '-o','KexAlgorithms=curve25519-sha256','-i',$connection.private_key_path,'-p',[string]$connection.port,
    ('root@'+$hostIp.ToString()),'python3','-B','-c',("'"+$remoteCode+"'"))
$info=[Diagnostics.ProcessStartInfo]::new();$info.FileName=$ssh;$info.UseShellExecute=$false;$info.CreateNoWindow=$true
$info.RedirectStandardInput=$true;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
# Windows PowerShell 5 does not expose ArgumentList. Quote only local argv;
# the remote program is fixed base64, never request values interpolated as code.
Import-Module (Join-Path $root 'modules/ProcessAdapter.psm1')
$info.Arguments=Join-ProcessArguments $arguments
$process=[Diagnostics.Process]::Start($info)
$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
$started=[DateTime]::UtcNow.ToString('o')
try {
    $process.StandardInput.Write(($request | ConvertTo-Json -Depth 5 -Compress));$process.StandardInput.Close()
    $timeout=$(if ($Phase -in @('Start','Stop')) {45000} else {30000})
    if (-not $process.WaitForExit($timeout)) {$process.Kill();throw 'LINUX_RECEIVER_SSH_TIMEOUT'}
    if ($stdout.Result.Length -gt 24MB -or $stderr.Result.Length -gt 65536) {throw 'LINUX_RECEIVER_SSH_OUTPUT_BOUND'}
    if ($process.ExitCode -ne 0) {throw ('LINUX_RECEIVER_OPERATION_FAILED: '+$stdout.Result+' '+$stderr.Result)}
    $result=Read-LinuxReceiverJson $stdout.Result
    if ($result.schema_version -ne 1 -or $result.status -eq 'REMOTE_OPERATION_FAILED') {throw 'LINUX_RECEIVER_REMOTE_RESULT_INVALID'}
    if ($Phase -eq 'Collect') {
        $payload=[Convert]::FromBase64String($result.evidence_base64)
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$actualHash=([BitConverter]::ToString($sha.ComputeHash($payload))).Replace('-','').ToLowerInvariant()} finally {$sha.Dispose()}
        if ($payload.Length -ne $result.bytes -or $actualHash -cne $result.sha256) {throw 'LINUX_RECEIVER_COLLECTION_HASH_DIFFERS'}
        $null=New-Item -ItemType Directory -Path $EvidenceDirectory
        [IO.File]::WriteAllBytes((Join-Path $EvidenceDirectory 'receiver.jsonl'),$payload)
        $result.PSObject.Properties.Remove('evidence_base64')
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'remote-collection.json') -Encoding UTF8
    }
    $receipt=[ordered]@{schema_version=1;scope='linux-cts-receiver-lifecycle';phase=$Phase;run_id=$RunId;
        started_at_utc=$started;completed_at_utc=[DateTime]::UtcNow.ToString('o');ssh_exit_code=$process.ExitCode;
        receiver_sha256=$receiverHash;control_sha256=$controlHash;host_key_fingerprint=$connection.host_key_fingerprint;
        trust_method=$connection.trust_method;result=$result;product_started=$false;native_client_compatibility_verified=$false}
    if ($Phase -eq 'Collect') {$receipt | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'collection-receipt.json') -Encoding UTF8}
    $receipt | ConvertTo-Json -Depth 15
} finally {$process.Dispose()}
