#Requires -RunAsAdministrator
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Enable','Disable')][string]$Mode)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Enable') {
    try { $secureBoot = Confirm-SecureBootUEFI -ErrorAction Stop }
    catch [System.PlatformNotSupportedException] { $secureBoot = $false }
    if ($secureBoot) { throw 'SECURE_BOOT_ENABLED: change the test machine firmware configuration before enabling TESTSIGNING.' }
}
$bcdedit = Join-Path $env:SystemRoot 'System32/bcdedit.exe'
$value = $(if ($Mode -eq 'Enable') { 'on' } else { 'off' })
# Do not disable other integrity policies or reboot from this helper.
& $bcdedit /set testsigning $value
if ($LASTEXITCODE -ne 0) { throw "TESTSIGNING_CONFIGURATION_FAILED: $LASTEXITCODE" }
& $bcdedit /enum
if ($LASTEXITCODE -ne 0) { throw 'TESTSIGNING_READBACK_FAILED' }
Write-Output 'Boot setting command succeeded; readback above. A restart is required to apply it. No restart was performed.'
