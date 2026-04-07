param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = $InputFile
)

$lines = Get-Content -Path $InputFile

function Get-MarkerIndex {
    param(
        [string[]]$Lines,
        [string]$Pattern,
        [int]$Start = 0
    )

    for ($i = $Start; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match [regex]::Escape($Pattern)) {
            return $i
        }
    }

    return $null
}

$keysAddedIndex = Get-MarkerIndex -Lines $lines -Pattern 'Keys added:'
if ($null -eq $keysAddedIndex) {
    Write-Error "The string 'Keys added:' was not found in the file."
    exit 1
}

$valuesDeletedIndex = Get-MarkerIndex -Lines $lines -Pattern 'Values deleted:' -Start ($keysAddedIndex + 1)
if ($null -eq $valuesDeletedIndex) {
    Write-Error "The string 'Values deleted:' was not found in the file."
    exit 1
}

$valuesAddedIndex = Get-MarkerIndex -Lines $lines -Pattern 'Values added:' -Start ($valuesDeletedIndex + 1)
if ($null -eq $valuesAddedIndex) {
    Write-Error "The string 'Values added:' was not found in the file."
    exit 1
}

$lineList = [System.Collections.Generic.List[string]]::new()
$lineList.AddRange($lines)

$deleteRanges = @(
    @{ Start = $keysAddedIndex;    Count = $valuesDeletedIndex - $keysAddedIndex }
    @{ Start = $valuesDeletedIndex; Count = $valuesAddedIndex - $valuesDeletedIndex }
) | Sort-Object Start -Descending

$deletedCount = 0

foreach ($range in $deleteRanges) {
    if ($range.Count -gt 0) {
        $lineList.RemoveRange($range.Start, $range.Count)
        $deletedCount += $range.Count
    }
}

Set-Content -Path $OutputFile -Value $lineList

Write-Output "Total lines deleted: $deletedCount"
