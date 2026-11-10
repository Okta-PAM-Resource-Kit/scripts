# OktaPAM-PowerShell: Tools for installing OPA/ASA ServerTools with PowerShell

**_These modules are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all modules before using.  Use at your own risk._**

## Available Functions

### `Install-OktaPamServerTools`

This function will download and install the OktaPAM Server Tools.  It can optionally set the enrollment token.  If the OktaPAM Server Tools are already installed, this function will upgrade them to the latest or specified version.

## Prerequisites

These modules are tested under PowerShell version 7

## Installation

1. Copy the entire module folder, OktaPAM.PS, into 'C:\Program Files (x86)\WindowsPowerShell\Modules'

```Powershell
mkdir "C:\Program Files\WindowsPowerShell\Modules\OktaPAM.PS"
cd "C:\Program Files\WindowsPowerShell\Modules\OktaPAM.PS"
cmd /c "curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/windows/Powershell/OktaPAM.PS/OktaPAM.PS.psd1"
cmd /c "curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/windows/Powershell/OktaPAM.PS/OktaPAM.psm1"
```

2. Verify the module is available

```Powershell
Get-Module -ListAvailable
```

3. Once verified, import the module

```Powershell
Import-Module -Name OktaPAM.PS -Force
```

## Usage

**_Functions from this module must be run as administrator._**

``` Powershell
Install-OktaPamServerTools [-ToolsVersion <version>] [-EnrollmentToken <enrollment_token>] [-OverwriteConfig]
                           [-Reenroll] [-Reinstall] [-Upgrade] [-EnrollmentTimeoutSeconds <n>]
#    -ToolsVersion        Installs the specified version of the software (mininum 1.66.4)
#                         Version must be in the form of n.nn.n
#                         If ommitted, the lastest available version will be used
#    -EnrollmentToken     Creates an enrollment token file using the provided token value
#                         Without a token the agent is installed but not enrolled
#                         For upgrades, there is no need to provide an enrollment token.
#    -OverwriteConfig     Regenerates sftd.yaml even if one already exists
#    -Reenroll            Deletes the enrollment flag and state directory so the server enrolls again
#    -Reinstall           Uninstalls the agent first. Add -Reenroll to also clear enrollment data
#    -Upgrade             Upgrades an enrolled server (latest, or -ToolsVersion) and keeps enrollment
#    -VersionsBehind      Installs the release N versions behind the latest (0 = latest, 1 = previous)
#                         Implies -Upgrade; cannot be combined with -ToolsVersion
#    -EnrollmentTimeoutSeconds
#                         How long to wait for enrollment to finish (default 120)

Uninstall-OktaPamServerTools [-ClearEnrollment]
Clear-OktaPamEnrollment      # same as -Reenroll without installing
Test-OktaPamEnrollment       # $true when device.token exists and enrollment.token is gone

Register-OktaPamScheduledTask -Schedule <AtStartup|Daily|Weekly|Repeat> [-At <time>]
                              [-DaysOfWeek <days>] [-DaysInterval <n>] [-WeeksInterval <n>]
                              [-RepeatEvery <timespan>] [-TaskName <name>]
                              [-Upgrade] [-VersionsBehind <n>] [-ToolsVersion <version>]
                              [-EnrollmentToken <token>]
Unregister-OktaPamScheduledTask [-TaskName <name>]
```

Progress is logged to the console and to `C:\sftd_bootstrap.log`.

**Already-enrolled servers are skipped.** If the server is enrolled (`device.token` present,
`enrollment.token` absent) the install does nothing, so it is safe to run on every boot. To
upgrade an enrolled server, pass `-Upgrade` (or `-ToolsVersion`, which implies it), or use
`-Reinstall`. Running with no parameters on an enrolled server no longer upgrades.

An upgrade only happens when the installed agent is older than the target version. An agent
already at or above the target is left alone, so `-VersionsBehind` never downgrades.

### Scheduled task

`Register-OktaPamScheduledTask` creates a task that imports the module and runs
`Install-OktaPamServerTools`. It always runs as the local `NT AUTHORITY\SYSTEM` account,
not an AD account. An existing task with the same name is replaced.

The usual use is automating agent updates. Install and enroll the agent once, then schedule
`-Upgrade`:

```Powershell
# Check for a newer agent every Sunday at 02:00 and upgrade to the latest
Register-OktaPamScheduledTask -Schedule Weekly -DaysOfWeek Sunday -At 02:00 -Upgrade

# Stay one release behind the latest (use 2 for two behind, and so on)
Register-OktaPamScheduledTask -Schedule Weekly -DaysOfWeek Sunday -At 02:00 -Upgrade -VersionsBehind 1

# Pin to a specific version
Register-OktaPamScheduledTask -Schedule Weekly -DaysOfWeek Sunday -At 02:00 -ToolsVersion 1.75.2

# Check at every boot / every 6 hours instead
Register-OktaPamScheduledTask -Schedule AtStartup -Upgrade
Register-OktaPamScheduledTask -Schedule Repeat -RepeatEvery (New-TimeSpan -Hours 6) -Upgrade

# Remove the task
Unregister-OktaPamScheduledTask
```

A scheduled task can also install and enroll a new server by adding `-EnrollmentToken <token>`,
but the token is stored in plain text in the task definition. Prefer a single-use token, or
enroll once and schedule without one.

The function also writes `sftd.yaml` to the agent's config directory
(`C:\Windows\System32\config\systemprofile\AppData\Local\ScaleFT`) with the server's
hostname as `CanonicalName` and `BrokeredLoginGracePeriodInSeconds: 60`. An existing
`sftd.yaml` is left alone unless `-OverwriteConfig` is given.

## What's New

### 0.1.1

* Updated to use new repository structure as of 2023Q1.
* Removed support for non-stable release trains
* Removed support for custom instances

