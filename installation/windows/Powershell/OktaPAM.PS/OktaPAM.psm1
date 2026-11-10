<#
 .Synopsis
  Installs the OktaPAM Server Toools

 .Description
  Installs the OktaPAM Server Tools to a specific version, and if installing for the first time
  will set the configuration file with various values.

  Also provides Uninstall-OktaPamServerTools, Clear-OktaPamEnrollment and Test-OktaPamEnrollment.
  Progress is logged to the console and to C:\sftd_bootstrap.log.

 .Parameter ToolsVersion
  Optional, version of the OktaPAM Server Tools to Install. If not supplied, the latest available
  version is installed. Supplying a version on an already enrolled server implies -Upgrade.

 .Parameter EnrollmentToken
  Optionally sets the OktaPAM Enrollment Token. Without a token the agent is installed but not
  enrolled; enroll it later by running again with -EnrollmentToken.

 .Parameter OverwriteConfig
  Optional, regenerates sftd.yaml (CanonicalName and BrokeredLoginGracePeriodInSeconds) even if
  one already exists. By default an existing sftd.yaml is left unchanged.

 .Parameter Reenroll
  Optional, clears enrollment data (enrollment.complete flag and the state directory) so the
  server enrolls again. The agent stays installed.

 .Parameter Reinstall
  Optional, uninstalls the agent before installing it again. Combine with -Reenroll to also
  clear enrollment data.

 .Parameter Upgrade
  Optional, upgrades an already enrolled server (to the latest version, or to -ToolsVersion)
  while keeping its enrollment. Without -Upgrade an enrolled server is skipped. Supplying
  -ToolsVersion or -VersionsBehind implies -Upgrade. An agent already at or above the target
  version is left alone.

 .Parameter VersionsBehind
  Optional, installs the release N versions behind the latest (0 = latest, 1 = the one before it,
  and so on) for admins who don't want the newest agent. Implies -Upgrade, cannot be combined
  with -ToolsVersion, and never downgrades an agent that is already at or above that version.

 .Parameter EnrollmentTimeoutSeconds
  Optional, how long to wait for the agent to consume enrollment.token and create device.token.
  Defaults to 120.

 .Example
   # Installs the OktaPAM Server Agent
   Install-OktaPAMServerTools -ToolsVersion 1.22.1

 .Example
   # Installs and enrolls the agent
   Install-OktaPamServerTools -EnrollmentToken <token>

 .Example
   # Clears enrollment data and enrolls again with a new token
   Install-OktaPamServerTools -EnrollmentToken <token> -Reenroll

 .Example
   # Uninstalls and reinstalls the agent, clearing enrollment data
   Install-OktaPamServerTools -EnrollmentToken <token> -Reinstall -Reenroll
#>

$script:LogFile = "C:\sftd_bootstrap.log"

function Write-OktaPamLog(){
    param(
        [Parameter(Mandatory=$true)][string]$Message,
        [Parameter(Mandatory=$false)][ValidateSet("INFO","WARNING","ERROR","SUCCESS")][string]$Level = "INFO"
    )
    process{
        $line = "[{0:yyyy-MM-dd HH:mm}] {1}: {2}" -f (Get-Date), $Level, $Message
        Write-Host $line
        Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
    }
}

function Assert-OktaPamAdministrator(){
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This command must be run as an administrator."
    }
}

function Get-OktaPamPaths(){
    # Select Local System User, where the ScaleFT Server Agent Runs
    $systemprofile = (Get-CIMInstance win32_userprofile  | where-object sid -eq "S-1-5-18" | select -ExpandProperty localpath)
    $configDir = Join-Path $systemprofile -ChildPath 'AppData' | Join-Path -ChildPath "Local" | Join-Path -ChildPath "ScaleFT"
    [pscustomobject]@{
        ConfigDir       = $configDir
        StateDir        = Join-Path $configDir -ChildPath "state"
        YamlFile        = Join-Path $configDir -ChildPath "sftd.yaml"
        TokenFile       = Join-Path $configDir -ChildPath "enrollment.token"
        DeviceTokenFile = Join-Path $configDir -ChildPath "device.token"
        EnrollmentFlag  = Join-Path $configDir -ChildPath "enrollment.complete"
        SftdExe         = Join-Path $env:ProgramFiles -ChildPath "ScaleFT\Server Agent\sftd.exe"
    }
}

