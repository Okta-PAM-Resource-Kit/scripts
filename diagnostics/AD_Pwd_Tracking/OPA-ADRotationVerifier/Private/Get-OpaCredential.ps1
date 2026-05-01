function Get-OpaCredential {
    [CmdletBinding()]
    param(
        [hashtable]$Config
    )

    if (-not $Config) {
        $Config = Initialize-OpaConfig
    }

    Write-Host "Retrieving API credentials from OPA Secrets..." -ForegroundColor Yellow

    $sftCommand = "sft secrets reveal --resource-group `"$($Config.secrets_resource_group)`" --project `"$($Config.secrets_project)`" --id `"$($Config.secrets_id)`" --output json"
    Write-Verbose "Running: $sftCommand"

    try {
        $secretJson = Invoke-Expression $sftCommand 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "sft command failed: $secretJson"
        }

        $secretData = $secretJson | ConvertFrom-Json
        Write-Verbose "Secret data retrieved: $($secretData | ConvertTo-Json -Compress)"

        $keyId = $null
        $keySecret = $null
        $keyIdName = $Config.secrets_key_id_name
        $keySecretName = $Config.secrets_key_secret_name

        foreach ($item in $secretData) {
            if ($item.key_name -eq $keyIdName) {
                $keyId = $item.secret_value
            }
            elseif ($item.key_name -eq $keySecretName) {
                $keySecret = $item.secret_value
            }
        }

        if ([string]::IsNullOrWhiteSpace($keyId)) {
            throw "Could not find '$keyIdName' in secret response"
        }
        if ([string]::IsNullOrWhiteSpace($keySecret)) {
            throw "Could not find '$keySecretName' in secret response"
        }

        Write-Host "API credentials retrieved successfully." -ForegroundColor Green
        Write-Verbose "Key-ID length: $($keyId.Length), Key-Secret length: $($keySecret.Length)"

        return @{
            KeyId = $keyId
            KeySecret = $keySecret
        }
    }
    catch {
        Write-Host "Failed to retrieve credentials from OPA Secrets." -ForegroundColor Red
        throw "Failed to get credentials via sft: $_"
    }
}
