function Compare-OpaAdRotations {
    [CmdletBinding()]
    param(
        [string]$ExportPath,

        [string]$Domain,

        [int]$LookbackDays = 0,

        [switch]$ForceTokenRefresh
    )

    # Clear cached token if force refresh requested
    if ($ForceTokenRefresh) {
        $script:BearerToken = $null
        $script:TokenExpiresAt = $null
        Write-Verbose "Cleared cached bearer token"
    }

    $config = Initialize-OpaConfig
    $toleranceSeconds = $config.timestamp_tolerance_seconds

    # Use CLI parameter if provided, otherwise use config value
    $eventDays = if ($LookbackDays -gt 0) { $LookbackDays } else { $config.event_lookback_days }

    Write-Host "OPA AD Rotation Verification" -ForegroundColor Cyan
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "Tolerance: $toleranceSeconds seconds"
    Write-Host "Event Lookback: $eventDays days"
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

        $adHistory = Get-AdPasswordHistory -UserPrincipalName $account.Username -Days $eventDays

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

    # Group results by status
    $matches = $results | Where-Object { $_.Status -eq 'MATCH' }
    $mismatches = $results | Where-Object { $_.Status -eq 'MISMATCH' }
    $others = $results | Where-Object { $_.Status -notin @('MATCH', 'MISMATCH') }

    # Display matches
    if ($matches.Count -gt 0) {
        Write-Host ""
        Write-Host "=== MATCHES ($($matches.Count)) ===" -ForegroundColor Green
        foreach ($result in $matches) {
            Write-Host "  $($result.Account)" -ForegroundColor Green
            if ($result.DeltaSeconds) {
                Write-Host "    Delta: $($result.DeltaSeconds) seconds" -ForegroundColor DarkGray
            }
        }
    }

    # Display mismatches (highlighted)
    if ($mismatches.Count -gt 0) {
        Write-Host ""
        Write-Host "=== MISMATCHES ($($mismatches.Count)) ===" -ForegroundColor Red -BackgroundColor Black
        foreach ($result in $mismatches) {
            Write-Host "  $($result.Account)" -ForegroundColor Red -BackgroundColor Black
            Write-Host "    OPA Last Rotation:  $($result.OpaLastRotation)" -ForegroundColor Red
            Write-Host "    AD PasswordLastSet: $($result.AdPasswordLastSet)" -ForegroundColor Red
            Write-Host "    Delta: $($result.DeltaSeconds) seconds" -ForegroundColor Red
            if ($result.OtherChangers) {
                Write-Host "    Non-OPA changes: $($result.OtherChangers)" -ForegroundColor Yellow
            }
        }
    }

    # Display others
    if ($others.Count -gt 0) {
        Write-Host ""
        Write-Host "=== OTHER ($($others.Count)) ===" -ForegroundColor Yellow
        foreach ($result in $others) {
            Write-Host "  $($result.Account) - $($result.Status)" -ForegroundColor Yellow
            if ($result.OtherChangers) {
                Write-Host "    Non-OPA changes: $($result.OtherChangers)" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ""
    Write-Host "Summary: " -NoNewline
    Write-Host "$($matches.Count) MATCH" -ForegroundColor Green -NoNewline
    Write-Host ", " -NoNewline
    Write-Host "$($mismatches.Count) MISMATCH" -ForegroundColor Red -NoNewline
    Write-Host ", " -NoNewline
    Write-Host "$($others.Count) OTHER" -ForegroundColor Yellow

    if ($ExportPath) {
        Export-RotationReport -Results $results -Path $ExportPath
    }

    return $results
}
