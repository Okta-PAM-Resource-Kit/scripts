#!/usr/bin/env bash

# For headless installation, key variables are initialized below with the appropriate default values.  
# Run with script with -h option for command line options
# This script is provided as-is, with no support or warranty expressed or implied, use at your own risk!

# To install the OPA server agent, set the following value to true:
INSTALL_SERVER_TOOLS=false

# Except when using an AWS or GCP account/project linked with an OPA project, 
# an enrollment token for the server agent is required.
# If using an enrollment token, place the token in between the quotes in the  
# following line:
SERVER_ENROLLMENT_TOKEN=""

# To leverage OPA for machine to machine authentication, the OPA client tools are required.
# To install the OPA client tools, set the following value to true:
INSTALL_CLIENT_TOOLS=false
# OPA Client tools will automatically be installed with the OPA Gateway service
# for use in decoding SSH and RDP session recordings.

# To install the OPA Gateway service, set the following value to true:
INSTALL_GATEWAY=false
# When installing OPA Gateway service, place the gateway setup token between the quotes
# in the following line:
GATEWAY_TOKEN=""

# Some EA and beta features are available only with the latest un-released agents.  These
# agents are currently undergoing rapid development and testing and may be unstable.  Not
# suitable for production deployments!!!
# To switch to the test branch, change the following value to test:
REPOSITORY="prod"

# This script uses awk to extract certificate change information necessary to validate there is no
# TLS inspection web proxy in the egress traffic path.  If awk is unavailable on the local host, disable
# the check by setting PROXY_CHECK_ENABLED=false below.
PROXY_CHECK_ENABLED=false

# In Okta Privilege Access, course grained privilege elevation (admin checkbox in UI) is not currently 
# supported. Therefore users create by the sftd agent will be normal users with no sudo rights.  Change
# the below value to true to have this script automatically create agent lifecycle hooks that well
# force all sftd created users to have full sudo rights, just like checking the admin box in the OPA UI.
DEFAULT_TO_ADMIN=false

# By default, this script will not reinstall the current version of the OPA agents.  Change the below
# value to "true" to force reinstallation.
FORCE_REINSTALL=false

# Install arguments will be updated automatically based on the FORCE_REINSTALL flag above.  Do not change
# the default setting below.
REPO_INSTALL_ARG="install"

# Variables for new command-line options
ENABLE_SSH_PASSWORD_AUTH=false
CREATE_TEST_ADMIN_USER=""
CREATE_TEST_USER=""
FORCE_OVERWRITE_SERVER_CONFIG=false
FORCE_OVERWRITE_GATEWAY_CONFIG=false
CREATE_ORCHESTRATOR_GATEWAY=false

# Flags to track if configs were overwritten (for restart logic)
SERVER_CONFIG_OVERWRITTEN=false
GATEWAY_CONFIG_OVERWRITTEN=false

# Flag to track if sshd needs reloading
SSHD_NEEDS_RELOAD=false


# List of required executabled
required_executables=(cut awk grep sort curl tr openssl)

# Script functions begin here


function check_required_executables() {
	# Check if the required executables are installed and if their versions are sufficient
	for (( i=0; i<${#required_executables[@]}; i++ )); do
		executable=${required_executables[i]}
		if ! command -v "$executable" &> /dev/null; then
			echo "ERROR: $executable is not installed"
			exit 1
		fi
	done
}

function setRepoUrl (){
	# Set the repo URL and other parameter based on selected branch
	case ${REPOSITORY} in
		prod )
			REPO_URL="https://dist.scaleft.com"
			REPO_RPM="stable"
			REPO_DEB="okta"
			REPO_BSD="stable"
			;;
		test )
			REPO_URL="https://dist-testing.scaleft.com"
			REPO_RPM="testing"
			REPO_DEB="okta-testing"
			REPO_BSD="testing"
			;;
		* )
			echo "Invalid repository specified.  Set REPOSITORY to either prod or test."
			exit 1
			;;
	esac
}

function getVersionInteger(){
	# Check if the cut command is available
	VERSION=$(echo $VERSION | cut -d. -f1)
}

