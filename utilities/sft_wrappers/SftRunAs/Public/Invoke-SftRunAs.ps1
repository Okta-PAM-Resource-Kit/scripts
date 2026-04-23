function Invoke-SftRunAs {
  [CmdletBinding(PositionalBinding=$true)]
  param(
    [Parameter(Position=0)]
    [string]$RunAs,

    [Parameter(Position=1)]
    [string]$Tool,

    [Parameter(Position=2, ValueFromRemainingArguments=$true)]
    [string[]]$ToolArgs,

    [string]$Team,
    [string]$AdDomainFqdn,

    [string]$ComputerName,   # doctor only
    [switch]$VerboseDoctor,

    [string]$Folder,         # create-shortcuts only
    [switch]$StartMenu,      # create-shortcuts only

    [switch]$Wait,
    [switch]$PassThru
  )

  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  if ($PSBoundParameters.Count -eq 0) {
    Write-Host @"
Run Windows administrative tools under a privileged Active Directory account,
using just-in-time credentials from Okta Privileged Access.

Usage:
  sft-runas <account> <tool> [tool_args]
  sft-runas list-tools
  sft-runas create-shortcuts <account> [-Folder <name>] [-StartMenu]
  sft-runas doctor [-ComputerName <target>]

Arguments:
  <account>      Privileged account (e.g. 'CORP\admin' or 'admin@corp.example.com')
  <tool>         Tool preset (e.g. 'aduc') or path to an executable.
  [tool_args]    Arguments to pass to the tool.

Special Commands:
  list-tools     Show available tool presets.
  create-shortcuts Create desktop shortcuts for all tool presets.
                 Use -Folder to place shortcuts in a subfolder.
                 Use -StartMenu to create in Start Menu (-Folder required).
  doctor         Run diagnostic checks.

"@
    return
  }

  # After the no-arg check, we can validate that the core arguments were provided.
  if (-not $PSBoundParameters.ContainsKey('RunAs')) {
    throw "Missing required argument: <account>. Run 'sft-runas' with no arguments to see usage."
  }

  function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
      throw "Required command not found in PATH: $Name"
    }
  }

  function Parse-Identity([string]$IdentityString) {
    if ($IdentityString -match '^(?<usr>[^@]+)@(?<dom>.+)$') {
      return [pscustomobject]@{ User=$Matches.usr; UPN=$Matches.dom; Raw=$IdentityString }
    }
    return [pscustomobject]@{ User=$IdentityString; UPN=$null; Raw=$IdentityString }
  }

  function Format-LogonName($id) {
    if ($id.UPN) {
      # Convert FQDN from UPN to a NetBIOS domain name.
      $netbiosDomain = ($id.UPN.Split('.'))[0].ToUpper()
      return "$netbiosDomain\$($id.User)"
    }
    else {
      throw "RunAs '$($id.Raw)' has no domain info. Please provide the account in user@domain.com format."
    }
  }

  function Invoke-Sft([string[]]$MyArgs) {
    # Use ProcessStartInfo to capture stdout/stderr in memory without writing to disk.
    # This is critical for security as sft can output plaintext passwords.
    $psi = [System.Diagnostics.ProcessStartInfo]@{
      FileName               = "sft"
      # Manually quote arguments to support very old PowerShell versions (e.g. v2)
      # where modern argument escaping methods don't exist.
      Arguments              = ($MyArgs | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
      }) -join ' '
      RedirectStandardInput  = $true
      RedirectStandardOutput = $true
      RedirectStandardError  = $true
      UseShellExecute        = $false
      CreateNoWindow         = $true
    }

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    try {
      $p.Start() | Out-Null

      # Wait for the process to exit, with a 120-second timeout.
      if (-not ($p.WaitForExit(120000))) {
        # If the process is still running after the timeout, assume it's waiting for input.
        $p.Kill()
        $partialOutput = $p.StandardOutput.ReadToEnd()
        $errorMessage = "sft command timed out after 120 seconds, likely waiting for interactive input. Please run 'sft $MyArgs' manually to resolve the ambiguity."
        Write-Host $errorMessage -ForegroundColor Yellow
        exit 1
      }

      # Process exited within the timeout.
      $output = $p.StandardOutput.ReadToEnd()
      $errorOutput = $p.StandardError.ReadToEnd()

      if ($p.ExitCode -ne 0) { throw "sft failed (ExitCode: $($p.ExitCode)): $errorOutput" }
      return ($output -split "`r?`n")
    } finally {
      $p.Dispose()
    }
  }

  function Get-OpaAdPasswordSecure([string]$AdDomainFqdn, [string]$AdUsername, [string]$Team) {
    $teamArgs = @()
    if ($Team) { $teamArgs += @("--team",$Team) }

    try {
      Write-Host "Authenticating with Okta Privileged Access..." -ForegroundColor Cyan
      Invoke-Sft -MyArgs (@("login") + $teamArgs) | Out-Null
      Write-Host "Retrieving credentials for $AdUsername@$AdDomainFqdn..." -ForegroundColor Cyan
      $out = Invoke-Sft -MyArgs (@("ad","reveal","--domain",$AdDomainFqdn,"--ad-account",$AdUsername) + $teamArgs)
      $pw = ($out | Where-Object { $_ -and $_.Trim().Length -gt 0 -and $_ -notmatch 'PASSWORD\s+ACCOUNT' -and $_ -notmatch 'Session expires' } | Select-Object -First 1).Split(' ')[0]

      if (-not $pw) { throw "OPA did not return a password for $AdDomainFqdn\$AdUsername." }

      return (ConvertTo-SecureString -String $pw -AsPlainText -Force)
    } finally {
      # Ensure plaintext variables are cleared immediately after use.
      $pw = $null
    }
  }

  function Test-TcpPort {
    param([string]$Host, [int]$Port, [int]$TimeoutMs = 1500)
    try { $client = New-Object System.Net.Sockets.TcpClient; $client.Connect($Host, $Port); $client.Close(); return $true } catch { return $false }
  }

  function Parse-Identity([string]$IdentityString) {
    if ($IdentityString -match '^(?<usr>[^@]+)@(?<dom>.+)$') {
      return [pscustomobject]@{ User=$Matches.usr; UPN=$Matches.dom; Raw=$IdentityString }
    }
    return [pscustomobject]@{ User=$IdentityString; UPN=$null; Raw=$IdentityString }
  }

  $mmc = Join-Path $env:SystemRoot "System32\mmc.exe"
  $sys32 = Join-Path $env:SystemRoot "System32"
  $Presets = @{
    aduc     = @{ File=$mmc; Args=@((Join-Path $sys32 "dsa.msc"));      Icon="$sys32\dsadmin.dll,0";            Name="Active Directory Users and Computers" }
    gpo      = @{ File=$mmc; Args=@((Join-Path $sys32 "gpmc.msc"));     Icon="$sys32\gpoadmin.dll,0";           Name="Group Policy Management" }
    dns      = @{ File=$mmc; Args=@((Join-Path $sys32 "dnsmgmt.msc")); Icon="$sys32\dnsmgr.dll,0";              Name="DNS Manager" }
    dhcp     = @{ File=$mmc; Args=@((Join-Path $sys32 "dhcpmgmt.msc")); Icon="$sys32\dhcpssvc.dll,0";           Name="DHCP Manager" }
    sites    = @{ File=$mmc; Args=@((Join-Path $sys32 "dssite.msc"));   Icon="$sys32\dsadmin.dll,2";            Name="Active Directory Sites and Services" }
    domains  = @{ File=$mmc; Args=@((Join-Path $sys32 "domain.msc"));   Icon="$sys32\domadmin.dll,0";           Name="Active Directory Domains and Trusts" }
    adsiedit = @{ File=$mmc; Args=@((Join-Path $sys32 "adsiedit.msc")); Icon="$sys32\adsiedit.dll,0";           Name="ADSI Edit" }
    certtmpl = @{ File=$mmc; Args=@("certtmpl.msc"); Icon="$sys32\certmgr.dll,0";                               Name="Certificate Templates" }
    certsrv  = @{ File=$mmc; Args=@("certsrv.msc");  Icon="$sys32\certmgr.dll,0";                               Name="Certification Authority" }
    pkiview  = @{ File=$mmc; Args=@("pkiview.msc");  Icon="$sys32\certmgr.dll,0";                               Name="Enterprise PKI" }
    compmgmt = @{ File=$mmc; Args=@((Join-Path $sys32 "compmgmt.msc")); Icon="$sys32\mycomput.dll,0";           Name="Computer Management" }
    eventvwr = @{ File=$mmc; Args=@((Join-Path $sys32 "eventvwr.msc")); Icon="$sys32\eventvwr.exe,0";           Name="Event Viewer" }
    services = @{ File=$mmc; Args=@("services.msc"); Icon="$sys32\filemgmt.dll,0";                              Name="Services" }
    taskschd = @{ File=$mmc; Args=@("taskschd.msc"); Icon="$sys32\mstask.dll,0";                                Name="Task Scheduler" }
    diskmgmt = @{ File=$mmc; Args=@("diskmgmt.msc"); Icon="$sys32\dmdskres.dll,0";                              Name="Disk Management" }
    wf       = @{ File=$mmc; Args=@("wf.msc");       Icon="$sys32\FirewallControlPanel.dll,0";                  Name="Windows Firewall with Advanced Security" }
    regedit  = @{ File="regedit.exe"; Args=@();      Icon="$env:SystemRoot\regedit.exe,0";                      Name="Registry Editor" }
    control  = @{ File="control.exe"; Args=@();      Icon="$sys32\control.exe,0";                               Name="Control Panel" }
    pwsh     = @{ File="pwsh.exe"; Args=@("-NoExit"); Icon="";                                                  Name="PowerShell 7" }
    powershell = @{ File="powershell.exe"; Args=@("-NoExit"); Icon="";                                          Name="Windows PowerShell" }
  }

  # Commands that don't need credentials
  if ($RunAs.ToLowerInvariant() -eq "list-tools") {
    $Presets.Keys | Sort-Object | ForEach-Object { $_ }
    return
  }

  if ($RunAs.ToLowerInvariant() -eq "create-shortcuts") {
    if (-not $Tool) {
      throw "The 'create-shortcuts' command requires an account argument. e.g. 'sft-runas create-shortcuts admin@corp.example.com'"
    }
    if ($StartMenu -and -not $Folder) {
      throw "The -StartMenu option requires -Folder to be specified. e.g. 'sft-runas create-shortcuts admin@corp.example.com -StartMenu -Folder ""Admin Tools""'"
    }

    $account = $Tool

    if ($StartMenu) {
      $basePath = Join-Path ([System.Environment]::GetFolderPath('StartMenu')) "Programs"
    } else {
      $basePath = [System.Environment]::GetFolderPath('Desktop')
    }

    if ($Folder) {
      $basePath = Join-Path $basePath $Folder
      if (-not (Test-Path $basePath)) {
        New-Item -ItemType Directory -Path $basePath -Force | Out-Null
      }
    }

    $wshShell = New-Object -ComObject WScript.Shell

    if ($StartMenu) {
      $location = "Start Menu folder '$Folder'"
    } elseif ($Folder) {
      $location = "desktop folder '$Folder'"
    } else {
      $location = "desktop"
    }
    Write-Host "Creating shortcuts in your $location for account '$account'..." -ForegroundColor Cyan

    $createdCount = 0
    $skippedCount = 0

    foreach ($preset in $Presets.GetEnumerator() | Sort-Object Name) {
      $toolName = $preset.Name
      $toolInfo = $preset.Value

      # Check if tool is available locally
      $isAvailable = $false
      if ($toolInfo.File -eq $mmc) {
        $mscPath = $toolInfo.Args[0]
        if ($mscPath -notmatch '^[A-Z]:\\' -and $mscPath -notmatch '^\\\\') {
          $mscPath = Join-Path $sys32 $mscPath
        }
        $isAvailable = Test-Path $mscPath
      } else {
        $isAvailable = $null -ne (Get-Command $toolInfo.File -ErrorAction SilentlyContinue)
      }

      $displayName = if ($toolInfo.Name) { $toolInfo.Name } else { $toolName }

      if (-not $isAvailable) {
        Write-Host "Skipped: $displayName (not installed)" -ForegroundColor Yellow
        $skippedCount++
        continue
      }

      $shortcutName = "$displayName (SftRunAs)"
      $shortcutPath = Join-Path $basePath "$shortcutName.lnk"

      $psExe = Get-Command pwsh
      $shortcut = $wshShell.CreateShortcut($shortcutPath)
      $shortcut.TargetPath = $psExe.Source
      $shortcut.Arguments = "-NoProfile -Command `"Import-Module SftRunAs; sft-runas '$account' '$toolName'`""
      $shortcut.WorkingDirectory = $env:USERPROFILE
      $shortcut.Description = "Run $displayName as $account via Okta Privileged Access"

      if ($toolInfo.Icon) {
        $shortcut.IconLocation = $toolInfo.Icon
      }
      $shortcut.Save()
      Write-Host "Created: $displayName" -ForegroundColor Green
      $createdCount++
    }

    Write-Host ""
    Write-Host "Done. Created $createdCount shortcut(s), skipped $skippedCount." -ForegroundColor Cyan
    if ($skippedCount -gt 0) {
      Write-Host "Tip: Install RSAT to enable additional AD/DNS/DHCP tools." -ForegroundColor Yellow
    }
    return
  }

  if ($RunAs.ToLowerInvariant() -eq "doctor") {
    Require-Command "sft"

    Write-Host "Environment" -ForegroundColor Cyan
    Write-Host "  sft path:        $((Get-Command sft).Source)"
    Write-Host "  User DNS domain: $($env:USERDNSDOMAIN)"
    Write-Host "  MMC path:        $mmc"
    Write-Host "  MMC exists:      $(Test-Path $mmc)"
    Write-Host ""

    if ($ComputerName) {
      Write-Host "Remote Target: $ComputerName" -ForegroundColor Cyan
      $dnsResolves = $false
      try { [System.Net.Dns]::GetHostAddresses($ComputerName) | Out-Null; $dnsResolves = $true } catch {}
      Write-Host "  DNS resolves: $dnsResolves"
      Write-Host "  WinRM 5985:   $(Test-TcpPort -Host $ComputerName -Port 5985)"
      Write-Host "  WinRM 5986:   $(Test-TcpPort -Host $ComputerName -Port 5986)"
      Write-Host ""
    }

    Write-Host "Tool Availability" -ForegroundColor Cyan
    $available = @()
    $unavailable = @()
    foreach ($preset in $Presets.GetEnumerator() | Sort-Object Name) {
      $toolName = $preset.Name
      $toolInfo = $preset.Value

      $isAvailable = $false
      if ($toolInfo.File -eq $mmc) {
        $mscPath = $toolInfo.Args[0]
        if ($mscPath -notmatch '^[A-Z]:\\' -and $mscPath -notmatch '^\\\\') {
          $mscPath = Join-Path $sys32 $mscPath
        }
        $isAvailable = Test-Path $mscPath
      } else {
        $isAvailable = $null -ne (Get-Command $toolInfo.File -ErrorAction SilentlyContinue)
      }

      if ($isAvailable) {
        $available += $toolName
      } else {
        $unavailable += $toolName
      }
    }

    Write-Host "  Available ($($available.Count)):" -ForegroundColor Green
    $available | ForEach-Object { Write-Host "    $_" }

    if ($unavailable.Count -gt 0) {
      Write-Host "  Unavailable ($($unavailable.Count)):" -ForegroundColor Yellow
      $unavailable | ForEach-Object { Write-Host "    $_" }
      Write-Host ""
      Write-Host "  Tip: Install RSAT to enable AD/DNS/DHCP tools" -ForegroundColor Yellow
    }

    return
  }

  # Main execution
  Require-Command "sft"
  
  Write-Host "Attempting to run '$Tool' as '$RunAs'..." -ForegroundColor Cyan

  $id = Parse-Identity -IdentityString $RunAs

  if (-not $AdDomainFqdn) {
    if ($id.UPN) { $AdDomainFqdn = $id.UPN }
    elseif ($env:USERDNSDOMAIN) { $AdDomainFqdn = $env:USERDNSDOMAIN }
    else { throw "Could not determine AD Domain FQDN. Provide it via the -AdDomainFqdn parameter, as part of the user identity (user@domain.com), or ensure the USERDNSDOMAIN environment variable is set." }
  }

  $logonName = Format-LogonName -id $id

  $toolKey = $Tool
  if (-not $toolKey) { throw "Tool is required (or use: list-tools / doctor)." }

  $launchFile = $null
  $launchArgs = @()

  if ($toolKey.ToLowerInvariant() -eq "remote-ps") {
    if (-not $ToolArgs -or $ToolArgs.Count -lt 1) { throw "remote-ps requires a target computer name." }
    $target = $ToolArgs[0]
    $shellExe = (Get-Command pwsh).Source
    $launchFile = $shellExe
    $launchArgs = @("-NoExit","-Command","Enter-PSSession -ComputerName `"$target`"")
  }
  elseif ($Presets.ContainsKey($toolKey.ToLowerInvariant())) {
    $launchFile = $Presets[$toolKey.ToLowerInvariant()].File
    $launchArgs = @($Presets[$toolKey.ToLowerInvariant()].Args)
    if ($ToolArgs) { $launchArgs += $ToolArgs }
  }
  else {
    $launchFile = $toolKey
    if ($ToolArgs) { $launchArgs = $ToolArgs }
  }


  try {
    $secure = Get-OpaAdPasswordSecure -AdDomainFqdn $AdDomainFqdn -AdUsername $($id.User) -Team $Team
    Write-Host "Credentials retrieved successfully." -ForegroundColor Green
    $cred   = [pscredential]::new($logonName, $secure)

    # Start-Process cannot use -Credential and -Verb RunAs together.
    # The workaround is to start a new PowerShell process with the credentials,
    # and from within that process, launch the target tool with elevation.
    $encodedArgs = [System.Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($launchArgs))
    $command = "Start-Process -FilePath '$launchFile' -ArgumentList (([System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String('$encodedArgs'))) | ConvertFrom-Csv -Header 'Arg' | Select-Object -ExpandProperty 'Arg') -Verb RunAs"

    Write-Host "Launching $Tool with elevated privileges..." -ForegroundColor Cyan
    $p = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoProfile", "-Command", $command -Credential $cred -WindowStyle Hidden -PassThru

    if ($Wait) { $p.WaitForExit() | Out-Null }
    if ($PassThru) { $p }
  }
  finally {
    $secure = $null
    $cred   = $null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
  }
}

Set-Alias -Name sft-runas -Value Invoke-SftRunAs
Set-Alias -Name sftrunas -Value Invoke-SftRunAs
Export-ModuleMember -Function Invoke-SftRunAs -Alias sft-runas, sftrunas
