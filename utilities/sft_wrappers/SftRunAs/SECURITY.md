# Security

This document describes the security model, assumptions, and operational guidance for `SftRunAs`.

---

## Threat model (high-level)

`SftRunAs` is designed to reduce the operational risk of privileged credentials by:

- Retrieving a privileged password **just in time** from Okta Privileged Access (OPA)
- Using that password only to create a **Windows logon token** for launching a specific tool
- Avoiding password persistence on disk

It is **not** intended to:

- Bypass UAC or local privilege boundaries
- Inject passwords into third-party tools on the command line
- Provide SSH password automation

---

## How credentials are handled

1. The user invokes `sft-runas <account> <tool>`
2. The module calls:
   - `sft login` (best-effort refresh)
   - `sft ad reveal --domain <fqdn> --ad-account <user>` (and `--team` if supplied)
3. The returned password is converted into a `SecureString` and used to create a `PSCredential`
4. The target tool is launched via:

```powershell
Start-Process -Credential $cred
```

5. The plaintext password and credential objects are set to `$null` and garbage collection is requested.

---

## Logging and telemetry

Recommended operational practice:

- Do **not** log the plaintext password
- Avoid verbose logging of process arguments unless required
- Capture:
  - User identity initiating the request
  - Tool preset / executable launched
  - Target host (for `remote-ps`)
  - OPA account identifier (username only)
  - Timestamp and outcome (success/failure)

OPA/Okta should provide authoritative audit logs for reveals and checkouts.

---

## Execution policy

This module can be run unsigned in permissive environments, but most enterprises should plan to adopt:

- **Signed module** distribution, or
- packaging via a trusted software deployment method (Intune/GPO/software center)

If endpoints enforce `AllSigned`, you will need code signing enabled and the publisher trusted.

---

## Recommendations

- Prefer short-lived privileged access and enforce OPA policies:
  - limited checkout windows
  - approvals where appropriate
  - MFA requirements
- Reduce endpoint exposure:
  - ensure RSAT is installed only for the admin population
  - disable local admin where not needed
- Prefer WinRM over ad-hoc remote tools when possible and enforce:
  - TLS/HTTPS (5986) if feasible
  - constrained endpoints / JEA for sensitive operations

---

## Known limitations

- The password exists in process memory briefly (inevitable given the requirements)
- Launching GUI tools via `Start-Process -Credential` may create additional user profile artifacts
  (e.g., HKCU settings under that identity) depending on the tool
- `remote-ps` uses WinRM and requires network/firewall/policy alignment

---

## Reporting vulnerabilities

For internal use, report issues via your organization’s security escalation process.
