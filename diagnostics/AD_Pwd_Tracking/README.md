# OPA AD Rotation Verifier

**_These scripts, modules, or binaries are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Overview

PowerShell module for verifying Okta Privileged Access (OPA) Active Directory credential rotations against actual AD password change records. Compares OPA's rotation timestamps with AD's PasswordLastSet attribute and Security Event Log entries to ensure rotations are occurring correctly and detect unauthorized password changes.

## Disclaimer

This module is provided as-is for diagnostic and verification purposes. It requires:
- Domain Controller or domain-joined server with AD PowerShell module
- OPA Service Account API credentials (Key-ID and Key-Secret)
- Read access to Security Event Log (Event ID 4724)
- Network access to OPA API endpoints

Always test in a non-production environment first. The module stores API credentials in Windows Credential Manager - ensure appropriate access controls on the server.

## Capabilities

- Auto-detects local AD domain and matches to OPA AD connection
- Retrieves all OPA-managed AD accounts and their rotation status
- Queries AD for actual PasswordLastSet timestamps (via UPN lookup)
- Analyzes Security Event Log for password change events (last 7 days)
- Identifies discrepancies between OPA rotation records and AD state
- Detects password changes made by processes other than OPA
- Configurable timestamp tolerance (default: 2 minutes)
- Exports detailed CSV reports for audit/compliance

## Installation

### Download via curl

```powershell
# Set base URL and module path
$baseUrl = "https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/diagnostics/AD_Pwd_Tracking/OPA-ADRotationVerifier"
$modulePath = "$env:USERPROFILE\Documents\PowerShell\Modules\OPA-ADRotationVerifier"

# Create module directory structure
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

# Unblock downloaded files (required for files downloaded from the internet)
Get-ChildItem -Path $modulePath -Recurse | Unblock-File
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
```

## Configuration

On first run, the module prompts for:
1. **OPA URL** - e.g., `https://myorg.pam.okta.com`
2. **Team Name** - your OPA team identifier
3. **Key-ID** - OPA Service Account key ID
4. **Key-Secret** - OPA Service Account key secret

Settings are stored in `config.json` (URL/team) and Windows Credential Manager (secrets).