function Get-URL-With-Authenticode(){
    param(
        [Parameter(Mandatory=$true)][string]$url,
        [Parameter(Mandatory=$true)][string]$output
    )
    process{
        $baseDir = Split-Path -Parent -Path $output

        if (!(Test-Path "$output")) {
            echo "Downloading $url to $output"
            New-Item -force -path $baseDir -type directory
            Invoke-WebRequest -UserAgent "OktaPAM/PS1-0.1.1" -UseBasicParsing -TimeoutSec 30 -Uri $url -OutFile $output
        } else {
            echo "Existing $output found"
        }

        $sig = Get-AuthenticodeSignature $output

        if ($sig.Status -ne "Valid") {
            echo "error: signature for $($output) is invalid: $($sig.Status) from $($sig.SignerCertificate.ToString())"
            throw "error: signature for $($output) is invalid: $($sig.Status) from $($sig.SignerCertificate.ToString())"
        }

        echo "$($output) is signed by ScaleFT"
    }
}

# The service is registered as scaleft-server-tools and displayed as "ScaleFT Server Agent"
function Get-ScaleFTService(){
    Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq "scaleft-server-tools" -or $_.DisplayName -eq "ScaleFT Server Agent" } |
        Select-Object -First 1
}

function Stop-ScaleFTService(){
    $svc = Get-ScaleFTService
    if ($svc) {
        if ($svc.Status -ne "Stopped") {
            Write-OktaPamLog "Stopping service $($svc.Name)"
            Stop-Service -Name $svc.Name
            return $true
        }
        Write-OktaPamLog "Service $($svc.Name) is not running"
    }
    return $false
}

function Start-ScaleFTService(){
    $svc = Get-ScaleFTService
    if ($svc) {
        Write-OktaPamLog "Starting service $($svc.Name)"
        Start-Service -Name $svc.Name
        return $true
    }
    return $false
}

# Enrollment is only confirmed when device.token exists and enrollment.token is absent
function Test-OktaPamEnrollment(){
    $paths = Get-OktaPamPaths
    return ((-not (Test-Path $paths.TokenFile)) -and (Test-Path $paths.DeviceTokenFile))
}

# Polls until enrollment is confirmed. Returns $true on success, $false on timeout.
function Wait-OktaPamEnrollment(){
    param(
        [Parameter(Mandatory=$false)][int]$TimeoutSeconds = 120,
        [Parameter(Mandatory=$false)][int]$IntervalSeconds = 5
    )
    $waited = 0
    while ($waited -lt $TimeoutSeconds) {
        if (Test-OktaPamEnrollment) {
            return $true
        }
        Start-Sleep -Seconds $IntervalSeconds
        $waited += $IntervalSeconds
    }
    return (Test-OktaPamEnrollment)
}

function Set-OktaPamEnrollmentFlag(){
    $paths = Get-OktaPamPaths
    New-Item -ItemType directory -Path $paths.ConfigDir -Force | Out-Null
    "Enrolled on $(Get-Date)" | Out-File $paths.EnrollmentFlag -Encoding "ASCII" -Force
    Write-OktaPamLog "Enrollment flag created at: $($paths.EnrollmentFlag)"
}

# Deletes the enrollment flag and state directory. Does not touch the service.
function Remove-OktaPamEnrollmentData(){
    $paths = Get-OktaPamPaths
    if (Test-Path $paths.EnrollmentFlag) {
        Write-OktaPamLog "Deleting enrollment flag: $($paths.EnrollmentFlag)"
        Remove-Item -Force $paths.EnrollmentFlag
    }
    if (Test-Path $paths.StateDir) {
        Write-OktaPamLog "Deleting state directory: $($paths.StateDir)"
        Remove-Item -Recurse -Force $paths.StateDir
    }
    Write-OktaPamLog "Enrollment data cleared"
}

