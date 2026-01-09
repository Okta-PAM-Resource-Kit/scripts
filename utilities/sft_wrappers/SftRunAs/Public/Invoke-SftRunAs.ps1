function Invoke-SftRunAs {
  [CmdletBinding(PositionalBinding=$true)]
  param(
    [Parameter(Position=0, Mandatory=$true)]
    [string]$RunAs,          # DOMAIN\user | user@domain | bare user | list-tools | doctor

    [Parameter(Position=1)]
    [string]$Tool,

    [Parameter(Position=2, ValueFromRemainingArguments=$true)]
    [string[]]$ToolArgs,

    [string]$Team,
    [string]$AdDomainFqdn,

    [ValidateSet("Auto","NetBIOS","UPN")]
    [string]$AccountNameFormat = "Auto",

    [switch]$UseUpn,
    [switch]$UseNetBios,

    [string]$NetBiosDomain,
    [string]$UpnDomain,

    [ValidateSet("Auto","Pwsh","WindowsPowerShell")]
    [string]$Shell = "Auto", # used by remote-ps preset only

    [string]$ComputerName,   # doctor only
    [switch]$VerboseDoctor,

    [switch]$Wait,
    [switch]$PassThru
  )

  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'

  if ($UseUpn -and $UseNetBios) { throw "Choose only one: -UseUpn or -UseNetBios." }
  if ($UseUpn)     { $AccountNameFormat = "UPN" }
  if ($UseNetBios) { $AccountNameFormat = "NetBIOS" }

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

  function Parse-Identity([string]$Input) {
    if ($Input -match '^(?<dom>[^\\]+)\\(?<usr>.+)$') {
      return [pscustomobject]@{ User=$Matches.usr; NetBIOS=$Matches.dom; UPN=$null; Raw=$Input }
    }
    if ($Input -match '^(?<usr>[^@]+)@(?<dom>.+)$') {
      return [pscustomobject]@{ User=$Matches.usr; NetBIOS=$null; UPN=$Matches.dom; Raw=$Input }
    }
    return [pscustomobject]@{ User=$Input; NetBIOS=$null; UPN=$null; Raw=$Input }
  }

  function Format-LogonName($id) {
    switch ($AccountNameFormat) {
      "Auto" {
        if ($id.Raw -match '[\\@]') { return $id.Raw }
        if ($NetBiosDomain) { return "$NetBiosDomain\$($id.User)" }
        if ($UpnDomain)     { return "$($id.User)@$UpnDomain" }
        throw "RunAs '$($id.Raw)' has no domain info. Provide -NetBiosDomain or -UpnDomain, or pass DOMAIN\user / user@domain."
      }
      "NetBIOS" {
        $dom = if ($id.NetBIOS) { $id.NetBIOS } else { $NetBiosDomain }
        if (-not $dom) { throw "NetBIOS domain required (DOMAIN\user or -NetBiosDomain)." }
        return "$dom\$($id.User)"
      }
      "UPN" {
        $dom = if ($id.UPN) { $id.UPN } else { $UpnDomain }
        if (-not $dom) { throw "UPN domain required (user@domain or -UpnDomain)." }
        return "$($id.User)@$dom"
      }
    }
  }

  function Invoke-Sft([string[]]$Args) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "sft"
    $psi.Arguments = ($Args | ForEach-Object {
      if ($_ -match '\s') { '"' + ($_ -replace '"','\"') + '"' } else { $_ }
    }) -join ' '
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()

    if ($p.ExitCode -ne 0) { throw "sft failed ($($p.ExitCode)): $err" }
    return ($out -split "`r?`n")
  }

  function Get-OpaAdPasswordPlain([string]$AdDomainFqdn, [string]$AdUsername, [string]$Team) {
    $teamArgs = @()
    if ($Team) { $teamArgs += @("--team",$Team) }

    Invoke-Sft (@("login") + $teamArgs) | Out-Null
    $out = Invoke-Sft (@("ad","reveal","--domain",$AdDomainFqdn,"--ad-account",$AdUsername) + $teamArgs)

    $pw = ($out | Where-Object { $_ -and $_.Trim().Length -gt 0 } | Select-Object -First 1).Trim()
    if (-not $pw) { throw "OPA did not return a password for $AdDomainFqdn\$AdUsername." }
    return $pw
  }

  function Test-TcpPort {
    param([string]$Host, [int]$Port, [int]$TimeoutMs = 1500)
    try {
      $client = New-Object System.Net.Sockets.TcpClient
      $iar = $client.BeginConnect($Host, $Port, $null, $null)
      if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) { $client.Close(); return $false }
      $client.EndConnect($iar) | Out-Null
      $client.Close()
      return $true
    } catch { return $false }
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

  $id = Parse-Identity -Input $RunAs

  if (-not $AdDomainFqdn) {
    if ($env:USERDNSDOMAIN) { $AdDomainFqdn = $env:USERDNSDOMAIN }
    else { throw "No -AdDomainFqdn provided and USERDNSDOMAIN is empty. Provide -AdDomainFqdn (e.g. corp.example.com)." }
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

  $plain = Get-OpaAdPasswordPlain -AdDomainFqdn $AdDomainFqdn -AdUsername $id.User -Team $Team

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
