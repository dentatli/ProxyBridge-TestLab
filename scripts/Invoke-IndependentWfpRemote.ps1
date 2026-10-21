[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$ComputerName,
    [Parameter(Mandatory=$true)][string]$ExpectedComputerName,
    [Parameter(Mandatory=$true)][PSCredential]$Credential,
    [Parameter(Mandatory=$true)][string]$ScriptPath,
    [Parameter(Mandatory=$true)][string]$EvidenceDirectory,
    [string]$TransferDirectory,
    [string]$RemoteDirectory,
    [hashtable]$ScriptParameters=@{},
    [string]$RemoteCollectDirectory
)

# A single reviewed remote command. Credentials are never serialized.
# The caller controls target actions; this wrapper only restores its client setup.
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if (Test-Path -LiteralPath $EvidenceDirectory) {throw 'REMOTE_EVIDENCE_DIRECTORY_MUST_BE_FRESH'}
$source=Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8
$sourceSha=(Get-FileHash -LiteralPath $ScriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
$null=New-Item -ItemType Directory -Path $EvidenceDirectory
$wasRunning=(Get-Service WinRM).Status -eq 'Running'
$originalTrusted=$null
$trustedChanged=$false
$remoteSession=$null
$cleanupErrors=@()
$result=[ordered]@{status='PENDING';script_sha256=$sourceSha;identity_confirmed=$false}
try {
    if (-not $wasRunning) {
        Start-Service WinRM
        (Get-Service WinRM).WaitForStatus('Running',[TimeSpan]::FromSeconds(10))
    }
    $originalTrusted=[string](Get-Item WSMan:\localhost\Client\TrustedHosts).Value
    [ordered]@{service_was_running=$wasRunning;trusted_hosts=$originalTrusted} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'client-before.json') -Encoding UTF8
    $entries=@($originalTrusted -split ',' | ForEach-Object {$_.Trim()} | Where-Object {$_})
    if (($entries -notcontains $ComputerName) -and ($entries -notcontains '*')) {
        Set-Item WSMan:\localhost\Client\TrustedHosts -Value ((@($entries)+$ComputerName) -join ',') -Force | Out-Null
        $trustedChanged=$true
    }
    $options=New-PSSessionOption -OpenTimeout 15000 -OperationTimeout 30000
    $remoteSession=New-PSSession -ComputerName $ComputerName -Credential $Credential -Authentication Negotiate -SessionOption $options
    $actualName=Invoke-Command -Session $remoteSession -ScriptBlock {$env:COMPUTERNAME}
    if ($actualName -ne $ExpectedComputerName) {throw 'REMOTE_COMPUTER_IDENTITY_DIFFERS'}
    $result.identity_confirmed=$true
    if ($TransferDirectory) {
        if (-not $RemoteDirectory) {throw 'REMOTE_DIRECTORY_REQUIRED'}
        $null=Invoke-Command -Session $remoteSession -ScriptBlock {
            param($destination)
            if(Test-Path -LiteralPath $destination){throw 'REMOTE_DIRECTORY_MUST_BE_FRESH'}
            New-Item -ItemType Directory -Path $destination | Out-Null
        } -ArgumentList $RemoteDirectory
        Get-ChildItem -LiteralPath $TransferDirectory -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $RemoteDirectory -ToSession $remoteSession
        }
        $result['transferred_directory']=$RemoteDirectory
    }
    # Remoting executes reviewed command content, without changing execution policy.
    $output=(Invoke-Command -Session $remoteSession -ScriptBlock {
        param($text,$parameters)
        & ([scriptblock]::Create($text)) @parameters
    } -ArgumentList $source,$ScriptParameters) -join "`n"
    $null=$output | ConvertFrom-Json
    $output | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'command-output.json') -Encoding UTF8
    if($RemoteCollectDirectory){
        Copy-Item -LiteralPath $RemoteCollectDirectory -Destination (Join-Path $EvidenceDirectory 'target-files') -FromSession $remoteSession -Recurse
    }
    $result.status='COLLECTED'
} catch {
    $result.status='FAILED'
    $message=$_.Exception.Message
    # Some conversion errors embed an entire system capture in Message.
    $result['error']=$message.Substring(0,[Math]::Min(1200,$message.Length))
} finally {
    if ($remoteSession) {
        try {Remove-PSSession $remoteSession} catch {$cleanupErrors+=$_.Exception.Message}
    }
    if ($trustedChanged) {
        try {
            Set-Item WSMan:\localhost\Client\TrustedHosts -Value $originalTrusted -Force | Out-Null
            if ([string](Get-Item WSMan:\localhost\Client\TrustedHosts).Value -ne $originalTrusted) {throw 'TRUSTED_HOSTS_RESTORE_DIFFERS'}
        } catch {$cleanupErrors+=$_.Exception.Message}
    }
    if (-not $wasRunning) {
        try {
            Stop-Service WinRM
            (Get-Service WinRM).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(10))
        } catch {$cleanupErrors+=$_.Exception.Message}
    }
    $result['cleanup_errors']=$cleanupErrors
    $result['client_service_state_after']=[string](Get-Service WinRM).Status
    $result['client_trusted_hosts_temporary_change']=$trustedChanged
    if ($cleanupErrors.Count) {$result.status='CLIENT_CLEANUP_INCOMPLETE'}
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDirectory 'result.json') -Encoding UTF8
}
Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'result.json') -Raw -Encoding UTF8