function getOsData(){
	# Get distribution, version, and code name
	if [ -f /etc/os-release ]; then
		. /etc/os-release
		DISTRIBUTION=$ID
		VERSION=$VERSION_ID
		CODENAME=$VERSION_CODENAME
	elif [ -f /etc/lsb-release ]; then
		. /etc/lsb-release
		DISTRIBUTION=${DISTRIB_ID,,}
		VERSION=$DISTRIB_RELEASE
		CODENAME=$DISTRIB_CODENAME
	else
		DISTRIBUTION=$(uname -s)
		VERSION=$(uname -r)
		CODENAME=""
	fi

	# Get CPU Architecture
	CPU_ARCH=$(uname -m)

	# Make necessary adjustments to align with OPA repo structure
	case "$DISTRIBUTION" in
		amzn )
			DISTRIBUTION="amazonlinux"
			;;
		fedora )
			echo "ERROR: Fedora is not supported."
			echo "OPA packages are not available for Fedora."
			echo "Please use RHEL, CentOS, Rocky Linux, or another supported distribution."
			exit 1
			;;
		rocky|ol )
			getVersionInteger
			# Check if version 7 or earlier (no longer supported for Oracle Linux)
			if [[ "$VERSION" -le 7 ]]; then
				echo "ERROR: $DISTRIBUTION version $VERSION is no longer supported."
				echo "OPA packages are not available for this version."
				echo "Please upgrade to version 8 or later."
				exit 1
			fi
			DISTRIBUTION="rhel"
			;;
		rhel|centos )
			getVersionInteger
			# Check if version 7 or earlier (no longer supported)
			if [[ "$VERSION" -le 7 ]]; then
				echo "ERROR: RHEL/CentOS version $VERSION is no longer supported."
				echo "OPA packages are not available for this version."
				echo "Please upgrade to RHEL/CentOS 8 or later, or use Rocky Linux 8+."
				exit 1
			fi
			DISTRIBUTION="rhel"
			;;
		sles|opensuse-leap )
			getVersionInteger
			# Check for unsupported SLES/OpenSuse versions (12 and earlier)
			if [[ "$VERSION" -lt 15 ]]; then
				echo "ERROR: SLES/OpenSuse version $VERSION is no longer supported."
				echo "OPA packages are not available for this version."
				echo "Please upgrade to SLES/OpenSuse 15 or later."
				exit 1
			fi
			DISTRIBUTION="suse"
			;;
		debian )
			# Check for unsupported Debian versions (9 and earlier)
			if [[ "$CODENAME" == "stretch" || "$CODENAME" == "jessie" ]];then
				echo "ERROR: Debian $CODENAME (version 9 or earlier) is no longer supported."
				echo "OPA packages are not available for this version."
				echo "Please upgrade to Debian 10 (buster) or later."
				exit 1
			fi
			;;
	esac
}

