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
  sft-runas create-shortcuts <account>
  sft-runas doctor [-ComputerName <target>]

Arguments:
  <account>      Privileged account (e.g. 'CORP\admin' or 'admin@corp.example.com')
  <tool>         Tool preset (e.g. 'aduc') or path to an executable.
  [tool_args]    Arguments to pass to the tool.

Special Commands:
  list-tools     Show available tool presets.
  create-shortcuts Create desktop shortcuts for all tool presets.
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
  $Presets = @{
    aduc     = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\dsa.msc")) }
    gpo      = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\gpmc.msc")) }
    dns      = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\dnsmgmt.msc")) }
    dhcp     = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\dhcpmgmt.msc")) }
    sites    = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\dssite.msc")) }
    domains  = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\domain.msc")) }
    adsiedit = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\adsiedit.msc")) }
    certtmpl = @{ File=$mmc; Args=@("certtmpl.msc") }
    certsrv  = @{ File=$mmc; Args=@("certsrv.msc") }
    pkiview  = @{ File=$mmc; Args=@("pkiview.msc") }
    compmgmt = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\compmgmt.msc")) }
    eventvwr = @{ File=$mmc; Args=@((Join-Path $env:SystemRoot "System32\eventvwr.msc")) }
    services = @{ File=$mmc; Args=@("services.msc") }
    taskschd = @{ File=$mmc; Args=@("taskschd.msc") }
    diskmgmt = @{ File=$mmc; Args=@("diskmgmt.msc") }
    wf       = @{ File=$mmc; Args=@("wf.msc") }
    regedit  = @{ File="regedit.exe"; Args=@() }
    control  = @{ File="control.exe"; Args=@() }
    pwsh     = @{ File="pwsh.exe"; Args=@("-NoExit") }
    powershell = @{ File="powershell.exe"; Args=@("-NoExit") }
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
    $account = $Tool
    $desktopPath = [System.Environment]::GetFolderPath('Desktop')
    $scriptPath = $MyInvocation.MyCommand.Path
    $wshShell = New-Object -ComObject WScript.Shell

    Write-Host "Creating shortcuts on your desktop for account '$account'..." -ForegroundColor Cyan

    foreach ($preset in $Presets.GetEnumerator() | Sort-Object Name) {
      $toolName = $preset.Name
      $toolInfo = $preset.Value
      $shortcutName = "SftRunAs - $toolName"
      $shortcutPath = Join-Path $desktopPath "$shortcutName.lnk"

      $psExe = Get-Command pwsh
      $shortcut = $wshShell.CreateShortcut($shortcutPath)
      $shortcut.TargetPath = $psExe.Source
      $shortcut.Arguments = "-NoProfile -File `"$scriptPath`" -RunAs '$account' -Tool '$toolName'"
      $shortcut.Description = "Run $toolName as $account via Okta Privileged Access"
      
      if ($toolInfo.File -eq $mmc) {
        $shortcut.IconLocation = $toolInfo.Args[0] # .msc file
      } else {
        $shortcut.IconLocation = $toolInfo.File # .exe file
      }
      $shortcut.Save()
      Write-Host "Created shortcut: $shortcutName"
    }
    return
  }

  if ($RunAs.ToLowerInvariant() -eq "doctor") {
    Require-Command "sft"
    $result = [ordered]@{
      SftPath         = (Get-Command sft).Source
      UserDnsDomain   = $env:USERDNSDOMAIN
      MmcPath         = $mmc
      MmcExists       = (Test-Path $mmc)
      ToolPresetCount = $Presets.Count
    }

    if ($ComputerName) {
      $result.RemoteTarget = $ComputerName
      try { [System.Net.Dns]::GetHostAddresses($ComputerName) | Out-Null; $result.DnsResolves = $true } catch { $result.DnsResolves = $false }
      $result.WinRM5985 = (Test-TcpPort -Host $ComputerName -Port 5985)
      $result.WinRM5986 = (Test-TcpPort -Host $ComputerName -Port 5986)
    }

    if ($VerboseDoctor) { $result } else { [pscustomobject]$result }
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
