# Linux OPA Database Setup Script

## Overview

`LinuxOpaDbSetup.sh` is a unified installation and configuration script for PostgreSQL and MySQL databases with Okta Privileged Access (OPA) orchestrator integration. The script automates database installation, network configuration, and user account creation with appropriate privileges.

**_These scripts are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Key Features

- **Multi-distribution support**: Works on Debian/Ubuntu (apt) and RHEL/CentOS/Rocky/Alma Linux (yum/dnf)
- **Auto-detection**: Automatically detects installed database (PostgreSQL or MySQL/MariaDB)
- **Flexible installation**: Explicit database selection with `-p` (PostgreSQL) or `-m` (MySQL)
- **Orchestrator account**: Creates `orchestrator_integration_user` with configurable privileges
- **Example users**: Optional creation of 5 example user accounts with different privilege levels
- **Idempotent design**: Safely re-run without recreating existing accounts
- **Secure credentials**: Generates random passwords and stores them in `/root/`
- **Network ready**: Configures databases to accept remote connections

## Supported Operating Systems

### Debian-based
- Ubuntu 20.04, 22.04, 24.04
- Debian 10, 11, 12

### RPM-based
- RHEL 8, 9
- CentOS 8, 9 (Stream)
- Rocky Linux 8, 9
- AlmaLinux 8, 9
- Oracle Linux 8, 9
- Fedora (recent versions)

## Prerequisites

- Supported Linux distribution (see above)
- Root or sudo access
- `openssl` for password generation
- Internet access for package installation
- `systemd` for service management

## Usage

```bash
./LinuxOpaDbSetup.sh [OPTIONS]
```

### Options

| Flag | Description |
|------|-------------|
| `-p` | Install and configure PostgreSQL |
| `-m` | Install and configure MySQL |
| `-s` | Grant SUPERUSER/SYSTEM_USER to orchestrator (allows password changes on all accounts) |
| `-e` | Create example user accounts (app_admin, app_readwrite, app_readonly, report_user, backup_user) |
| `-d` | Detect installed database without setup |
| `-h` | Show help message |

**Note:** If no database option (`-p` or `-m`) is specified, the script will auto-detect the installed database.

## Examples

### Auto-detect and configure orchestrator only
```bash
./LinuxOpaDbSetup.sh
```

### Install PostgreSQL with orchestrator (default privileges)
```bash
./LinuxOpaDbSetup.sh -p
```

### Install PostgreSQL with orchestrator as superuser
```bash
./LinuxOpaDbSetup.sh -p -s
```

### Install PostgreSQL with orchestrator and example users
```bash
./LinuxOpaDbSetup.sh -p -e
```

### Install PostgreSQL with orchestrator (superuser) and example users
```bash
./LinuxOpaDbSetup.sh -p -s -e
```

### Install MySQL with orchestrator only
```bash
./LinuxOpaDbSetup.sh -m
```

### Detect installed database
```bash
./LinuxOpaDbSetup.sh -d
```

## User Accounts Created

### Orchestrator Account

**Username:** `orchestrator_integration_user`

**Default Privileges (without `-s` flag):**
- **PostgreSQL:** `CREATEROLE` - Can change passwords for non-superuser accounts only
- **MySQL:** Limited privileges - Can create users and manage target database

**Superuser Privileges (with `-s` flag):**
- **PostgreSQL:** `SUPERUSER` - Can change all passwords including superusers
- **MySQL:** `SYSTEM_USER` - Can perform admin actions on all accounts

### Example User Accounts (with `-e` flag)

1. **app_admin**
   - PostgreSQL: `CREATEDB`, `SUPERUSER`
   - MySQL: `ALL PRIVILEGES ON *.*`
   - Purpose: Full administrative privileges

2. **app_readwrite**
   - PostgreSQL: `ALL PRIVILEGES ON DATABASE postgres`
   - MySQL: `SELECT, INSERT, UPDATE, DELETE ON *.*`
   - Purpose: Read and write access for application use

3. **app_readonly**
   - PostgreSQL: `CONNECT ON DATABASE postgres`
   - MySQL: `SELECT ON *.*`
   - Purpose: Read-only access for applications

4. **report_user**
   - PostgreSQL: `CONNECT ON DATABASE postgres`
   - MySQL: `SELECT, SHOW VIEW ON *.*`
   - Purpose: Reporting and analytics access

5. **backup_user**
   - PostgreSQL: `REPLICATION`
   - MySQL: `SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.*`
   - Purpose: Database backup operations

