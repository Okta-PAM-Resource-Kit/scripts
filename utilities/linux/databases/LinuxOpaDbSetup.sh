#!/usr/bin/env bash
set -e

# LinuxOpaDbSetup.sh - Unified PostgreSQL and MySQL setup script
# Supports auto-detection or explicit database selection
# Supports Debian/Ubuntu (apt) and RHEL/CentOS/Rocky/Alma (yum/dnf)
# Automatically detects database version and applies version-specific permissions

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Setup PostgreSQL or MySQL with OPA orchestrator account.
The script will use sudo for privileged operations as needed.

Supported distributions:
  - Debian/Ubuntu (apt-get)
  - RHEL/CentOS/Rocky/Alma Linux (yum/dnf)

OPTIONS:
    -p                    Install and configure PostgreSQL
    -m                    Install and configure MySQL
    -s                    Grant SUPERUSER to orchestrator (allows password changes on all accounts)
                          Default: orchestrator can only change non-superuser passwords
    -e                    Create example user accounts (app_admin, app_readwrite, app_readonly, report_user, backup_user)
    -d                    Detect installed database and version without setup
    -h                    Show this help message

If no database option (-p/-m) is specified, the script will auto-detect the installed database.

Version Detection:
The script automatically detects the database version and applies appropriate permissions:
  - PostgreSQL 16+: Requires ADMIN OPTION for password changes with CREATEROLE
  - PostgreSQL <16: CREATEROLE can change non-superuser passwords directly
  - MySQL 8.0+: Uses SYSTEM_USER and role management features
  - MySQL 5.x: Uses SUPER privilege and legacy permission model

Examples:
    $0 -p                # Install PostgreSQL with orchestrator only (default privileges)
    $0 -p -s             # Install PostgreSQL with orchestrator as superuser
    $0 -p -e             # Install PostgreSQL with orchestrator and example users
    $0 -p -s -e          # Install PostgreSQL with orchestrator (superuser) and example users
    $0 -m                # Install MySQL with orchestrator only
    $0                   # Auto-detect and configure orchestrator only
EOF
    exit 1
}

# Detect Linux distribution type
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ -f /etc/redhat-release ]]; then
        echo "rhel"
    elif [[ -f /etc/debian_version ]]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

# Detect package manager
detect_package_manager() {
    local distro=$(detect_distro)

    case "$distro" in
        ubuntu|debian)
            echo "apt"
            ;;
        rhel|centos|rocky|almalinux|fedora|ol)
            if command -v dnf >/dev/null 2>&1; then
                echo "dnf"
            else
                echo "yum"
            fi
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Detect which database is installed
detect_database() {
    local detected=""

    # Check PostgreSQL
    if command -v psql >/dev/null 2>&1; then
        if systemctl is-active --quiet postgresql 2>/dev/null || \
           systemctl is-active --quiet postgresql-*.service 2>/dev/null; then
            detected="postgres"
        fi
    fi

    # Check MySQL/MariaDB
    if [[ -z "$detected" ]] && command -v mysql >/dev/null 2>&1; then
        if systemctl is-active --quiet mysql 2>/dev/null || \
           systemctl is-active --quiet mysqld 2>/dev/null || \
           systemctl is-active --quiet mariadb 2>/dev/null; then
            detected="mysql"
        fi
    fi

    echo "$detected"
}

# Detect PostgreSQL version
detect_postgres_version() {
    local version_string=""
    local major_version=""

    if command -v psql >/dev/null 2>&1; then
        # Get version from psql command
        version_string=$(psql --version 2>/dev/null | head -1)
        if [[ $version_string =~ ([0-9]+)\.([0-9]+) ]]; then
            major_version="${BASH_REMATCH[1]}"
        elif [[ $version_string =~ ([0-9]+)[[:space:]] ]]; then
            # PostgreSQL 10+ uses single number versioning
            major_version="${BASH_REMATCH[1]}"
        fi
    fi

    echo "$major_version"
}

