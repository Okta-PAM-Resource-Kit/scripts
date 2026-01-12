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

    [ValidateSet("Auto","Pwsh","WindowsPowerShell")]
    [string]$Shell = "Auto", # used by remote-ps preset only

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
  sft-runas doctor [-ComputerName <target>]

Arguments:
  <account>      Privileged account (e.g. 'CORP\admin' or 'admin@corp.example.com')
  <tool>         Tool preset (e.g. 'aduc') or path to an executable.
  [tool_args]    Arguments to pass to the tool.

Special Commands:
  list-tools     Show available tool presets.
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

  function Get-PowerShellEngines {
    [pscustomobject]@{
      Pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
      WindowsPowerShell = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source
    }
  }

  function Select-PowerShellEngine {
    param([ValidateSet("Auto","Pwsh","WindowsPowerShell")] [string]$Mode = "Auto")
    $e = Get-PowerShellEngines
    if ($Mode -eq "Pwsh") { if (-not $e.Pwsh) { throw "pwsh not found." }; return $e.Pwsh }
    if ($Mode -eq "WindowsPowerShell") { if (-not $e.WindowsPowerShell) { throw "powershell.exe not found." }; return $e.WindowsPowerShell }
    if ($e.Pwsh) { return $e.Pwsh }
    if ($e.WindowsPowerShell) { return $e.WindowsPowerShell }
    throw "Neither pwsh nor powershell.exe was found."
  }

  function Parse-Identity([string]$IdentityString) {
    Write-Host "IdentityString is '$IdentityString'" -ForegroundColor Cyan
    if ($IdentityString -match '^(?<usr>[^@]+)@(?<dom>.+)$') {
      return [pscustomobject]@{ User=$Matches.usr; UPN=$Matches.dom; Raw=$IdentityString }
    }
    return [pscustomobject]@{ User=$IdentityString; UPN=$null; Raw=$IdentityString }
  }

  function Format-LogonName($id) {
    if ($id.UPN) {
      return "$($id.User)@$($id.UPN)"
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
    $p.Start() | Out-Null

    $output = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit(1000) # Wait up to 1 second for exit

    # If process is still running, it's likely waiting for input.
    if (-not $p.HasExited) {
      if ($output -match "Select an access method from the above list:") {
        Write-Host $output -ForegroundColor Yellow
        $selection = Read-Host "Please enter your selection"
        $p.StandardInput.WriteLine($selection)
        $finalOutput = $p.StandardOutput.ReadToEnd() # Read the final output after providing input
        $output += $finalOutput
      } else {
        # The process is hung for a reason we don't handle. Terminate it.
        $p.Kill()
        throw "sft process became unresponsive without a recognized prompt. Output: $output"
      }
    }

    $errorOutput = $p.StandardError.ReadToEnd()
    if ($p.ExitCode -ne 0) { throw "sft failed (ExitCode: $($p.ExitCode)): $errorOutput" }

    return ($output -split "`r?`n")
  }

  function Get-OpaAdPasswordPlain([string]$AdDomainFqdn, [string]$AdUsername, [string]$Team) {
    $teamArgs = @()
    if ($Team) { $teamArgs += @("--team",$Team) }

    Invoke-Sft -MyArgs (@("login") + $teamArgs)
    $out = Invoke-Sft -MyArgs (@("ad","reveal","--domain",$AdDomainFqdn,"--ad-account",$AdUsername) + $teamArgs)
    Write-Host "sft output was '$out'" -ForegroundColor Cyan
    $pw = ($out | Where-Object { $_ -and $_.Trim().Length -gt 0 -and $_ -notmatch 'PASSWORD\s+ACCOUNT' } | Select-Object -First 1).Split(' ')[0]
    if (-not $pw) { throw "OPA did not return a password for $AdDomainFqdn\$AdUsername." }
    return $pw
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
  }

  # Commands that don't need credentials
  if ($RunAs.ToLowerInvariant() -eq "list-tools") {
    $Presets.Keys | Sort-Object | ForEach-Object { $_ }
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
    $shellExe = Select-PowerShellEngine -Mode $Shell
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


  $plain = Get-OpaAdPasswordPlain -AdDomainFqdn $AdDomainFqdn -AdUsername $($id.User) -Team $Team

  try {
    $secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
    $cred   = [pscredential]::new($logonName, $secure)

    $p = Start-Process -FilePath $launchFile -ArgumentList $launchArgs -Credential $cred -PassThru

    if ($Wait) { $p.WaitForExit() | Out-Null }
    if ($PassThru) { $p }
  }
  finally {
    $plain  = $null
    $secure = $null
    $cred   = $null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
  }
}

Set-Alias -Name sft-runas -Value Invoke-SftRunAs
Export-ModuleMember -Function Invoke-SftRunAs -Alias sft-runas