function getServerName(){
	# Determine the server name that will appear in OPA
	if [[ $(curl -s -w "%{http_code}\n" http://169.254.169.254/latest/dynamic/instance-identity/document -o /dev/null) == "200" ]]; then
		echo "This instance is hosted in AWS, attempting to retrieve Name tag."
		# Retrieve the instance name tag
		if [[ $(curl -s -w "%{http_code}\n" http://169.254.169.254/latest/meta-data/tags/instance/Name -o /dev/null) == "200" ]]; then
			echo "Using AWS Name tag for server name in OPA."
			INSTANCE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/Name)
		else
			echo "Unable to retrieve Name tag, using hostname for server name in OPA."
			INSTANCE_NAME=$HOSTNAME	
		fi
		echo "Instance not hosted in AWS, using hostname for server name in OPA."
		echo "Instance Name: $INSTANCE_NAME"
	else
		INSTANCE_NAME=$HOSTNAME
		echo "This host is not hosted in AWS"
	fi
	echo "Setting server name used in OPA to $INSTANCE_NAME."
}

function updatePackageManager(){
	# Add Okta OPA repository to local package manager
	case "$DISTRIBUTION" in
		amazonlinux|rhel|centos|alma|rocky )
			# Set the package manager to dnf if installed, otherwise use yum
			if which dnf >/dev/null 2>&1;then
				PACKAGE_MANAGER="dnf"
			else
				PACKAGE_MANAGER="yum"
			fi
			#adjust install command if forcing reinstall
			if [[ "$FORCE_REINSTALL" == "true" ]]; then
				REPO_INSTALL_ARG="reinstall"
			fi
			
			# Import OPA repo key
			echo "Adding Okta repository to local package manager for Amazon Linux, RHEL, CentOS, Rocky, Alma, or Oracle Linux"
			sudo rpm --import $REPO_URL/GPG-KEY-OktaPAM-2023
			
			# Create the yum repo artifact for inclusion in the package manager
			rpm_art=$(cat <<-EOF
			[oktapam-stable]
			name=Okta PAM $REPO_RPM - $DISTRIBUTION $VERSION
			baseurl=$REPO_URL/repos/rpm/$REPO_RPM/$DISTRIBUTION/$VERSION/$CPU_ARCH
			gpgcheck=1
			repo_gpgcheck=1
			enabled=1
			gpgkey=$REPO_URL/GPG-KEY-OktaPAM-2023
			EOF
			)
			
			echo -e "$rpm_art" | sudo tee /etc/yum.repos.d/oktapam.repo
			
			# Update package manager indexes
			sudo $PACKAGE_MANAGER makecache -q -y
			
			;;
		suse )
			# Use Zypper as the package manager
			PACKAGE_MANAGER="zypper"
			
			#adjust install command if forcing reinstall
			if [[ "$FORCE_REINSTALL" == "true" ]]; then
				REPO_INSTALL_ARG="install -f"
			fi
			
			echo "Adding Okta repository to local package manager for SLES or OpenSuse"
			
			# Import OPA repo key 
			sudo rpm --import $REPO_URL/GPG-KEY-OktaPAM-2023
			
			# Add/replace OPA repo to local package manager
			sudo zypper -q -n removerepo oktapam 2>>/dev/null
			sudo zypper -q -n addrepo --check --name "OktaPAM" --enable --refresh --keep-packages --gpgcheck-strict $REPO_URL/repos/rpm/$REPO_RPM/suse/$VERSION/x86_64 oktapam
			
			# Update package manager indexes
			sudo zypper refresh
			;;
		ubuntu|debian )
			# Use apt-get as the package manager
			PACKAGE_MANAGER="apt-get"
			
			#adjust install command if forcing reinstall
			if [[ "$FORCE_REINSTALL" == "true" ]]; then
				REPO_INSTALL_ARG="install --reinstall"
			fi
			
			echo "Adding Okta repository to local package manager for Ubuntu or Debian"

			# Update package manager indexes 
			sudo $PACKAGE_MANAGER update -qy
			
			# Ensure curl and gpg are installed, as they are needed to add OPA repo keys
			sudo $PACKAGE_MANAGER install -qy curl gpg
			
			# Download and unwrap OPA repo keys
			curl -fsSL $REPO_URL/GPG-KEY-OktaPAM-2023 | gpg --dearmor | sudo tee /usr/share/keyrings/oktapam-2023-archive-keyring.gpg > /dev/null
			
			# Create apt-get repo config file
			echo "deb [signed-by=/usr/share/keyrings/oktapam-2023-archive-keyring.gpg] $REPO_URL/repos/deb $CODENAME $REPO_DEB" | sudo tee /etc/apt/sources.list.d/oktapam.list
			
			# Update package manager indexes again
			sudo $PACKAGE_MANAGER update -qy
			;;
		* )
			echo "Unrecognized OS type: $DISTRIBUTION"
			exit 1
			;;
	esac
}

function createSftdConfig() {
	# Create sftd configuration file

	sudo mkdir -p /etc/sft/

	# Check if config file exists and handle accordingly
	if [ -f /etc/sft/sftd.yaml ] && [ "$FORCE_OVERWRITE_SERVER_CONFIG" != "true" ]; then
		echo "Server config /etc/sft/sftd.yaml already exists. Skipping creation."
		echo "Use -F option to force overwrite."
		return 0
	fi

	# Track if we're overwriting an existing config
	if [ -f /etc/sft/sftd.yaml ] && [ "$FORCE_OVERWRITE_SERVER_CONFIG" == "true" ]; then
		SERVER_CONFIG_OVERWRITTEN=true
		echo "Overwriting existing server config /etc/sft/sftd.yaml"
	else
		echo "Creating basic sftd configuration"
	fi

	sftdcfg=$(cat <<-EOF

	---

	# CanonicalName: Specifies the name clients should use/see when connecting to this host.

	CanonicalName: "$INSTANCE_NAME"

	EOF

	)

	echo -e "$sftdcfg" | sudo tee /etc/sft/sftd.yaml
}

function createSftdEnrollmentToken(){
	# Create an OPA Server Tools enrollment token file with the provide token value
	if [ -z "$SERVER_ENROLLMENT_TOKEN" ]; then
		echo "Unable to create sftd enrollment token. SERVER_ENROLLMENT_TOKEN is not set or is empty"
	else
		echo "Creating sftd enrollment token"

		sudo mkdir -p /var/lib/sftd

		echo "$SERVER_ENROLLMENT_TOKEN" | sudo tee /var/lib/sftd/enrollment.token
	fi
}

function createSftGatewaySetupToken(){
	# Create an OPA Gateway setup token file with the provided token value

	if [ -z "$GATEWAY_TOKEN" ]; then
		echo "Unable to create sft-gatewayd setup token. GATEWAY_TOKEN is not set or is empty"
	else
		GW_TOKEN_PATH=/var/lib/sft-gatewayd

		echo "Creating sft-gatewayd setup token"

		sudo mkdir -p $GW_TOKEN_PATH

		echo "$GATEWAY_TOKEN" | sudo tee $GW_TOKEN_PATH/setup.token
	fi
}

function checkTmpVarLogSameVolume(){
	# Check if /tmp and /var/log are on the same filesystem
	# Returns 0 if same volume, 1 if different volumes

	local tmp_device=$(df /tmp 2>/dev/null | awk 'NR==2 {print $1}')
	local varlog_device=$(df /var/log 2>/dev/null | awk 'NR==2 {print $1}')

	if [ "$tmp_device" == "$varlog_device" ]; then
		echo "/tmp and /var/log are on the same volume ($tmp_device)"
		return 0
	else
		echo "/tmp and /var/log are on different volumes (/tmp: $tmp_device, /var/log: $varlog_device)"
		return 1
	fi
}

function setupGatewaySessionTmpStorage(){
	# If /tmp and /var/log are on different volumes, create temp storage directory
	# Returns the config line to add to sft-gatewayd.yaml, or empty string if not needed

	if ! checkTmpVarLogSameVolume; then
		echo "Creating /var/log/sft/sessions/tmp for session log temporary storage"
		sudo mkdir -p /var/log/sft/sessions/tmp
		echo "SessionLogTempStorageDirectory: /var/log/sft/sessions/tmp"
	else
		echo ""
	fi
}

function createSftGwConfig(){
	# Create an OPA Gateway configuration file for handling only SSH traffic.

	# Check if config file exists and handle accordingly
	if [ -f /etc/sft/sft-gatewayd.yaml ] && [ "$FORCE_OVERWRITE_GATEWAY_CONFIG" != "true" ]; then
		echo "Gateway config /etc/sft/sft-gatewayd.yaml already exists. Skipping creation."
		echo "Use -W option to force overwrite."
		return 0
	fi

	# Track if we're overwriting an existing config
	if [ -f /etc/sft/sft-gatewayd.yaml ] && [ "$FORCE_OVERWRITE_GATEWAY_CONFIG" == "true" ]; then
		GATEWAY_CONFIG_OVERWRITTEN=true
		echo "Overwriting existing gateway config /etc/sft/sft-gatewayd.yaml"
	else
		echo "Creating gateway configuration"
	fi

	sudo mkdir -p /var/lib/sft-gatewayd

	# Check if we need to configure alternate temp storage
	SESSION_TMP_CONFIG=$(setupGatewaySessionTmpStorage)

	sftgwcfg=$(cat <<-EOF
	#Loglevel: debug

	LogFileNameFormats:
	  SSHRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"

	EOF

	)

	# Add session temp storage config if needed
	if [ -n "$SESSION_TMP_CONFIG" ]; then
		sftgwcfg="${sftgwcfg}${SESSION_TMP_CONFIG}"$'\n'
	fi

	echo -e "$sftgwcfg" | sudo tee /etc/sft/sft-gatewayd.yaml
}

function createSftGwConfigRDP(){
	# Create an OPA Gateway configuration file for handling SSH & RDP traffic.

	# Check if config file exists and handle accordingly
	if [ -f /etc/sft/sft-gatewayd.yaml ] && [ "$FORCE_OVERWRITE_GATEWAY_CONFIG" != "true" ]; then
		echo "Gateway config /etc/sft/sft-gatewayd.yaml already exists. Skipping creation."
		echo "Use -W option to force overwrite."
		return 0
	fi

	# Track if we're overwriting an existing config
	if [ -f /etc/sft/sft-gatewayd.yaml ] && [ "$FORCE_OVERWRITE_GATEWAY_CONFIG" == "true" ]; then
		GATEWAY_CONFIG_OVERWRITTEN=true
		echo "Overwriting existing gateway config /etc/sft/sft-gatewayd.yaml"
	else
		echo "Creating gateway configuration with RDP support"
	fi

	sudo mkdir -p /var/lib/sft-gatewayd

	# Check if we need to configure alternate temp storage
	SESSION_TMP_CONFIG=$(setupGatewaySessionTmpStorage)

	sftgwcfg=$(cat <<-EOF
	#Loglevel: debug

	RDP:
	  Enabled: true
	  DangerouslyIgnoreServerCertificates: true

	LogFileNameFormats:
	  SSHRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"
	  RDPRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"

	EOF

	)

	# Add session temp storage config if needed
	if [ -n "$SESSION_TMP_CONFIG" ]; then
		sftgwcfg="${sftgwcfg}${SESSION_TMP_CONFIG}"$'\n'
	fi

	echo -e "$sftgwcfg" | sudo tee /etc/sft/sft-gatewayd.yaml
}

function createSftGwConfigOrchestrator(){
	# Create an OPA Gateway configuration file for Infrastructure Orchestrator.

	# Check if config file exists and handle accordingly
	if [ -f /etc/sft/sft-gatewayd.yaml ] && [ "$FORCE_OVERWRITE_GATEWAY_CONFIG" != "true" ]; then
		echo "Gateway config /etc/sft/sft-gatewayd.yaml already exists. Skipping creation."
		echo "Use -W option to force overwrite."
		return 0
	fi

	# Track if we're overwriting an existing config
	if [ -f /etc/sft/sft-gatewayd.yaml ] && [ "$FORCE_OVERWRITE_GATEWAY_CONFIG" == "true" ]; then
		GATEWAY_CONFIG_OVERWRITTEN=true
		echo "Overwriting existing gateway config /etc/sft/sft-gatewayd.yaml"
	else
		echo "Creating Infrastructure Orchestrator gateway configuration"
	fi

	sudo mkdir -p /var/lib/sft-gatewayd

	# Check if we need to configure alternate temp storage
	SESSION_TMP_CONFIG=$(setupGatewaySessionTmpStorage)

	sftgwcfg=$(cat <<-EOF
	LogLevel: debug

	RDP:
	  Enabled: false

	Orchestrator:
	  Enabled: true
	  BinaryPath: /usr/sbin/sft-orchestrator

	EOF

	)

	# Add session temp storage config if needed
	if [ -n "$SESSION_TMP_CONFIG" ]; then
		sftgwcfg="${sftgwcfg}${SESSION_TMP_CONFIG}"$'\n'
	fi

	echo -e "$sftgwcfg" | sudo tee /etc/sft/sft-gatewayd.yaml
}

function setDefaultAdmin(){
	# Create sftd lifecycle hook scripts to grant sftd created users sudo rights.
	sudo mkdir -p /usr/lib/sftd/hooks/user-created.d
	sudo mkdir -p /usr/lib/sftd/hooks/user-deleted.d
	sftcreateuser=$(cat <<-EOF
	#!/usr/bin/env bash

	group_name="opa-admin"
	sudoers_file="/etc/sudoers.d/opa-admin"

	# Check if the group already exists
	if grep -qE "^\$group_name:" /etc/group; then
	    echo "Group \$group_name already exists."
	else
	    # Create the group
	    sudo groupadd \$group_name
	    echo "Group \$group_name created."
	fi

	# Check if the sudoers file already exists
	if [ -e "\$sudoers_file" ]; then
	    echo "Sudoers file \$sudoers_file already exists."
	else
	    # Create the sudoers file with no password prompt
	    echo "%\$group_name ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee \$sudoers_file
	    sudo chmod 440 \$sudoers_file
	    echo "Sudoers file \$sudoers_file created."
	fi

	#Add new OPA user to the adm group
	sudo usermod -aG opa-admin \${SFT_HOOK_USERNAME}

	if [ \$? -eq 0 ];then
	    echo "\${SFT_HOOK_USERNAME} added to opa-admin group for full root privileges."
	else
	    echo "Error adding \${SFT_HOOK_USERNAME} to opa-admin group, no root privileges assigned."
	fi

	EOF
	
	)
	
	sftdeleteuser=$(cat <<-EOF
	#!/usr/bin/env bash

	#Remove OPA user from the adm group
	sudo usermod -rG opa-admin \${SFT_HOOK_USERNAME}

	if [ \$? -eq 0 ];then
	    echo "\${SFT_HOOK_USERNAME} removed from opa-admin group, revoking full root privileges."
	else
	    echo "Error removing \${SFT_HOOK_USERNAME} from opa-admin group, root privileges unchanged."
	fi

	EOF
	
	)

	echo -e "$sftcreateuser" | sudo tee /usr/lib/sftd/hooks/user-created.d/assign-opa-admin.sh
	echo -e "$sftdeleteuser" | sudo tee /usr/lib/sftd/hooks/user-deleted.d/remove-opa-admin.sh
	sudo chmod 700 /usr/lib/sftd/hooks/user-created.d/assign-opa-admin.sh
	sudo chmod 700 /usr/lib/sftd/hooks/user-deleted.d/remove-opa-admin.sh
}

function installSftd(){
	# Install OPA Server tools
	case "$DISTRIBUTION" in
		suse )
			sudo $PACKAGE_MANAGER -q -n $REPO_INSTALL_ARG scaleft-server-tools
			;;
		* )
			sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-server-tools -qy
			;;
	esac
}

