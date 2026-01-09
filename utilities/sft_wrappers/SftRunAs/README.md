# SftRunAs

**Run Windows administrative tools under a privileged Active Directory account, using credentials managed by Okta Privileged Access (OPA).**

`SftRunAs` provides a safe, repeatable way for users logged in with **non-admin Windows accounts** to launch administrative tools (ADUC, GPMC, DNS, etc.) using **just-in-time credentials** retrieved from Okta Privileged Access via the `sft` client.

No passwords are stored on disk. Credentials are retrieved at runtime, used to create a Windows logon token, and discarded.

---

## Key Features

- 🔐 **Just-in-time credentials** via Okta Privileged Access (`sft ad reveal`)
- 🪪 Launch tools with **real Windows logon tokens** (`Start-Process -Credential`)
- 🔄 Supports **NetBIOS (`DOMAIN\user`) or UPN (`user@domain`)** formats
- 🧰 Built-in **presets** for common admin tools (ADUC, GPMC, DNS, PKI, etc.)
- 🖥️ **Remote PowerShell (WinRM)** preset
- 🩺 Built-in **diagnostics** (`doctor`)
- 📋 Tool discovery via `list-tools`
- 📦 Delivered as a **PowerShell module**
- ❌ No SSH functionality (by design)

---

## Requirements

### Required

- Windows 10/11 **Pro, Enterprise, or Education**
- Okta Privileged Access client (`sft`) installed and enrolled
- Access to an OPA-managed **Active Directory account**
- PowerShell 5.1 or later (PowerShell 7+ supported)

### Optional

- RSAT (required for most AD-related tools)

---

## Installation

### Install the module

Copy the `SftRunAs` folder to one of the following locations:

**Per-user**

```
$HOME\Documents\PowerShell\Modules\SftRunAs
```

**All users**

```
C:\Program Files\PowerShell\Modules\SftRunAs
```

If the files were downloaded from the internet, unblock them:

```powershell
Get-ChildItem SftRunAs -Recurse | Unblock-File
```

Import the module:

```powershell
Import-Module SftRunAs
```

The command `sft-runas` will now be available.

---

## Installing RSAT (Required for AD / DNS / GPO Tools)

Many presets rely on **Remote Server Administration Tools (RSAT)**.

### Windows 10 / Windows 11 (1809+)

RSAT is installed via **Optional Features**.

#### Install via Settings (GUI)

1. Open **Settings**
2. Go to **Apps**
3. Select **Optional features**
4. Click **View features**
5. Search for **RSAT**
6. Install the components you need, commonly:
   - RSAT: AD DS and LDS Tools
   - RSAT: Group Policy Management Tools
   - RSAT: DNS Server Tools
   - RSAT: DHCP Server Tools
7. Restart if prompted

#### Install via PowerShell (run as Administrator)

```powershell
# List RSAT components
Get-WindowsCapability -Name RSAT* -Online

# Install common components
Get-WindowsCapability RSAT.ActiveDirectory* -Online | Add-WindowsCapability -Online
Get-WindowsCapability RSAT.GroupPolicy*     -Online | Add-WindowsCapability -Online
Get-WindowsCapability RSAT.Dns*             -Online | Add-WindowsCapability -Online
```

Verify installation:

```powershell
Get-WindowsCapability RSAT* -Online |
  Where-Object State -eq Installed
```

### Windows Server

```powershell
Install-WindowsFeature RSAT-AD-Tools
Install-WindowsFeature GPMC
```

---

## Usage

### List available tools

```powershell
sft-runas list-tools
```

### Launch Active Directory Users and Computers

```powershell
sft-runas CORP\adm-shad aduc
```

### Use UPN format

```powershell
sft-runas adm-shad@corp.example.com gpo
```

### Force NetBIOS formatting

```powershell
sft-runas adm-shad aduc -UseNetBios -NetBiosDomain CORP
```

### Remote PowerShell (WinRM)

```powershell
sft-runas CORP\adm-shad remote-ps SERVER01
```

### Custom executable with arguments

Use `--%` to stop PowerShell argument parsing:

```powershell
sft-runas CORP\adm-shad "C:\Windows\System32\cmd.exe" --% /c whoami /all
```

---

## Tool Presets

Built-in presets include:

- `aduc` – Active Directory Users and Computers
- `gpo` – Group Policy Management
- `dns` – DNS Manager
- `dhcp` – DHCP Manager
- `sites` – AD Sites and Services
- `domains` – AD Domains and Trusts
- `adsiedit` – ADSI Edit
- `certtmpl` – Certificate Templates
- `certsrv` – Certification Authority
- `pkiview` – Enterprise PKI
- `compmgmt` – Computer Management
- `eventvwr` – Event Viewer
- `services` – Services
- `taskschd` – Task Scheduler
- `diskmgmt` – Disk Management
- `wf` – Windows Firewall (Advanced)
- `regedit` – Registry Editor
- `control` – Control Panel
- `remote-ps` – Remote PowerShell (WinRM)

Run `sft-runas list-tools` for the authoritative list.

---

## Diagnostics

### Basic environment check

```powershell
sft-runas doctor
```

### Check remote PowerShell readiness

```powershell
sft-runas doctor -ComputerName SERVER01
```

The `doctor` command checks:

- `sft` availability
- Domain join hints
- MMC presence
- Preset count
- DNS resolution
- WinRM ports (5985/5986)

---

## Security Model

- Passwords are retrieved **on demand** from Okta Privileged Access
- Passwords:
  - Are never written to disk
  - Are not logged
  - Exist in memory only briefly
- Tools are launched using:

  ```powershell
  Start-Process -Credential
  ```

  which creates a **real Windows logon session**

- UAC is not bypassed
- No credential caching or `runas /savecred`

This aligns with:

- Just-in-time access
- Auditability
- Least privilege

For more details, see [SECURITY.md](SECURITY.md).

---

## Limitations / Non-Goals

- ❌ No SSH support
- ❌ No password injection into network tools
- ❌ No local privilege escalation beyond Windows rules
- ❌ Does not install RSAT automatically

---

## Troubleshooting

### RSAT tools fail to launch

- Ensure RSAT is installed
- Restart after installation
- Run `sft-runas doctor`

### `sft` command not found

- Install and enroll Okta Privileged Access client
- Ensure `sft` is in `PATH`

### Authentication prompts

- First use may require interactive `sft login`
- Ensure the AD account is authorized in OPA

---

## Versioning

- Module version follows **semantic versioning**
- The module GUID must never change once published

See [CHANGELOG.md](CHANGELOG.md).

---

## License / Internal Use

This module is intended for **internal enterprise use**.  
Review and adapt security practices as required by your organization.

---

## Future Enhancements (Not Implemented)

- SSH remoting
- OPA checkout enforcement
- Module signing
- Central logging hooks
- Intune / GPO deployment packaging
