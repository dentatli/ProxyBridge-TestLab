[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
foreach ($module in @('Env','Config','HealthChecks','ProxyBridgeCli','Assertions')) { Import-Module (Join-Path $root "modules/$module.psm1") -Force }

$environment = Import-DotEnv (Join-Path $PSScriptRoot 'fixtures/.env.test')
$files = @{}
$files[$environment['PB_CLIENT_EXE']] = $environment['PB_EXPECTED_CLIENT_SHA256']
$files[$environment['PB_PROXYBRIDGE_CLI_EXE']] = $environment['PB_EXPECTED_PROXYBRIDGE_CLI_SHA256']
$files[$environment['PB_PROXYBRIDGE_EXE']] = $environment['PB_EXPECTED_PROXYBRIDGE_EXE_SHA256']
$files[$environment['PB_DRIVER_PATH']] = $environment['PB_EXPECTED_DRIVER_SHA256']
$tcp = @{}
$tcp[$environment['PB_VPS_IPV4'] + ':' + $environment['PB_ENDPOINT_A_PORT']] = $true
$tcp[$environment['PB_VPS_IPV4'] + ':' + $environment['PB_ENDPOINT_B_PORT']] = $true
$tcp[$environment['PB_SOCKS_HOST'] + ':' + $environment['PB_SOCKS_PORT']] = $true
$healthAdapter = New-MockHealthCheckAdapter -Files $files -Processes @() -ServiceState ([pscustomobject]@{exists=$true;state='Running'}) -TcpResults $tcp
$health = @(Invoke-HealthCheckPlan -Plan (New-HealthCheckPlan $environment) -Environment $environment -Adapter $healthAdapter)
Assert-True (Test-HealthResults $health).passed 'configured mock health checks must pass'
Assert-True (@($health | Where-Object status -eq 'NOT_EXECUTED').Count -eq 0) 'real-smoke preflight must not use NOT_EXECUTED'
Assert-True (@($health | Where-Object id -eq 'endpoint-b-reachability').Count -eq 1) 'issue206 first endpoint must be preflighted'

$conflictAdapter = New-MockHealthCheckAdapter -Files $files -Processes @([pscustomobject]@{name='ProxyBridge';pid=10}) -ServiceState ([pscustomobject]@{exists=$true;state='Running'}) -TcpResults $tcp
$conflict = @(Invoke-HealthCheckPlan -Plan (New-HealthCheckPlan $environment) -Environment $environment -Adapter $conflictAdapter)
Assert-True (-not (Test-HealthResults $conflict).passed) 'conflicting product process must fail preflight'

$missingServiceAdapter = New-MockHealthCheckAdapter -Files $files -Processes @() -ServiceState ([pscustomobject]@{exists=$false;state='MISSING'}) -TcpResults $tcp
$missingService = @(Invoke-HealthCheckPlan -Plan (New-HealthCheckPlan $environment) -Environment $environment -Adapter $missingServiceAdapter)
Assert-Equal 'FAIL_INFRASTRUCTURE' ($missingService | Where-Object id -eq 'driver-service-state').status 'configured missing service must fail preflight precisely'

Assert-Equal 'new-cli-profile-boundary' (New-ResetPlan rules_only).operation 'rules_only must create a new CLI/profile boundary'
Assert-True (New-ResetPlan driver).manual_only 'driver reset must remain manual-only'
Assert-True (New-ResetPlan vm).manual_only 'VM reset must remain manual-only'

$suite = Import-SuiteConfig (Join-Path $root 'config/suites/mock-full.json')
Assert-True (Test-ShouldStopRun 'FAIL_INFRASTRUCTURE' $suite 0) 'infrastructure failure must stop'
Assert-True (-not (Test-ShouldStopRun 'EXPECTED_FAIL' $suite 0)) 'expected failure must continue'
Assert-True (Test-ShouldStopRun 'FAIL_PRODUCT' $suite 5) 'max consecutive product failures must stop'

'PASS: mock runtime'