# Detect MySQL version
detect_mysql_version() {
    local version_string=""
    local major_version=""
    local minor_version=""

    if command -v mysql >/dev/null 2>&1; then
        # Get version from mysql command
        version_string=$(mysql --version 2>/dev/null)
        if [[ $version_string =~ ([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
            major_version="${BASH_REMATCH[1]}"
            minor_version="${BASH_REMATCH[2]}"
        fi
    fi

    # Return as major.minor for easier comparison
    if [[ -n "$major_version" ]]; then
        echo "${major_version}.${minor_version}"
    fi
}

# Compare version numbers (returns 0 if v1 >= v2, 1 otherwise)
version_ge() {
    local v1=$1
    local v2=$2

    # Handle empty versions
    [[ -z "$v1" ]] && return 1
    [[ -z "$v2" ]] && return 0

    # Compare versions
    if [[ $(echo -e "$v1\n$v2" | sort -V | head -n1) == "$v2" ]]; then
        return 0
    else
        return 1
    fi
}

# Generate random passwords (shared function)
generate_passwords() {
    ADMIN_PASS=$(openssl rand -base64 16)
    ORCH_PASS=$(openssl rand -base64 16)
    USER1_PASS=$(openssl rand -base64 12)
    USER2_PASS=$(openssl rand -base64 12)
    USER3_PASS=$(openssl rand -base64 12)
    USER4_PASS=$(openssl rand -base64 12)
    USER5_PASS=$(openssl rand -base64 12)
}

# Install and configure MySQL
install_mysql() {
    local pkg_mgr=$(detect_package_manager)
    echo "Installing MySQL (using $pkg_mgr)..."

    case "$pkg_mgr" in
        apt)
            sudo apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server
            local config_file="/etc/mysql/mysql.conf.d/mysqld.cnf"
            local service_name="mysql"
            ;;
        dnf|yum)
            sudo $pkg_mgr install -y mysql-server
            local config_file="/etc/my.cnf.d/mysql-server.cnf"
            local service_name="mysqld"

            # Enable and start service
            sudo systemctl enable $service_name
            sudo systemctl start $service_name
            ;;
        *)
            echo "ERROR: Unsupported package manager: $pkg_mgr"
            exit 1
            ;;
    esac

    # Configure MySQL to listen on all interfaces
    if [[ -f "$config_file" ]]; then
        if grep -q "^bind-address" "$config_file"; then
            sudo sed -i "s/^bind-address.*/bind-address = 0.0.0.0/" "$config_file"
        else
            echo "bind-address = 0.0.0.0" | sudo tee -a "$config_file" >/dev/null
        fi
    else
        echo "[mysqld]" | sudo tee "$config_file" >/dev/null
        echo "bind-address = 0.0.0.0" | sudo tee -a "$config_file" >/dev/null
    fi

    sudo systemctl restart $service_name
    echo "MySQL installation and configuration complete."
}

# Install and configure PostgreSQL
install_postgres() {
    local pkg_mgr=$(detect_package_manager)
    echo "Installing PostgreSQL (using $pkg_mgr)..."

    case "$pkg_mgr" in
        apt)
            sudo apt-get update
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib

            # Find PostgreSQL version directory
            local pg_version=$(ls /etc/postgresql/ | sort -V | tail -1)
            local config_dir="/etc/postgresql/$pg_version/main"
            local service_name="postgresql"
            ;;
        dnf|yum)
            sudo $pkg_mgr install -y postgresql-server postgresql-contrib

            # Initialize database if not already initialized
            if [[ ! -d /var/lib/pgsql/data/base ]]; then
                echo "Initializing PostgreSQL database..."
                sudo postgresql-setup --initdb || sudo /usr/bin/postgresql-setup initdb
            fi

            # Find config directory
            local pg_version=$(psql --version | awk '{print $3}' | cut -d. -f1)
            if [[ -d "/var/lib/pgsql/$pg_version/data" ]]; then
                local config_dir="/var/lib/pgsql/$pg_version/data"
            else
                local config_dir="/var/lib/pgsql/data"
            fi
            local service_name="postgresql"

            # Enable and start service
            sudo systemctl enable $service_name
            sudo systemctl start $service_name
            ;;
        *)
            echo "ERROR: Unsupported package manager: $pkg_mgr"
            exit 1
            ;;
    esac

    echo "Configuring PostgreSQL to listen on all interfaces..."

    # Configure listen_addresses
    local conf_file="$config_dir/postgresql.conf"
    if sudo grep -q "^listen_addresses" "$conf_file"; then
        sudo sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$conf_file"
    else
        echo "listen_addresses = '*'" | sudo tee -a "$conf_file" >/dev/null
    fi

    # Configure pg_hba.conf for remote access
    local hba_file="$config_dir/pg_hba.conf"
    if ! sudo grep -q "0.0.0.0/0" "$hba_file"; then
        echo "host    all             all             0.0.0.0/0               md5" | sudo tee -a "$hba_file" >/dev/null
    fi

    sudo systemctl restart $service_name
    echo "PostgreSQL installation and configuration complete."
}

