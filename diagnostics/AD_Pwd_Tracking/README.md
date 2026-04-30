# OPA AD Rotation Verifier

**_These scripts, modules, or binaries are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Overview

PowerShell module for verifying Okta Privileged Access (OPA) Active Directory credential rotations against actual AD password change records. Compares OPA's rotation timestamps with AD's PasswordLastSet attribute and Security Event Log entries to ensure rotations are occurring correctly and detect unauthorized password changes.

## Requirements

- **PowerShell 7.x** (pwsh) - Windows PowerShell 5.1 is not supported
- Domain Controller or domain-joined server with AD PowerShell module
- OPA Service Account API credentials (Key-ID and Key-Secret)
- Read access to Security Event Log (Event IDs 4723, 4724)
- Network access to OPA API endpoints

### OPA Service User Permissions

The OPA Service User used for API authentication requires the following roles:
- **Resource Admin** - to access AD connection and account information
- **Security Admin** - to access rotation status and password change details

## Disclaimer

This module is provided as-is for diagnostic and verification purposes. Always test in a non-production environment first.

## Capabilities

- Auto-detects local AD domain and matches to OPA AD connection
- Retrieves all OPA-managed AD accounts and their rotation status
- Queries AD for actual PasswordLastSet timestamps (via UPN lookup)
- Analyzes Security Event Log for password change events across all domain controllers
- Identifies discrepancies between OPA rotation records and AD state
- Detects password changes made by processes other than OPA
- Configurable timestamp tolerance (default: 2 minutes)
- Configurable event lookback period (default: 7 days)
- Exports detailed CSV reports for audit/compliance

## Installation

### Download via curl

```powershell
# Set base URL and module path (system-wide for PowerShell 7)
$baseUrl = "https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/diagnostics/AD_Pwd_Tracking/OPA-ADRotationVerifier"
$modulePath = "$env:ProgramFiles\PowerShell\Modules\OPA-ADRotationVerifier"

# Create module directory structure (requires admin)
New-Item -ItemType Directory -Path "$modulePath\Private" -Force
New-Item -ItemType Directory -Path "$modulePath\Public" -Force

# Download module manifest and loader
curl -o "$modulePath\OPA-ADRotationVerifier.psd1" "$baseUrl/OPA-ADRotationVerifier.psd1"
curl -o "$modulePath\OPA-ADRotationVerifier.psm1" "$baseUrl/OPA-ADRotationVerifier.psm1"

# Download private functions
curl -o "$modulePath\Private\Initialize-OpaConfig.ps1" "$baseUrl/Private/Initialize-OpaConfig.ps1"
curl -o "$modulePath\Private\Get-OpaCredential.ps1" "$baseUrl/Private/Get-OpaCredential.ps1"
curl -o "$modulePath\Private\Invoke-OpaApiRequest.ps1" "$baseUrl/Private/Invoke-OpaApiRequest.ps1"

# Download public functions
curl -o "$modulePath\Public\Get-OpaAdConnection.ps1" "$baseUrl/Public/Get-OpaAdConnection.ps1"
curl -o "$modulePath\Public\Get-OpaAdAccounts.ps1" "$baseUrl/Public/Get-OpaAdAccounts.ps1"
curl -o "$modulePath\Public\Get-AdPasswordHistory.ps1" "$baseUrl/Public/Get-AdPasswordHistory.ps1"
curl -o "$modulePath\Public\Compare-OpaAdRotations.ps1" "$baseUrl/Public/Compare-OpaAdRotations.ps1"
curl -o "$modulePath\Public\Export-RotationReport.ps1" "$baseUrl/Public/Export-RotationReport.ps1"

# Download standalone scripts
curl -o "$modulePath\..\Update-GroupRoles.ps1" "https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/diagnostics/AD_Pwd_Tracking/Update-GroupRoles.ps1"

# Unblock downloaded files (required for files downloaded from the internet)
Get-ChildItem -Path $modulePath -Recurse | Unblock-File
Get-ChildItem -Path "$modulePath\..\Update-GroupRoles.ps1" | Unblock-File
```

### Import and Run

```powershell
# Import module (use -Force to reload if already imported)
Import-Module OPA-ADRotationVerifier -Force

# First run - will prompt for OPA URL, Team Name, and API credentials
Compare-OpaAdRotations

# Run with verbose output
Compare-OpaAdRotations -Verbose

# Export results to CSV
Compare-OpaAdRotations -ExportPath "C:\Reports\rotation-report.csv"

# Force token refresh
Compare-OpaAdRotations -ForceTokenRefresh
```

## Configuration

On first run, the module prompts for:
1. **OPA URL** - e.g., `https://myorg.pam.okta.com`
2. **Team Name** - your OPA team identifier
3. **Secrets Resource Group** - OPA resource group containing API credentials
4. **Secrets Project** - OPA project containing API credentials
5. **Secret ID** - UUID of the secret containing apikey/apisecret

Settings are stored in `config.json`.

## Additional Scripts

### Update-GroupRoles.ps1

Standalone script to update OPA group roles. Uses the same config.json and sft secrets reveal mechanism.

```powershell
# Default: updates ad-rotate-validator with end_user, pam_admin, resource_admin
.\Update-GroupRoles.ps1

# Custom group and roles
.\Update-GroupRoles.ps1 -GroupName "my-group" -Roles @("end_user", "pam_admin")
```
