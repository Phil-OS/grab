#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

function Assert-TrustedParent {
    param([string]$Path, [switch]$AllowMissing)
    $trusted = @('S-1-5-18','S-1-5-32-544',
        'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
    $write = [Security.AccessControl.FileSystemRights]::Write -bor
        [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    $replacement = [Security.AccessControl.FileSystemRights]::Delete -bor
        [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [Security.AccessControl.FileSystemRights]::TakeOwnership
    $parent = [IO.Path]::GetDirectoryName($Path)
    $current = $Path
    while ($current) {
        if ($AllowMissing -and -not (Test-Path -LiteralPath $current)) {
            $current = [IO.Path]::GetDirectoryName($current)
            continue
        }
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw ('Installation path contains a junction or symbolic link: ' + $current)
        }
        $acl = Get-Acl -LiteralPath $current
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($owner -notin $trusted) { throw ('Untrusted installation owner at ' + $current + ': ' + $owner) }
        $mask = $replacement
        if ($current -eq $Path -or $current -eq $parent) { $mask = $write }
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if (($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) { continue }
            if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $mask) -ne 0 -and
                $rule.IdentityReference.Value -notin $trusted) {
                throw ('Untrusted installation permissions at ' + $current + ': ' + $rule.IdentityReference.Value)
            }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}

function Set-NaylorDirectorySecurity {
    param([string]$Path)
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl.SetOwner($administrators)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-32-544','S-1-5-18')) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Set-NaylorFileSecurity {
    param([string]$Path)
    $acl = New-Object Security.AccessControl.FileSecurity
    $administrators = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $acl.SetOwner($administrators)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @('S-1-5-32-544','S-1-5-18')) {
        $identity = New-Object Security.Principal.SecurityIdentifier($sid)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')))
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

function Test-NaylorInstalledConfiguration {
    param([string]$ExecutablePath, [string]$ConfigPath, [string]$SourceConfigPath)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $ExecutablePath
    $info.Arguments = 'validate --config "{0}"' -f $ConfigPath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $validation = New-Object Diagnostics.Process
    $validation.StartInfo = $info
    try {
        if (-not $validation.Start()) { throw 'Cannot launch configuration validation.' }
        $stdout = $validation.StandardOutput.ReadToEndAsync()
        $stderr = $validation.StandardError.ReadToEndAsync()
        if (-not $validation.WaitForExit(10000)) {
            $validation.Kill()
            throw 'Configuration validation timed out.'
        }
        $null = $stdout.GetAwaiter().GetResult()
        $null = $stderr.GetAwaiter().GetResult()
        if ($validation.ExitCode -ne 0) {
            throw ('Configuration validation failed. Correct the package configuration at ' + $SourceConfigPath + ' and rerun the installer.')
        }
    }
    finally { $validation.Dispose() }
}

function Initialize-NaylorEventLog {
    if ([Diagnostics.EventLog]::SourceExists('NaylorNocker')) {
        if ([Diagnostics.EventLog]::LogNameFromSourceName('NaylorNocker','.') -ne 'Application') {
            throw 'The NaylorNocker Event Log source belongs to another log.'
        }
    }
    else { [Diagnostics.EventLog]::CreateEventSource('NaylorNocker','Application') }
}

function Invoke-NaylorInternalInstall {
    param([string]$SourceDirectory, [string]$DestinationDirectory)
    if (Get-Service -Name NaylorNocker -ErrorAction SilentlyContinue) {
        throw 'NaylorNocker is already registered. Stop and remove its registration before reinstalling.'
    }
    $sourceExe = Join-Path ([IO.Path]::GetFullPath($SourceDirectory)) 'naylor-nocker.exe'
    $sourceConfig = Join-Path ([IO.Path]::GetFullPath($SourceDirectory)) 'naylor-nocker.json'
    foreach ($file in @($sourceExe,$sourceConfig)) {
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw ('Required package file is missing: ' + $file) }
    }
    $destination = [IO.Path]::GetFullPath($DestinationDirectory)
    $exe = Join-Path $destination 'naylor-nocker.exe'
    $config = Join-Path $destination 'naylor-nocker.json'
    Assert-TrustedParent -Path $exe -AllowMissing
    Assert-TrustedParent -Path $config -AllowMissing
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Set-NaylorDirectorySecurity -Path $destination
    foreach ($pair in @(@($sourceExe,$exe),@($sourceConfig,$config))) {
        if (-not [string]::Equals($pair[0],$pair[1],[StringComparison]::OrdinalIgnoreCase)) {
            Copy-Item -LiteralPath $pair[0] -Destination $pair[1] -Force
        }
        Set-NaylorFileSecurity -Path $pair[1]
    }
    Assert-TrustedParent -Path $exe
    Assert-TrustedParent -Path $config
    Test-NaylorInstalledConfiguration -ExecutablePath $exe -ConfigPath $config -SourceConfigPath $sourceConfig
    Initialize-NaylorEventLog
    $binaryPath = '"{0}" --config "{1}"' -f $exe,$config
    New-Service -Name NaylorNocker -DisplayName 'naylor nocker' -BinaryPathName $binaryPath -StartupType Manual | Out-Null
    Write-Host ('Installed NaylorNocker in ' + $destination + '. Run Start-Service NaylorNocker when ready.')
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitProcess) {
    throw 'Run this installer from elevated 64-bit Windows PowerShell.'
}
Invoke-NaylorInternalInstall -SourceDirectory $PSScriptRoot -DestinationDirectory (Join-Path $env:ProgramFiles 'NaylorNocker')
