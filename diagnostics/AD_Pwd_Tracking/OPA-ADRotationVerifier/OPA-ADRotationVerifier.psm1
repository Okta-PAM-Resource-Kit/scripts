$script:ModuleRoot = $PSScriptRoot
$script:ConfigPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config.json'
$script:CredentialTarget = 'OPA-ADRotationVerifier'
$script:BearerToken = $null
$script:TokenExpiresAt = $null

# Dot-source private functions
Get-ChildItem -Path "$PSScriptRoot\Private\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Dot-source public functions
Get-ChildItem -Path "$PSScriptRoot\Public\*.ps1" -ErrorAction SilentlyContinue | ForEach-Object {
    . $_.FullName
}

# Export public functions
Export-ModuleMember -Function @(
    'Compare-OpaAdRotations',
    'Get-OpaAdConnection',
    'Get-OpaAdAccounts',
    'Get-AdPasswordHistory',
    'Export-RotationReport'
)
