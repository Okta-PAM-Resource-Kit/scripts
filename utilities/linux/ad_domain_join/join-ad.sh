#!/usr/bin/env bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Parse command line arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <domain_name> <ad_account_name>"
    echo "Example: $0 example.com administrator"
    exit 1
fi

DOMAIN_NAME="$1"
AD_ACCOUNT="$2"

log_info "Starting Active Directory domain join process..."

# Detect Linux distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=$ID
    OS_ID_LIKE=$ID_LIKE
else
    log_error "Cannot detect Linux distribution"
    exit 1
fi

# Determine package manager and distribution type
if [[ "$OS_ID" =~ ^(ubuntu|debian)$ ]] || [[ "$OS_ID_LIKE" =~ debian ]]; then
    DISTRO_TYPE="debian"
    PKG_MANAGER="apt-get"
    log_info "Detected Debian-based distribution: ${OS_ID}"
elif [[ "$OS_ID" =~ ^(rhel|centos|rocky|almalinux|fedora)$ ]] || [[ "$OS_ID_LIKE" =~ rhel|fedora ]]; then
    DISTRO_TYPE="rpm"
    # Determine if dnf or yum
    if command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    else
        PKG_MANAGER="yum"
    fi
    log_info "Detected RPM-based distribution: ${OS_ID}"
else
    log_error "Unsupported Linux distribution: ${OS_ID}"
    exit 1
fi

# Step 1: Install required packages
log_info "Installing required packages using ${PKG_MANAGER}..."

if [ "$DISTRO_TYPE" = "debian" ]; then
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        realmd \
        sssd \
        sssd-tools \
        samba-common-bin \
        adcli \
        packagekit \
        oddjob \
        oddjob-mkhomedir
elif [ "$DISTRO_TYPE" = "rpm" ]; then
    sudo $PKG_MANAGER install -y \
        realmd \
        sssd \
        sssd-tools \
        samba-common-tools \
        adcli \
        oddjob \
        oddjob-mkhomedir \
        krb5-workstation
fi

log_info "Package installation complete"

# Ensure nslookup is available
if ! command -v nslookup &> /dev/null; then
    log_info "Installing bind-utils/dnsutils for DNS lookup..."
    if [ "$DISTRO_TYPE" = "debian" ]; then
        sudo apt-get install -y dnsutils
    elif [ "$DISTRO_TYPE" = "rpm" ]; then
        sudo $PKG_MANAGER install -y bind-utils
    fi
fi

# Step 2: Verify DNS configuration
log_info "Verifying DNS can resolve domain controller..."

# Test DNS resolution for the domain
log_info "Testing DNS resolution for ${DOMAIN_NAME}..."

# First get the DC hostname from SRV record
DC_HOSTNAME=$(nslookup -type=srv _ldap._tcp.${DOMAIN_NAME} 2>/dev/null | grep "service" | awk '{print $NF}' | sed 's/\.$//' | head -1)