# Create MySQL users
create_mysql_users() {
    local orch_superuser=$1
    local create_examples=$2
    echo "Creating MySQL users..."
    local new_users=false

    # Detect MySQL version
    local mysql_version=$(detect_mysql_version)
    echo "Detected MySQL version: ${mysql_version:-unknown}"

    # Determine orchestrator privileges based on flag and version
    local supports_system_user=false
    if version_ge "$mysql_version" "8.0"; then
        supports_system_user=true
    fi

    if [[ "$orch_superuser" == "true" ]]; then
        if [[ "$supports_system_user" == "true" ]]; then
            echo "Granting SYSTEM_USER to orchestrator (MySQL 8.0+: can perform admin actions on all accounts)"
        else
            echo "Granting SUPER to orchestrator (MySQL 5.x: elevated privileges)"
        fi
    else
        echo "Granting limited privileges to orchestrator (can create users and manage target database)"
    fi

    # Handle orchestrator_integration_user - always update privileges, set password only on creation
    local orch_exists=$(sudo mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'orchestrator_integration_user' AND host = '%')")

    if [[ "$orch_exists" == "1" ]]; then
        echo "orchestrator_integration_user exists, updating privileges only..."
    else
        echo "Creating orchestrator_integration_user..."
        new_users=true
        sudo mysql -u root <<SQL
CREATE USER 'orchestrator_integration_user'@'%' IDENTIFIED BY '$ORCH_PASS';
SQL
    fi

    # Grant/update orchestrator privileges based on version
    if [[ "$orch_superuser" == "true" ]]; then
        if [[ "$supports_system_user" == "true" ]]; then
            # MySQL 8.0.16+ supports SYSTEM_USER privilege
            sudo mysql -u root <<SQL
GRANT SYSTEM_USER ON *.* TO 'orchestrator_integration_user'@'%';
SQL
        else
            # MySQL 5.x uses SUPER privilege for elevated access
            sudo mysql -u root <<SQL
GRANT SUPER ON *.* TO 'orchestrator_integration_user'@'%';
SQL
        fi
    fi

    # Grant common orchestrator privileges
    # Some privileges are version-specific
    if [[ "$supports_system_user" == "true" ]]; then
        # MySQL 8.0+ privileges (includes role support)
        sudo mysql -u root <<SQL
GRANT SELECT ON mysql.user TO 'orchestrator_integration_user'@'%';
GRANT UPDATE ON mysql.user TO 'orchestrator_integration_user'@'%';
GRANT SELECT ON mysql.role_edges TO 'orchestrator_integration_user'@'%';
GRANT RELOAD ON *.* TO 'orchestrator_integration_user'@'%';
GRANT CREATE USER ON *.* TO 'orchestrator_integration_user'@'%';
GRANT CREATE ROLE ON *.* TO 'orchestrator_integration_user'@'%';
GRANT ALL PRIVILEGES ON \`<target_db>\`.* TO 'orchestrator_integration_user'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    else
        # MySQL 5.x privileges (no role support)
        sudo mysql -u root <<SQL
GRANT SELECT ON mysql.user TO 'orchestrator_integration_user'@'%';
GRANT UPDATE ON mysql.user TO 'orchestrator_integration_user'@'%';
GRANT RELOAD ON *.* TO 'orchestrator_integration_user'@'%';
GRANT CREATE USER ON *.* TO 'orchestrator_integration_user'@'%';
GRANT ALL PRIVILEGES ON \`<target_db>\`.* TO 'orchestrator_integration_user'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL
    fi

    # Create example users only if -e flag is set
    if [[ "$create_examples" == "true" ]]; then
        echo "Creating example user accounts..."

        local app_admin_exists=$(sudo mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'app_admin' AND host = '%')")
        if [[ "$app_admin_exists" == "1" ]]; then
            echo "app_admin already exists, skipping..."
        else
            echo "Creating app_admin..."
            new_users=true
            sudo mysql -u root <<SQL
CREATE USER 'app_admin'@'%' IDENTIFIED BY '$USER1_PASS';
GRANT ALL PRIVILEGES ON *.* TO 'app_admin'@'%';
SQL
        fi

        local app_readwrite_exists=$(sudo mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'app_readwrite' AND host = '%')")
        if [[ "$app_readwrite_exists" == "1" ]]; then
            echo "app_readwrite already exists, skipping..."
        else
            echo "Creating app_readwrite..."
            new_users=true
            sudo mysql -u root <<SQL
CREATE USER 'app_readwrite'@'%' IDENTIFIED BY '$USER2_PASS';
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO 'app_readwrite'@'%';
SQL
        fi

        local app_readonly_exists=$(sudo mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'app_readonly' AND host = '%')")
        if [[ "$app_readonly_exists" == "1" ]]; then
            echo "app_readonly already exists, skipping..."
        else
            echo "Creating app_readonly..."
            new_users=true
            sudo mysql -u root <<SQL
CREATE USER 'app_readonly'@'%' IDENTIFIED BY '$USER3_PASS';
GRANT SELECT ON *.* TO 'app_readonly'@'%';
SQL
        fi

        local report_user_exists=$(sudo mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'report_user' AND host = '%')")
        if [[ "$report_user_exists" == "1" ]]; then
            echo "report_user already exists, skipping..."
        else
            echo "Creating report_user..."
            new_users=true
            sudo mysql -u root <<SQL
CREATE USER 'report_user'@'%' IDENTIFIED BY '$USER4_PASS';
GRANT SELECT, SHOW VIEW ON *.* TO 'report_user'@'%';
SQL
        fi

        local backup_user_exists=$(sudo mysql -u root -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = 'backup_user' AND host = '%')")
        if [[ "$backup_user_exists" == "1" ]]; then
            echo "backup_user already exists, skipping..."
        else
            echo "Creating backup_user..."
            new_users=true
            sudo mysql -u root <<SQL
CREATE USER 'backup_user'@'%' IDENTIFIED BY '$USER5_PASS';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup_user'@'%';
SQL
        fi
    fi

    sudo mysql -u root <<SQL
FLUSH PRIVILEGES;
SQL

    # Return whether new users were created
    echo "$new_users"
}

# Create PostgreSQL users
create_postgres_users() {
    local orch_superuser=$1
    local create_examples=$2
    echo "Creating PostgreSQL users..."
    local new_users=false

    # Detect PostgreSQL version
    local pg_version=$(detect_postgres_version)
    echo "Detected PostgreSQL version: ${pg_version:-unknown}"

    # Determine version-specific requirements
    local requires_admin_option=false
    if version_ge "$pg_version" "16"; then
        requires_admin_option=true
        echo "PostgreSQL 16+ detected: Will use ADMIN OPTION for password change privileges"
    fi

    # Determine orchestrator privileges based on flag
    local orch_privileges
    if [[ "$orch_superuser" == "true" ]]; then
        orch_privileges="SUPERUSER"
        echo "Granting SUPERUSER to orchestrator (can change all passwords including superusers)"
    else
        orch_privileges="CREATEROLE"
        if [[ "$requires_admin_option" == "true" ]]; then
            echo "Granting CREATEROLE to orchestrator (PostgreSQL 16+: requires ADMIN OPTION for password changes)"
        else
            echo "Granting CREATEROLE to orchestrator (can change non-superuser passwords only)"
        fi
    fi

    # Handle orchestrator_integration_user - always update privileges, set password only on creation
    local orch_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='orchestrator_integration_user'")
    if [[ "$orch_exists" == "1" ]]; then
        echo "orchestrator_integration_user exists, updating privileges only..."
        sudo -u postgres psql <<SQL
ALTER USER orchestrator_integration_user WITH $orch_privileges;
SQL
    else
        echo "Creating orchestrator_integration_user..."
        new_users=true
        sudo -u postgres psql <<SQL
CREATE USER orchestrator_integration_user WITH PASSWORD '$ORCH_PASS' $orch_privileges;
SQL
    fi

    # If orchestrator is NOT superuser, grant specific privileges
    # (SUPERUSER already has all these privileges, so they're redundant in that case)
    if [[ "$orch_superuser" != "true" ]]; then
        echo "Granting specific database privileges to orchestrator..."

        # Version-specific privilege grants
        if [[ "$requires_admin_option" == "true" ]]; then
            # PostgreSQL 16+ requires more explicit privilege management
            sudo -u postgres psql <<SQL
GRANT CONNECT ON DATABASE postgres TO orchestrator_integration_user;
GRANT pg_signal_backend TO orchestrator_integration_user;
GRANT USAGE ON SCHEMA public TO orchestrator_integration_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO orchestrator_integration_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO orchestrator_integration_user WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO orchestrator_integration_user WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON SCHEMA public TO orchestrator_integration_user WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON TABLES TO orchestrator_integration_user WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON SEQUENCES TO orchestrator_integration_user WITH GRANT OPTION;
SQL
        else
            # Pre-16 PostgreSQL versions
            sudo -u postgres psql <<SQL
GRANT CONNECT ON DATABASE postgres TO orchestrator_integration_user;
GRANT pg_signal_backend TO orchestrator_integration_user;
GRANT USAGE ON SCHEMA public TO orchestrator_integration_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO orchestrator_integration_user;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO orchestrator_integration_user WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO orchestrator_integration_user WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON SCHEMA public TO orchestrator_integration_user WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON TABLES TO orchestrator_integration_user WITH GRANT OPTION;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT ALL PRIVILEGES ON SEQUENCES TO orchestrator_integration_user WITH GRANT OPTION;
SQL
        fi
    fi

    # Create example users only if -e flag is set
    if [[ "$create_examples" == "true" ]]; then
        echo "Creating example user accounts..."

        local app_admin_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='app_admin'")
        if [[ "$app_admin_exists" == "1" ]]; then
            echo "app_admin already exists, skipping..."
        else
            echo "Creating app_admin..."
            new_users=true
            sudo -u postgres psql <<SQL
CREATE USER app_admin WITH PASSWORD '$USER1_PASS' CREATEDB SUPERUSER;
SQL
        fi

        local app_readwrite_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='app_readwrite'")
        if [[ "$app_readwrite_exists" == "1" ]]; then
            echo "app_readwrite already exists, skipping..."
        else
            echo "Creating app_readwrite..."
            new_users=true
            sudo -u postgres psql <<SQL
CREATE USER app_readwrite WITH PASSWORD '$USER2_PASS';
GRANT ALL PRIVILEGES ON DATABASE postgres TO app_readwrite;
SQL
        fi

        local app_readonly_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='app_readonly'")
        if [[ "$app_readonly_exists" == "1" ]]; then
            echo "app_readonly already exists, skipping..."
        else
            echo "Creating app_readonly..."
            new_users=true
            sudo -u postgres psql <<SQL
CREATE USER app_readonly WITH PASSWORD '$USER3_PASS';
GRANT CONNECT ON DATABASE postgres TO app_readonly;
SQL
        fi

        local report_user_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='report_user'")
        if [[ "$report_user_exists" == "1" ]]; then
            echo "report_user already exists, skipping..."
        else
            echo "Creating report_user..."
            new_users=true
            sudo -u postgres psql <<SQL
CREATE USER report_user WITH PASSWORD '$USER4_PASS';
GRANT CONNECT ON DATABASE postgres TO report_user;
SQL
        fi

        local backup_user_exists=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='backup_user'")
        if [[ "$backup_user_exists" == "1" ]]; then
            echo "backup_user already exists, skipping..."
        else
            echo "Creating backup_user..."
            new_users=true
            sudo -u postgres psql <<SQL
CREATE USER backup_user WITH PASSWORD '$USER5_PASS' REPLICATION;
SQL
        fi
    fi

    # If orchestrator is NOT superuser, grant ADMIN option on all non-superuser roles
    # This allows password changes on non-superuser accounts
    # PostgreSQL 16+ requires ADMIN OPTION for password changes even with CREATEROLE
    # Earlier versions: CREATEROLE can change passwords without ADMIN OPTION (optional but harmless)
    if [[ "$orch_superuser" != "true" && "$create_examples" == "true" ]]; then
        if [[ "$requires_admin_option" == "true" ]]; then
            echo "Granting ADMIN option on non-superuser roles to orchestrator (required for PostgreSQL 16+)..."
        else
            echo "Granting ADMIN option on non-superuser roles to orchestrator (best practice)..."
        fi
        sudo -u postgres psql <<SQL
DO \$\$
DECLARE
    role_name TEXT;
BEGIN
    FOR role_name IN
        SELECT rolname FROM pg_roles
        WHERE rolname NOT IN ('postgres', 'pg_monitor', 'pg_read_all_settings', 'pg_read_all_stats',
                              'pg_stat_scan_tables', 'pg_read_server_files', 'pg_write_server_files',
                              'pg_execute_server_program', 'pg_signal_backend', 'orchestrator_integration_user')
          AND rolsuper = false
          AND rolname NOT LIKE 'pg_%'
    LOOP
        EXECUTE format('GRANT %I TO orchestrator_integration_user WITH ADMIN OPTION', role_name);
    END LOOP;
END
\$\$;
SQL
    fi

    # Return whether new users were created
    echo "$new_users"
}

# Write credentials file
write_credentials() {
    local db_type=$1
    local include_examples=$2
    local creds_file="/root/${db_type}-credentials.txt"

    # Backup existing credentials file if it exists
    if sudo test -f "$creds_file"; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_file="${creds_file}.backup.${timestamp}"
        sudo cp "$creds_file" "$backup_file"
        echo "Existing credentials backed up to $backup_file"
    fi

    if [[ "$include_examples" == "true" ]]; then
        sudo bash -c "cat > '$creds_file'" <<CREDS
${db_type^^} Orchestrator Account:
  Username: orchestrator_integration_user
  Password: $ORCH_PASS

Example User Accounts:
  1. app_admin (full/superuser privileges)
     Password: $USER1_PASS

  2. app_readwrite (read/write access)
     Password: $USER2_PASS

  3. app_readonly (read-only access)
     Password: $USER3_PASS

  4. report_user (reporting access)
     Password: $USER4_PASS

  5. backup_user (backup privileges)
     Password: $USER5_PASS
CREDS
    else
        sudo bash -c "cat > '$creds_file'" <<CREDS
${db_type^^} Orchestrator Account:
  Username: orchestrator_integration_user
  Password: $ORCH_PASS
CREDS
    fi

    sudo chmod 600 "$creds_file"
    echo "${db_type^^} setup complete. Credentials saved to $creds_file"
}

# Main execution
main() {
    local db_engine=""
    local detect_only=false
    local orchestrator_superuser=false
    local create_example_users=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p)
                db_engine="postgres"
                shift
                ;;
            -m)
                db_engine="mysql"
                shift
                ;;
            -s)
                orchestrator_superuser=true
                shift
                ;;
            -e)
                create_example_users=true
                shift
                ;;
            -d)
                detect_only=true
                shift
                ;;
            -h)
                usage
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Auto-detect if no engine specified
    if [[ -z "$db_engine" ]]; then
        echo "No database engine specified. Auto-detecting..."
        db_engine=$(detect_database)

        if [[ -z "$db_engine" ]]; then
            echo "ERROR: No database detected. Please specify --postgres or --mysql"
            exit 1
        fi

        echo "Detected: $db_engine"
    fi

    # If detect-only mode, show version and exit
    if [[ "$detect_only" == true ]]; then
        echo "Database engine: $db_engine"

        case $db_engine in
            postgres)
                local pg_version=$(detect_postgres_version)
                if [[ -n "$pg_version" ]]; then
                    echo "PostgreSQL version: $pg_version"
                fi
                ;;
            mysql)
                local mysql_version=$(detect_mysql_version)
                if [[ -n "$mysql_version" ]]; then
                    echo "MySQL version: $mysql_version"
                fi
                ;;
        esac
        exit 0
    fi

    # Generate passwords once for all operations
    generate_passwords

    # Execute database-specific setup
    case $db_engine in
        postgres)
            # Check if already installed
            if ! command -v psql >/dev/null 2>&1; then
                install_postgres
            else
                echo "PostgreSQL already installed. Skipping installation."
            fi
            local new_users=$(create_postgres_users "$orchestrator_superuser" "$create_example_users")
            if [[ "$new_users" == "true" ]]; then
                write_credentials "postgresql" "$create_example_users"
            else
                echo "No new PostgreSQL users created. Credentials file not modified."
            fi
            ;;
        mysql)
            # Check if already installed
            if ! command -v mysql >/dev/null 2>&1; then
                install_mysql
            else
                echo "MySQL already installed. Skipping installation."
            fi
            local new_users=$(create_mysql_users "$orchestrator_superuser" "$create_example_users")
            if [[ "$new_users" == "true" ]]; then
                write_credentials "mysql" "$create_example_users"
            else
                echo "No new MySQL users created. Credentials file not modified."
            fi
            ;;
        *)
            echo "ERROR: Unknown database engine: $db_engine"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
