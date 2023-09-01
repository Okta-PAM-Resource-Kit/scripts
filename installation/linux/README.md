# Universal Linux and BSD Installation Script

## Overview

LinuxAndBsdAsaInstall.sh is intended to function as a universal install script for support Linux and BSD versions of the ASA Server Tools, ASA Gateway and RDP session Transcoder, and ASA Client Tools.  

**_These scripts are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Capabilities

At a high level, the script will:

* Add the ASA repos to the local package manager when possible, allowing easy updates using standard tools
* Test for the presence of TLS inspection (MITM) which would interfere with outbound calls to Okta
* Extract a useful server name from the "Name" tag in AWS.  (_Allow tags in instance metadata_ must be enabled.)
* Create default configuration files for ASA Server Tools and ASA Gateway
* Create enrollment token file for ASA Server Tools
* Create setup token file for ASA Gateway
* And finally, install ASA Server Tools, ASA Gateway (and Transcoder on RDP capable OSes), ASA Client Tools, or any combination of the three.

## Usage

This script can be run interactively from the command line using arguments, or parameters can be set within the script for simple, automated execution.

**_This script requires bash, awk, curl, and openssl to run successfully._**

```bash
LinuxAndBsdAsaInstall.sh [-a] [-s] [-S server_enrollment_token] [-g GATEWAY_TOKEN] [-c|-r [prod|test]] [-p] [-h] 
    -s                          Install ASA Server Tools without providing an enrollment token.
    -S server_enrollment_token  Install ASA Server Tools with the provided enrollment token.
    -a                          Set OPA created users to full sudo access by default.
    -f                          Force re-installation of existing packages.
    -g                          Install ASA Gateway assuming device or setup tokens already exist.
    -G gateway_setup_token      Install ASA Gateway with the provided gateway token.
    -c                          Install ASA Client Tools.
    -r                          Set installation branch, default is prod.
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
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdAsaInstall.sh
chmod +x LinuxAndBsdAsaInstall.sh
./LinuxAndBsdAsaInstall.sh -S enrollment_token
```

### Server and Client Agent Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdAsaInstall.sh
chmod +x LinuxAndBsdAsaInstall.sh
./LinuxAndBsdAsaInstall.sh -S enrollment_token -c
```

### Gateway Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdAsaInstall.sh
chmod +x LinuxAndBsdAsaInstall.sh
./LinuxAndBsdAsaInstall.sh -G setup_token
```

### Server Agent and Gateway Installation

```bash
#!/usr/bin/env bash
#Download, make executable, and launch install script with desired options.
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/installation/linux/LinuxAndBsdAsaInstall.sh
chmod +x LinuxAndBsdAsaInstall.sh
./LinuxAndBsdAsaInstall.sh -S enrollment_token -g setup_token
```
