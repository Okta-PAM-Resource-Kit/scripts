function Compare-OpaAdRotations {
    [CmdletBinding()]
    param(
        [string]$ExportPath,

        [string]$Domain,

        [int]$EventDays = 7
    )

    $config = Initialize-OpaConfig
    $toleranceSeconds = $config.timestamp_tolerance_seconds

    Write-Host "OPA AD Rotation Verification" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "Tolerance: $toleranceSeconds seconds"
    Write-Host ""

    $connection = Get-OpaAdConnection -Domain $Domain
    if (-not $connection) {
        throw "No matching AD connection found"
    }

    Write-Host "AD Connection: $($connection.domain) (ID: $($connection.id))" -ForegroundColor Green
    Write-Host ""

    Write-Host "Fetching managed accounts..." -ForegroundColor Yellow
    $accounts = Get-OpaAdAccounts -ConnectionId $connection.id
    Write-Host "Found $($accounts.Count) managed accounts" -ForegroundColor Green
    Write-Host ""

    $results = @()

    foreach ($account in $accounts) {
        Write-Verbose "Processing account: $($account.Username)"

        $adHistory = Get-AdPasswordHistory -UserPrincipalName $account.Username -Days $EventDays

        $opaTimestamp = $null
        if ($account.LastPasswordChangeSuccessTimestamp) {
            try {
                $opaTimestamp = [DateTime]::Parse($account.LastPasswordChangeSuccessTimestamp)
            }
            catch {
                Write-Warning "Failed to parse OPA timestamp for $($account.Username)"
            }
        }

        $adTimestamp = $adHistory.PasswordLastSet
        $deltaSeconds = $null
        $status = 'UNKNOWN'

        if (-not $adHistory.AdUserFound) {
            $status = 'AD_USER_NOT_FOUND'
        }
        elseif (-not $opaTimestamp) {
            $status = 'NO_OPA_ROTATION'
        }
        elseif (-not $adTimestamp) {
            $status = 'NO_AD_TIMESTAMP'
        }
        else {
            $deltaSeconds = [Math]::Abs(($opaTimestamp - $adTimestamp).TotalSeconds)
            if ($deltaSeconds -le $toleranceSeconds) {
                $status = 'MATCH'
            }
            else {
                $status = 'MISMATCH'
            }
        }

        $otherChangers = @()
        foreach ($event in $adHistory.PasswordEvents) {
            if ($event.SubjectUserName -notmatch 'OPA|sft|scaleft') {
                $otherChangers += "$($event.SubjectDomainName)\$($event.SubjectUserName) at $($event.TimeCreated)"
            }
        }

        $results += [PSCustomObject]@{
            Account = $account.Username
            Status = $status
            OpaLastRotation = $opaTimestamp
            AdPasswordLastSet = $adTimestamp
            DeltaSeconds = $deltaSeconds
            OpaSuccessCount = $account.PasswordChangeSuccessCount
            OpaErrorCount = $account.PasswordChangeErrorCount
            RecentAdEvents = $adHistory.EventCount
            OtherChangers = ($otherChangers -join '; ')
            AdUserFound = $adHistory.AdUserFound
        }
    }

    Write-Host ""
    Write-Host "Rotation Comparison Results" -ForegroundColor Cyan
    Write-Host "============================" -ForegroundColor Cyan
    Write-Host ""

    foreach ($result in $results) {
        $statusColor = switch ($result.Status) {
            'MATCH' { 'Green' }
            'MISMATCH' { 'Red' }
            'AD_USER_NOT_FOUND' { 'Yellow' }
            'NO_OPA_ROTATION' { 'Yellow' }
            default { 'Gray' }
        }

        Write-Host "$($result.Account)" -ForegroundColor White -NoNewline
        Write-Host " - " -NoNewline
        Write-Host "$($result.Status)" -ForegroundColor $statusColor

        if ($result.DeltaSeconds) {
            Write-Host "  Delta: $($result.DeltaSeconds) seconds"
        }
        if ($result.OtherChangers) {
            Write-Host "  WARNING: Non-OPA password changes detected:" -ForegroundColor Yellow
            Write-Host "    $($result.OtherChangers)" -ForegroundColor Yellow
        }
    }

    Write-Host ""
    $matchCount = ($results | Where-Object { $_.Status -eq 'MATCH' }).Count
    $mismatchCount = ($results | Where-Object { $_.Status -eq 'MISMATCH' }).Count
    $otherCount = ($results | Where-Object { $_.Status -notin @('MATCH', 'MISMATCH') }).Count

    Write-Host "Summary: " -NoNewline
    Write-Host "$matchCount MATCH" -ForegroundColor Green -NoNewline
    Write-Host ", " -NoNewline
    Write-Host "$mismatchCount MISMATCH" -ForegroundColor Red -NoNewline
    Write-Host ", " -NoNewline
    Write-Host "$otherCount OTHER" -ForegroundColor Yellow

    if ($ExportPath) {
        Export-RotationReport -Results $results -Path $ExportPath
    }

    return $results
}
