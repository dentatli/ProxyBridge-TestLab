Set-StrictMode -Version Latest

function Get-CaseSignature {
    param($Case, [string[]]$Names)
    return (($Names | ForEach-Object { "$_=$($Case.$_)" }) -join ';')
}

function Get-PairKeys {
    param($Case, [string[]]$Names)
    $keys = [System.Collections.Generic.List[string]]::new()
    for ($left = 0; $left -lt $Names.Count; $left++) {
        for ($right = $left + 1; $right -lt $Names.Count; $right++) {
            $leftValue = $Case.($Names[$left]) | ConvertTo-Json -Compress
            $rightValue = $Case.($Names[$right]) | ConvertTo-Json -Compress
            $keys.Add("$left|$leftValue|$right|$rightValue")
        }
    }
    return $keys.ToArray()
}

function Add-CartesianCases {
    param([string[]]$Names, $Dimensions, [int]$Index, [hashtable]$Current, $Output)
    if ($Index -ge $Names.Count) {
        $copy = [ordered]@{}
        foreach ($name in $Names) { $copy[$name] = $Current[$name] }
        $Output.Add([pscustomobject]$copy)
        return
    }
    $name = $Names[$Index]
    foreach ($value in @($Dimensions.$name)) {
        $Current[$name] = $value
        Add-CartesianCases -Names $Names -Dimensions $Dimensions -Index ($Index + 1) -Current $Current -Output $Output
    }
}

function Get-DeterministicPairwiseCases {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dimensions)

    $names = @($Dimensions.PSObject.Properties.Name)
    if ($names.Count -lt 2) { throw 'Pairwise generation requires at least two dimensions.' }
    foreach ($name in $names) {
        if (@($Dimensions.$name).Count -eq 0) { throw "Pairwise dimension '$name' has no values." }
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    Add-CartesianCases -Names $names -Dimensions $Dimensions -Index 0 -Current @{} -Output $candidates
    $uncovered = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($candidate in $candidates) {
        foreach ($key in @(Get-PairKeys -Case $candidate -Names $names)) { $null = $uncovered.Add($key) }
    }

    $selected = [System.Collections.Generic.List[object]]::new()
    $remaining = @($candidates | Sort-Object { Get-CaseSignature -Case $_ -Names $names })
    while ($uncovered.Count -gt 0) {
        $best = $null
        $bestScore = -1
        foreach ($candidate in $remaining) {
            $score = 0
            foreach ($key in @(Get-PairKeys -Case $candidate -Names $names)) { if ($uncovered.Contains($key)) { $score++ } }
            if ($score -gt $bestScore) { $best = $candidate; $bestScore = $score }
        }
        if ($null -eq $best -or $bestScore -le 0) { throw 'Pairwise generator could not cover remaining pairs.' }
        $selected.Add($best)
        foreach ($key in @(Get-PairKeys -Case $best -Names $names)) { $null = $uncovered.Remove($key) }
        $signature = Get-CaseSignature -Case $best -Names $names
        $remaining = @($remaining | Where-Object { (Get-CaseSignature -Case $_ -Names $names) -ne $signature })
    }
    return $selected.ToArray()
}

function Test-PairwiseCoverage {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Dimensions, [Parameter(Mandatory)][object[]]$Cases)
    $names = @($Dimensions.PSObject.Properties.Name)
    $required = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $cartesian = [System.Collections.Generic.List[object]]::new()
    Add-CartesianCases -Names $names -Dimensions $Dimensions -Index 0 -Current @{} -Output $cartesian
    foreach ($candidate in $cartesian) { foreach ($key in @(Get-PairKeys -Case $candidate -Names $names)) { $null = $required.Add($key) } }
    foreach ($case in $Cases) { foreach ($key in @(Get-PairKeys -Case $case -Names $names)) { $null = $required.Remove($key) } }
    return [pscustomobject]@{ covered = ($required.Count -eq 0); missing_pairs = $required.Count }
}

Export-ModuleMember -Function Get-DeterministicPairwiseCases, Test-PairwiseCoverage
