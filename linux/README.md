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

```
LinuxAndBsdAsaInstall.sh [-s] [-S server_enrollment_token] [-g GATEWAY_TOKEN] [-c|-r [prod|test]] [-p] [-h] 
				-s                          Install ASA Server Tools without providing an enrollment token.
				-S server_enrollment_token  Install ASA Server Tools with the provided enrollment token.
			  	-f                          Force re-installation of existing packages.
				-g gateway_setup_token      Install ASA Gateway with the provided gateway token.
				-c                          Install ASA Client Tools.
				-r                          Set installation branch, default is prod.
			  	-p                          Skip detection of TLS inspection web proxy.
				-h                          Display this help message.
```