if [ -z "$DC_HOSTNAME" ]; then
    log_error "Cannot find domain controller SRV record for ${DOMAIN_NAME}"
    log_error "DNS is not configured to query the domain controller."
    log_error ""
    log_info "You need to configure DNS servers for the domain."
    log_info "Please enter the IP address(es) of your domain DNS servers."
    log_info "Enter one or more IPs separated by spaces (e.g., 10.0.0.10 10.0.0.11):"
    read -r DNS_SERVERS

    if [ -z "$DNS_SERVERS" ]; then
        log_error "No DNS servers provided. Cannot continue."
        exit 1
    fi

    log_info "Configuring DNS servers: ${DNS_SERVERS}"

    # Configure DNS based on distribution
    if [ "$DISTRO_TYPE" = "debian" ]; then
        log_info "Installing and configuring resolvconf for Ubuntu/Debian..."

        # Install resolvconf
        sudo apt-get install -y resolvconf

        # Create the head file with domain DNS servers
        sudo mkdir -p /etc/resolvconf/resolv.conf.d
        {
            echo "# Domain DNS servers for ${DOMAIN_NAME}"
            for DNS_IP in $DNS_SERVERS; do
                echo "nameserver ${DNS_IP}"
            done
            echo "search ${DOMAIN_NAME}"
        } | sudo tee /etc/resolvconf/resolv.conf.d/head > /dev/null

        log_info "Created /etc/resolvconf/resolv.conf.d/head"

        # Enable and update resolvconf
        sudo systemctl enable resolvconf.service
        sudo systemctl start resolvconf.service
        sudo resolvconf -u

        log_info "resolvconf service enabled and updated"

    elif [ "$DISTRO_TYPE" = "rpm" ]; then
        log_info "Configuring DNS for RHEL/CentOS using NetworkManager..."

        # Use NetworkManager to add DNS servers
        # Get the primary connection name
        PRIMARY_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep -v '^lo:' | head -1 | cut -d: -f1)

        if [ ! -z "$PRIMARY_CONN" ]; then
            log_info "Configuring connection: ${PRIMARY_CONN}"

            # Add DNS servers
            DNS_ARRAY=($DNS_SERVERS)
            for i in "${!DNS_ARRAY[@]}"; do
                DNS_INDEX=$((i + 1))
                sudo nmcli connection modify "${PRIMARY_CONN}" ipv4.dns${DNS_INDEX} "${DNS_ARRAY[$i]}"
            done

            # Add search domain
            sudo nmcli connection modify "${PRIMARY_CONN}" ipv4.dns-search "${DOMAIN_NAME}"

            # Set DNS priority
            sudo nmcli connection modify "${PRIMARY_CONN}" ipv4.dns-priority -1

            # Reload the connection
            sudo nmcli connection up "${PRIMARY_CONN}"

            log_info "NetworkManager DNS configuration updated"
        else
            log_error "Could not determine primary network connection"
            log_error "Please configure DNS manually"
            exit 1
        fi
    fi

    log_info "DNS configuration complete. Waiting 3 seconds for DNS to propagate..."
    sleep 3

    # Retry DNS lookup
    log_info "Retrying domain controller DNS lookup..."
    DC_HOSTNAME=$(nslookup -type=srv _ldap._tcp.${DOMAIN_NAME} 2>/dev/null | grep "service" | awk '{print $NF}' | sed 's/\.$//' | head -1)

    if [ -z "$DC_HOSTNAME" ]; then
        log_error "Still cannot resolve domain controller after DNS configuration"
        log_error "Please verify the DNS server IPs are correct and accessible"
        exit 1
    fi

    log_info "Successfully found domain controller: ${DC_HOSTNAME}"
fi

log_info "Found domain controller hostname: ${DC_HOSTNAME}"

# Then resolve the hostname to an IP
DC_IP=$(nslookup ${DC_HOSTNAME} 2>/dev/null | grep -A 1 "^Name:" | grep "Address:" | awk '{print $2}' | head -1)

if [ -z "$DC_IP" ]; then
    log_error "Cannot resolve IP address for domain controller ${DC_HOSTNAME}"
    log_error "DNS configuration may be incomplete."

    # Check if we already configured DNS servers
    if [ -z "$DNS_SERVERS" ]; then
        log_info "Please enter the IP address(es) of your domain DNS servers."
        log_info "Enter one or more IPs separated by spaces (e.g., 10.0.0.10 10.0.0.11):"
        read -r DNS_SERVERS

        if [ -z "$DNS_SERVERS" ]; then
            log_error "No DNS servers provided. Cannot continue."
            exit 1
        fi

        log_info "Configuring DNS servers: ${DNS_SERVERS}"

        # Configure DNS based on distribution (same logic as above)
        if [ "$DISTRO_TYPE" = "debian" ]; then
            log_info "Installing and configuring resolvconf for Ubuntu/Debian..."
            sudo apt-get install -y resolvconf
            sudo mkdir -p /etc/resolvconf/resolv.conf.d
            {
                echo "# Domain DNS servers for ${DOMAIN_NAME}"
                for DNS_IP in $DNS_SERVERS; do
                    echo "nameserver ${DNS_IP}"
                done
                echo "search ${DOMAIN_NAME}"
            } | sudo tee /etc/resolvconf/resolv.conf.d/head > /dev/null
            log_info "Created /etc/resolvconf/resolv.conf.d/head"
            sudo systemctl enable resolvconf.service
            sudo systemctl start resolvconf.service
            sudo resolvconf -u
            log_info "resolvconf service enabled and updated"
        elif [ "$DISTRO_TYPE" = "rpm" ]; then
            log_info "Configuring DNS for RHEL/CentOS using NetworkManager..."
            PRIMARY_CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep -v '^lo:' | head -1 | cut -d: -f1)
            if [ ! -z "$PRIMARY_CONN" ]; then
                log_info "Configuring connection: ${PRIMARY_CONN}"
                DNS_ARRAY=($DNS_SERVERS)
                for i in "${!DNS_ARRAY[@]}"; do
                    DNS_INDEX=$((i + 1))
                    sudo nmcli connection modify "${PRIMARY_CONN}" ipv4.dns${DNS_INDEX} "${DNS_ARRAY[$i]}"
                done
                sudo nmcli connection modify "${PRIMARY_CONN}" ipv4.dns-search "${DOMAIN_NAME}"
                sudo nmcli connection modify "${PRIMARY_CONN}" ipv4.dns-priority -1
                sudo nmcli connection up "${PRIMARY_CONN}"
                log_info "NetworkManager DNS configuration updated"
            else
                log_error "Could not determine primary network connection"
                exit 1
            fi
        fi

        log_info "DNS configuration complete. Waiting 3 seconds for DNS to propagate..."
        sleep 3

        # Retry DNS lookup
        log_info "Retrying IP resolution for ${DC_HOSTNAME}..."
        DC_IP=$(nslookup ${DC_HOSTNAME} 2>/dev/null | grep -A 1 "^Name:" | grep "Address:" | awk '{print $2}' | head -1)

        if [ -z "$DC_IP" ]; then
            log_error "Still cannot resolve ${DC_HOSTNAME} after DNS configuration"
            log_error "Please verify the DNS server IPs are correct and accessible"
            exit 1
        fi
    else
        log_error "Already configured DNS but still cannot resolve ${DC_HOSTNAME}"
        log_error "Please verify the DNS configuration is correct"
        exit 1
    fi
