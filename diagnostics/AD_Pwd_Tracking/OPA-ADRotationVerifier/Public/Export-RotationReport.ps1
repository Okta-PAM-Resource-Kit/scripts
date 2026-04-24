function Export-RotationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Results,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $exportData = $Results | Select-Object @(
        'Account'
        'Status'
        @{Name='OpaLastRotation'; Expression={
            if ($_.OpaLastRotation) { $_.OpaLastRotation.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        }}
        @{Name='AdPasswordLastSet'; Expression={
            if ($_.AdPasswordLastSet) { $_.AdPasswordLastSet.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
        }}
        'DeltaSeconds'
        'OpaSuccessCount'
        'OpaErrorCount'
        'RecentAdEvents'
        'OtherChangers'
        'AdUserFound'
    )

    try {
        # Create directory if it doesn't exist
        $directory = Split-Path -Parent $Path
        if ($directory -and -not (Test-Path $directory)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
            Write-Verbose "Created directory: $directory"
        }

        $exportData | Export-Csv -Path $Path -NoTypeInformation -Force
        Write-Host "Report exported to: $Path" -ForegroundColor Green
    }
    catch {
        throw "Failed to export report: $_"
    }
}
