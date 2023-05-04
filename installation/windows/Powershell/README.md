# OktaPAM-PowerShell: Tools for installing OktaPAM (ASA) ServerTools with PowerShell

**_These modules are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all modules before using.  Use at your own risk._**

## Available Functions

### `Install-OktaPamServerTools`

This function will download and install the OktaPAM Server Tools.  It can optionally set the enrollment token.  If the OktaPAM Server Tools are already installed, this function will upgrade them to the latest or specified version.

## Prerequisites

These modules are tested under PowerShell version 7

## Installation

1. Copy the entire module folder, OktaPAM.PS, into 'C:\Program Files (x86)\WindowsPowerShell\Modules'

```Powershell
mkdir 'C:\Program Files (x86)\WindowsPowerShell\Modules\OktaPAM.PS'
cd 'C:\Program Files (x86)\WindowsPowerShell\Modules\OktaPAM.PS'
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
Install-OktaPamServerTools [-ToolsVersion <version>] [-EnrollmentToken <enrollment_token>]
#    -ToolsVersion        Installs the specified version of the software (mininum 1.66.4)
#                         Version must be in the form of n.nn.n
#                         If ommitted, the lastest available version will be used
#    -EnrollmentToken     Creates an enrollment token file using the provided token value
#                         For upgrades, there is no need to provide an enrollment token.
```

## What's New

### 0.1.1

* Updated to use new repository structure as of 2023Q1.
* Removed support for non-stable release trains
* Removed support for custom instances

