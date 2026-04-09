#!/usr/bin/env bash
set -e

# LinuxOpaDbSetup.sh - Unified PostgreSQL and MySQL setup script
# Supports auto-detection or explicit database selection

# Usage information
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Setup PostgreSQL or MySQL with OPA-ready user accounts.
The script will use sudo for privileged operations as needed.

OPTIONS:
    --postgres          Install and configure PostgreSQL
    --mysql             Install and configure MySQL
    --detect-only       Detect installed database without setup
    -h, --help          Show this help message

If no option is specified, the script will auto-detect the installed database.

Examples:
    $0 --postgres       # Install PostgreSQL
    $0 --mysql          # Install MySQL
    $0                  # Auto-detect and configure
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
    echo "Creating MySQL users..."
    sudo mysql -u root <<SQL
-- Create admin service account
CREATE USER IF NOT EXISTS 'dbadmin'@'%' IDENTIFIED BY '$ADMIN_PASS';
GRANT ALL PRIVILEGES ON *.* TO 'dbadmin'@'%' WITH GRANT OPTION;

-- Create the OPA service account
CREATE USER 'orchestrator_integration_user'@'%' IDENTIFIED BY '$ORCH_PASS';
GRANT SELECT ON mysql.user TO 'orchestrator_integration_user'@'%';
GRANT SELECT ON mysql.role_edges TO 'orchestrator_integration_user'@'%';
GRANT RELOAD ON *.* TO 'orchestrator_integration_user'@'%';
GRANT CREATE USER ON *.* TO 'orchestrator_integration_user'@'%';
GRANT CREATE ROLE ON *.* TO 'orchestrator_integration_user'@'%';
GRANT ALL PRIVILEGES ON \`<target_db>\`.* TO 'orchestrator_integration_user'@'%' WITH GRANT OPTION;

-- Create example users with various roles
CREATE USER IF NOT EXISTS 'app_admin'@'%' IDENTIFIED BY '$USER1_PASS';
GRANT ALL PRIVILEGES ON *.* TO 'app_admin'@'%';

CREATE USER IF NOT EXISTS 'app_readwrite'@'%' IDENTIFIED BY '$USER2_PASS';
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO 'app_readwrite'@'%';

CREATE USER IF NOT EXISTS 'app_readonly'@'%' IDENTIFIED BY '$USER3_PASS';
GRANT SELECT ON *.* TO 'app_readonly'@'%';

CREATE USER IF NOT EXISTS 'report_user'@'%' IDENTIFIED BY '$USER4_PASS';
GRANT SELECT, SHOW VIEW ON *.* TO 'report_user'@'%';

CREATE USER IF NOT EXISTS 'backup_user'@'%' IDENTIFIED BY '$USER5_PASS';
GRANT SELECT, LOCK TABLES, SHOW VIEW, EVENT, TRIGGER ON *.* TO 'backup_user'@'%';

FLUSH PRIVILEGES;
SQL
}

# Create PostgreSQL users
create_postgres_users() {
    echo "Creating PostgreSQL users..."
    sudo -u postgres psql <<SQL
-- Create admin service account with superuser privileges
CREATE USER dbadmin WITH PASSWORD '$ADMIN_PASS' SUPERUSER CREATEDB CREATEROLE;

-- Create OPA orchestrator user
CREATE USER orchestrator_integration_user WITH PASSWORD '$ORCH_PASS' CREATEROLE;
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

-- Create example users with various roles
CREATE USER app_admin WITH PASSWORD '$USER1_PASS' CREATEDB;
ALTER USER app_admin WITH SUPERUSER;

CREATE USER app_readwrite WITH PASSWORD '$USER2_PASS';
GRANT ALL PRIVILEGES ON DATABASE postgres TO app_readwrite;

CREATE USER app_readonly WITH PASSWORD '$USER3_PASS';
GRANT CONNECT ON DATABASE postgres TO app_readonly;

CREATE USER report_user WITH PASSWORD '$USER4_PASS';
GRANT CONNECT ON DATABASE postgres TO report_user;

CREATE USER backup_user WITH PASSWORD '$USER5_PASS' REPLICATION;
SQL
}

# Write credentials file
write_credentials() {
    local db_type=$1
    local creds_file="/root/${db_type}-credentials.txt"

    sudo bash -c "cat > '$creds_file'" <<CREDS
${db_type^^} Admin Account:
  Username: dbadmin
  Password: $ADMIN_PASS

Orchestrator account:
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

    sudo chmod 600 "$creds_file"
    echo "${db_type^^} setup complete. Credentials saved to $creds_file"
}

# Main execution
main() {
    local db_engine=""
    local detect_only=false

    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --postgres)
                db_engine="postgres"
                shift
                ;;
            --mysql)
                db_engine="mysql"
                shift
                ;;
            --detect-only)
                detect_only=true
                shift
                ;;
            -h|--help)
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
            create_postgres_users
            write_credentials "postgresql"
            ;;
        mysql)
            # Check if already installed
            if ! command -v mysql >/dev/null 2>&1; then
                install_mysql
            else
                echo "MySQL already installed. Skipping installation."
            fi
            create_mysql_users
            write_credentials "mysql"
            ;;
        *)
            echo "ERROR: Unknown database engine: $db_engine"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