fi

if [ ! -z "$DC_IP" ]; then
    log_info "Successfully resolved domain controller at: ${DC_IP}"
    log_info "DNS configuration is correct"
fi

# Check reverse DNS for this host
log_info "Checking reverse DNS configuration..."
HOST_IP=$(hostname -I | awk '{print $1}')
if [ ! -z "$HOST_IP" ]; then
    REVERSE_DNS=$(nslookup ${HOST_IP} 2>/dev/null | grep "name = " | awk '{print $NF}' | sed 's/\.$//')
    if [ ! -z "$REVERSE_DNS" ]; then
        log_info "Reverse DNS for ${HOST_IP}: ${REVERSE_DNS}"
    else
        log_warning "No reverse DNS found for ${HOST_IP}"
        log_warning "This may cause issues with Kerberos authentication"
    fi
fi

# Step 3: Verify time synchronization
log_info "Verifying system time synchronization..."

# Check if time sync service is running
TIME_SYNC_ACTIVE=false
if systemctl is-active --quiet systemd-timesyncd; then
    log_info "systemd-timesyncd is active"
    TIME_SYNC_ACTIVE=true
    # Force immediate sync on Ubuntu
    sudo systemctl restart systemd-timesyncd
    sleep 2
elif systemctl is-active --quiet chronyd; then
    log_info "chronyd is active"
    TIME_SYNC_ACTIVE=true
    sudo chronyc makestep 2>/dev/null || true
elif systemctl is-active --quiet ntpd; then
    log_info "ntpd is active"
    TIME_SYNC_ACTIVE=true
fi

if [ "$TIME_SYNC_ACTIVE" = false ]; then
    log_warning "No time synchronization service detected. Installing and enabling..."
    if [ "$DISTRO_TYPE" = "debian" ]; then
        sudo apt-get install -y systemd-timesyncd
        sudo systemctl enable --now systemd-timesyncd
    elif [ "$DISTRO_TYPE" = "rpm" ]; then
        sudo $PKG_MANAGER install -y chrony
        sudo systemctl enable --now chronyd
    fi
fi

# Display current time
log_info "Current system time: $(date)"
log_info "Current system time (UTC): $(date -u)"

# Check sync status
timedatectl status | grep "synchronized" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    log_info "System clock is synchronized"
else
    log_warning "System clock may not be synchronized yet"
    log_warning "Waiting 5 seconds for time sync..."
    sleep 5
fi

