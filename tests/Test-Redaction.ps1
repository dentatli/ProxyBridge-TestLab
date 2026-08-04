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
    Assert-NoUtf8Bom $report.transcript_path 'transcript must have no BOM'
    Assert-NoUtf8Bom $report.selection_path 'JSONL must have no BOM'
    foreach ($path in @($report.transcript_path, $report.selection_path)) {
        $content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        Assert-True (-not $content.Contains($rawPath)) 'report boundary must redact path'
        Assert-True (-not $content.Contains($escapedPath)) 'report boundary must redact escaped path'
    }
}
finally { Remove-Item -LiteralPath $temp -Recurse -Force }
'PASS: redaction'
