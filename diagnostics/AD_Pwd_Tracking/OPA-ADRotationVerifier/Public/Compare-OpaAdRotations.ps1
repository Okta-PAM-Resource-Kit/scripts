<#
.SYNOPSIS
    Compares OPA AD credential rotations against actual AD password changes.

.DESCRIPTION
    Verifies that OPA-managed AD account password rotations match the actual
    PasswordLastSet timestamps in Active Directory. Detects mismatches and
    identifies password changes made by non-OPA processes.

.PARAMETER ExportPath
    Path to export results as CSV file.

.PARAMETER Domain
    AD domain to check. If not specified, auto-detects from local machine.

.PARAMETER LookbackDays
    Number of days to search event logs for password changes. Default from config.

.PARAMETER ForceTokenRefresh
    Clear cached bearer token and re-authenticate.

.PARAMETER ShowDetails
    Display detailed rotation information for all accounts.

.PARAMETER ForceRotation
    Trigger password rotation for accounts with mismatches.

.PARAMETER Help
    Display usage information.

.PARAMETER ShowConfig
    Display current configuration and config file path.

.PARAMETER ClearConfig
    Delete the config file to reset all settings.

.EXAMPLE
    Compare-OpaAdRotations
    Run basic comparison with default settings.

.EXAMPLE
    Compare-OpaAdRotations -ShowDetails
    Run comparison and show detailed output for all accounts.

.EXAMPLE
    Compare-OpaAdRotations -ExportPath "C:\Reports\rotation-report.csv"
    Run comparison and export results to CSV.

.EXAMPLE
    Compare-OpaAdRotations -ForceRotation
    Run comparison and trigger rotation for mismatched accounts.
#>
function Compare-OpaAdRotations {
    [CmdletBinding()]
    param(
        [string]$ExportPath,

        [string]$Domain,

        [int]$LookbackDays = 0,

        [switch]$ForceTokenRefresh,

        [switch]$ShowDetails,

        [switch]$ForceRotation,

        [switch]$Help,

        [switch]$ShowConfig,

        [switch]$ClearConfig
    )

    if ($Help) {
        Write-Host ""
        Write-Host "Compare-OpaAdRotations - Verify OPA AD credential rotations" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "USAGE:" -ForegroundColor Yellow
        Write-Host "  Compare-OpaAdRotations [options]"
        Write-Host ""
        Write-Host "OPTIONS:" -ForegroundColor Yellow
        Write-Host "  -ExportPath <path>    Export results to CSV file"
        Write-Host "  -Domain <domain>      AD domain to check (default: auto-detect)"
        Write-Host "  -LookbackDays <n>     Days to search event logs (default: from config)"
        Write-Host "  -ForceTokenRefresh    Clear cached token and re-authenticate"
        Write-Host "  -ShowDetails          Show detailed rotation info for all accounts"
        Write-Host "  -ForceRotation        Trigger rotation for mismatched accounts"
        Write-Host "  -Help                 Show this help message"
        Write-Host "  -ShowConfig           Show current configuration"
        Write-Host "  -ClearConfig          Delete config file and reset all settings"
        Write-Host ""
        Write-Host "EXAMPLES:" -ForegroundColor Yellow
        Write-Host "  Compare-OpaAdRotations"
        Write-Host "  Compare-OpaAdRotations -ShowDetails"
        Write-Host "  Compare-OpaAdRotations -ExportPath 'C:\Reports\report.csv'"
        Write-Host "  Compare-OpaAdRotations -ForceRotation"
        Write-Host ""
        return
    }

    if ($ShowConfig) {
        $configPath = Join-Path (Split-Path $script:ModuleRoot -Parent) 'config.json'
        Write-Host ""
        Write-Host "Configuration" -ForegroundColor Cyan
        Write-Host "=============" -ForegroundColor Cyan
        Write-Host "Config file: $configPath"
        Write-Host ""
        if (Test-Path $configPath) {
            $config = Get-Content $configPath -Raw | ConvertFrom-Json
            Write-Host "  opa_url:                    $($config.opa_url)"
            Write-Host "  team_name:                  $($config.team_name)"
            Write-Host "  timestamp_tolerance_seconds: $($config.timestamp_tolerance_seconds)"
            Write-Host "  event_lookback_days:        $($config.event_lookback_days)"
            Write-Host "  secrets_resource_group:     $($config.secrets_resource_group)"
            Write-Host "  secrets_project:            $($config.secrets_project)"
            Write-Host "  secrets_id:                 $($config.secrets_id)"
            Write-Host "  secrets_key_id_name:        $($config.secrets_key_id_name)"
            Write-Host "  secrets_key_secret_name:    $($config.secrets_key_secret_name)"
        }
        else {
            Write-Host "  (config file not found - will be created on first run)" -ForegroundColor Yellow
        }
        Write-Host ""
        return
    }

    if ($ClearConfig) {
        $configPath = Join-Path (Split-Path $script:ModuleRoot -Parent) 'config.json'
        if (Test-Path $configPath) {
            Remove-Item $configPath -Force
            Write-Host "Config file deleted: $configPath" -ForegroundColor Green
        }
        else {
            Write-Host "Config file not found: $configPath" -ForegroundColor Yellow
        }
        return
    }

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
            ResourceGroupId = $account.ResourceGroupId
            ProjectId = $account.ProjectId
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

    # Always show mismatches in summary
    if ($mismatches.Count -gt 0) {
        Write-Host ""
        Write-Host "Mismatched Accounts:" -ForegroundColor Red
        foreach ($mismatch in $mismatches) {
            Write-Host "  $($mismatch.Account)" -ForegroundColor Red
            Write-Host "    AD PasswordLastSet: $($mismatch.AdPasswordLastSet)" -ForegroundColor Yellow
            if ($mismatch.OtherChangers) {
                Write-Host "    Changed by: $($mismatch.OtherChangers)" -ForegroundColor Yellow
            }
        }
    }

    # Show detailed rotation info only if -ShowDetails specified
    if ($ShowDetails) {
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
            Write-Verbose "    AccountId: $($mismatch.AccountId)"
            Write-Verbose "    ResourceGroupId: $($mismatch.ResourceGroupId)"
            Write-Verbose "    ProjectId: $($mismatch.ProjectId)"
            try {
                $rotateEndpoint = "/v1/teams/$($config.team_name)/resource_groups/$($mismatch.ResourceGroupId)/projects/$($mismatch.ProjectId)/rotate_resource"
                $rotateBody = @{
                    resource_id = $mismatch.AccountId
                    resource_type = 'pam_ad_account_password_login'
                }
                Write-Verbose "    Endpoint: $rotateEndpoint"
                Write-Verbose "    Body: $($rotateBody | ConvertTo-Json -Compress)"
                $null = Invoke-OpaApiRequest -Endpoint $rotateEndpoint -Method 'POST' -Body $rotateBody -Config $config
                Write-Host " OK" -ForegroundColor Green
            }
            catch {
                Write-Host " FAILED: $_" -ForegroundColor Red
            }
        }
    }

    if ($ExportPath) {
        Export-RotationReport -Results $results -Path $ExportPath
        return $results
    }

    # Only return results if captured to a variable (not displayed to console)
    if ($MyInvocation.Line -match '^\s*\$\w+\s*=') {
        return $results
    }
}
