[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')

$repoRoot = Split-Path -Parent $PSScriptRoot
$uiRoot = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui'
$probeDll = Join-Path $repoRoot 'ui\ProxyBridge.TestLab.Ui.SecurityProbe\bin\Release\net10.0-windows\ProxyBridge.TestLab.Ui.SecurityProbe.dll'
$dotnet = 'C:\Program Files\dotnet\dotnet.exe'

Assert-True (Test-Path -LiteralPath $probeDll -PathType Leaf) 'settings security probe must be built before the targeted test'
$probeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('proxybridge-testlab-settings-' + [guid]::NewGuid().ToString('N'))
try {
    $probeOutput = & $dotnet $probeDll $probeRoot
    Assert-Equal 0 $LASTEXITCODE 'settings security probe exit code'
    Assert-True (@($probeOutput) -contains 'PASS: UI settings security probe') 'settings security probe result'

    $publicPath = Join-Path $probeRoot 'app-storage\config\settings.json'
    $protectedPath = Join-Path $probeRoot 'app-storage\config\secrets.dpapi'
    Assert-True (Test-Path -LiteralPath $publicPath -PathType Leaf) 'public settings must be persisted'
    Assert-True (Test-Path -LiteralPath $protectedPath -PathType Leaf) 'protected settings must be persisted'
    $publicText = Get-Content -LiteralPath $publicPath -Raw
    $protectedText = Get-Content -LiteralPath $protectedPath -Raw
    foreach ($privateValue in @('fixture-host.invalid', 'fixture_ed25519', '192.0.2.20', '198.51.100.10')) {
        Assert-True ($publicText -notmatch [regex]::Escape($privateValue)) 'public settings must not contain protected values'
        Assert-True ($protectedText -notmatch [regex]::Escape($privateValue)) 'DPAPI envelope must not contain protected plaintext'
    }
    Assert-True ($publicText -match 'fixture-user') 'SSH user must be stored as a normal public setting'
    Assert-True ($protectedText -match 'DPAPI_CURRENT_USER') 'protected settings must declare DPAPI CurrentUser'

    $program = Get-Content -LiteralPath (Join-Path $uiRoot 'Program.cs') -Raw
    $javascript = Get-Content -LiteralPath (Join-Path $uiRoot 'wwwroot\app.js') -Raw
    $schema = Get-Content -LiteralPath (Join-Path $uiRoot 'Services\SettingsSchema.cs') -Raw
    $styles = Get-Content -LiteralPath (Join-Path $uiRoot 'wwwroot\styles.css') -Raw
    Assert-True ($program -match 'X-TestLab-CSRF') 'mutating settings endpoints must require a request token'
    Assert-True ($program -match 'Headers\.Origin') 'mutating settings endpoints must require same origin'
    Assert-True ($program -match 'MapPost\("/runs/dry-run"') 'guarded run review endpoint must remain available'

    $html = Get-Content -LiteralPath (Join-Path $uiRoot 'wwwroot\index.html') -Raw
    Assert-True ($html -match 'No manual environment file is required') 'UI must state the UI-only configuration contract'
    Assert-True ($html -match 'Protected values are encrypted') 'UI must explain protected storage'
    Assert-True ($javascript -notmatch 'data-sensitive="true" type="password"') 'non-password protected settings must not trigger browser password storage prompts'
    Assert-True ($javascript -match 'data-sensitive="true" type="text" autocomplete="off"') 'protected settings must retain explicit local-only autocomplete suppression'
    Assert-True ($schema -match 'new\("proxy", "Proxy tests"') 'SOCKS settings must be explained as proxy-test configuration'
    Assert-True ($schema -match 'Listener ports and server evidence paths are managed automatically') 'traffic endpoint automation must be explicit'
    Assert-True ($javascript -match 'advancedSettingsSections' -and $javascript -match 'settings-advanced-fields') 'technical defaults must be grouped under advanced settings'
    Assert-True ($javascript -match 'function beginButtonAction' -and $javascript -match 'button\.dataset\.busy === "true"') 'async UI actions must reject repeat clicks immediately'
    Assert-True ($javascript -match 'Trusting host\.\.\.' -and $javascript -match 'Applying and verifying\.\.\.') 'long server actions must expose human-readable progress'
    Assert-True ($styles -match '\.button\[aria-busy="true"\]') 'busy buttons must have a visible progress treatment'
}
finally {
    $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    $resolvedProbe = [System.IO.Path]::GetFullPath($probeRoot)
    if ($resolvedProbe.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase) -and
        [System.IO.Path]::GetFileName($resolvedProbe).StartsWith('proxybridge-testlab-settings-', [System.StringComparison]::Ordinal)) {
        if (Test-Path -LiteralPath $resolvedProbe) { Remove-Item -LiteralPath $resolvedProbe -Recurse -Force }
    }
}

'PASS: UI-managed settings and secret boundary'
