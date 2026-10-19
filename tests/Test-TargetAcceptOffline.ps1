$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
foreach ($relative in @('scripts/Invoke-TargetAccept.ps1','modules/TargetAcceptNative.psm1')) {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root $relative),[ref]$tokens,[ref]$errors)
    if ($errors.Count) {throw ($errors | Out-String)}
}
Import-Module (Join-Path $root 'modules/TargetAcceptNative.psm1') -Force
Initialize-TargetTcpTable
$rows=@([PBTargetTcpTable]::Read())
if (-not $rows.Count -or @($rows | Where-Object {$_.LocalPort -lt 0 -or $_.LocalPort -gt 65535 -or $_.State -lt 1 -or $_.State -gt 12}).Count) {throw 'TCP_TABLE_SMOKE_INVALID'}
# Read-only API smoke: no sockets created and no product/traffic started.
Write-Output ('TARGET_PS_PARSER_AND_TCP_TABLE_READ_PASSED rows='+$rows.Count)
