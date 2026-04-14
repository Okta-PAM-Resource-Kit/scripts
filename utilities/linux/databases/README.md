# Linux OPA Database Setup Script

Automated installation and configuration of PostgreSQL or MySQL with OPA orchestrator integration. Supports database-scoped (default) or global user privileges.

**_These scripts are not supported by Okta, are experimental, and are not intended for production use. No warranty is expressed or implied. Please review and understand all scripts before using. Use at your own risk._**

## Quick Start

```bash
# Download
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/utilities/linux/databases/LinuxOpaDbSetup.sh
chmod +x LinuxOpaDbSetup.sh

# Install PostgreSQL, create database, scoped users (recommended for testing)
./LinuxOpaDbSetup.sh -p -D testdb -c -e

# Install MySQL, create database, scoped users
./LinuxOpaDbSetup.sh -m -D myapp_db -c -e

# Install PostgreSQL with global users (cluster-wide privileges)
./LinuxOpaDbSetup.sh -p -g -e
```

## Requirements

- Debian/Ubuntu (20.04+) or RHEL/Rocky/Alma/CentOS (8+)
- Root or sudo access
- Internet access for package installation

## Options

| Flag | Description |
|------|-------------|
| `-p` | Install and configure PostgreSQL |
| `-m` | Install and configure MySQL |
| `-D NAME` | Target database name (required by default) |
| `-c` | Create target database if it doesn't exist |
| `-e` | Create example users (app_admin, app_readwrite, app_readonly, report_user, backup_user) |
| `-l` | Database-scoped users (default) - limited to specific database |
| `-g` | Global-scope users - cluster-wide privileges, no -D required |
| `-s` | Grant SUPERUSER to orchestrator (password changes on all accounts) |
| `-d` | Detect database and exit |
| `-h` | Show help |

**Default:** Database-scoped mode (requires `-D`). Use `-g` for global mode.

## User Scope Modes

### Database-Scoped (Default, requires `-D`)
All users limited to specified database. Recommended for orchestrator testing.

**Orchestrator:** Database privileges only
- MySQL: No CREATE USER, RELOAD, or mysql.user access
- PostgreSQL: No SUPERUSER or CREATEROLE

**Example users:** Limited to target database
- MySQL: `GRANT ... ON dbname.*`
- PostgreSQL: `GRANT ... ON DATABASE dbname`

### Global Mode (`-g`)
All users have cluster-wide privileges.

**Orchestrator:** Cluster management privileges
- MySQL: CREATE USER, RELOAD, mysql.user access, role management
- PostgreSQL: SUPERUSER or CREATEROLE

**Example users:** Access to all databases
- MySQL: `GRANT ... ON *.*`
- PostgreSQL: Privileges on all databases

## Example Users

Created with `-e` flag. Privileges scoped based on mode:

1. **app_admin** - Full privileges (SUPERUSER in global mode, ALL PRIVILEGES ON DATABASE in scoped)
2. **app_readwrite** - Read/write access (SELECT, INSERT, UPDATE, DELETE)
3. **app_readonly** - Read-only access (SELECT)
4. **report_user** - Reporting access (SELECT, SHOW VIEW)
5. **backup_user** - Backup operations (REPLICATION in global mode, SELECT in scoped)

## Credentials

Passwords stored in `/root/postgresql-credentials.txt` or `/root/mysql-credentials.txt` (mode 600). Includes scope information. Existing files backed up automatically.

## What the Script Does

1. Detects Linux distribution and package manager
2. Installs database if not present (PostgreSQL or MySQL)
3. Configures remote access (`listen_addresses = '*'`, `bind-address = 0.0.0.0`)
4. Creates orchestrator account with scoped or global privileges
5. Creates optional example users
6. Generates and stores random passwords

**Idempotent:** Safe to re-run. Existing accounts preserved, privileges updated, passwords only set on creation.

## Troubleshooting

**"Database-scoped mode requires -D flag"** - Specify database with `-D dbname` or use `-g` for global mode

**"No database detected"** - Use `-p` or `-m` to install PostgreSQL or MySQL

**"Permission denied"** - Run with `sudo`

**Cannot connect remotely** - Open firewall ports (5432 for PostgreSQL, 3306 for MySQL):
```bash
# RHEL/Rocky/Alma
firewall-cmd --add-service=postgresql --permanent  # or --add-port=3306/tcp
firewall-cmd --reload
```

**Check service status:**
```bash
systemctl status postgresql  # or mysql/mysqld
```

## Security Notes

- Passwords generated with `openssl rand -base64`
- Credentials files restricted to root (mode 600)
- Remote access enabled by default - use firewall rules in production
- Database-scoped mode (default) follows principle of least privilege
- Use `-s` (SUPERUSER) only when required

---
**Author:** Shad Lutz  
**Related:** [Linux Universal OPA Install](../../../installation/linux/README.md) | [Linux AD Join](../ad_domain_join/README.md)