function installSft(){
	# Install OPA Client tools
	case "$DISTRIBUTION" in
		suse )
			sudo $PACKAGE_MANAGER -q -n $REPO_INSTALL_ARG scaleft-client-tools
			;;
		* )
			sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-client-tools -q -y
			;;
	esac
}

function installSft-Gateway(){
	# Install OPA Gateway
	if [[ "$CREATE_ORCHESTRATOR_GATEWAY" == "true" ]]; then
		# Use orchestrator config regardless of OS
		createSftGwConfigOrchestrator
	elif [[ "$DISTRIBUTION" == "rhel" && ( "$VERSION" == "8" || "$VERSION" == "9" ) ]] || [[ "$DISTRIBUTION" == "ubuntu" && ( "$VERSION" == "20.04" || "$VERSION" == "22.04" || "$VERSION" == "24.04" ) ]]; then
		sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-rdp-transcoder -q -y
		createSftGwConfigRDP
	else
		createSftGwConfig
	fi
	case "$DISTRIBUTION" in
		suse )
			sudo $PACKAGE_MANAGER -q -n $REPO_INSTALL_ARG scaleft-gateway
			;;
		* )
			sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-gateway -q -y
			;;
	esac
}

function enableSshPasswordAuth() {
	# Enable password authentication for SSH
	echo "Enabling SSH password authentication..."
	sudo mkdir -p /etc/ssh/sshd_config.d
	echo "PasswordAuthentication yes" | sudo tee /etc/ssh/sshd_config.d/05-opa-settings.conf > /dev/null
	SSHD_NEEDS_RELOAD=true
	echo "SSH password authentication enabled. SSH daemon will be reloaded."
}

