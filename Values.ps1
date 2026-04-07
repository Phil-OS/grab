
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $false)]
    [string]$OutputFile = $InputFile
)

# Read all lines
$lines = Get-Content -Path $InputFile
$originalCount = $lines.Count

# ---- FIRST FILTER: Keep everything from "Values added:" onward ----
$index = $lines | Select-String -Pattern "Values added:" | Select-Object -First 1 | ForEach-Object { $_.LineNumber - 1 }

if ($null -ne $index) {
    $filtered = $lines[$index..($lines.Count - 1)]
    $deletedFirstPass = $index
    Set-Content -Path $OutputFile -Value $filtered
} else {
    Write-Error "The string 'Values added:' was not found in the file."
    exit 1
}

# ---- SECOND FILTER: Remove everything after "Values modified:" ----
$lines = Get-Content -Path $OutputFile

$cutIndex = $null
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match [regex]::Escape('Values modified:')) {
        $cutIndex = $i
        break
    }
}

if ($cutIndex -eq $null) {
    Write-Error "Marker 'Values modified:' not found."
    exit 1
}

$newLines = $lines[0..($cutIndex - 1)]
$deletedSecondPass = $lines.Count - $cutIndex

Set-Content -Path $OutputFile -Value $newLines

# ---- THIRD FILTER: Keep only lines containing "\Policy\" ----
$lines = Get-Content -Path $OutputFile

$result = @()
$keptCount = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -like "*\Policy\*") {
        $result += $lines[$i]
        $keptCount++
    }
}

$deletedThirdPass = $lines.Count - $keptCount

Set-Content -Path $OutputFile -Value $result

# ---- TOTAL REPORT ----
$totalDeleted = $deletedFirstPass + $deletedSecondPass + $deletedThirdPass

Write-Output "Total lines deleted: $totalDeleted"

# ---- REGISTRY DELETION ----
$lines = Get-Content -Path $OutputFile
$keysDeleted = 0

foreach ($line in $lines) {
    # Skip empty lines
    if ([string]::IsNullOrWhiteSpace($line)) { continue }

    # Extract path before first colon
    $regPathRaw = ($line -split ":", 2)[0].Trim()
    if ([string]::IsNullOrWhiteSpace($regPathRaw)) { continue }

    # Normalize hive prefix
    if ($regPathRaw -match '^(HKLM|HKEY_LOCAL_MACHINE)\\(.+)$') {
        $regPath = "Registry::HKEY_LOCAL_MACHINE\$($Matches[2])"
    } elseif ($regPathRaw -match '^(HKCU|HKEY_CURRENT_USER)\\(.+)$') {
        $regPath = "Registry::HKEY_CURRENT_USER\$($Matches[2])"
    } else {
        # Skip unsupported hives
        continue
    }

    # Check that key exists
    if (-not (Test-Path -LiteralPath $regPath)) { continue }

    try {
        # Take ownership
        $key = Get-Item -LiteralPath $regPath
        $acl = $key.GetAccessControl()
        $acl.SetOwner([System.Security.Principal.NTAccount]"BUILTIN\Administrators")
        $key.SetAccessControl($acl)

        # Delete key
       # Remove-Item -LiteralPath $regPath -Recurse -Force -ErrorAction Stop

        $keysDeleted++
    } catch {
        # Could not take ownership or delete
        continue
    }
}

#Write-Output "Registry keys deleted: $keysDeleted"
