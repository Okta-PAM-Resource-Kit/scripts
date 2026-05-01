function Get-OpaAdAccounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionId,

        [switch]$IncludeRotationDetails
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

    Write-Verbose "Retrieved $($allAccounts.Count) managed accounts"

    if (-not $IncludeRotationDetails) {
        $results = @()
        foreach ($account in $allAccounts) {
            $results += [PSCustomObject]@{
                Id = $account.id
                Username = if ($account.upn) { $account.upn } else { $account.username }
                LastRotationAt = $account.last_rotation_at
                ResourceGroupId = $account.resource_group_id
                ProjectId = $account.project_id
            }
        }
        return $results
    }

    $accountsWithRotation = @()
    foreach ($account in $allAccounts) {
        $accountUpn = if ($account.upn) { $account.upn } else { $account.username }
        Write-Verbose "Fetching rotation details for account: $accountUpn"

        $detailEndpoint = "/v1/teams/$($config.team_name)/resource_assignment/active_directory/$ConnectionId/accounts/$($account.id)"
        try {
            $detail = Invoke-OpaApiRequest -Endpoint $detailEndpoint -Config $config

            Write-Verbose "Detail response: $($detail | ConvertTo-Json -Depth 3 -Compress)"

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
                LastRotationAt = $account.last_rotation_at
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

    return $accountsWithRotation
}

function Get-OpaAdAccountDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionId,

        [Parameter(Mandatory)]
        [string]$AccountId
    )

    $config = Initialize-OpaConfig
    $endpoint = "/v1/teams/$($config.team_name)/resource_assignment/active_directory/$ConnectionId/accounts/$AccountId"

    Write-Verbose "Fetching account detail from $endpoint"
    $detail = Invoke-OpaApiRequest -Endpoint $endpoint -Config $config

    return [PSCustomObject]@{
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
