<#
.SYNOPSIS
    Extracts and displays icons from a DLL file with their index numbers.

.DESCRIPTION
    Lists all icons in a DLL and optionally saves them as .ico files to help
    identify the correct icon index for Windows shortcuts.

.PARAMETER DllPath
    Path to the DLL file. Defaults to dsadmin.dll.

.PARAMETER OutputFolder
    Optional folder to save extracted icons as .ico files.

.EXAMPLE
    .\Get-DllIcons.ps1
    Lists icons in dsadmin.dll

.EXAMPLE
    .\Get-DllIcons.ps1 -DllPath "C:\Windows\System32\dnsmgr.dll"
    Lists icons in dnsmgr.dll

.EXAMPLE
    .\Get-DllIcons.ps1 -OutputFolder "C:\Temp\Icons"
    Extracts icons from dsadmin.dll to C:\Temp\Icons
#>

param(
    [string]$DllPath = "$env:SystemRoot\System32\dsadmin.dll",
    [string]$OutputFolder
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class IconExtractor {
    [DllImport("shell32.dll", CharSet = CharSet.Auto)]
    public static extern int ExtractIconEx(string lpszFile, int nIconIndex, IntPtr[] phiconLarge, IntPtr[] phiconSmall, int nIcons);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool DestroyIcon(IntPtr hIcon);
}
"@

if (-not (Test-Path $DllPath)) {
    Write-Host "DLL not found: $DllPath" -ForegroundColor Red
    exit 1
}

# Get total icon count (pass -1 as index)
$iconCount = [IconExtractor]::ExtractIconEx($DllPath, -1, $null, $null, 0)

Write-Host ""
Write-Host "DLL: $DllPath" -ForegroundColor Cyan
Write-Host "Total icons: $iconCount" -ForegroundColor Cyan
Write-Host ""

if ($iconCount -eq 0) {
    Write-Host "No icons found in this DLL." -ForegroundColor Yellow
    exit 0
}

if ($OutputFolder) {
    if (-not (Test-Path $OutputFolder)) {
        New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
    }
    Write-Host "Saving icons to: $OutputFolder" -ForegroundColor Green
    Write-Host ""
}

Add-Type -AssemblyName System.Drawing

for ($i = 0; $i -lt $iconCount; $i++) {
    $largeIcons = New-Object IntPtr[] 1
    $smallIcons = New-Object IntPtr[] 1

    [IconExtractor]::ExtractIconEx($DllPath, $i, $largeIcons, $smallIcons, 1) | Out-Null

    $status = "Index $i"

    if ($largeIcons[0] -ne [IntPtr]::Zero) {
        if ($OutputFolder) {
            try {
                $icon = [System.Drawing.Icon]::FromHandle($largeIcons[0])
                $iconPath = Join-Path $OutputFolder "icon_$i.ico"
                $stream = [System.IO.File]::Create($iconPath)
                $icon.Save($stream)
                $stream.Close()
                $status += " - Saved to icon_$i.ico"
            } catch {
                $status += " - Failed to save: $_"
            }
        }
        [IconExtractor]::DestroyIcon($largeIcons[0]) | Out-Null
    }

    if ($smallIcons[0] -ne [IntPtr]::Zero) {
        [IconExtractor]::DestroyIcon($smallIcons[0]) | Out-Null
    }

    Write-Host $status
}

Write-Host ""
Write-Host "Usage in shortcuts: `"$DllPath,<index>`"" -ForegroundColor Yellow
Write-Host "Example: `"$DllPath,0`" for the first icon" -ForegroundColor Yellow
