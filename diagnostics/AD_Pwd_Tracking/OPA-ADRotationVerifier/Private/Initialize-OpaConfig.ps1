function Initialize-OpaConfig {
    [CmdletBinding()]
    param()

    $config = @{
        opa_url = ''
        team_name = ''
        timestamp_tolerance_seconds = 120
        event_lookback_days = 7
        secrets_resource_group = ''
        secrets_project = ''
        secrets_id = ''
        secrets_key_id_name = ''
        secrets_key_secret_name = ''
    }

    if (Test-Path $script:ConfigPath) {
        try {
            $fileConfig = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            if ($fileConfig.opa_url) { $config.opa_url = $fileConfig.opa_url }
            if ($fileConfig.team_name) { $config.team_name = $fileConfig.team_name }
            if ($fileConfig.timestamp_tolerance_seconds) {
                $config.timestamp_tolerance_seconds = $fileConfig.timestamp_tolerance_seconds
            }
            if ($fileConfig.event_lookback_days) {
                $config.event_lookback_days = $fileConfig.event_lookback_days
            }
            if ($fileConfig.secrets_resource_group) { $config.secrets_resource_group = $fileConfig.secrets_resource_group }
            if ($fileConfig.secrets_project) { $config.secrets_project = $fileConfig.secrets_project }
            if ($fileConfig.secrets_id) { $config.secrets_id = $fileConfig.secrets_id }
            if ($fileConfig.secrets_key_id_name) { $config.secrets_key_id_name = $fileConfig.secrets_key_id_name }
            if ($fileConfig.secrets_key_secret_name) { $config.secrets_key_secret_name = $fileConfig.secrets_key_secret_name }
        }
        catch {
            Write-Warning "Failed to read config file: $_"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.opa_url)) {
        $config.opa_url = Read-Host "Enter OPA URL (e.g., https://myorg.pam.okta.com)"
        if ([string]::IsNullOrWhiteSpace($config.opa_url)) {
            throw "OPA URL is required"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.team_name)) {
        $config.team_name = Read-Host "Enter OPA Team Name"
        if ([string]::IsNullOrWhiteSpace($config.team_name)) {
            throw "Team name is required"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.secrets_resource_group)) {
        $config.secrets_resource_group = Read-Host "Enter Secrets Resource Group"
        if ([string]::IsNullOrWhiteSpace($config.secrets_resource_group)) {
            throw "Secrets Resource Group is required"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.secrets_project)) {
        $config.secrets_project = Read-Host "Enter Secrets Project"
        if ([string]::IsNullOrWhiteSpace($config.secrets_project)) {
            throw "Secrets Project is required"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.secrets_id)) {
        $config.secrets_id = Read-Host "Enter Secret ID (UUID)"
        if ([string]::IsNullOrWhiteSpace($config.secrets_id)) {
            throw "Secret ID is required"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.secrets_key_id_name)) {
        $config.secrets_key_id_name = Read-Host "Enter Key Name for API Key ID (e.g., apikey)"
        if ([string]::IsNullOrWhiteSpace($config.secrets_key_id_name)) {
            throw "Key Name for API Key ID is required"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.secrets_key_secret_name)) {
        $config.secrets_key_secret_name = Read-Host "Enter Key Name for API Key Secret (e.g., apisecret)"
        if ([string]::IsNullOrWhiteSpace($config.secrets_key_secret_name)) {
            throw "Key Name for API Key Secret is required"
        }
    }

    $config.opa_url = $config.opa_url.TrimEnd('/')

    $configToSave = @{
        opa_url = $config.opa_url
        team_name = $config.team_name
        timestamp_tolerance_seconds = $config.timestamp_tolerance_seconds
        event_lookback_days = $config.event_lookback_days
        secrets_resource_group = $config.secrets_resource_group
        secrets_project = $config.secrets_project
        secrets_id = $config.secrets_id
        secrets_key_id_name = $config.secrets_key_id_name
        secrets_key_secret_name = $config.secrets_key_secret_name
    }
    $configToSave | ConvertTo-Json | Set-Content $script:ConfigPath -Force

    Write-Verbose "Configuration loaded: URL=$($config.opa_url), Team=$($config.team_name)"
    return $config
}
