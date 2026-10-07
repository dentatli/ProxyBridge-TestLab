[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$workspace=(Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
$targets=@(
    'artifacts\diagnostics\tcp-pull-trace-20261001-190248-ba3e5b\WPR_initiated_WprApp_WPR Event Collector.etl',
    'artifacts\diagnostics\tcp-pull-trace-20261001-190248-ba3e5b\WPR_initiated_WprApp_WPR System Collector.etl',
    'artifacts\diagnostics\symbols\msedge.dll.pdb\98A07F48065B9D454C4C44205044422E1\downloadBE6BDB0E72104CE498664E83CB2590C8.error'
)
$receiptPath=Join-Path $workspace 'artifacts/diagnostics/disk-cleanup-20261002.json'
$rows=@()
$before=([IO.DriveInfo]::new([IO.Path]::GetPathRoot($workspace))).AvailableFreeSpace
foreach ($target in $targets) {
    $path=[IO.Path]::GetFullPath((Join-Path $workspace $target))
    if (-not $path.StartsWith($workspace+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'CLEANUP_OUTSIDE_PROJECT' }
    $bytes=0
    if (Test-Path -LiteralPath $path) {
        $file=Get-Item -LiteralPath $path
        if ($file.PSIsContainer) { throw 'CLEANUP_REQUIRES_FILE' }
        $bytes=$file.Length
    }
    $rows+= [ordered]@{relative_path=$target;bytes=$bytes;removed=$false;already_absent=($bytes -eq 0 -and -not (Test-Path -LiteralPath $path))}
}
$receipt=[ordered]@{started_at_utc=[DateTime]::UtcNow.ToString('o');scope='THREE_EXPLICIT_FILES_ONLY';free_bytes_before=$before;files=$rows;status='PREPARED'}
function Save-Receipt { [IO.File]::WriteAllText($receiptPath,($receipt | ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false)) }
Save-Receipt
try {
    foreach ($row in $rows) {
        if ($row.already_absent) { continue }
        $path=(Resolve-Path -LiteralPath (Join-Path $workspace $row.relative_path)).Path
        if (-not $path.StartsWith($workspace+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'CLEANUP_OUTSIDE_PROJECT' }
        Remove-Item -LiteralPath $path -Force
        $row.removed= -not (Test-Path -LiteralPath $path)
        Save-Receipt
    }
    $receipt.status='COMPLETED'
} catch { $receipt.status='FAILED';$receipt['error']=$_.Exception.Message;throw }
finally {
    $receipt['free_bytes_after']=([IO.DriveInfo]::new([IO.Path]::GetPathRoot($workspace))).AvailableFreeSpace
    $removedBytes=[long]0
    foreach ($row in $rows) { if ($row['removed']) { $removedBytes += [long]$row['bytes'] } }
    $receipt['removed_bytes']=$removedBytes
    Save-Receipt
}
Write-Host ('Freed: {0:N2} GiB; free C: {1:N2} GiB' -f ($receipt.removed_bytes/1GB),($receipt.free_bytes_after/1GB))
