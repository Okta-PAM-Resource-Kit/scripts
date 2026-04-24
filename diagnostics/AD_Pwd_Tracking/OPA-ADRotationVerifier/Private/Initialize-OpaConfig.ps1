function Initialize-OpaConfig {
    [CmdletBinding()]
    param()

    $config = @{
        opa_url = ''
        team_name = ''
        timestamp_tolerance_seconds = 120
    }

    if (Test-Path $script:ConfigPath) {
        try {
            $fileConfig = Get-Content $script:ConfigPath -Raw | ConvertFrom-Json
            if ($fileConfig.opa_url) { $config.opa_url = $fileConfig.opa_url }
            if ($fileConfig.team_name) { $config.team_name = $fileConfig.team_name }
            if ($fileConfig.timestamp_tolerance_seconds) {
                $config.timestamp_tolerance_seconds = $fileConfig.timestamp_tolerance_seconds
            }
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

    $config.opa_url = $config.opa_url.TrimEnd('/')

    $configToSave = @{
        opa_url = $config.opa_url
        team_name = $config.team_name
        timestamp_tolerance_seconds = $config.timestamp_tolerance_seconds
    }
    $configToSave | ConvertTo-Json | Set-Content $script:ConfigPath -Force

    Write-Verbose "Configuration loaded: URL=$($config.opa_url), Team=$($config.team_name)"
    return $config
}
