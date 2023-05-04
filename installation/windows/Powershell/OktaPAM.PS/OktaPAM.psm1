<# 
 .Synopsis
  Installs the OktaPAM Server Toools

 .Description
  Installs the OktaPAM Server Tools to a specific version, and if installing for the first time
  will set the configuration file with various values.

 .Parameter ToolsVersion
  Optional, version of the OktaPAM Server Tools to Install. If not supplied, the latest available
  version is installed.

 .Parameter EnrollmentToken
  Optionally sets the OktaPAM Enrollment Token 

 .Example
   # Installs the OktaPAM Server Agent
   Install-OktaPAMServerTools -ToolsVersion 1.22.1
#>

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

function Stop-ScaleFTService(){
    $installed = [bool](Get-Service -ErrorAction SilentlyContinue | Where-Object Name -eq "scaleft-server-tools")
    if ($installed -eq $true) {
        echo "Stoping Service scaleft-server-tools"
        Stop-Service -Name "scaleft-server-tools"
        return $true
    }
    return $false
}

function Start-ScaleFTService(){
    $installed = [bool](Get-Service -ErrorAction SilentlyContinue | Where-Object Name -eq "scaleft-server-tools")
    if ($installed -eq $true) {
        echo "Starting Service scaleft-server-tools"
        Start-Service -Name "scaleft-server-tools"
        return $true
    }
    return $false
}



function Install-OktaPamServerTools(){
    param(
        [Parameter(Mandatory=$false)][string]$EnrollmentToken,
        [Parameter(Mandatory=$false)][string]$ToolsVersion
    )
    process{
        $ErrorActionPreference = "Stop";
        # Check that the function is being run as administator.
        if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Error "This command must be run as an administrator."
            return
        }
        $installBaseUrl = "https://dist.scaleft.com/repos/windows/stable/amd64/server-tools"
        $jsonUrl = "$($installBaseUrl)/dull.json"
        $jsonData = Invoke-RestMethod -Uri $jsonUrl
        $latestRelease = $jsonData.releases[0]
        $latestVersion = $latestRelease.version
        $latestInstallerLink = ($latestRelease.links | where { $_.rel -eq "installer" }).href
        
        if ($PSBoundParameters.ContainsKey("ToolsVersion")) {
            $installerURL = "$($installBaseUrl)/v$($ToolsVersion)/ScaleFT-Server-Tools-$($ToolsVersion).msi"
        } else {
            $installerURL = "$($installBaseUrl)/$($latestInstallerLink)"
        }

        # Select Local System User, where the ScaleFT Server Agent Runs
        $systemprofile = (Get-CIMInstance win32_userprofile  | where-object sid -eq "S-1-5-18" | select -ExpandProperty localpath)
        $stateDir = Join-Path $systemprofile -ChildPath 'AppData' | Join-Path -ChildPath "Local" | Join-Path -ChildPath "ScaleFT"
    
        if ($PSBoundParameters.ContainsKey("EnrollmentToken")) {
            $tokenPath = Join-Path $stateDir -ChildPath "enrollment.token"
            New-Item -ItemType directory -Path $stateDir -force
            $EnrollmentToken | Out-File $tokenPath -Encoding "ASCII" -Force
        }

        $msiPath = [System.IO.Path]::ChangeExtension([System.IO.Path]::GetTempFileName(), '.msi')
        $msiLog = [System.IO.Path]::ChangeExtension($msiPath, '.log')

        Get-URL-With-Authenticode -url $installerURL -output $msiPath

        $stopped = Stop-ScaleFTService

        trap {
            if ($stopped -eq $true) {
                Start-ScaleFTService
            }
            break
        }

        echo "Starting msiexec on $($msiPath)"
        echo "MSI Log path: $($msiLog)"

        $status = Start-Process -FilePath msiexec -ArgumentList /i,$msiPath,/qn,/L*V!,$msiLog  -Wait -PassThru

        if ($status.ExitCode -ne 0) {
	        Start-ScaleFTService
            throw "msiexec failed with exit code: $($status.ExitCode) Log: $($msiLog)"
        }

        echo "Removing $($msiPath)"
        Remove-Item -Force $msiPath

        Start-ScaleFTService
    }
}

Export-ModuleMember -function Install-OktaPamServerTools