function createTestAdminUser() {
	# Create a test user with sudo privileges
	local username="$1"
	echo "Creating test admin user: $username"
	if id "$username" &>/dev/null; then
		echo "User '$username' already exists. Skipping creation."
	else
		sudo useradd -m -s /bin/bash "$username"
		echo "User '$username' created."
	fi

	local sudoers_file="/etc/sudoers.d/99-test-user-$username"
	echo "$username ALL=(ALL) NOPASSWD:ALL" | sudo tee "$sudoers_file" > /dev/null
	sudo chmod 440 "$sudoers_file"
	echo "Sudo privileges granted to '$username'."
}

function createTestUser() {
	# Create a test user without sudo privileges
	local username="$1"
	echo "Creating test user: $username"
	if id "$username" &>/dev/null; then
		echo "User '$username' already exists. Skipping creation."
	else
		sudo useradd -m -s /bin/bash "$username"
		echo "User '$username' created."
	fi
}

function reloadSshd() {
    #check SSHD configuration to prevent bricking SSH access
	echo "Validating SSHD configuration before applying..."
	if command -v sshd >/dev/null 2>&1; then
		if ! sudo sshd -t; then
			echo "ERROR: sshd config test failed. Not reloading SSH."
			return 1
		fi
		echo "SSHD config validation OK."
	else
		echo "WARNING: sshd binary not found; skipping syntax validation."
	fi

	echo "Applying SSHD config change (reload preferred; restart only if reload fails)..."

	# Try in order: systemd ssh, systemd sshd, sysv ssh, sysv sshd.
	if command -v systemctl >/dev/null 2>&1; then
		if systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx 'ssh.service'; then
			sudo systemctl reload ssh.service 2>/dev/null || sudo systemctl restart ssh.service
			echo "ssh.service reloaded/restarted."
			return 0
		fi
		if systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}' | grep -qx 'sshd.service'; then
			sudo systemctl reload sshd.service 2>/dev/null || sudo systemctl restart sshd.service
			echo "sshd.service reloaded/restarted."
			return 0
		fi
	fi

	if command -v service >/dev/null 2>&1; then
		if sudo service ssh reload 2>/dev/null || sudo service ssh restart 2>/dev/null; then
			echo "ssh service reloaded/restarted via 'service'."
			return 0
		elif sudo service sshd reload 2>/dev/null || sudo service sshd restart 2>/dev/null; then
			echo "sshd service reloaded/restarted via 'service'."
			return 0
		fi
	fi

	echo "WARNING: SSH service manager not found. Config applied but SSH not reloaded."
}