## Network Configuration

The script automatically configures databases to accept remote connections:

### PostgreSQL
- Sets `listen_addresses = '*'` in `postgresql.conf`
- Adds `host all all 0.0.0.0/0 md5` to `pg_hba.conf`

### MySQL
- Sets `bind-address = 0.0.0.0` in `mysqld.cnf`

**Security Note:** These settings allow connections from any IP address. In production environments, restrict access using firewall rules or modify the configuration to allow only specific IP ranges.

## Credentials Storage

Generated passwords are stored in:
- PostgreSQL: `/root/postgresql-credentials.txt`
- MySQL: `/root/mysql-credentials.txt`

File permissions are set to `600` (owner read/write only). Existing credential files are automatically backed up with a timestamp before being overwritten.

## Idempotent Behavior

The script is designed to be re-run safely:
- Existing accounts are preserved
- Privileges are updated if the `-s` flag changes
- Passwords are only set during account creation
- Credential files are backed up before updates
- Only displays new credentials when new accounts are created

## What the Script Does

1. **Distribution Detection**
   - Automatically detects Linux distribution (Debian/Ubuntu vs RHEL/CentOS/Rocky/Alma)
   - Selects appropriate package manager (apt, yum, or dnf)
   - Adapts configuration paths based on distribution

2. **Database Installation** (if not already installed)
   - **Debian/Ubuntu**: Installs using `apt-get`, service name `mysql`/`postgresql`
   - **RHEL/CentOS/Rocky/Alma**: Installs using `yum`/`dnf`, runs PostgreSQL `initdb` if needed
   - Configures for remote access with distribution-specific config paths

3. **Orchestrator Account Setup**
   - Creates or updates `orchestrator_integration_user`
   - Grants appropriate privileges based on `-s` flag
   - Sets secure random password on creation

4. **Example Users** (if `-e` flag is used)
   - Creates 5 example accounts with different privilege levels
   - Assigns unique random passwords
   - Configures appropriate database permissions

5. **Credential Management**
   - Generates secure random passwords
   - Saves credentials to `/root/` with restricted permissions
   - Backs up existing credential files

## Distribution-Specific Details

### PostgreSQL
- **Debian/Ubuntu**: Config in `/etc/postgresql/[version]/main/`
- **RHEL/Rocky/Alma**: Config in `/var/lib/pgsql/data/` or `/var/lib/pgsql/[version]/data/`
- **RPM systems**: Requires database initialization on first install

### MySQL
- **Debian/Ubuntu**: Service name `mysql`, config in `/etc/mysql/mysql.conf.d/mysqld.cnf`
- **RHEL/Rocky/Alma**: Service name `mysqld`, config in `/etc/my.cnf.d/mysql-server.cnf`

## Troubleshooting

### Script exits with "No database detected"
- Install PostgreSQL or MySQL first, or use `-p` or `-m` flag to install

### Permission denied errors
- Run with `sudo` or as root user

### Unsupported distribution error
- Ensure you're running on a supported Debian or RPM-based distribution
- Check `/etc/os-release` for distribution information

### Service not active
**Debian/Ubuntu:**
- PostgreSQL: `systemctl status postgresql`
- MySQL: `systemctl status mysql`

**RHEL/Rocky/Alma:**
- PostgreSQL: `systemctl status postgresql`
- MySQL: `systemctl status mysqld`

### Cannot connect remotely
- Verify firewall rules allow database ports (5432 for PostgreSQL, 3306 for MySQL)
- **RPM-based systems**: Configure firewall with `firewall-cmd --add-service=postgresql --permanent` or `firewall-cmd --add-port=3306/tcp --permanent`
- Check database configuration files for network settings (paths vary by distribution)

## Security Considerations

- Generated passwords use `openssl rand -base64` for cryptographic randomness
- Credential files are restricted to root access only (mode 600)
- Default orchestrator privileges follow principle of least privilege
- Use `-s` flag only when full superuser access is required
- Remote access is enabled by default - secure with firewall rules in production

## Download and Run

```bash
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/utilities/linux/databases/LinuxOpaDbSetup.sh
chmod +x LinuxOpaDbSetup.sh
./LinuxOpaDbSetup.sh -p -e  # Example: PostgreSQL with example users
```

## Author

Shad Lutz

## Related Scripts

- [Linux Universal OPA Install](../../../installation/linux/README.md) - Agent installation
- [Linux AD Join](../ad_domain_join/README.md) - Active Directory integration
