[CmdletBinding()]
param([switch]$Administrator,[switch]$Run,[string]$ExpectedUserSid='',[ValidateRange(1024,65535)][int]$Port=5178,[string]$AssemblyPath='')
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$elevated=[Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($ExpectedUserSid -and $identity.User.Value -ne $ExpectedUserSid){throw 'UI_REQUIRES_SAME_USER_FOR_DPAPI_SETTINGS'}
$root=Split-Path -Parent $PSScriptRoot
$dotnet=Join-Path $env:ProgramFiles 'dotnet/dotnet.exe'
$assembly=Join-Path $root 'ui/ProxyBridge.TestLab.Ui/bin/Debug/net10.0-windows/ProxyBridge.TestLab.Ui.dll'
if($AssemblyPath){
    $assembly=[IO.Path]::GetFullPath($AssemblyPath)
    if(-not $assembly.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($assembly) -ne 'ProxyBridge.TestLab.Ui.dll'){throw 'UI_ASSEMBLY_OUTSIDE_THIS_WORKTREE'}
}
if(-not (Test-Path -LiteralPath $assembly -PathType Leaf)){throw 'UI_BUILD_REQUIRED'}
if($Administrator -and -not $elevated){
    $arguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',('"'+$PSCommandPath+'"'),'-Administrator','-Run','-ExpectedUserSid',$identity.User.Value,
        '-Port',$Port,'-AssemblyPath',('"'+$assembly+'"'))
    Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden
    Write-Output 'UI_UAC_REQUESTED; no driver installation or system-proxy change.'
    return
}
if(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $Port -State Listen -ErrorAction SilentlyContinue){throw 'UI_PORT_ALREADY_IN_USE'}
$arguments=@(('"'+$assembly+'"'),'--RepositoryRoot',('"'+$root+'"'),'--webroot',('"'+(Join-Path $root 'ui/ProxyBridge.TestLab.Ui/wwwroot')+'"'),
    '--UiPort',$Port,'--Logging:LogLevel:Default','Warning')
if($Run){$process=Start-Process -FilePath $dotnet -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru -Wait; exit $process.ExitCode}
$process=Start-Process -FilePath $dotnet -ArgumentList $arguments -WorkingDirectory $root -WindowStyle Hidden -PassThru
Write-Output ('UI_STARTED pid='+$process.Id+' administrator='+$elevated+' http://127.0.0.1:'+$Port)