function Remove-OktaPamAgent(){
    $paths = Get-OktaPamPaths
    if (Test-Path $paths.SftdExe) {
        Write-OktaPamLog "Uninstalling existing OPA agent..."
        Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like '*ScaleFT*' } | ForEach-Object { $_.Uninstall() | Out-Null }
        Start-Sleep -Seconds 10
        if (Test-Path $paths.SftdExe) {
            Write-OktaPamLog "Agent executable still exists after uninstall attempt" "WARNING"
        } else {
            Write-OktaPamLog "Agent uninstalled successfully"
        }
    } else {
        Write-OktaPamLog "No existing agent installation found"
    }
}

<#
 .Synopsis
  Clears the OktaPAM enrollment data so the server can enroll again.

 .Description
  Deletes the enrollment.complete flag and the state directory. The agent stays installed. The
  service is stopped while the data is removed and started again if it was running.
#>
function Clear-OktaPamEnrollment(){
    process{
        $ErrorActionPreference = "Stop";
        Assert-OktaPamAdministrator
        $stopped = Stop-ScaleFTService
        try {
            Remove-OktaPamEnrollmentData
        } finally {
            if ($stopped) {
                Start-ScaleFTService | Out-Null
            }
        }
    }
}

<#
 .Synopsis
  Uninstalls the OktaPAM Server Tools.

 .Description
  Stops the agent service and uninstalls the ScaleFT MSI. Enrollment data is left in place unless
  -ClearEnrollment is given.

 .Parameter ClearEnrollment
  Optional, also deletes the enrollment.complete flag and state directory.
#>
function Uninstall-OktaPamServerTools(){
    param(
        [Parameter(Mandatory=$false)][switch]$ClearEnrollment
    )
    process{
        $ErrorActionPreference = "Stop";
        Assert-OktaPamAdministrator
        Stop-ScaleFTService | Out-Null
        Remove-OktaPamAgent
        if ($ClearEnrollment) {
            Remove-OktaPamEnrollmentData
        }
    }
}

