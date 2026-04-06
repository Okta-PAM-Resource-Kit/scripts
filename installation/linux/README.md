# Universal Linux and BSD Installation Script

## Overview

LinuxAndBsdOPAInstall.sh is intended to function as a universal install script for support Linux and BSD versions of the OPA Server Tools, OPA Gateway and RDP session Transcoder, and OPA Client Tools.  

**_These scripts are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Capabilities

At a high level, the script will:

* Add the OPA repos to the local package manager when possible, allowing easy updates using standard tools
* Test for the presence of TLS inspection (MITM) which would interfere with outbound calls to Okta
* Extract a useful server name from the "Name" tag in AWS.  (_Allow tags in instance metadata_ must be enabled.)
* Create default configuration files for OPA Server Tools and OPA Gateway
* Protect existing configuration files from being overwritten (unless force flags are used)
* Support Infrastructure Orchestrator gateway configuration
* Create enrollment token file for OPA Server Tools
* Create setup token file for OPA Gateway
* Enable SSH password authentication (optional)
* Create test users with or without sudo privileges (optional)
* And finally, install OPA Server Tools, OPA Gateway (and Transcoder on RDP capable OSes), OPA Client Tools, or any combination of the three.

## Usage

This script can be run interactively from the command line using arguments, or parameters can be set within the script for simple, automated execution.

**_This script requires bash, awk, curl, and openssl to run successfully._**

```bash
LinuxAndBsdOPAInstall.sh [options]
    -a                          Create agent lifecycle hooks to grant sudo to all sftd created users.
    -s                          Install OPA Server Tools without providing an enrollment token.
    -S server_enrollment_token  Install OPA Server Tools with the provided enrollment token.
    -f                          Force re-installation of existing packages.
    -F                          Force overwrite of server config (/etc/sft/sftd.yaml) if it exists.
    -g                          Install OPA Gateway without providing a gateway setup token.
    -G gateway_setup_token      Install OPA Gateway with the provided gateway token.
    -W                          Force overwrite of gateway config (/etc/sft/sft-gatewayd.yaml) if it exists.
    -O                          Create an Infrastructure Orchestrator gateway config (implies -g).
    -c                          Install OPA Client Tools.
    -r                          Set installation branch, default is prod.
    -E                          Enable password authentication for SSH.
    -U username                 Create a test user with sudo privileges.
    -u username                 Create a test user without sudo privileges.
    -p                          Skip detection of TLS inspection web proxy.
    -h                          Display this help message.
```

## Tested Operating Systems

* Ubuntu 18.04, 20.04, 22.04
* Debian 9, 10, 11
* Redhat 7, 8
* CentOS 7, 8
* Rocky Linux 8
* AmazonLinux 2, 2022
* SLES 12, 15
* OpenSuse 15
* Fedora 35
* FreeBSD 12, 13

## Automation

To automate installation using AWS EC2 User Data, GCP startup-script, or orchestration, you can create a simple launcher for your specific use case.  In the server installation example below, the launcher downloads the installation script, then invokes it with the desired enrollment token.  

**_It is highly recommended to store your own copy of the installation script and reference in the launcher script below._**

### Server Agent Installation Only

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdOPAInstall.sh
chmod +x LinuxAndBsdOPAInstall.sh
./LinuxAndBsdOPAInstall.sh -S enrollment_token
```

### Server and Client Agent Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdOPAInstall.sh
chmod +x LinuxAndBsdOPAInstall.sh
./LinuxAndBsdOPAInstall.sh -S enrollment_token -c
```

### Gateway Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdOPAInstall.sh
chmod +x LinuxAndBsdOPAInstall.sh
./LinuxAndBsdOPAInstall.sh -G setup_token
```

### Server Agent and Gateway Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdOPAInstall.sh
chmod +x LinuxAndBsdOPAInstall.sh
./LinuxAndBsdOPAInstall.sh -S enrollment_token -G setup_token
```

### Infrastructure Orchestrator Gateway Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdOPAInstall.sh
chmod +x LinuxAndBsdOPAInstall.sh
./LinuxAndBsdOPAInstall.sh -O -G setup_token
```
