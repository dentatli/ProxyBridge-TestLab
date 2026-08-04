[CmdletBinding()]param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'TestSupport.ps1')
$root = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'modules/Env.psm1') -Force
Import-Module (Join-Path $root 'modules/Report.psm1') -Force
$environment = Import-DotEnv -Path (Join-Path $PSScriptRoot 'fixtures/.env.test')
$rawPath = $environment['PB_SSH_KEY']; $escapedPath = $rawPath.Replace('\', '\\')
$text = "raw=$rawPath escaped=$escapedPath host=$($environment['PB_SSH_HOST']) user=$($environment['PB_SSH_USER']) ip=$($environment['PB_VPS_IPV4']) secret=$($environment['PB_FIXTURE_SECRET']) ProxyConfigId=1"
$safe = Protect-SensitiveText -Text $text -Environment $environment
foreach ($value in @($rawPath, $escapedPath, $environment['PB_SSH_HOST'], $environment['PB_SSH_USER'], $environment['PB_VPS_IPV4'], $environment['PB_FIXTURE_SECRET'])) { Assert-True (-not $safe.Contains($value)) 'raw and escaped sensitive values must be redacted' }
Assert-True ($safe -match 'ProxyConfigId=1') 'short harmless scalar must remain'
$shortEnvironment = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$shortEnvironment['PB_SSH_USER'] = 'x'
$shortSafe = Protect-SensitiveText -Text 'PB_SSH_USER=x note=x ProxyConfigId=1' -Environment $shortEnvironment
Assert-True ($shortSafe -match 'PB_SSH_USER=\[REDACTED\]') 'short sensitive keyed value must be redacted'
Assert-True ($shortSafe -match 'note=x') 'short sensitive value must not be replaced globally'
Assert-True ($shortSafe -match 'ProxyConfigId=1') 'short harmless scalar must survive short-secret redaction'
$shortJson = Protect-SensitiveText -Text '{"PB_SSH_USER":"x","ProxyConfigId":1}' -Environment $shortEnvironment
$shortJsonObject = $shortJson | ConvertFrom-Json
Assert-Equal '[REDACTED]' $shortJsonObject.PB_SSH_USER 'quoted short secret must preserve valid JSON'
Assert-Equal 1 $shortJsonObject.ProxyConfigId 'quoted short-secret redaction must preserve harmless JSON scalar'
$temp = New-TestDirectory
try {
    $report = New-RunReport -OutputRoot $temp -RunId 'redaction'
    Write-SafeTranscript -Report $report -Environment $environment -Message $text
    Add-RedactedJsonLine -Path $report.selection_path -Environment $environment -Record ([pscustomobject]@{ reason = $text })
    $structuredPath = Join-Path $report.run_root 'structured.json'
    $structuredJsonl = Join-Path $report.run_root 'structured.jsonl'
    $emptyArrayPath = Join-Path $report.run_root 'empty-array.json'
    $structured = [pscustomobject][ordered]@{
        PB_SSH_PORT = 22
        ProxyConfigId = 1
        actual_path = $rawPath
        PB_SSH_HOST = $environment['PB_SSH_HOST']
        PB_VPS_IPV4 = $environment['PB_VPS_IPV4']
        values = @($rawPath, $escapedPath, $environment['PB_SSH_HOST'], 'public-value')
    }
    Write-RedactedJsonReport -Value $structured -Path $structuredPath -Environment $environment
    Write-RedactedJsonReport -Value @() -Path $emptyArrayPath -Environment $environment
    Add-RedactedJsonLine -Path $structuredJsonl -Record $structured -Environment $environment
    $parsedStructured = Get-Content -LiteralPath $structuredPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal '[REDACTED]' $parsedStructured.PB_SSH_PORT 'sensitive numeric property must become a JSON string'
    Assert-Equal 1 $parsedStructured.ProxyConfigId 'harmless numeric scalar must retain its type and value'
    Assert-Equal '[REDACTED]' $parsedStructured.actual_path 'path property must be redacted structurally'
    $emptyArrayJson = Get-Content -LiteralPath $emptyArrayPath -Raw -Encoding UTF8
    $null = $emptyArrayJson | ConvertFrom-Json
    Assert-Equal '[]' $emptyArrayJson.Trim() 'empty structured array must retain JSON array form'
    foreach ($line in @(Get-Content -LiteralPath $structuredJsonl -Encoding UTF8 | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) { $null = $line | ConvertFrom-Json }
    Assert-NoUtf8Bom $report.transcript_path 'transcript must have no BOM'
    Assert-NoUtf8Bom $report.selection_path 'JSONL must have no BOM'
    Assert-NoUtf8Bom $structuredPath 'structured JSON must have no BOM'
    Assert-NoUtf8Bom $structuredJsonl 'structured JSONL must have no BOM'
    foreach ($path in @($report.transcript_path, $report.selection_path)) {
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        Assert-True (-not $content.Contains($rawPath)) 'report boundary must redact path'
        Assert-True (-not $content.Contains($escapedPath)) 'report boundary must redact escaped path'
    }
    foreach ($path in @($structuredPath, $structuredJsonl)) {
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        foreach ($value in @($rawPath, $escapedPath, $environment['PB_SSH_HOST'], $environment['PB_VPS_IPV4'])) { Assert-True (-not $content.Contains($value)) 'structured output must not contain protected values' }
    }
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
'PASS: redaction'
