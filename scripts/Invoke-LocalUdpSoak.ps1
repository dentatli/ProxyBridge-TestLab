#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateSet('STANDARD','LONG','FAST','PARALLEL','MULTI_TARGET','MULTI_TARGET_LONG','LOG_FLUSH')][string]$Profile = 'STANDARD',
    [ValidateSet('FLUSH_EACH','BUFFERED')][string]$EvidenceLogMode = 'FLUSH_EACH',
    [string]$EvidenceDirectory = '',
    [string]$EnvPath = '',
    [string]$UdpProxyPythonPath = '',
    [switch]$Resume
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Profile -eq 'LOG_FLUSH' -and $EvidenceLogMode -ne 'FLUSH_EACH') { throw 'LOG_FLUSH_SELECTS_POLICY_PER_VARIANT' }
$packetCount = $(if ($Profile -in @('MULTI_TARGET_LONG','LOG_FLUSH')) { 40000 } elseif ($Profile -in @('LONG','FAST','PARALLEL','MULTI_TARGET')) { 20000 } else { 6000 })
$messageSize = $(if ($Profile -in @('LONG','FAST','PARALLEL','MULTI_TARGET','MULTI_TARGET_LONG','LOG_FLUSH')) { 1200 } else { 512 })
$intervalMs = $(if ($Profile -in @('FAST','PARALLEL','MULTI_TARGET','LOG_FLUSH')) { 0 } else { 20 })
$streams = $(if ($Profile -in @('PARALLEL','MULTI_TARGET','MULTI_TARGET_LONG','LOG_FLUSH')) { 2 } else { 1 })
$destinationMode = $(if ($Profile -in @('MULTI_TARGET','MULTI_TARGET_LONG','LOG_FLUSH')) { 'DISTINCT' } else { 'SHARED' })
$estimate = $(if ($Profile -in @('LONG','MULTI_TARGET_LONG')) { '65–80' } elseif ($Profile -in @('FAST','PARALLEL','MULTI_TARGET','LOG_FLUSH')) { '5–20' } else { '20–30' })
if ($Resume) {
    if (-not $EvidenceDirectory) { throw 'RESUME_REQUIRES_EVIDENCE_DIRECTORY' }
    $estimate = $(if ($Profile -in @('LONG','MULTI_TARGET_LONG')) { '10–20' } else { '1–5' })
}
if (-not $EnvPath) { $EnvPath = Join-Path $root 'artifacts/product-builds/driver-63be0eb-testlab-cli/product.env' }
if (-not $UdpProxyPythonPath) { $UdpProxyPythonPath = Join-Path $env:USERPROFILE '.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' }
if (-not $EvidenceDirectory) {
    $prefix = $(if ($Profile -eq 'LONG') { 'udp-soak-long-' } elseif ($Profile -eq 'FAST') { 'udp-soak-fast-' } elseif ($Profile -eq 'PARALLEL') { 'udp-soak-parallel-' } elseif ($Profile -eq 'MULTI_TARGET') { 'udp-soak-multi-target-' } elseif ($Profile -eq 'MULTI_TARGET_LONG') { 'udp-soak-multi-target-long-' } elseif ($Profile -eq 'LOG_FLUSH') { 'udp-log-flush-' } else { 'udp-soak-' })
    if ($EvidenceLogMode -eq 'BUFFERED') { $prefix += 'buffered-' }
    $name = $prefix + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,6)
    $EvidenceDirectory = Join-Path $root ('artifacts/local-route/' + $name)
}
$EvidenceDirectory = [IO.Path]::GetFullPath($EvidenceDirectory)
if ($Resume) {
    if (-not (Test-Path -LiteralPath (Join-Path $EvidenceDirectory 'comparison-manifest.json') -PathType Leaf)) { throw 'RESUME_MANIFEST_MISSING' }
} elseif (Test-Path -LiteralPath $EvidenceDirectory) { throw 'SOAK_REQUIRES_NEW_DIRECTORY' }
foreach ($file in @($EnvPath,$UdpProxyPythonPath)) { if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "SOAK_DEPENDENCY_MISSING_$file" } }
$parent = Split-Path -Parent $EvidenceDirectory
$null = New-Item -ItemType Directory -Path $parent -Force
if ($Profile -eq 'LOG_FLUSH') {
    Write-Host ('UDP через ProxyBridge/SOCKS5: flush per event vs buffered helper logs; 3 pairs, {0} packets/run, {1} bytes, pause {2} ms, warmup 100/stream.' -f $packetCount,$messageSize,$intervalMs)
    Write-Host 'Все packet/hash/route проверки сохранены; буфер 256 KiB в receiver/proxy; generator/product logs unchanged. Это часть стоимости инструментирования / This measures only helper file-flush policy.'
} else {
Write-Host ('UDP: напрямую / direct vs ProxyBridge + SOCKS5; profile {0}; 3 pairs, {1} packets/run, {2} bytes, pause {3} ms, warmup 100/stream.' -f $Profile,$packetCount,$messageSize,$intervalMs)
Write-Host ('Журналы receiver/proxy в обоих режимах / Receiver/proxy logs in both modes: {0}; buffer 256 KiB; generator/product logs unchanged. Все проверки сохранены / All assertions retained.' -f $EvidenceLogMode)
}
Write-Host ('Ориентировочно {0} минут / approximately {0} minutes. {1} UDP streams; one echo in flight per stream; not maximum throughput.' -f $estimate,$streams)
if ($streams -eq 2) { Write-Host ('Два одновременных сокета, по {0} обменов; прогрев 100 на каждый / Two concurrent sockets, {0} echoes and 100 warmup packets each. CPU/RAM генератора суммарные / Combined generator CPU/RAM.' -f ($packetCount/$streams)) }
if ($destinationMode -eq 'DISTINCT') { Write-Host 'Два контролируемых UDP-порта: по одному сокету на порт / Two controlled UDP destination ports: one socket per port. Ошибка двух сокетов к одному порту этим профилем не проверяется / Same-destination cross-stream defect is not exercised.' }
if ($Profile -in @('LONG','MULTI_TARGET_LONG')) { Write-Host 'Около 10 минут на соединение / approximately 10 minutes per connection; actual duration depends on Windows scheduling and RTT. Пауза после ответа, не фиксированная интенсивность / Pause after each reply, not a fixed offered rate.' }
if ($Profile -eq 'FAST') { Write-Host 'Без дополнительной паузы; один запрос в полёте / No added pause; one request in flight. Темп включает RTT и журналирование / Rate includes RTT and logging.' }
Write-Host ('Результаты / Results: ' + $EvidenceDirectory)
Start-Transcript -LiteralPath ($EvidenceDirectory + '.log') -Append:$Resume | Out-Null
try {
    & (Join-Path $PSScriptRoot 'Invoke-WfpUnruledComparison.ps1') -EnvPath $EnvPath -EvidenceDirectory $EvidenceDirectory -UdpProxyPythonPath $UdpProxyPythonPath -ComparisonMode $(if ($Profile -eq 'LOG_FLUSH') { 'LOGGING' } else { 'ROUTED' }) -EvidenceLogMode $EvidenceLogMode -PairCount 3 -PacketCount $packetCount -IntervalMs $intervalMs -MessageSize $messageSize -WarmupPackets 100 -Streams $streams -DestinationMode $destinationMode -AllowProductRuntime -Resume:$Resume | Out-Null
    $report = Get-Content -LiteralPath (Join-Path $EvidenceDirectory 'comparison-report.json') -Raw | ConvertFrom-Json
    Write-Host ('Сопоставимость / Comparability: ' + $report.status)
    Write-Host ('Отчёт / Report: ' + (Join-Path $EvidenceDirectory 'summary.md'))
    if ($report.status -ne 'LIMITED_COMPARISON') { throw 'SOAK_RESULTS_NOT_COMPARABLE' }
} finally { Stop-Transcript | Out-Null }