# Critical: Check time difference with domain controller
log_info "Checking time difference with domain controller..."
if [ ! -z "$DC_IP" ]; then
    # Try to get DC time via ntpdate or similar
    if command -v ntpdate &> /dev/null; then
        DC_TIME_CHECK=$(sudo ntpdate -q ${DC_IP} 2>/dev/null | tail -1)
        log_info "DC time check: ${DC_TIME_CHECK}"
    else
        log_warning "ntpdate not available - cannot verify time difference with DC"
        log_warning "Installing ntpdate..."
        if [ "$DISTRO_TYPE" = "debian" ]; then
            sudo apt-get install -y ntpdate
        elif [ "$DISTRO_TYPE" = "rpm" ]; then
            sudo $PKG_MANAGER install -y ntpdate
        fi
        DC_TIME_CHECK=$(sudo ntpdate -q ${DC_IP} 2>/dev/null | tail -1)
        log_info "DC time check: ${DC_TIME_CHECK}"
    fi

    # Extract time offset
    TIME_OFFSET=$(echo "$DC_TIME_CHECK" | grep -oP 'offset \K[-+]?[0-9]+\.[0-9]+' || echo "unknown")
    if [ "$TIME_OFFSET" != "unknown" ]; then
        log_info "Time offset from DC: ${TIME_OFFSET} seconds"

        # Check if offset is greater than 5 minutes (300 seconds)
        OFFSET_ABS=$(echo "$TIME_OFFSET" | tr -d '-')
        if (( $(echo "$OFFSET_ABS > 300" | bc -l 2>/dev/null || echo 0) )); then
            log_error "Time difference with DC is greater than 5 minutes!"
            log_error "Kerberos requires time sync within 5 minutes"
            log_error "Please sync your system time with the domain controller"
            exit 1
        elif (( $(echo "$OFFSET_ABS > 60" | bc -l 2>/dev/null || echo 0) )); then
            log_warning "Time offset is ${TIME_OFFSET} seconds - syncing now..."
            sudo ntpdate -u ${DC_IP} 2>/dev/null || true
        else
            log_info "Time sync is within acceptable range"
        fi
    fi
fi

# Step 4: Configure Kerberos
log_info "Configuring Kerberos for domain ${DOMAIN_NAME}..."

# Backup existing krb5.conf if it exists
if [ -f /etc/krb5.conf ]; then
    sudo cp /etc/krb5.conf /etc/krb5.conf.backup
    log_info "Backed up existing /etc/krb5.conf"
fi

# Create a proper krb5.conf - this is critical for Ubuntu
# The rdns = false setting is REQUIRED to prevent Kerberos errors
log_info "Creating /etc/krb5.conf with rdns disabled (required for Ubuntu)..."
sudo tee /etc/krb5.conf > /dev/null << EOF
[libdefaults]
    default_realm = ${DOMAIN_NAME^^}
    dns_lookup_realm = true
    dns_lookup_kdc = true
    rdns = false
    ticket_lifetime = 24h
    forwardable = yes
    udp_preference_limit = 0
    default_ccache_name = KEYRING:persistent:%{uid}

[realms]
    ${DOMAIN_NAME^^} = {
        kdc = ${DC_HOSTNAME}
        admin_server = ${DC_HOSTNAME}
        default_domain = ${DOMAIN_NAME}
    }

[domain_realm]
    .${DOMAIN_NAME} = ${DOMAIN_NAME^^}
    ${DOMAIN_NAME} = ${DOMAIN_NAME^^}
EOF

log_info "Kerberos configuration created"

# Verify rdns is disabled (critical for Ubuntu)
if grep -q "rdns = false" /etc/krb5.conf; then
    log_info "Verified: rdns = false is set in /etc/krb5.conf"
else
    log_error "CRITICAL: rdns = false is NOT set in /etc/krb5.conf"
    log_error "This will cause 'Server not found in Kerberos database' errors on Ubuntu"
    exit 1
fi

# Test Kerberos configuration
log_info "Testing Kerberos configuration..."
klist 2>/dev/null || log_info "No existing Kerberos tickets (this is normal)"

# Step 5: Discover domain
log_info "Discovering domain: ${DOMAIN_NAME}..."
realm discover ${DOMAIN_NAME}

if [ $? -ne 0 ]; then
    log_error "Failed to discover domain ${DOMAIN_NAME}"
    exit 1
fi

# Check if already joined to a domain
log_info "Checking if system is already joined to a domain..."
CURRENT_REALM=$(realm list | grep "domain-name" | awk '{print $2}')

if [ ! -z "$CURRENT_REALM" ]; then
    log_error "System is already joined to domain: ${CURRENT_REALM}"
    log_error "Please leave the current domain before joining a new one"
    exit 1
fi

log_info "No existing domain membership found. Proceeding with join..."

# Step 5: Join the domain
log_info "Joining domain ${DOMAIN_NAME} as ${AD_ACCOUNT}..."