function Install-OktaPamServerTools(){
    param(
        [Parameter(Mandatory=$false)][string]$EnrollmentToken,
        [Parameter(Mandatory=$false)][string]$ToolsVersion,
        [Parameter(Mandatory=$false)][switch]$OverwriteConfig,
        [Parameter(Mandatory=$false)][switch]$Reenroll,
        [Parameter(Mandatory=$false)][switch]$Reinstall,
        [Parameter(Mandatory=$false)][switch]$Upgrade,
        [Parameter(Mandatory=$false)][ValidateRange(0,50)][int]$VersionsBehind,
        [Parameter(Mandatory=$false)][int]$EnrollmentTimeoutSeconds = 120
    )
    process{
        $ErrorActionPreference = "Stop";
        # Check that the function is being run as administator.
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Error "This command must be run as an administrator."
            return
        }

        $paths = Get-OktaPamPaths
        $haveToken = $PSBoundParameters.ContainsKey("EnrollmentToken")
        $explicitVersion = $PSBoundParameters.ContainsKey("ToolsVersion")
        $explicitBehind = $PSBoundParameters.ContainsKey("VersionsBehind")
        if ($explicitVersion -and $explicitBehind) {
            throw "-ToolsVersion and -VersionsBehind cannot be used together."
        }
        # -ToolsVersion and -VersionsBehind also count as an explicit request to upgrade
        $doUpgrade = $Upgrade -or $explicitVersion -or $explicitBehind
        $enrolled = $false

        if ($haveToken) {
            Write-OktaPamLog "Using provided enrollment token"
        } else {
            Write-OktaPamLog "No enrollment token provided - agent will be installed without enrollment"
        }
        if ($explicitVersion) {
            Write-OktaPamLog "Specific version requested: $ToolsVersion"
        }

        # Force re-enrollment: clear enrollment data, leave the agent installed
        if ($Reenroll) {
            Write-OktaPamLog "Force re-enrollment requested - clearing enrollment data..." "WARNING"
            if (-not $Reinstall) {
                Stop-ScaleFTService | Out-Null
            }
            Remove-OktaPamEnrollmentData
        }

        # Force reinstallation: uninstall the agent first
        if ($Reinstall) {
            Write-OktaPamLog "Force reinstallation requested - removing existing agent..." "WARNING"
            Stop-ScaleFTService | Out-Null
            Remove-OktaPamAgent
        }

        # Prevent duplicate enrollments when the script is run again (for example at every boot).
        # Asking for a specific version is treated as an explicit upgrade and goes ahead.
        if (-not $Reenroll -and -not $Reinstall) {
            Write-OktaPamLog "Checking if OPA agent is already installed and enrolled..."

            if (Test-Path $paths.EnrollmentFlag) {
                if (Test-OktaPamEnrollment) {
                    Write-OktaPamLog "Enrollment verified - device.token present, enrollment.token absent"
                    $enrolled = $true
                } else {
                    Write-OktaPamLog "Enrollment flag found but enrollment is not confirmed - clearing flag" "WARNING"
                    Remove-Item -Force $paths.EnrollmentFlag
                }
            }

            $svc = Get-ScaleFTService
            if (-not $enrolled -and $svc -and $svc.Status -eq "Running") {
                Write-OktaPamLog "Service $($svc.Name) is running"
                if (Test-OktaPamEnrollment) {
                    Write-OktaPamLog "Enrollment confirmed - device.token present, enrollment.token absent"
                    Set-OktaPamEnrollmentFlag
                    $enrolled = $true
                } else {
                    Write-OktaPamLog "Service is running but enrollment not yet confirmed - enrollment may still be in progress"
                }
            }

            # Installed but not running: start it and see whether it was mid-enrollment
            if (-not $enrolled -and (Test-Path $paths.SftdExe) -and (-not $svc -or $svc.Status -ne "Running")) {
                Write-OktaPamLog "OPA agent is installed but service is not running - attempting to start it" "WARNING"
                try {
                    Start-ScaleFTService | Out-Null
                    if ((Test-Path $paths.TokenFile) -or (Test-Path $paths.DeviceTokenFile)) {
                        Write-OktaPamLog "Waiting for enrollment to complete..."
                        if (Wait-OktaPamEnrollment -TimeoutSeconds $EnrollmentTimeoutSeconds) {
                            Set-OktaPamEnrollmentFlag
                            $enrolled = $true
                        } else {
                            Write-OktaPamLog "Service started but enrollment did not complete - will attempt installation" "WARNING"
                        }
                    }
                } catch {
                    Write-OktaPamLog "Failed to start service - will attempt installation: $($_.Exception.Message)" "WARNING"
                }
            }

            if ($enrolled -and -not $doUpgrade) {
                Write-OktaPamLog "OPA agent is already enrolled. Skipping installation."
                Write-OktaPamLog "Use -Upgrade (optionally with -VersionsBehind) to upgrade, -Reenroll to force re-enrollment, or -Reinstall to force reinstallation."
                return
            }
            if ($enrolled) {
                Write-OktaPamLog "OPA agent is already enrolled - checking for an upgrade and keeping enrollment"
            } else {
                Write-OktaPamLog "No existing enrolled installation found - proceeding"
            }
        }

        $installBaseUrl = "https://dist.scaleft.com/repos/windows/stable/amd64/server-tools"
        $jsonUrl = "$($installBaseUrl)/dull.json"
        $jsonData = Invoke-RestMethod -Uri $jsonUrl
        # Releases are listed newest first, so -VersionsBehind N picks the Nth release back from the latest
        $releases = @($jsonData.releases)
        $releaseIndex = if ($explicitBehind) { $VersionsBehind } else { 0 }
        if ($releaseIndex -ge $releases.Count) {
            throw "-VersionsBehind $VersionsBehind is out of range: only $($releases.Count) releases are available (0 = latest)."
        }
        $release = $releases[$releaseIndex]
        $releaseLink = ($release.links | where { $_.rel -eq "installer" }).href

        if ($explicitVersion) {
            $targetVersion = $ToolsVersion
            $installerURL = "$($installBaseUrl)/v$($ToolsVersion)/ScaleFT-Server-Tools-$($ToolsVersion).msi"
        } else {
            $targetVersion = if ($releaseLink -match 'v?(\d+\.\d+\.\d+)') { $Matches[1] } else { $release.version }
            $installerURL = "$($installBaseUrl)/$($releaseLink)"
        }
        if ($explicitBehind) {
            Write-OktaPamLog "Selected release $VersionsBehind version(s) behind the latest: $targetVersion"
        }
        Write-OktaPamLog "Target version: $targetVersion"
        Write-OktaPamLog "MSI URL: $installerURL"

        # Don't reinstall (or downgrade) an enrolled agent that is already at or above the target
        if ($enrolled -and (Test-Path $paths.SftdExe)) {
            $installedVersion = $null
            $target = $null
            if ([version]::TryParse((Get-Item $paths.SftdExe).VersionInfo.ProductVersion, [ref]$installedVersion) -and
                [version]::TryParse($targetVersion, [ref]$target)) {
                if ($installedVersion -ge $target) {
                    Write-OktaPamLog "Installed version $installedVersion is already at or above $targetVersion. Nothing to do."
                    return
                }
                Write-OktaPamLog "Upgrading from $installedVersion to $targetVersion"
            } else {
                Write-OktaPamLog "Could not compare installed and target versions - proceeding with installation" "WARNING"
            }
        }

        New-Item -ItemType directory -Path $paths.ConfigDir -force | Out-Null

        # Write sftd.yaml on first install only, so upgrades keep any local customizations.
        # Use -OverwriteConfig to regenerate it.
        if ($OverwriteConfig -or !(Test-Path $paths.YamlFile)) {
            Write-OktaPamLog "Writing $($paths.YamlFile)"
            $yaml = @(
                "CanonicalName: $([System.Net.Dns]::GetHostName())",
                "BrokeredLoginGracePeriodInSeconds: 60"
            )
            $yaml | Out-File $paths.YamlFile -Encoding "ASCII" -Force
        } else {
            Write-OktaPamLog "Existing $($paths.YamlFile) found, leaving it unchanged"
        }

        if ($haveToken) {
            Write-OktaPamLog "Writing enrollment token"
            $EnrollmentToken | Out-File $paths.TokenFile -Encoding "ASCII" -Force
        }

        $msiPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.msi')
        $msiLog = [System.IO.Path]::ChangeExtension($msiPath, '.log')

        Get-URL-With-Authenticode -url $installerURL -output $msiPath

        # An error page saved in place of the MSI is far smaller than any real installer
        $msiSize = (Get-Item $msiPath).Length
        if ($msiSize -lt 1000000) {
            Remove-Item -Force $msiPath
            throw "Downloaded file is too small ($msiSize bytes) - may be an error page, not an MSI"
        }

        $stopped = Stop-ScaleFTService

        trap {
            if ($stopped -eq $true) {
                Start-ScaleFTService
            }
            break
        }

        Write-OktaPamLog "Starting msiexec on $($msiPath)"
        Write-OktaPamLog "MSI Log path: $($msiLog)"

        $status = Start-Process -FilePath msiexec -ArgumentList /i,$msiPath,/qn,/L*V!,$msiLog  -Wait -PassThru

        if ($status.ExitCode -ne 0) {
	        Start-ScaleFTService
            throw "msiexec failed with exit code: $($status.ExitCode) Log: $($msiLog)"
        }

        Write-OktaPamLog "Removing $($msiPath)"
        Remove-Item -Force $msiPath

        if (Test-Path $paths.SftdExe) {
            Write-OktaPamLog "Installation verified - sftd.exe found"
        } else {
            Write-OktaPamLog "sftd.exe not found at $($paths.SftdExe)" "WARNING"
        }

        Start-ScaleFTService | Out-Null

        if ($haveToken) {
            # Wait for the agent to consume enrollment.token and create device.token
            Write-OktaPamLog "Waiting for enrollment to complete..."
            if (Wait-OktaPamEnrollment -TimeoutSeconds $EnrollmentTimeoutSeconds) {
                Set-OktaPamEnrollmentFlag
                Write-OktaPamLog "Okta OPA enrollment completed successfully" "SUCCESS"
            } else {
                Write-OktaPamLog "Enrollment did not complete within $EnrollmentTimeoutSeconds seconds - enrollment.token was not consumed or device.token was not created" "ERROR"
                Write-OktaPamLog "The agent may still complete enrollment - check the agent logs. Log file: $($script:LogFile)" "ERROR"
            }
        } else {
            Write-OktaPamLog "Okta OPA agent installed successfully (without enrollment)" "SUCCESS"
        }
    }
}

