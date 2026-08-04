Set-StrictMode -Version Latest

function Assert-True {
    param([Parameter(Mandatory)][bool]$Condition, [Parameter(Mandatory)][string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [Parameter(Mandatory)][string]$Message)
    if ($Expected -ne $Actual) { throw "ASSERTION FAILED: $Message; expected='$Expected' actual='$Actual'" }
}

function Assert-Throws {
    param([Parameter(Mandatory)][scriptblock]$Action, [Parameter(Mandatory)][string]$Pattern, [Parameter(Mandatory)][string]$Message)
    $matched = $false
    try { $null = & $Action } catch { $matched = $_.Exception.Message -match $Pattern }
    Assert-True $matched $Message
}

function New-TestDirectory {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ('proxybridge-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $path
    return $path
}

function Assert-NoUtf8Bom {
    param([string]$Path, [string]$Message)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    Assert-True (-not $hasBom) $Message
}

function Assert-SequenceEqual {
    param([object[]]$Expected, [object[]]$Actual, [string]$Message)
    Assert-Equal @($Expected).Count @($Actual).Count "$Message count"
    for ($index = 0; $index -lt @($Expected).Count; $index++) {
        Assert-Equal ([string]$Expected[$index]) ([string]$Actual[$index]) "$Message index=$index"
    }
}

function Write-TestUtf8NoBom {
    param([string]$Path, [AllowEmptyString()][string]$Text)
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory -Force }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}
