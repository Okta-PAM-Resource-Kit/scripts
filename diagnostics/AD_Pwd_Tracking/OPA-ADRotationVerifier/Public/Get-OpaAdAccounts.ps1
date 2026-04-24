function Get-OpaAdAccounts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionId
    )

    $config = Initialize-OpaConfig

    $endpoint = "/v1/teams/$($config.team_name)/resource_assignment/active_directory/$ConnectionId/accounts"
    Write-Verbose "Fetching AD accounts from $endpoint"

    $response = Invoke-OpaApiRequest -Endpoint $endpoint -Config $config

    Write-Verbose "Response type: $($response.GetType().FullName)"
    Write-Verbose "Response content: $($response | ConvertTo-Json -Depth 3 -Compress)"

    $accounts = @()
    if ($response.list -and $response.list.Count -gt 0) {
        $accounts = $response.list
    }
    elseif ($response.accounts -and $response.accounts.Count -gt 0) {
        $accounts = $response.accounts
    }
    elseif ($response -is [array]) {
        $accounts = $response
    }

    Write-Verbose "Retrieved $($accounts.Count) managed accounts"

    $accountsWithRotation = @()
    foreach ($account in $accounts) {
        Write-Verbose "Fetching rotation details for account: $($account.username)"

        $detailEndpoint = "/v1/teams/$($config.team_name)/active_directory/$ConnectionId/accounts/$($account.id)"
        try {
            $detail = Invoke-OpaApiRequest -Endpoint $detailEndpoint -Config $config

            $accountsWithRotation += [PSCustomObject]@{
                Id = $account.id
                Username = $account.username
                AccountType = $detail.account.account_type
                AvailabilityStatus = $detail.account.availability_status
                DisplayName = $detail.account.display_name
                SamAccountName = $detail.account.sam_account_name
                DistinguishedName = $detail.account.distinguished_name
                BroughtUnderManagementAt = $detail.account.brought_under_management_at
                LastPasswordChangeSuccessTimestamp = $detail.rotation.last_password_change_success_report_timestamp
                LastPasswordChangeSystemTimestamp = $detail.rotation.last_password_change_system_timestamp
                LastPasswordChangeErrorTimestamp = $detail.rotation.last_password_change_error_report_timestamp
                PasswordChangeSuccessCount = $detail.rotation.password_change_success_count
                PasswordChangeErrorCount = $detail.rotation.password_change_error_count
                PasswordChangeErrorCountSinceLastSuccess = $detail.rotation.password_change_error_count_since_last_success
            }
        }
        catch {
            Write-Warning "Failed to get rotation details for $($account.username): $_"
            $accountsWithRotation += [PSCustomObject]@{
                Id = $account.id
                Username = $account.username
                AccountType = $null
                AvailabilityStatus = $null
                DisplayName = $null
                SamAccountName = $null
                DistinguishedName = $null
                BroughtUnderManagementAt = $null
                LastPasswordChangeSuccessTimestamp = $null
                LastPasswordChangeSystemTimestamp = $null
                LastPasswordChangeErrorTimestamp = $null
                PasswordChangeSuccessCount = $null
                PasswordChangeErrorCount = $null
                PasswordChangeErrorCountSinceLastSuccess = $null
            }
        }
    }

    return $accountsWithRotation
}