<#
 .Synopsis
  Creates a scheduled task that runs Install-OktaPamServerTools.

 .Description
  Registers a task that runs as SYSTEM and imports this module to call Install-OktaPamServerTools.
  Because the install is idempotent, an already enrolled server is skipped, so the task is safe
  to run repeatedly. Add -Upgrade (or -ToolsVersion) to make each run upgrade an enrolled server.
  An existing task with the same name is replaced.

  The task definition stores -EnrollmentToken in plain text, readable by local administrators.
  Prefer a single-use token, or install and enroll once and schedule without a token.

 .Parameter TaskName
  Optional, name of the scheduled task. Defaults to OktaPAM-ServerTools.

 .Parameter Schedule
  When to run: AtStartup, Daily, Weekly or Repeat.

 .Parameter At
  Time of day to run for Daily and Weekly (for example "02:30"). For Repeat, the first run time;
  defaults to one minute from now.

 .Parameter DaysOfWeek
  Weekly only, days to run on. Defaults to Sunday.

 .Parameter DaysInterval
  Daily only, run every N days. Defaults to 1.

 .Parameter WeeksInterval
  Weekly only, run every N weeks. Defaults to 1.

 .Parameter RepeatEvery
  Repeat only, interval between runs, for example (New-TimeSpan -Hours 4).

 .Parameter EnrollmentToken
  Optional, passed to Install-OktaPamServerTools on each run.

 .Parameter ToolsVersion
  Optional, passed to Install-OktaPamServerTools on each run.

 .Parameter Upgrade
  Optional, passes -Upgrade to Install-OktaPamServerTools on each run.

 .Parameter VersionsBehind
  Optional, passes -VersionsBehind to Install-OktaPamServerTools on each run, so the server tracks
  the release N versions behind the latest.

 .Example
   # Keep the agent up to date: check every Sunday at 02:00
   Register-OktaPamScheduledTask -Schedule Weekly -DaysOfWeek Sunday -At 02:00 -Upgrade

 .Example
   # Stay one release behind the latest
   Register-OktaPamScheduledTask -Schedule Weekly -At 02:00 -Upgrade -VersionsBehind 1

 .Example
   Register-OktaPamScheduledTask -Schedule Repeat -RepeatEvery (New-TimeSpan -Hours 6)
