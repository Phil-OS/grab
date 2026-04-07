param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = $InputFile
)

# Read all lines
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
$valuesDeletedIndex = Get-MarkerIndex -Lines $lines -Pattern 'Values deleted:' -Start ($keysAddedIndex + 1)
$valuesAddedIndex = Get-MarkerIndex -Lines $lines -Pattern 'Values added:' -Start ($valuesDeletedIndex + 1)

if ($keysAddedIndex -eq $null -or $valuesDeletedIndex -eq $null -or $valuesAddedIndex -eq $null) {
    Write-Error "One or more required markers were not found in the file."
    exit 1
}

# Convert array to List[string] properly
$lineList = [System.Collections.Generic.List[string]]::new()
foreach ($line in $lines) { $lineList.Add($line) }

# Define ranges to remove
$deleteRanges = @(
    @{ Start = $keysAddedIndex;    Count = $valuesDeletedIndex - $keysAddedIndex }
    @{ Start = $valuesDeletedIndex; Count = $valuesAddedIndex - $valuesDeletedIndex }
) | Sort-Object Start -Descending  # delete from end first to avoid offset issues

$deletedCount = 0

foreach ($range in $deleteRanges) {
    # Ensure Count does not exceed list bounds
    $safeCount = [Math]::Min($range.Count, $lineList.Count - $range.Start)
    if ($safeCount -gt 0) {
        $lineList.RemoveRange($range.Start, $safeCount)
        $deletedCount += $safeCount
    }
}

# Write back to file
Set-Content -Path $OutputFile -Value $lineList

Write-Output "Total lines deleted: $deletedCount"
