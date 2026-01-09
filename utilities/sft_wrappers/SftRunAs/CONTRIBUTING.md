# Contributing

This repository is intended for internal use.

---

## Local development

1. Clone the repo and open a PowerShell session.
2. Import the module from the working directory:

```powershell
Import-Module .\SftRunAs\SftRunAs.psd1 -Force
```

3. Run a quick check:

```powershell
sft-runas list-tools
sft-runas doctor
```

---

## Style and safety

- Do not log or print OPA passwords.
- Do not add features that inject passwords into third-party processes unless reviewed.
- Prefer passing arguments as arrays to `Start-Process -ArgumentList` to avoid quoting bugs.

---

## Releasing

- Update `ModuleVersion` in `SftRunAs.psd1`
- Update `CHANGELOG.md`
- Tag the release in your source control system
