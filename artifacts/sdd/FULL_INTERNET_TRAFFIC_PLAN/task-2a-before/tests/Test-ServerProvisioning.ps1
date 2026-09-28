[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui'
$probeDll = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui.ServerProbe\bin\Release\net10.0-windows\ProxyBridge.TestLab.Ui.ServerProbe.dll'
$dotnet = 'C:\Program Files\dotnet\dotnet.exe'

Assert-True (Test-Path -LiteralPath $probeDll -PathType Leaf) 'server provisioning probe must be built before the targeted test'
$probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('proxybridge-testlab-server-' + [guid]::NewGuid().ToString('N'))
try {
    $probeOutput = & $dotnet $probeDll $probeRoot
    Assert-Equal 0 $LASTEXITCODE 'server provisioning probe exit code'
    Assert-True (@($probeOutput) -contains 'PASS: offline server provisioning state machine') 'server provisioning probe result'

    $program = Get-Content -LiteralPath (Join-Path $uiRoot 'Program.cs') -Raw
    $transport = Get-Content -LiteralPath (Join-Path $uiRoot 'Services\ServerTransport.cs') -Raw
    $artifactBuilder = Get-Content -LiteralPath (Join-Path $uiRoot 'Services\ServerArtifactBuilder.cs') -Raw
    $schema = Get-Content -LiteralPath (Join-Path $uiRoot 'Services\SettingsSchema.cs') -Raw
    $javascript = Get-Content -LiteralPath (Join-Path $uiRoot 'wwwroot\app.js') -Raw

    Assert-True ($program -match 'MapPost\("/server/validate"') 'server validation endpoint must exist'
    Assert-True ($program -match 'MapPost\("/server/plan"') 'server plan endpoint must exist'
    Assert-True ($program -match 'MapPost\("/server/protocol-smoke"') 'server UI must expose the isolated protocol endpoint smoke'
    $smokeService = Get-Content -LiteralPath (Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui\Services\ServerProtocolSmokeService.cs') -Raw -Encoding UTF8
    Assert-True ($smokeService -match 'FirstOrDefault\(IsProtocolSmokeSummary\)') 'protocol smoke must select its tagged summary instead of trusting unrelated process output'
    Assert-True ($program -match 'MapPost\("/server/apply"') 'server apply endpoint must exist'
    Assert-True ($program -match 'MapPost\("/runs/dry-run"') 'Milestone 4 run mutations must retain an explicit review endpoint'
    Assert-True ($transport -match 'StrictHostKeyChecking=yes') 'SSH must fail closed on host-key changes'
    Assert-True ($transport -match 'sudo -n -u proxybridge-testlab python3 -B /opt/proxybridge-testlab/current/pb_server_agent.py --self-test') 'installed manifest verification must run as the service identity that can read the protected TestLab key'
    Assert-True ($transport -match 'StrictHostKeyChecking=accept-new' -and $transport -match 'host-key-probe-') 'host-key discovery must have a protected authenticated fallback for incompatible ssh-keyscan KEX'
    Assert-True ($transport -match 'HashKnownHosts=no' -and $transport -match 'Directory\.Delete\(resolvedProbe, recursive: true\)') 'temporary host-key fallback must be exact-target parseable and securely removed'
    Assert-True ($transport -match 'PasswordAuthentication=no') 'SSH password authentication must be disabled'
    Assert-True ($transport -match 'BatchMode=yes') 'SSH must be non-interactive'
    Assert-True ($transport -match 'server-plugin-manifest\.json' -and $transport -match 'PLUGIN_SELFTEST') 'server discovery and verification must require the installed plugin manifest self-test'
    Assert-True ($transport -match 'backup_captured=0' -and $transport -match 'if \[ "\$backup_captured" -eq 1 \]') 'rollback must not touch the prior installation before its backup is complete'
    Assert-True ($transport -match 'find "\$version" -type d -exec chmod 0755') 'installed plugin directories must be readable by the unprivileged service account'
    Assert-True ($transport -match 'chmod 0600 "\$version/tls/server\.key\.pem"') 'protocol private key must remain readable only by the service account'
    Assert-True ($artifactBuilder -match 'ExecStartPre=.+pb_server_agent\.py --self-test') 'systemd readiness must run the server plugin self-test before endpoint start'
    Assert-True ($artifactBuilder -match 'ExecStartPre=.+pb_protocol_server\.py --self-test' -and $artifactBuilder -match 'pb_server_agent\.py --serve') 'protocol server must be self-tested and supervised by the endpoint agent'
    $protocolSmoke = Get-Content -LiteralPath (Join-Path $repoRoot 'scripts\Invoke-ProtocolOnlySmoke.ps1') -Raw
    Assert-True ($protocolSmoke -match "'protocol-dns-udp-direct'" -and $protocolSmoke -match "'protocol-https-direct'") 'protocol-only smoke must cover DNS through HTTPS'
    Assert-True ($protocolSmoke -match 'proxybridge_started=\$false') 'protocol-only smoke must explicitly prove that product startup is absent'
    Assert-True ($protocolSmoke -notmatch 'ProxyBridgeCli|Invoke-ProxyBridge|PrepareRuntimeEnvironment') 'protocol-only smoke must not contain a product or driver launch path'
    Assert-True ($schema -notmatch 'GUI SHA-256|CLI SHA-256|Driver SHA-256|Client SHA-256') 'manual SHA-256 fields must be absent'
    Assert-True ($schema -notmatch 'Client executable path') 'client executable path field must be absent'
    Assert-True ($schema -match 'server_connection\.username.+false, true') 'SSH user must be a public required field'
    Assert-True ($javascript -match 'validateServer') 'server UI must require an explicit validation action'

    $families = Get-Content -LiteralPath (Join-Path $repoRoot 'config\protocol-families.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $pluginCatalog = Get-Content -LiteralPath (Join-Path $repoRoot 'src\server_agent\plugins\catalog.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $expectedPluginIds = @($families.families | Where-Object delivery_status -ne 'UNSUPPORTED_PRODUCT_SCOPE' | Select-Object -ExpandProperty server_plugin_id | Sort-Object -Unique)
    $catalogPluginIds = @($pluginCatalog.plugins | Select-Object -ExpandProperty id | Sort-Object -Unique)
    Assert-SequenceEqual $expectedPluginIds $catalogPluginIds 'server plugin catalog must cover every supported protocol family'
    Assert-Equal 17 @($pluginCatalog.plugins | Where-Object implementation_status -eq 'IMPLEMENTED').Count 'Milestone 16 endpoint plugins'

    $python = Get-Command python -ErrorAction SilentlyContinue
    Assert-True ($null -ne $python) 'Python is required for the offline server-agent contract test'
    $agentRoot = Join-Path $probeRoot 'agent-contract'
    $null = New-Item -ItemType Directory -Path (Join-Path $agentRoot 'plugins') -Force
    Copy-Item -LiteralPath (Join-Path $repoRoot 'src\server_agent\pb_server_agent.py') -Destination (Join-Path $agentRoot 'pb_server_agent.py')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'src\pb_net_endpoint.py') -Destination (Join-Path $agentRoot 'pb_net_endpoint.py')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'src\server_agent\plugins\catalog.json') -Destination (Join-Path $agentRoot 'plugins\catalog.json')
    $manifest = [pscustomobject][ordered]@{
        schema_version=1;agent_contract_version=1
        artifacts=@(
            [pscustomobject]@{path='pb_net_endpoint.py';sha256=(Get-FileHash -LiteralPath (Join-Path $agentRoot 'pb_net_endpoint.py') -Algorithm SHA256).Hash.ToLowerInvariant()},
            [pscustomobject]@{path='pb_server_agent.py';sha256=(Get-FileHash -LiteralPath (Join-Path $agentRoot 'pb_server_agent.py') -Algorithm SHA256).Hash.ToLowerInvariant()},
            [pscustomobject]@{path='plugins/catalog.json';sha256=(Get-FileHash -LiteralPath (Join-Path $agentRoot 'plugins\catalog.json') -Algorithm SHA256).Hash.ToLowerInvariant()}
        )
        plugins=@([pscustomobject]@{id='endpoint-core';implementation_status='IMPLEMENTED';milestone=8;artifacts=@('pb_net_endpoint.py');capabilities=@('server_endpoint_core')})
    }
    $manifestPath = Join-Path $agentRoot 'server-plugin-manifest.json'
    Write-TestUtf8NoBom $manifestPath (($manifest | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
    $agentOutput = & $python.Source -I -B (Join-Path $agentRoot 'pb_server_agent.py') --self-test --manifest $manifestPath
    Assert-Equal 0 $LASTEXITCODE 'offline server-agent self-test exit code'
    Assert-Equal 'SERVER_AGENT_SELF_TEST_OK plugins=1' ([string]$agentOutput).Trim() 'offline server-agent self-test output'
    [System.IO.File]::AppendAllText((Join-Path $agentRoot 'pb_net_endpoint.py'), '#tamper' + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    $savedErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $agentFailure = @(& $python.Source -I -B (Join-Path $agentRoot 'pb_server_agent.py') --self-test --manifest $manifestPath 2>&1)
        $agentFailureExit = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $savedErrorAction }
    Assert-True ($agentFailureExit -ne 0) 'tampered server artifact must fail the plugin self-test'
    Assert-True ([string]($agentFailure -join '') -match 'SERVER_AGENT_ERROR ARTIFACT_HASH_MISMATCH') 'tamper failure must expose only the stable error code'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedProbe = [System.IO.Path]::GetFullPath($probeRoot)
    if ($resolvedProbe.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedProbe).StartsWith('proxybridge-testlab-server-', [System.StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedProbe) { Remove-Item -LiteralPath $resolvedProbe -Recurse -Force }
    }
}

'PASS: guarded offline server provisioning'