function restartSftd() {
	# Restart the sftd (server agent) service
	echo "Restarting sftd service to apply configuration changes..."

	if command -v systemctl >/dev/null 2>&1; then
		sudo systemctl restart sftd.service
		if [ $? -eq 0 ]; then
			echo "sftd service restarted successfully."
		else
			echo "WARNING: Failed to restart sftd service."
		fi
	elif command -v service >/dev/null 2>&1; then
		sudo service sftd restart
		if [ $? -eq 0 ]; then
			echo "sftd service restarted successfully."
		else
			echo "WARNING: Failed to restart sftd service."
		fi
	else
		echo "WARNING: Service manager not found. Unable to restart sftd."
	fi
}

function restartSftGatewayd() {
	# Restart the sft-gatewayd (gateway) service
	echo "Restarting sft-gatewayd service to apply configuration changes..."

	if command -v systemctl >/dev/null 2>&1; then
		sudo systemctl restart sft-gatewayd.service
		if [ $? -eq 0 ]; then
			echo "sft-gatewayd service restarted successfully."
		else
			echo "WARNING: Failed to restart sft-gatewayd service."
		fi
	elif command -v service >/dev/null 2>&1; then
		sudo service sft-gatewayd restart
		if [ $? -eq 0 ]; then
			echo "sft-gatewayd service restarted successfully."
		else
			echo "WARNING: Failed to restart sft-gatewayd service."
		fi
	else
		echo "WARNING: Service manager not found. Unable to restart sft-gatewayd."
	fi
}

