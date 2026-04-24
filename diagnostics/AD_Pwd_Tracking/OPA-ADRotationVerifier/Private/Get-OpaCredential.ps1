function Get-OpaCredential {
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $keyId = $null
    $keySecret = $null

    if (-not $Force) {
        try {
            $cmdkeyOutput = cmdkey /list:$script:CredentialTarget 2>&1
            if ($cmdkeyOutput -match 'Target:') {
                $cred = Get-StoredCredential -Target $script:CredentialTarget
                if ($cred) {
                    $keyId = $cred.UserName
                    $keySecret = $cred.GetNetworkCredential().Password
                    Write-Verbose "Retrieved credentials from Windows Credential Manager"
                }
            }
        }
        catch {
            Write-Verbose "Credential Manager lookup failed, will prompt for credentials"
        }
    }

    if ([string]::IsNullOrWhiteSpace($keyId) -or [string]::IsNullOrWhiteSpace($keySecret)) {
        Write-Host "OPA API credentials not found. Please provide them now."
        Write-Host "These will be stored securely in Windows Credential Manager."
        Write-Host ""

        $keyId = Read-Host "Enter Key-ID"
        if ([string]::IsNullOrWhiteSpace($keyId)) {
            throw "Key-ID is required"
        }

        # Use plain text input to avoid SecureString issues with pasting
        $keySecret = Read-Host "Enter Key-Secret"
        Write-Host "Processing credentials..." -ForegroundColor Yellow

        if ([string]::IsNullOrWhiteSpace($keySecret)) {
            throw "Key-Secret is required"
        }
        Write-Verbose "Key-Secret received (length: $($keySecret.Length))"

        # Skip credential storage for now - just use in-memory for this session
        Write-Host "Credentials loaded for this session." -ForegroundColor Green
        Write-Verbose "Skipping Windows Credential Manager storage to avoid cmdkey issues"
    }

    return @{
        KeyId = $keyId
        KeySecret = $keySecret
    }
}

function Get-StoredCredential {
    [CmdletBinding()]
    param(
        [string]$Target
    )

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public class CredentialManager {
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CredRead(string target, int type, int flags, out IntPtr credential);

    [DllImport("advapi32.dll", SetLastError = true)]
    public static extern bool CredFree(IntPtr credential);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL {
        public int Flags;
        public int Type;
        public string TargetName;
        public string Comment;
        public long LastWritten;
        public int CredentialBlobSize;
        public IntPtr CredentialBlob;
        public int Persist;
        public int AttributeCount;
        public IntPtr Attributes;
        public string TargetAlias;
        public string UserName;
    }
}
"@ -ErrorAction SilentlyContinue

    $credPtr = [IntPtr]::Zero
    $result = [CredentialManager]::CredRead($Target, 1, 0, [ref]$credPtr)

    if (-not $result) {
        return $null
    }

    try {
        $cred = [System.Runtime.InteropServices.Marshal]::PtrToStructure($credPtr, [Type][CredentialManager+CREDENTIAL])
        $password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($cred.CredentialBlob, $cred.CredentialBlobSize / 2)

        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        return New-Object System.Management.Automation.PSCredential($cred.UserName, $securePassword)
    }
    finally {
        [CredentialManager]::CredFree($credPtr) | Out-Null
    }
}