# Get the short hostname (without domain suffix)
SHORT_HOSTNAME=$(hostname -s)
FULL_HOSTNAME=$(hostname -f)
# Convert to uppercase for AD computer name (Windows convention)
COMPUTER_NAME=$(echo "${SHORT_HOSTNAME}" | tr '[:lower:]' '[:upper:]')

log_info "Short hostname: ${SHORT_HOSTNAME}"
log_info "Full hostname: ${FULL_HOSTNAME}"
log_info "Computer name (uppercase): ${COMPUTER_NAME}"

# Display realm discover info for debugging
log_info "Domain discovery info:"
realm discover ${DOMAIN_NAME} | grep -E "server-software|required-package" || true

log_info "You will be prompted for the password..."

# Use verbose mode and explicitly set the computer name to avoid FQDN issues
# Computer name is uppercase following Windows/AD convention
# Do NOT specify --computer-ou unless necessary as it can cause permission issues
sudo realm join --user="${AD_ACCOUNT}" --verbose --computer-name="${COMPUTER_NAME}" "${DOMAIN_NAME}"

if [ $? -ne 0 ]; then
    log_error "Failed to join domain ${DOMAIN_NAME}"
    log_error ""
    log_error "Troubleshooting steps:"
    log_error "  1. Check journalctl -xe for detailed error messages"
    log_error "  2. Verify account has 'Add workstations to domain' permission"
    log_error "  3. Check if DNS reverse lookup returns correct domain"
    log_error "  4. Try: sudo realm join --user=${AD_ACCOUNT} ${DOMAIN_NAME} (without --computer-name)"
    log_error ""
    exit 1
fi

log_info "Successfully joined domain ${DOMAIN_NAME}"

# Step 6: Configure SSSD
log_info "Configuring SSSD..."

# Backup original sssd.conf
if [ -f /etc/sssd/sssd.conf ]; then
    sudo cp /etc/sssd/sssd.conf /etc/sssd/sssd.conf.backup
fi

# Fine-tune SSSD configuration
sudo tee /etc/sssd/sssd.conf > /dev/null << EOF
[sssd]
domains = ${DOMAIN_NAME}
config_file_version = 2
services = nss, pam

[domain/${DOMAIN_NAME}]
default_shell = /bin/bash
krb5_store_password_if_offline = True
cache_credentials = True
krb5_realm = ${DOMAIN_NAME^^}
realmd_tags = manages-system joined-with-adcli
id_provider = ad
fallback_homedir = /home/%u@%d
ad_domain = ${DOMAIN_NAME}
use_fully_qualified_names = True
ldap_id_mapping = True
access_provider = ad

# Disable dynamic DNS updates (avoids permission errors in most setups)
dyndns_update = False

EOF

# Set proper permissions
sudo chmod 600 /etc/sssd/sssd.conf

# Restart SSSD
log_info "Restarting SSSD service..."
sudo systemctl restart sssd
sudo systemctl enable sssd

log_info "SSSD configuration complete"

# Step 7: Configure PAM to create home directories
log_info "Configuring PAM to auto-create home directories..."

if [ "$DISTRO_TYPE" = "debian" ]; then
    # Enable mkhomedir using pam-auth-update (Debian/Ubuntu)
    sudo pam-auth-update --enable mkhomedir
elif [ "$DISTRO_TYPE" = "rpm" ]; then
    # Enable mkhomedir for RPM-based systems
    if command -v authselect &> /dev/null; then
        # RHEL 8+ / CentOS 8+ / Rocky 8+ uses authselect
        log_info "Using authselect to enable mkhomedir..."
        sudo authselect select sssd with-mkhomedir --force
    elif command -v authconfig &> /dev/null; then
        # RHEL 7 / CentOS 7 uses authconfig
        log_info "Using authconfig to enable mkhomedir..."
        sudo authconfig --enablemkhomedir --update
    else
        # Manual PAM configuration as fallback
        log_warning "No authselect or authconfig found, configuring PAM manually..."
        if ! grep -q "pam_oddjob_mkhomedir.so" /etc/pam.d/system-auth; then
            sudo sed -i '/pam_unix.so/a session optional pam_oddjob_mkhomedir.so skel=/etc/skel umask=0077' /etc/pam.d/system-auth
        fi
        if ! grep -q "pam_oddjob_mkhomedir.so" /etc/pam.d/password-auth; then
            sudo sed -i '/pam_unix.so/a session optional pam_oddjob_mkhomedir.so skel=/etc/skel umask=0077' /etc/pam.d/password-auth
        fi
    fi
