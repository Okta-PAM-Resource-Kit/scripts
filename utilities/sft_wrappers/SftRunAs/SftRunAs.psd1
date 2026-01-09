@{
  RootModule        = 'SftRunAs.psm1'
  ModuleVersion     = '1.0.0'
  GUID              = '2E9B611C-DB2E-40A2-BE89-79FE1E3210B5'
  Author            = 'Shad Lutz'
  CompanyName       = 'shadlutz.com'
  Copyright         = '(c) shadlutz.com'
  Description       = 'Run tools under OPA-managed AD credentials via sft ad reveal'
  PowerShellVersion = '5.1'

  FunctionsToExport = @('Invoke-SftRunAs')
  AliasesToExport   = @('sft-runas','sftrunas')

  PrivateData = @{
    PSData = @{
      Tags = @('Okta','OPA','PrivilegedAccess','RunAs','RSAT')
    }
  }
}
