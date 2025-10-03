# Okta OPA/ASA Installation and Diagnostic Scripts

**_These scripts are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Server Agent Installation

### Powershell Module

Refer to directions found in the Powershell folder

### Command Shell Script

This is a simple command shell script that will install a specific version of the scaleft-server-tools.  Update the script with latest version before executing.

Script usage:

```bash
cmd /c "curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/refs/heads/main/installation/windows/Okta-OPA-server-Windows.cmd"
```

Update the script with the target version, then execute with:

```bash
Okta-OPA-server-Windows.cmd
```


## Client ssh config update

This script updates the user's local .ssh/config file with a match clause that uses openssh proxycommand to invoke sft automatically.  This allows a user to connect to a server without calling sft directly:  

ssh <target_host>

This means that any app that uses SSH for transport should work natively.  For example, to SCP a file from a remote host to the current folder:

scp <target_host>:<target_file> .

Script usage:

```bash
cmd /c "curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/refs/heads/main/installation/windows/set-ssh-config.cmd"
cmd /c "set-ssh-config.cmd"
```