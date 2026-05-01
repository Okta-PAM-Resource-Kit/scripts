function Get-OpaAdAccounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionId,

        [switch]$ValidateTimestamps
    )

    $config = Initialize-OpaConfig

    $endpoint = "/v1/teams/$($config.team_name)/resource_assignment/active_directory/$ConnectionId/accounts"
    Write-Verbose "Fetching AD accounts from $endpoint"

    $allAccounts = @()
    $currentEndpoint = $endpoint
    $pageNum = 1

    do {
        Write-Verbose "Fetching page $pageNum from $currentEndpoint"
        $response = Invoke-OpaApiRequest -Endpoint $currentEndpoint -Config $config -IncludeHeaders

        $content = $response.Content
        Write-Verbose "Response type: $($content.GetType().FullName)"
        Write-Verbose "Response content: $($content | ConvertTo-Json -Depth 3 -Compress)"

        $pageAccounts = @()
        if ($content.list -and $content.list.Count -gt 0) {
            $pageAccounts = $content.list
        }
        elseif ($content.accounts -and $content.accounts.Count -gt 0) {
            $pageAccounts = $content.accounts
        }
        elseif ($content -is [array]) {
            $pageAccounts = $content
        }

        $allAccounts += $pageAccounts
        Write-Verbose "Page $pageNum returned $($pageAccounts.Count) accounts (total: $($allAccounts.Count))"

        $nextUrl = $null
        $linkHeader = $response.Headers['Link']
        if ($linkHeader) {
            $linkValue = if ($linkHeader -is [array]) { $linkHeader[0] } else { $linkHeader }
            Write-Verbose "Link header: $linkValue"
            if ($linkValue -match '<([^>]+)>;\s*rel="next"') {
                $nextUrl = $Matches[1]
                Write-Verbose "Found next page URL: $nextUrl"
            }
        }

        $currentEndpoint = $nextUrl
        $pageNum++
    } while ($currentEndpoint)

    $accounts = $allAccounts

    Write-Verbose "Retrieved $($accounts.Count) managed accounts"

    $accountsWithRotation = @()
    $timestampMatches = 0
    $timestampMismatches = 0

    foreach ($account in $accounts) {
        $accountUpn = if ($account.upn) { $account.upn } else { $account.username }
        $listLastRotation = $account.last_rotation_at
        Write-Verbose "Fetching rotation details for account: $accountUpn"

        $detailEndpoint = "/v1/teams/$($config.team_name)/resource_assignment/active_directory/$ConnectionId/accounts/$($account.id)"
        try {
            $detail = Invoke-OpaApiRequest -Endpoint $detailEndpoint -Config $config

            Write-Verbose "Detail response: $($detail | ConvertTo-Json -Depth 3 -Compress)"

            if ($ValidateTimestamps) {
                $detailTimestamp = $detail.last_password_change_success_report_timestamp
                if ($listLastRotation -eq $detailTimestamp) {
                    $timestampMatches++
                    Write-Verbose "MATCH: $accountUpn - List: $listLastRotation, Detail: $detailTimestamp"
                }
                else {
                    $timestampMismatches++
                    Write-Host "MISMATCH: $accountUpn" -ForegroundColor Yellow
                    Write-Host "  List API last_rotation_at:                      $listLastRotation" -ForegroundColor Yellow
                    Write-Host "  Detail API last_password_change_success_report: $detailTimestamp" -ForegroundColor Yellow
                }
            }

            $accountsWithRotation += [PSCustomObject]@{
                Id = $detail.id
                Username = $detail.upn
                AccountType = $detail.account_type
                CheckoutStatus = $detail.checkout_status
                DisplayName = $detail.display_name
                SamAccountName = $detail.sam_account_name
                DistinguishedName = $detail.distinguished_name
                Domain = $detail.domain.name
                BroughtUnderManagementAt = $detail.brought_under_management_at
                LastRotationAt = $detail.last_rotation_at
                LastPasswordChangeSuccessTimestamp = $detail.last_password_change_success_report_timestamp
                LastPasswordChangeSystemTimestamp = $detail.last_password_change_system_timestamp
                LastPasswordChangeErrorTimestamp = $detail.last_password_change_error_report_timestamp
                LastPasswordChangeErrorType = $detail.last_password_change_error_type
                PasswordChangeSuccessCount = $detail.password_change_success_count
                PasswordChangeErrorCount = $detail.password_change_error_count
                PasswordChangeErrorCountSinceLastSuccess = $detail.password_change_error_count_since_last_success
                NextScheduledRotation = $detail.next_scheduled_password_rotation_timestamp
                NextScheduledRotationReason = $detail.next_scheduled_password_rotation_reason
            }
        }
        catch {
            Write-Warning "Failed to get rotation details for $accountUpn : $_"
            $accountsWithRotation += [PSCustomObject]@{
                Id = $account.id
                Username = $accountUpn
                AccountType = $null
                CheckoutStatus = $null
                DisplayName = $null
                SamAccountName = $null
                DistinguishedName = $null
                Domain = $null
                BroughtUnderManagementAt = $null
                LastRotationAt = $null
                LastPasswordChangeSuccessTimestamp = $null
                LastPasswordChangeSystemTimestamp = $null
                LastPasswordChangeErrorTimestamp = $null
                LastPasswordChangeErrorType = $null
                PasswordChangeSuccessCount = $null
                PasswordChangeErrorCount = $null
                PasswordChangeErrorCountSinceLastSuccess = $null
                NextScheduledRotation = $null
                NextScheduledRotationReason = $null
            }
        }
    }

    if ($ValidateTimestamps) {
        Write-Host ""
        Write-Host "Timestamp Validation Summary" -ForegroundColor Cyan
        Write-Host "============================" -ForegroundColor Cyan
        Write-Host "Matches:    $timestampMatches" -ForegroundColor Green
        Write-Host "Mismatches: $timestampMismatches" -ForegroundColor $(if ($timestampMismatches -gt 0) { 'Red' } else { 'Green' })
        if ($timestampMismatches -eq 0) {
            Write-Host ""
            Write-Host "All timestamps match - individual account calls could be eliminated." -ForegroundColor Green
        }
    }

    return $accountsWithRotation
}
