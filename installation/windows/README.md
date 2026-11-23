# Okta OPA/ASA Installation and Diagnostic Scripts

**_These scripts are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Server Agent Installation

### Powershell Module

Refer to directions found in the Powershell folder

### Command Shell Script

This is a simple command shell script that installs, enrolls and upgrades the scaleft-server-tools.  It installs the latest version unless you pass `/version`.

Script usage:

```bash
cmd /c "curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/refs/heads/main/installation/windows/OPA-Windows-Server-Installer.cmd"
cmd /c "OPA-Windows-Server-Installer.cmd /token:<enrollment_token>"
```

Options:

| Option | Meaning |
| --- | --- |
| `/token:<token>` | Enroll the agent with this token. Without a token the agent is installed but not enrolled. |
| `/version:<x.y.z>` | Install a specific version instead of the latest. Implies `/upgrade` on an enrolled server. |
| `/upgrade` | Upgrade an already enrolled agent to the latest version (or `/version`) and keep its enrollment. Does nothing if the installed version is already at or above the target. |
| `/reenroll` | Delete `device.token` and the enrollment flag so the server enrolls again. |
| `/reinstall` | Uninstall the agent first, then install it again. |

To go back to an older version (a downgrade), use `/reinstall /version:<x.y.z>`.  `/upgrade` and `/version` alone never install a version older than the one already installed.

An enrolled server is skipped unless you pass `/upgrade`, `/version`, `/reenroll` or `/reinstall`, so the script is safe to run at every boot.

The downloaded MSI must have a valid Authenticode signature, and is checked against the size and SHA3-512 published in `dull.json`.  SHA3-512 needs PowerShell 7 on Windows 11 or Server 2025; elsewhere only the size is checked and a warning is logged.  An invalid signature, or a size or hash mismatch, stops the install.


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