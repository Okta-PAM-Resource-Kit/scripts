<#
.SYNOPSIS
    Updates OPA group roles using sft secrets reveal for authentication.

.DESCRIPTION
    Updates the roles for a specified OPA group. Uses the same config file
    and sft secrets reveal mechanism as the OPA-ADRotationVerifier module.

.PARAMETER GroupName
    The name of the group to update (default: ad-rotate-validator)

.PARAMETER Roles
    Array of roles to assign (default: end_user, pam_admin, resource_admin)

.EXAMPLE
    .\Update-GroupRoles.ps1
    Updates ad-rotate-validator group with default roles

.EXAMPLE
    .\Update-GroupRoles.ps1 -GroupName "my-group" -Roles @("end_user", "pam_admin")
    Updates my-group with specified roles
#>

[CmdletBinding()]
param(
    [string]$GroupName = "ad-rotate-validator",

    [string[]]$Roles = @("end_user", "pam_admin", "resource_admin")
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "config.json"

function Get-Config {
    $config = @{
        opa_url = ''
        team_name = ''
        secrets_resource_group = ''
        secrets_project = ''
        secrets_id = ''
    }

    if (Test-Path $configPath) {
        try {
            $fileConfig = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($fileConfig.opa_url) { $config.opa_url = $fileConfig.opa_url }
            if ($fileConfig.team_name) { $config.team_name = $fileConfig.team_name }
            if ($fileConfig.secrets_resource_group) { $config.secrets_resource_group = $fileConfig.secrets_resource_group }
            if ($fileConfig.secrets_project) { $config.secrets_project = $fileConfig.secrets_project }
            if ($fileConfig.secrets_id) { $config.secrets_id = $fileConfig.secrets_id }
        }
        catch {
            Write-Warning "Failed to read config file: $_"
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.opa_url)) {
        $config.opa_url = Read-Host "Enter OPA URL (e.g., https://myorg.pam.okta.com)"
    }
    if ([string]::IsNullOrWhiteSpace($config.team_name)) {
        $config.team_name = Read-Host "Enter OPA Team Name"
    }
    if ([string]::IsNullOrWhiteSpace($config.secrets_resource_group)) {
        $config.secrets_resource_group = Read-Host "Enter Secrets Resource Group"
    }
    if ([string]::IsNullOrWhiteSpace($config.secrets_project)) {
        $config.secrets_project = Read-Host "Enter Secrets Project"
    }
    if ([string]::IsNullOrWhiteSpace($config.secrets_id)) {
        $config.secrets_id = Read-Host "Enter Secret ID (UUID)"
    }

    $config.opa_url = $config.opa_url.TrimEnd('/')

    # Save config
    $configToSave = @{
        opa_url = $config.opa_url
        team_name = $config.team_name
        timestamp_tolerance_seconds = 120
        secrets_resource_group = $config.secrets_resource_group
        secrets_project = $config.secrets_project
        secrets_id = $config.secrets_id
    }
    $configToSave | ConvertTo-Json | Set-Content $configPath -Force

    return $config
}

function Get-Credentials {
    param([hashtable]$Config)

    Write-Host "Retrieving API credentials from OPA Secrets..." -ForegroundColor Yellow

    $sftCommand = "sft secrets reveal --resource-group `"$($Config.secrets_resource_group)`" --project `"$($Config.secrets_project)`" --id `"$($Config.secrets_id)`" --output json"
    Write-Verbose "Running: $sftCommand"

    $secretJson = Invoke-Expression $sftCommand 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "sft command failed: $secretJson"
    }

    $secretData = $secretJson | ConvertFrom-Json

    $keyId = $null
    $keySecret = $null

    foreach ($item in $secretData) {
        if ($item.key_name -eq 'apikey') {
            $keyId = $item.secret_value
        }
        elseif ($item.key_name -eq 'apisecret') {
            $keySecret = $item.secret_value
        }
    }

    if (-not $keyId -or -not $keySecret) {
        throw "Could not find apikey/apisecret in secret response"
    }

    Write-Host "API credentials retrieved successfully." -ForegroundColor Green
    return @{ KeyId = $keyId; KeySecret = $keySecret }
}

function Get-BearerToken {
    param(
        [hashtable]$Config,
        [hashtable]$Credential
    )

    $tokenUrl = "$($Config.opa_url)/v1/teams/$($Config.team_name)/service_token"
    $body = @{
        key_id = $Credential.KeyId
        key_secret = $Credential.KeySecret
    } | ConvertTo-Json

    Write-Host "Authenticating to OPA API..." -ForegroundColor Yellow

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30

    Write-Host "Authentication successful." -ForegroundColor Green
    return $response.bearer_token
}

function Update-GroupRoles {
    param(
        [hashtable]$Config,
        [string]$Token,
        [string]$GroupName,
        [string[]]$Roles
    )

    $url = "$($Config.opa_url)/v1/teams/$($Config.team_name)/groups/$GroupName"
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Accept' = 'application/json'
    }
    $body = @{ roles = $Roles } | ConvertTo-Json

    Write-Host "Updating roles for group '$GroupName'..." -ForegroundColor Yellow
    Write-Host "  Roles: $($Roles -join ', ')" -ForegroundColor Cyan

    try {
        $response = Invoke-RestMethod -Uri $url -Method Put -Headers $headers -Body $body -ContentType 'application/json' -TimeoutSec 30
        Write-Host "Group roles updated successfully." -ForegroundColor Green
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message
        throw "Failed to update group roles ($statusCode): $errorBody"
    }
}

function Get-GroupRoles {
    param(
        [hashtable]$Config,
        [string]$Token,
        [string]$GroupName
    )

    $url = "$($Config.opa_url)/v1/teams/$($Config.team_name)/groups/$GroupName"
    $headers = @{
        'Authorization' = "Bearer $Token"
        'Accept' = 'application/json'
    }

    Write-Host "Verifying roles for group '$GroupName'..." -ForegroundColor Yellow

    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers -TimeoutSec 30
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message
        throw "Failed to get group ($statusCode): $errorBody"
    }
}

# Main execution
Write-Host "=== OPA Group Roles Updater ===" -ForegroundColor Cyan
Write-Host ""

$config = Get-Config
Write-Verbose "Config loaded: URL=$($config.opa_url), Team=$($config.team_name)"

$credential = Get-Credentials -Config $config
$token = Get-BearerToken -Config $config -Credential $credential
$result = Update-GroupRoles -Config $config -Token $token -GroupName $GroupName -Roles $Roles

# Verify the roles were set
$group = Get-GroupRoles -Config $config -Token $token -GroupName $GroupName
$actualRoles = $group.roles

Write-Host ""
Write-Host "Verification:" -ForegroundColor Cyan
Write-Host "  Expected: $($Roles -join ', ')" -ForegroundColor White
Write-Host "  Actual:   $($actualRoles -join ', ')" -ForegroundColor White

$missingRoles = $Roles | Where-Object { $_ -notin $actualRoles }
$extraRoles = $actualRoles | Where-Object { $_ -notin $Roles }

if ($missingRoles.Count -eq 0 -and $extraRoles.Count -eq 0) {
    Write-Host "  Status:   VERIFIED" -ForegroundColor Green
}
else {
    if ($missingRoles.Count -gt 0) {
        Write-Host "  Missing:  $($missingRoles -join ', ')" -ForegroundColor Red
    }
    if ($extraRoles.Count -gt 0) {
        Write-Host "  Extra:    $($extraRoles -join ', ')" -ForegroundColor Yellow
    }
    Write-Host "  Status:   MISMATCH" -ForegroundColor Red
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