function checkNoProxy() {
	# Attempt to detect presence of tls-inspecting web proxy
	# Define your target domain and the expected public key fingerprints (SHA-256)
	# Set target website and known fingerprints
	website="dist.scaleft.com"
	known_server_cert_sha256_fingerprint="36A5672BA44AF889214EDA999B5556C036D1293079EFFEFC37D2A91033619434"
	known_intermediate_cert_sha256_fingerprint="B0F330A31A0C50987E1C3A7BB02C2DDA682991D3165B517BD44FBA4A6020BD94"

	# Get certificate chain
	cert_chain=$(openssl s_client -showcerts -connect "$website:443" -servername "$website" < /dev/null 2>/dev/null)

	# Extract server and intermediate certificates
	server_cert=$(echo "$cert_chain" | awk '/BEGIN CERT/,/END CERT/ {print}')
	intermediate_cert=$(echo "$cert_chain" | awk '/BEGIN CERT/{i++} i==2,/END CERT/ {print}')

	# Calculate SHA-256 fingerprints
	server_cert_sha256_fingerprint=$(echo "$server_cert" | openssl x509 -noout -fingerprint -sha256 | cut -d'=' -f2 | tr -d ':')
	intermediate_cert_sha256_fingerprint=$(echo "$intermediate_cert" | openssl x509 -noout -fingerprint -sha256 | cut -d'=' -f2 | tr -d ':')

	# Compare the calculated fingerprints with the known fingerprints
	if [[ "$server_cert_sha256_fingerprint" == "$known_server_cert_sha256_fingerprint" ]] && [[ "$intermediate_cert_sha256_fingerprint" == "$known_intermediate_cert_sha256_fingerprint" ]]; then
		echo "Server and Intermediate public key fingerprint checks PASSED."
	else
		if [[ "$server_cert_sha256_fingerprint" != "$known_server_cert_sha256_fingerprint" ]]; then
			echo "The server certificate fingerprint FAILED.  Now checking the intermediate cert fingerprint."
			# Check if the fetched intermediate CA key fingerprint matches the expected one
			if [[ "$intermediate_cert_sha256_fingerprint" != "$known_intermediate_cert_sha256_fingerprint" ]]; then
				echo "$website fingerprint check: FAILED"
				echo "Intermediate CA fingerprint check: FAILED"
				echo "************** Possible MITM Detected **************"
				echo "Okta Advanced Server Access uses certificate pinning to prevent MITM attacks."
				echo "Transparent web proxies that perform TLS inspection replace Okta's certificates"
				echo "with their own, causing the pinned certificate check to fail.  This will prevent"
				echo "OPA agents, gateways, and clients from successfully connecting to the OPA platform,"
				echo "causing enrollment, user & group provisioning, and audit logging to fail."
				echo "For OPA to function, you'll need to contact your web-proxy administrators and"
				echo "request the addition of *.scaleft.com, *.okta.com, and *.oktapreview.com to the"
				echo "tls-inspection exclusion list."
				exit 1					
			else
				echo "Intermediate CA fingerprint matches expected value, but the fingerprint check for $website FAILED."
			fi
		fi
	fi
}

#------------------------
# Main script body below

# Verify that required executables are available on the system
check_required_executables

INSTALLED_SOMETHING=false

# Parse command line options for overrides to static variable sets
while getopts ":S:G:U:u:sagcr:phfEFWO" opt; do
	case ${opt} in
		a )
			DEFAULT_TO_ADMIN=true
		;;
		s|S )
			INSTALL_SERVER_TOOLS=true
			if [[ "$OPTARG" =~ ^-.* ]]; then
				# If the next argument is another option, assume no enrollment token was provided
				((OPTIND--))
			else
				SERVER_ENROLLMENT_TOKEN=$OPTARG
			fi
		;;
		f )
			FORCE_REINSTALL=true
			;;
		F )
			FORCE_OVERWRITE_SERVER_CONFIG=true
			;;
		g|G )
			INSTALL_GATEWAY=true
			if [[ "$OPTARG" =~ ^-.* ]]; then
				# If the next argument is another option, assume no gateway token was provided
				((OPTIND--))
			else
				GATEWAY_TOKEN=$OPTARG
			fi
			;;
		W )
			FORCE_OVERWRITE_GATEWAY_CONFIG=true
			;;
		O )
			CREATE_ORCHESTRATOR_GATEWAY=true
			;;
		c )
			INSTALL_CLIENT_TOOLS=true
			;;
		r )
			if [ "$OPTARG" == "test" ]; then
				REPOSITORY="test"
			elif [ "$OPTARG" != "prod" ]; then
				echo "Invalid argument for -r: $OPTARG. Valid options are 'prod' and 'test'" >&2
				exit 1
			fi
			;;
		p )
			PROXY_CHECK_ENABLED=true
			;;
		E )
			ENABLE_SSH_PASSWORD_AUTH=true
			;;
		U )
			CREATE_TEST_ADMIN_USER=$OPTARG
			;;
		u )
			CREATE_TEST_USER=$OPTARG
			;;
		h )
			echo "Usage: $(basename "$0") [options]"
			echo "    -a                          Create agent lifecycle hooks to grant sudo to all sftd created users."
			echo "    -s                          Install OPA Server Tools without providing an enrollment token."
			echo "    -S server_enrollment_token  Install OPA Server Tools with the provided enrollment token."
			echo "    -f                          Force re-installation of existing packages."
			echo "    -F                          Force overwrite of server config (/etc/sft/sftd.yaml) if it exists."
			echo "    -g                          Install OPA Gateway without providing a gateway setup token."
			echo "    -G gateway_setup_token      Install OPA Gateway with the provided gateway token."
			echo "    -W                          Force overwrite of gateway config (/etc/sft/sft-gatewayd.yaml) if it exists."
			echo "    -O                          Create an Infrastructure Orchestrator gateway config (use with -g/-G to install)."
			echo "    -c                          Install OPA Client Tools."
			echo "    -r                          Set installation branch, default is prod."
			echo "    -E                          Enable password authentication for SSH."
			echo "    -U username                 Create a test user with sudo privileges."
			echo "    -u username                 Create a test user without sudo privileges."
			echo "    -p                          Skip detection of TLS inspection web proxy."
			echo "    -h                          Display this help message."
			exit 0
			;;
		\? )
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		: )
			# Options S, G, U, u, r require an argument.
			if [[ "SGUur" =~ $OPTARG ]]; then
				echo "Option -$OPTARG requires an argument." >&2
				exit 1
			fi
			;;
	esac
