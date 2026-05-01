@{
    RootModule = 'OPA-ADRotationVerifier.psm1'
    ModuleVersion = '1.0.0'
    GUID = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author = 'Okta'
    CompanyName = 'Okta'
    Copyright = '(c) 2024 Okta. All rights reserved.'
    Description = 'Verifies OPA Active Directory credential rotations against actual AD password changes'
    PowerShellVersion = '7.0'
    RequiredModules = @('ActiveDirectory')
    FunctionsToExport = @(
        'Compare-OpaAdRotations',
        'Get-OpaAdConnection',
        'Get-OpaAdAccounts',
        'Get-OpaAdAccountDetail',
        'Get-AdPasswordHistory',
        'Export-RotationReport'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('OPA', 'ActiveDirectory', 'PasswordRotation', 'Security', 'Audit')
            ProjectUri = ''
            ReleaseNotes = 'Initial release'
        }
    }
}
