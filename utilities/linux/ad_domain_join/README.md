# Linux Active Directory Join Script

Automated script to join Linux systems to an Active Directory domain with proper SSSD configuration.

## Overview

The `join-ad.sh` script automates the process of joining Linux systems to an Active Directory domain. It handles package installation, DNS verification, domain discovery, SSSD configuration, and SSH setup across multiple Linux distributions.

**_These scripts are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Supported Distributions

### Debian-based
- Ubuntu
- Debian
- Other Debian derivatives

### RPM-based
- RHEL (Red Hat Enterprise Linux)
- CentOS
- Rocky Linux
- AlmaLinux
- Fedora

## Prerequisites

1. **Root/sudo access** - Script requires sudo privileges
2. **DNS configuration** - System must be able to resolve the domain controller
   - For GCP: Configure Cloud DNS private zones or VPC DNS
   - For AWS: Use Route 53 Resolver or DHCP option sets
3. **Network connectivity** - Must be able to reach the domain controller
4. **Time synchronization** - System time must be synchronized (Kerberos requirement)
5. **AD account credentials** - Valid domain administrator or account with domain join privileges

## Download and Usage

```bash
curl -O "https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/refs/heads/main/utilities/linux/ad_domain_join/join-ad.sh"
chmod +x join-ad.sh
./join-ad.sh <domain_name> <ad_account_name>
```

### Example

```bash
./join-ad.sh example.com administrator
```

The script will securely prompt for the AD account password.

## What the Script Does

1. **Package Installation**
   - Installs required packages: `realmd`, `sssd`, `adcli`, `samba-common`, `oddjob`
   - Automatically detects package manager (apt-get, dnf, or yum)

2. **DNS Verification**
   - Validates that the domain controller can be resolved via DNS
   - Tests SRV record lookup for `_ldap._tcp.<domain>`
   - Exits with helpful error messages if DNS is misconfigured

3. **Time Sync Check**
   - Verifies that time synchronization is active
   - Warns if no sync service is detected (critical for Kerberos)

4. **Domain Discovery**
   - Uses `realm discover` to find domain information
   - Checks for existing domain membership

5. **Domain Join**
   - Joins the domain using the provided credentials
   - Uses `realm join` with secure password input

6. **SSSD Configuration**
   - Creates optimized `/etc/sssd/sssd.conf`
   - Configures:
     - Credential caching
     - Simplified usernames (no @domain suffix required)
     - Home directory auto-creation at `/home/<username>@<domain>`
     - Kerberos authentication
   - Sets proper file permissions (600)
   - Enables and restarts SSSD service

7. **PAM Configuration**
   - Enables automatic home directory creation on first login
   - Uses `pam-auth-update` (Debian) or `authselect`/`authconfig` (RPM)
   - Configures and enables `oddjobd` service

8. **SELinux Configuration** (RPM-based only)
   - Configures SELinux booleans if SELinux is enabled:
     - `use_nfs_home_dirs`
     - `oddjob_enable_homedirs`

9. **SSH Configuration**
   - Creates `/etc/ssh/sshd_config.d/05-OPA-settings.conf`
   - Enables password authentication for AD users
   - Restarts SSH service (handles both `sshd` and `ssh` service names)

10. **Verification**
    - Displays final domain join status
    - Provides instructions for testing

## Post-Join Configuration

### SSSD Settings Applied

```ini
[domain/<DOMAIN>]
default_shell = /bin/bash
cache_credentials = True
use_fully_qualified_names = False
fallback_homedir = /home/%u@%d
ldap_id_mapping = True
access_provider = ad
```

Key features:
- **Simplified usernames**: Login with `username` instead of `username@domain`
- **Credential caching**: Works offline with cached credentials
- **Auto home directory**: Created as `/home/username@domain`

## Testing the Join

After successful join, test AD authentication:

```bash
# Check if AD user is recognized
id <ad_username>

# Test login (if SSH is configured)
ssh <ad_username>@<hostname>

# View current realm status
realm list
```

## Troubleshooting

### DNS Resolution Fails

**Error:** `Cannot resolve domain controller for <domain>`

**Solution:**
- Verify DNS server configuration: `cat /etc/resolv.conf`
- Test manual lookup: `nslookup -type=srv _ldap._tcp.<domain>`
- Ensure the system is using the domain's DNS servers

### Time Synchronization Issues

**Warning:** `System time may not be synchronized`

**Solution:**
```bash
# Check time sync status
timedatectl status

# Enable time sync (if using systemd-timesyncd)
sudo timedatectl set-ntp true

# Or install/enable chrony or ntpd
```

### Already Joined to Another Domain

**Error:** `System is already joined to domain: <existing_domain>`

**Solution:**
```bash
# Leave the current domain first
sudo realm leave
```

### SSH Authentication Not Working

1. Verify SSSD is running: `sudo systemctl status sssd`
2. Check SSH configuration: `sudo sshd -T | grep -i password`
3. Review auth logs: `sudo journalctl -u ssh -f` or `sudo tail -f /var/log/auth.log`
4. Test user lookup: `getent passwd <username>`

## Files Modified

- `/etc/sssd/sssd.conf` (backup created as `sssd.conf.backup`)
- `/etc/ssh/sshd_config.d/05-OPA-settings.conf` (new file)
- PAM configuration files (via `pam-auth-update` or `authselect`)

## Security Considerations

- Password is read securely (hidden input) and not stored in shell history
- SSSD configuration file permissions set to 600 (root only)
- Credential caching allows offline authentication
- SELinux configurations follow security best practices

## Author

Shad Lutz

## License

Private/Internal Use