#>
function Register-OktaPamScheduledTask(){
    param(
        [Parameter(Mandatory=$false)][string]$TaskName = "OktaPAM-ServerTools",
        [Parameter(Mandatory=$true)][ValidateSet("AtStartup","Daily","Weekly","Repeat")][string]$Schedule,
        [Parameter(Mandatory=$false)][datetime]$At,
        [Parameter(Mandatory=$false)][System.DayOfWeek[]]$DaysOfWeek = @([System.DayOfWeek]::Sunday),
        [Parameter(Mandatory=$false)][ValidateRange(1,365)][int]$DaysInterval = 1,
        [Parameter(Mandatory=$false)][ValidateRange(1,52)][int]$WeeksInterval = 1,
        [Parameter(Mandatory=$false)][timespan]$RepeatEvery,
        [Parameter(Mandatory=$false)][string]$EnrollmentToken,
        [Parameter(Mandatory=$false)][string]$ToolsVersion,
        [Parameter(Mandatory=$false)][switch]$Upgrade,
        [Parameter(Mandatory=$false)][ValidateRange(0,50)][int]$VersionsBehind
    )
    process{
        $ErrorActionPreference = "Stop";
        Assert-OktaPamAdministrator

        if ($PSBoundParameters.ContainsKey("ToolsVersion") -and $PSBoundParameters.ContainsKey("VersionsBehind")) {
            throw "-ToolsVersion and -VersionsBehind cannot be used together."
        }

        switch ($Schedule) {
            "Daily"  { if (-not $PSBoundParameters.ContainsKey("At")) { throw "-At is required for a Daily schedule." } }
            "Weekly" { if (-not $PSBoundParameters.ContainsKey("At")) { throw "-At is required for a Weekly schedule." } }
            "Repeat" { if (-not $PSBoundParameters.ContainsKey("RepeatEvery")) { throw "-RepeatEvery is required for a Repeat schedule." } }
        }

        switch ($Schedule) {
            "AtStartup" { $trigger = New-ScheduledTaskTrigger -AtStartup }
            "Daily"     { $trigger = New-ScheduledTaskTrigger -Daily -At $At -DaysInterval $DaysInterval }
            "Weekly"    { $trigger = New-ScheduledTaskTrigger -Weekly -At $At -DaysOfWeek $DaysOfWeek -WeeksInterval $WeeksInterval }
            "Repeat"    {
                $start = if ($PSBoundParameters.ContainsKey("At")) { $At } else { (Get-Date).AddMinutes(1) }
                $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval $RepeatEvery -RepetitionDuration ([timespan]::FromDays(3650))
            }
        }

        # Single quotes are doubled so values cannot break out of the quoted command
        $modulePath = $MyInvocation.MyCommand.Module.Path -replace "'", "''"
        $installArgs = ""
        if ($PSBoundParameters.ContainsKey("EnrollmentToken")) {
            $installArgs += " -EnrollmentToken '$($EnrollmentToken -replace "'", "''")'"
        }
        if ($PSBoundParameters.ContainsKey("ToolsVersion")) {
            $installArgs += " -ToolsVersion '$($ToolsVersion -replace "'", "''")'"
        }
        if ($Upgrade) {
            $installArgs += " -Upgrade"
        }
        if ($PSBoundParameters.ContainsKey("VersionsBehind")) {
            $installArgs += " -VersionsBehind $VersionsBehind"
        }
        $command = "Import-Module '$modulePath' -Force; Install-OktaPamServerTools$installArgs"

        $psExe = (Get-Process -Id $PID).Path
        $action = New-ScheduledTaskAction -Execute $psExe -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command `"$command`""
        # Always the local SYSTEM account (S-1-5-18), never a domain/AD account
        $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 1)

        Register-ScheduledTask -TaskName $TaskName -Trigger $trigger -Action $action -Principal $principal -Settings $settings -Force | Out-Null
        Write-OktaPamLog "Scheduled task '$TaskName' registered ($Schedule)"
        if ($PSBoundParameters.ContainsKey("EnrollmentToken")) {
            Write-OktaPamLog "The enrollment token is stored in plain text in the task definition" "WARNING"
        }
    }
}

<#
 .Synopsis
  Removes the scheduled task created by Register-OktaPamScheduledTask.
#>
function Unregister-OktaPamScheduledTask(){
    param(
        [Parameter(Mandatory=$false)][string]$TaskName = "OktaPAM-ServerTools"
    )
    process{
        $ErrorActionPreference = "Stop";
        Assert-OktaPamAdministrator
        if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
            Write-OktaPamLog "Scheduled task '$TaskName' removed"
        } else {
            Write-OktaPamLog "Scheduled task '$TaskName' not found" "WARNING"
        }
    }
}

Export-ModuleMember -function Install-OktaPamServerTools, Uninstall-OktaPamServerTools, Clear-OktaPamEnrollment, Test-OktaPamEnrollment, Register-OktaPamScheduledTask, Unregister-OktaPamScheduledTask