done

# Verify that there is no web proxy inspecting TLS that will interfere with agent installation and function
if [[ "$PROXY_CHECK_ENABLED" == "true" ]];then
	checkNoProxy
else
	echo "Skipping TLS inspection web proxy check.  Note that the presence of such a proxy will cause"
	echo "agent enrollment and checkins to fail."
fi

# Execute new functions based on command-line flags
if [[ "$ENABLE_SSH_PASSWORD_AUTH" == "true" ]]; then
	enableSshPasswordAuth
	INSTALLED_SOMETHING=true
fi

if [[ -n "$CREATE_TEST_ADMIN_USER" ]]; then
	createTestAdminUser "$CREATE_TEST_ADMIN_USER"
	INSTALLED_SOMETHING=true
fi

if [[ -n "$CREATE_TEST_USER" ]]; then
	createTestUser "$CREATE_TEST_USER"
	INSTALLED_SOMETHING=true
fi

# Handle -F flag without -s/-S: overwrite server config and prepare to restart
if [[ "$FORCE_OVERWRITE_SERVER_CONFIG" == "true" ]] && [[ "$INSTALL_SERVER_TOOLS" != "true" ]]; then
	getOsData
	getServerName
	createSftdConfig
	INSTALLED_SOMETHING=true
fi

# Handle -W or -O flags without -g/-G: overwrite gateway config and prepare to restart
if [[ ("$FORCE_OVERWRITE_GATEWAY_CONFIG" == "true" || "$CREATE_ORCHESTRATOR_GATEWAY" == "true") && "$INSTALL_GATEWAY" != "true" ]]; then
	getOsData
	if [[ "$CREATE_ORCHESTRATOR_GATEWAY" == "true" ]]; then
		createSftGwConfigOrchestrator
	else
		# Determine which gateway config to create based on OS
		if [[ "$DISTRIBUTION" == "rhel" && ( "$VERSION" == "8" || "$VERSION" == "9" ) ]] || [[ "$DISTRIBUTION" == "ubuntu" && ( "$VERSION" == "20.04" || "$VERSION" == "22.04" || "$VERSION" == "24.04" ) ]]; then
			createSftGwConfigRDP
		else
			createSftGwConfig
		fi
	fi
	INSTALLED_SOMETHING=true
fi

# If something needs to be installed, collect necessary information and update the package manager
if [[ "$INSTALL_SERVER_TOOLS" == "true" ]] || [[ "$INSTALL_GATEWAY" == "true" ]] || [[ "$INSTALL_CLIENT_TOOLS" == "true" ]]; then
	setRepoUrl
	getOsData
	updatePackageManager
fi

# Perform necessary steps to install OPA Server Tools
if [[ "$INSTALL_SERVER_TOOLS" == "true" ]];then
	getServerName
	createSftdConfig
	createSftdEnrollmentToken
	installSftd
	INSTALLED_SOMETHING=true
fi

# Perform necessary steps to install OPA gateway
if [[ "$INSTALL_GATEWAY" == "true" ]];then
	createSftGatewaySetupToken
	installSft-Gateway
	INSTALL_CLIENT_TOOLS=true
	INSTALLED_SOMETHING=true
fi

# Perform necessary steps to install OPA Client Tools
if [[ "$INSTALL_CLIENT_TOOLS" == "true" ]];then
	installSft
	INSTALLED_SOMETHING=true
fi

# Perform necessary steps to force sftd created users to have sudo rights
if [[ "$DEFAULT_TO_ADMIN" == "true" ]];then
	setDefaultAdmin
	echo "ScaleFT-Server-Tools lifecycle hooks created to ensure sftd provisioned users have sudo rights."
fi

# Reload sshd if any changes were made that require it
if [[ "$SSHD_NEEDS_RELOAD" = "true" ]]; then
    reloadSshd
fi

# Restart sftd if config was overwritten but no fresh installation was done
if [[ "$SERVER_CONFIG_OVERWRITTEN" == "true" ]] && [[ "$INSTALL_SERVER_TOOLS" != "true" ]]; then
	restartSftd
fi

# Restart sft-gatewayd if config was overwritten but no fresh installation was done
if [[ "$GATEWAY_CONFIG_OVERWRITTEN" == "true" ]] && [[ "$INSTALL_GATEWAY" != "true" ]]; then
	restartSftGatewayd
fi

if [[ "$INSTALLED_SOMETHING" == "false" ]];then
	echo "No module(s) selected for installation, exiting."
	exit 1
fi
exit 0