fi

# Start and enable oddjob
sudo systemctl start oddjobd
sudo systemctl enable oddjobd

log_info "Home directory auto-creation enabled"

# Step 7b: Configure SELinux (RPM-based systems only)
if [ "$DISTRO_TYPE" = "rpm" ]; then
    if command -v getenforce &> /dev/null && [ "$(getenforce)" != "Disabled" ]; then
        log_info "Configuring SELinux for home directory creation..."
        sudo setsebool -P use_nfs_home_dirs on 2>/dev/null || true
        sudo setsebool -P oddjob_enable_homedirs on 2>/dev/null || true
        log_info "SELinux booleans configured"
    fi
fi

# Step 7c: Configure sudo access for Domain Admins
log_info "Configuring sudo access for Domain Admins..."

# Create sudoers.d directory if it doesn't exist
sudo mkdir -p /etc/sudoers.d

# Create sudo configuration for Domain Admins
# Note: AD "Domain Admins" group is typically mapped by SSSD as "domain admins" (with space)
# The group name format depends on use_fully_qualified_names setting
SUDOERS_TEMP=$(mktemp)

cat > ${SUDOERS_TEMP} << EOF
# Allow Domain Admins full sudo access without password
# Created by join-ad.sh script
%domain\ admins@${DOMAIN_NAME} ALL=(ALL) NOPASSWD: ALL
EOF

# Validate the sudoers file syntax
if sudo visudo -cf ${SUDOERS_TEMP}; then
    sudo cp ${SUDOERS_TEMP} /etc/sudoers.d/domain_admins
    sudo chmod 0440 /etc/sudoers.d/domain_admins
    log_info "Sudo access configured: %domain\ admins@${DOMAIN_NAME} ALL=(ALL) NOPASSWD: ALL"
    log_info "Domain Admins can now use sudo without a password"
else
    log_error "Failed to validate sudoers file syntax"
    log_warning "Skipping sudo configuration for Domain Admins"
fi

rm -f ${SUDOERS_TEMP}

# Step 8: Configure SSH to allow password authentication
log_info "Configuring SSH for password authentication..."

# Create sshd_config.d directory if it doesn't exist
sudo mkdir -p /etc/ssh/sshd_config.d

# Check if sshd_config includes the sshd_config.d directory
if ! sudo grep -q "^Include /etc/ssh/sshd_config.d/\*.conf" /etc/ssh/sshd_config; then
    log_info "Adding Include directive to /etc/ssh/sshd_config..."
    # Backup the original file
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    # Add Include directive at the beginning of the file
    echo "Include /etc/ssh/sshd_config.d/*.conf" | sudo tee /etc/ssh/sshd_config.tmp > /dev/null
    sudo cat /etc/ssh/sshd_config >> /etc/ssh/sshd_config.tmp
    sudo mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
    log_info "Include directive added to sshd_config"
else
    log_info "Include directive already present in sshd_config"
fi

# Create SSH configuration file
sudo tee /etc/ssh/sshd_config.d/05-OPA-settings.conf > /dev/null << EOF
# SSH configuration for Active Directory authentication
PasswordAuthentication yes
ChallengeResponseAuthentication yes
UsePAM yes
EOF

log_info "SSH configuration created at /etc/ssh/sshd_config.d/05-OPA-settings.conf"

# Restart SSH service
log_info "Restarting SSH service..."

# Determine SSH service name
if systemctl list-unit-files | grep -q "^sshd.service"; then
    SSH_SERVICE="sshd"
elif systemctl list-unit-files | grep -q "^ssh.service"; then
    SSH_SERVICE="ssh"
else
    log_warning "Could not determine SSH service name, trying sshd..."
    SSH_SERVICE="sshd"
fi

sudo systemctl restart $SSH_SERVICE

log_info "SSH service restarted"

# Final verification
log_info "Verifying domain join status..."
realm list

log_info ""
log_info "=========================================="
log_info "Domain join completed successfully!"
log_info "=========================================="
log_info "Domain: ${DOMAIN_NAME}"
log_info "Distribution: ${OS_ID} (${DISTRO_TYPE})"
log_info "You can now login with AD credentials"
log_info "Use format: username (without domain suffix)"
log_info ""
log_info "Test with: id <username>"
log_info "=========================================="

exit 0
