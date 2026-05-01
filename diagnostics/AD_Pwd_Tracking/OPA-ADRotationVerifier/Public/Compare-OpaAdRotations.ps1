function Compare-OpaAdRotations {
    [CmdletBinding()]
    param(
        [string]$ExportPath,

        [string]$Domain,

        [int]$LookbackDays = 0,

        [switch]$ForceTokenRefresh,

        [switch]$ShowDetails,

        [switch]$ForceRotation
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
    $detailFetchCount = 0

    foreach ($account in $accounts) {
        Write-Verbose "Processing account: $($account.Username)"

        $adHistory = Get-AdPasswordHistory -UserPrincipalName $account.Username -Days $eventDays

        # First try comparing with last_rotation_at from list API
        $opaTimestamp = $null
        if ($account.LastRotationAt) {
            try {
                $opaTimestamp = [DateTime]::Parse($account.LastRotationAt)
            }
            catch {
                Write-Warning "Failed to parse OPA timestamp for $($account.Username)"
            }
        }

        $adTimestamp = $adHistory.PasswordLastSet
        $deltaSeconds = $null
        $status = 'UNKNOWN'
        $rotationFailed = $false
        $opaSuccessCount = $null
        $opaErrorCount = $null

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
                # Mismatch with list API - fetch detail to check last successful rotation
                Write-Verbose "Mismatch detected for $($account.Username), fetching detail API..."
                $detailFetchCount++

                try {
                    $detail = Get-OpaAdAccountDetail -ConnectionId $connection.id -AccountId $account.Id
                    $opaSuccessCount = $detail.PasswordChangeSuccessCount
                    $opaErrorCount = $detail.PasswordChangeErrorCount

                    if ($detail.LastPasswordChangeSuccessTimestamp) {
                        $successTimestamp = [DateTime]::Parse($detail.LastPasswordChangeSuccessTimestamp)
                        $successDelta = [Math]::Abs(($successTimestamp - $adTimestamp).TotalSeconds)

                        if ($successDelta -le $toleranceSeconds) {
                            # AD matches last successful rotation - recent attempt failed
                            $status = 'MATCH'
                            $rotationFailed = $true
                            $opaTimestamp = $successTimestamp
                            $deltaSeconds = $successDelta
                            Write-Verbose "AD matches last successful rotation (recent attempt failed)"
                        }
                        else {
                            $status = 'MISMATCH'
                        }
                    }
                    else {
                        $status = 'MISMATCH'
                    }
                }
                catch {
                    Write-Warning "Failed to fetch detail for $($account.Username): $_"
                    $status = 'MISMATCH'
                }
            }
        }

        $otherChangers = @()
        foreach ($event in $adHistory.PasswordEvents) {
            if ($event.SubjectUserName -notmatch 'OPA|sft|scaleft') {
                $otherChangers += "$($event.SubjectDomainName)\$($event.SubjectUserName) at $($event.TimeCreated)"
            }
        }

        $results += [PSCustomObject]@{
            AccountId = $account.Id
            Account = $account.Username
            Status = $status
            RotationFailed = $rotationFailed
            OpaLastRotation = $opaTimestamp
            AdPasswordLastSet = $adTimestamp
            DeltaSeconds = $deltaSeconds
            OpaSuccessCount = $opaSuccessCount
            OpaErrorCount = $opaErrorCount
            RecentAdEvents = $adHistory.EventCount
            OtherChangers = ($otherChangers -join '; ')
            AdUserFound = $adHistory.AdUserFound
        }
    }

    # Group results by status
    $matches = $results | Where-Object { $_.Status -eq 'MATCH' }
    $mismatches = $results | Where-Object { $_.Status -eq 'MISMATCH' }
    $others = $results | Where-Object { $_.Status -notin @('MATCH', 'MISMATCH') }

    Write-Host ""
    Write-Host "Summary" -ForegroundColor Cyan
    Write-Host "=======" -ForegroundColor Cyan
    Write-Host "$($matches.Count) MATCH" -ForegroundColor Green -NoNewline
    Write-Host ", " -NoNewline
    Write-Host "$($mismatches.Count) MISMATCH" -ForegroundColor Red -NoNewline
    Write-Host ", " -NoNewline
    Write-Host "$($others.Count) OTHER" -ForegroundColor Yellow
    Write-Host "Detail API calls: $detailFetchCount (only fetched for AD mismatches)" -ForegroundColor DarkGray

    # Show detailed rotation info only if -ShowDetails or -ExportPath specified
    if ($ShowDetails -or $ExportPath) {
        Write-Host ""
        Write-Host "Rotation Details" -ForegroundColor Cyan
        Write-Host "================" -ForegroundColor Cyan

        # Display matches
        if ($matches.Count -gt 0) {
            Write-Host ""
            Write-Host "=== MATCHES ($($matches.Count)) ===" -ForegroundColor Green
            foreach ($result in $matches) {
                Write-Host "  $($result.Account)" -ForegroundColor Green
                if ($result.DeltaSeconds) {
                    Write-Host "    Delta: $($result.DeltaSeconds) seconds" -ForegroundColor DarkGray
                }
                if ($result.RotationFailed) {
                    Write-Host "    WARNING: Last rotation attempt failed (AD matches last successful rotation)" -ForegroundColor Yellow
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
    }

    # Force rotation for mismatched accounts
    if ($ForceRotation -and $mismatches.Count -gt 0) {
        Write-Host ""
        Write-Host "Forcing Password Rotation for Mismatched Accounts" -ForegroundColor Cyan
        Write-Host "==================================================" -ForegroundColor Cyan

        foreach ($mismatch in $mismatches) {
            Write-Host "  Rotating: $($mismatch.Account)..." -ForegroundColor Yellow -NoNewline
            try {
                $rotateEndpoint = "/v1/teams/$($config.team_name)/active_directory/$($connection.id)/accounts/$($mismatch.AccountId)/rotate_password"
                $null = Invoke-OpaApiRequest -Endpoint $rotateEndpoint -Method 'POST' -Config $config
                Write-Host " OK" -ForegroundColor Green
            }
            catch {
                Write-Host " FAILED: $_" -ForegroundColor Red
            }
        }
    }

    if ($ExportPath) {
        Export-RotationReport -Results $results -Path $ExportPath
    }

    return $results
}
