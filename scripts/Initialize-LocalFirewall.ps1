#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][string]$RepositoryRoot,[string]$PythonPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$root=[IO.Path]::GetFullPath($RepositoryRoot)
if(-not $PythonPath){$PythonPath=Join-Path $root 'bin/runtime/python/python.exe'}
$programs=@((Join-Path $root 'bin/pb_core_host.exe'),$PythonPath)
$group='ProxyBridge TestLab - local runtime'
# NetSecurity rejects the IPv6 loopback literal in rule scopes. The current local
# runtime uses IPv4 loopback; do not broaden the rule to all IPv6 addresses.
$loopback=@('127.0.0.0/8')
$rows=@()
foreach($program in $programs){
    $full=[IO.Path]::GetFullPath($program)
    if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw 'TRAFFIC_FIREWALL_EXECUTABLE_MISSING'}
    $current=$full
    while($current){
        if(((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'TRAFFIC_FIREWALL_REPARSE_POINT'}
        $current=[IO.Path]::GetDirectoryName($current)
    }
    $hasher=[Security.Cryptography.SHA256]::Create()
    try{$key=([BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($full.ToLowerInvariant())))).Replace('-','').Substring(0,24)}finally{$hasher.Dispose()}
    $name='ProxyBridge-TestLab-Loopback-'+$key
    $rule=Get-NetFirewallRule -PolicyStore PersistentStore -Name $name -ErrorAction SilentlyContinue
    $created=$false
    if(-not $rule){
        $rule=New-NetFirewallRule -PolicyStore PersistentStore -Name $name -DisplayName ('ProxyBridge TestLab: loopback - '+[IO.Path]::GetFileName($full)) -Group $group `
            -Description 'Local traffic lab only. Managed per executable path; no public or private network ingress.' `
            -Program $full -Direction Inbound -Action Allow -Enabled True -Profile Any -Protocol Any `
            -LocalAddress $loopback -RemoteAddress $loopback -EdgeTraversalPolicy Block -ErrorAction Stop
        $created=$true
    }
    $application=$rule|Get-NetFirewallApplicationFilter
    $addresses=$rule|Get-NetFirewallAddressFilter
    $ports=$rule|Get-NetFirewallPortFilter
    # Compare the normalized addresses returned by Windows, not our own input string.
    $allowed=@('127.0.0.0/255.0.0.0','127.0.0.0/8')
    if(@($rule).Count -ne 1 -or $rule.Group -ne $group -or $application.Program -ine $full -or
       [string]$rule.Enabled -ne 'True' -or [string]$rule.Direction -ne 'Inbound' -or [string]$rule.Action -ne 'Allow' -or
       [string]$rule.Profile -ne 'Any' -or [string]$ports.Protocol -ne 'Any' -or
       [string]$rule.EdgeTraversalPolicy -ne 'Block' -or
       @($addresses.LocalAddress).Count -ne 1 -or @($addresses.RemoteAddress).Count -ne 1 -or
       @($addresses.LocalAddress|Where-Object {$_ -notin $allowed}).Count -or @($addresses.RemoteAddress|Where-Object {$_ -notin $allowed}).Count){throw 'TRAFFIC_FIREWALL_RULE_SCOPE_CHANGED'}
    $active=Get-NetFirewallRule -PolicyStore ActiveStore -Name $name -ErrorAction Stop
    if([string]$active.Enabled -ne 'True'){throw 'TRAFFIC_FIREWALL_RULE_NOT_ACTIVE'}
    $rows+=@{name=$name;created=$created;program_name=[IO.Path]::GetFileName($full);scope='IPv4-loopback-only'}
}
[ordered]@{verified=$true;profile_settings_changed=$false;rules=$rows}|ConvertTo-Json -Depth 4 -Compress
