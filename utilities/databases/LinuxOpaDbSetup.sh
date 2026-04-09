#!/usr/bin/env bash
set -e

# LinuxOpaDbSetup.sh - Unified PostgreSQL and MySQL setup script
# Supports auto-detection or explicit database selection

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Setup PostgreSQL or MySQL with OPA orchestrator account.
The script will use sudo for privileged operations as needed.

OPTIONS:
    -p                    Install and configure PostgreSQL
    -m                    Install and configure MySQL
    -s                    Grant SUPERUSER to orchestrator (allows password changes on all accounts)
                          Default: orchestrator can only change non-superuser passwords
    -e                    Create example user accounts (app_admin, app_readwrite, app_readonly, report_user, backup_user)
    -d                    Detect installed database without setup
    -h                    Show this help message

If no database option (-p/-m) is specified, the script will auto-detect the installed database.

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

# Detect which database is installed
detect_database() {
    local detected=""

    if command -v psql >/dev/null 2>&1 && systemctl is-active --quiet postgresql 2>/dev/null; then
        detected="postgres"
    elif command -v mysql >/dev/null 2>&1 && systemctl is-active --quiet mysql 2>/dev/null; then
        detected="mysql"
    fi

    echo "$detected"
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
    echo "Installing MySQL..."
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

    # Configure MySQL to listen on all interfaces
    sudo sed -i "s/bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mysql.conf.d/mysqld.cnf
    sudo systemctl restart mysql
}

# Install and configure PostgreSQL
install_postgres() {
    echo "Installing PostgreSQL..."
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-contrib

    # Configure PostgreSQL to listen on all interfaces
    sudo bash -c "echo \"listen_addresses = '*'\" >> /etc/postgresql/16/main/postgresql.conf"
    sudo bash -c "echo \"host    all             all             0.0.0.0/0               md5\" >> /etc/postgresql/16/main/pg_hba.conf"

    sudo systemctl restart postgresql
}

# Create MySQL users
create_mysql_users() {
    local orch_superuser=$1
    local create_examples=$2
    echo "Creating MySQL users..."
    local new_users=false

    # Determine orchestrator privileges based on flag
    if [[ "$orch_superuser" == "true" ]]; then
        echo "Granting SYSTEM_USER to orchestrator (can perform admin actions on all accounts)"
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

    # Grant/update orchestrator privileges
    # SYSTEM_USER allows administrative actions on all accounts (MySQL 8.0.16+)
    if [[ "$orch_superuser" == "true" ]]; then
        sudo mysql -u root <<SQL
GRANT SYSTEM_USER ON *.* TO 'orchestrator_integration_user'@'%';
SQL
    fi

    # Grant common orchestrator privileges
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

    # Determine orchestrator privileges based on flag
    local orch_privileges
    if [[ "$orch_superuser" == "true" ]]; then
        orch_privileges="SUPERUSER"
        echo "Granting SUPERUSER to orchestrator (can change all passwords including superusers)"
    else
        orch_privileges="CREATEROLE"
        echo "Granting CREATEROLE to orchestrator (can change non-superuser passwords only)"
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
    # This allows password changes on non-superuser accounts (PostgreSQL 16+ requirement)
    if [[ "$orch_superuser" != "true" && "$create_examples" == "true" ]]; then
        echo "Granting ADMIN option on non-superuser roles to orchestrator..."
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

    # If detect-only mode, exit here
    if [[ "$detect_only" == true ]]; then
        echo "Database engine: $db_engine"
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
