#!/usr/bin/env bash

# For headless installation, key variables are initialized below with the appropriate default values.  
# Run with script with -h option for command line options
# This script is provided as-is, with no support or warranty expressed or implied, use at your own risk!

# To install the ASA server agent, set the following value to true:
INSTALL_SERVER_TOOLS=false

# Except when using an AWS or GCP account/project linked with an ASA project, 
# an enrollment token for the server agent is required.
# If using an enrollment token, place the token in between the quotes in the  
# following line:
SERVER_ENROLLMENT_TOKEN=""

# To leverage ASA for machine to machine authentication, the ASA client tools are required.
# To install the ASA client tools, set the following value to true:
INSTALL_CLIENT_TOOLS=false
# ASA Client tools will automatically be installed with the ASA Gateway service
# for use in decoding SSH and RDP session recordings.

# To install the ASA Gateway service, set the following value to true:
INSTALL_GATEWAY=false
# When installing ASA Gateway service, place the gateway setup token between the quotes
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
PROXY_CHECK_ENABLED=true

# In Okta Privilege Access, course grained privilege elevation (admin checkbox in UI) is not currently 
# supported. Therefore users create by the sftd agent will be normal users with no sudo rights.  Change
# the below value to true to have this script automatically create agent lifecycle hooks that well
# force all sftd created users to have full sudo rights, just like checking the admin box in the ASA UI.
DEFAULT_TO_ADMIN=false

# By default, this script will not reinstall the current version of the ASA agents.  Change the below
# value to "true" to force reinstallation.
FORCE_REINSTALL=false

# Install arguments will be updated automatically based on the FORCE_REINSTALL flag above.  Do not change
# the default setting below.
REPO_INSTALL_ARG="install"

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

	# Make necessary adjustments to align with ASA repo structure
	case "$DISTRIBUTION" in
		amzn )
			DISTRIBUTION="amazonlinux"
			;;
		rocky )
			getVersionInteger
			DISTRIBUTION="rhel"
			;;
		rhel )
			getVersionInteger
			;;
		freebsd )
			getVersionInteger
			if [[ "$CPU_ARCH" == "x86_64" ]];then
				CPU_ARCH="amd64"
			fi
			;;
		sles|opensuse-leap )
			getVersionInteger
			DISTRIBUTION="suse"
			;;		
		debian )
			# debian stretch is no longer an ASA supported OS so there's no path for it in the repository
			# however, packages for buster may continue to function on stretch even though that OS is no
			# longer included in unit or regression testing. 
			if [[ "$CODENAME" == "stretch" ]];then
				CODENAME="buster"
			fi
			;;
	esac
}

function getServerName(){
	# Determine the server name that will appear in ASA
	if [[ $(curl -s -w "%{http_code}\n" http://169.254.169.254/latest/dynamic/instance-identity/document -o /dev/null) == "200" ]]; then
		echo "This instance is hosted in AWS, attempting to retrieve Name tag."
		# Retrieve the instance name tag
		if [[ $(curl -s -w "%{http_code}\n" http://169.254.169.254/latest/meta-data/tags/instance/Name -o /dev/null) == "200" ]]; then
			echo "Using AWS Name tag for server name in ASA."
			INSTANCE_NAME=$(curl -s http://169.254.169.254/latest/meta-data/tags/instance/Name)
		else
			echo "Unable to retrieve Name tag, using hostname for server name in ASA."
			INSTANCE_NAME=$HOSTNAME	
		fi
		echo "Instance not hosted in AWS, using hostname for server name in ASA."
		echo "Instance Name: $INSTANCE_NAME"
	else
		INSTANCE_NAME=$HOSTNAME
		echo "This host is not hosted in AWS"
	fi
	echo "Setting server name used in ASA to $INSTANCE_NAME."
}

function updatePackageManager(){
	# Add Okta ASA/OPA repository to local package manager
	case "$DISTRIBUTION" in
		amazonlinux|rhel|centos|alma|fedora|rocky )
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
			
			# Import ASA repo key 
			echo "Adding Okta repository to local package manager for Amazon Linux, RHEL, CentOS, Alma, or Fedora"
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
			sudo $PACKAGE_MANAGER makecache -qy
			
			;;
		suse )
			# Use Zypper as the package manager
			PACKAGE_MANAGER="zypper"
			
			#adjust install command if forcing reinstall
			if [[ "$FORCE_REINSTALL" == "true" ]]; then
				REPO_INSTALL_ARG="install -f"
			fi
			
			echo "Adding Okta repository to local package manager for SLES or OpenSuse"
			
			# Import ASA repo key 
			sudo rpm --import $REPO_URL/GPG-KEY-OktaPAM-2023
			
			# Add/replace ASA repo to local package manager
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
			
			# Ensure curl and gpg are installed, as they are needed to add ASA repo keys
			sudo $PACKAGE_MANAGER install -qy curl gpg
			
			# Download and unwrap ASA repo keys
			curl -fsSL $REPO_URL/GPG-KEY-OktaPAM-2023 | gpg --dearmor | sudo tee /usr/share/keyrings/oktapam-2023-archive-keyring.gpg > /dev/null
			
			# Create apt-get repo config file
			echo "deb [signed-by=/usr/share/keyrings/oktapam-2023-archive-keyring.gpg] $REPO_URL/repos/deb $CODENAME $REPO_DEB" | sudo tee /etc/apt/sources.list.d/oktapam.list
			
			# Update package manager indexes again
			sudo $PACKAGE_MANAGER update -qy
			;;
		freebsd )
			#adjust install command if forcing reinstall
			if [[ "$FORCE_REINSTALL" == "true" ]]; then
				REPO_INSTALL_ARG="install -f"
			fi
			
			# There is currenlty no pkg repo integration, so downloading the packages locally for installation
			pkg_base_url="$REPO_URL/repos/$DISTRIBUTION/$REPO_BSD/$VERSION/$CPU_ARCH"

			# Use cURL to get the directory listing from the URL
			response=$(curl -s $pkg_base_url/)

			# Use grep to extract the directories from the response
			pkg_versions=$(echo "$response" | grep -o ">[0-9.]*<" | tr -d '<>' | sort -V)

			# Get the highest version directory from the list
			highest_version=$(echo "$pkg_versions" | tail -n1 )

			# Download the latest packages
			curl -O "$pkg_base_url/$highest_version/scaleft-server-tools-$highest_version.pkg"
			curl -O "$pkg_base_url/$highest_version/scaleft-client-tools-$highest_version.pkg"
			curl -O "$pkg_base_url/$highest_version/scaleft-gateway-$highest_version.pkg"
			;;
		* )
			echo "Unrecognized OS type: $DISTRIBUTION"
			exit 1
			;;
	esac
}

function createSftdConfig() {
	# Create sftd configuration file

	echo "Creating basic sftd configuration"
	sudo mkdir -p /etc/sft/

	sftdcfg=$(cat <<-EOF
	
	---
	
	# CanonicalName: Specifies the name clients should use/see when connecting to this host.
	
	CanonicalName: "$INSTANCE_NAME"
	
	EOF
	
	)

	echo -e "$sftdcfg" | sudo tee /etc/sft/sftd.yaml
}

function createSftdEnrollmentToken(){
	# Create an ASA Server Tools enrollment token file with the provide token value
	if [ -z "$SERVER_ENROLLMENT_TOKEN" ]; then
		echo "Unable to create sftd enrollment token. SERVER_ENROLLMENT_TOKEN is not set or is empty"
	else
		echo "Creating sftd enrollment token"

		sudo mkdir -p /var/lib/sftd

		echo "$SERVER_ENROLLMENT_TOKEN" | sudo tee /var/lib/sftd/enrollment.token
	fi
}

function createSftGatewaySetupToken(){
	# Create an ASA Gateway setup token file with the provided token value
	
	if [ -z "$GATEWAY_TOKEN" ]; then
		echo "Unable to create sft-gatewayd setup token. GATEWAY_TOKEN is not set or is empty"
	else
		case "$DISTRIBUTION" in 
			freebsd )
				GW_TOKEN_PATH=/var/db/sft-gatewayd
				;;
			* )
				GW_TOKEN_PATH=/var/lib/sft-gatewayd
				;;
		esac

		echo "Creating sft-gatewayd setup token"

		sudo mkdir -p $GW_TOKEN_PATH

		echo "$GATEWAY_TOKEN" | sudo tee $GW_TOKEN_PATH/setup.token
	fi
}

function createSftGwConfigRDP(){
	# Create an ASA Gateway configuration file for handling SSH & RDP traffic.
	sudo mkdir -p /var/lib/sft-gatewayd
	sftgwcfg=$(cat <<-EOF
	#Loglevel: debug

	LDAP:
	  StartTLS: false

	RDP:
	  Enabled: true
	  DangerouslyIgnoreServerCertificates: true

	LogFileNameFormats:
	  SSHRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"
	  RDPRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"

	EOF
	
	)
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

function createSftGwConfig(){
	# Create an ASA Gateway configuration file for handling only SSH traffic.
	sudo mkdir -p /var/lib/sft-gatewayd
	sftgwcfg=$(cat <<-EOF
	#Loglevel: debug
	
	LogFileNameFormats:
	  SSHRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"
	
	EOF

	)
	echo -e "$sftgwcfg" | sudo tee /etc/sft/sft-gatewayd.yaml
}

function installSftd(){
	# Install ASA Server tools
	case "$DISTRIBUTION" in 
		freebsd )
			sudo pkg $REPO_INSTALL_ARG -y libsecret
			sudo pkg $REPO_INSTALL_ARG -y ./scaleft-server-tools-$highest_version.pkg
			sudo sysrc sftd_enable=YES
			sudo service sftd start
			;;
		suse )
			sudo $PACKAGE_MANAGER -q -n $REPO_INSTALL_ARG scaleft-server-tools
			;;
		* )
			sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-server-tools -qy
			;;
	esac
}

function installSft(){
	# Install ASA Client tools
	case "$DISTRIBUTION" in 
		freebsd )
			sudo pkg $REPO_INSTALL_ARG -y ./scaleft-client-tools-$highest_version.pkg
			;;
		suse )
			sudo $PACKAGE_MANAGER -q -n $REPO_INSTALL_ARG scaleft-client-tools
			;;
		* )
			sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-client-tools -qy
			;;
	esac
}

function installSft-Gateway(){
	# Install ASA Gateway
	if [[ "$DISTRIBUTION" == "rhel" && "$VERSION" == "8" ]] || [[ "$DISTRIBUTION" == "ubuntu" && ( "$VERSION" == "20.04" || "$VERSION" == "22.04" ) ]]; then
		sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-rdp-transcoder -qy
		createSftGwConfigRDP
	else
		createSftdConfig
	fi
	case "$DISTRIBUTION" in 
		freebsd )
			sudo pkg $REPO_INSTALL_ARG -y ./scaleft-gateway-$highest_version.pkg
			sudo mkdir /var/log/sft/sessions
			sudo sysrc sft_gatewayd_enable=YES
			sudo service sft-gatewayd start
			;;
		suse )
			sudo $PACKAGE_MANAGER -q -n $REPO_INSTALL_ARG scaleft-gateway
			;;
		* )
			sudo $PACKAGE_MANAGER $REPO_INSTALL_ARG scaleft-gateway -qy
			;;
	esac
}

function checkNoProxy() {
	# Attempt to detect presence of tls-inspecting web proxy
	# Define your target domain and the expected public key fingerprints (SHA-256)
	# Set target website and known fingerprints
	website="dist.scaleft.com"
	known_server_cert_sha256_fingerprint="46DBEC3BE9BF82793E7BCC8944A5E1A537FA6FB39671F0042E73240BA37B1231"
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
				echo "ASA agents, gateways, and clients from successfully connecting to the ASA platform,"
				echo "causing enrollment, user & group provisioning, and audit logging to fail."
				echo "For ASA to function, you'll need to contact your web-proxy administrators and"
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
while getopts ":S:G:sagcr:phf" opt; do
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
		g|G )
			INSTALL_GATEWAY=true
			if [[ "$OPTARG" =~ ^-.* ]]; then
				# If the next argument is another option, assume no gateway token was provided
				((OPTIND--))
			else
				GATEWAY_TOKEN=$OPTARG
			fi
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
			PROXY_CHECK_ENABLED=false
			;;
		h )
			echo "Usage: LinuxAndBsdAsaInstall.sh [-s] [-S server_enrollment_token] [-g] [-G gateway_setup_token] [-c|-r [prod|test]] [-p] [-h] "
			echo "    -a                          Create agent lifecycle hooks to grant sudo to all sftd created users."
			echo "    -s                          Install ASA Server Tools without providing an enrollment token."
			echo "    -S server_enrollment_token  Install ASA Server Tools with the provided enrollment token."
			echo "    -f                          Force re-installation of existing packages."
			echo "    -g                          Install ASA Gateway without providing a gateway setup token."
			echo "    -G gateway_setup_token      Install ASA Gateway with the provided gateway token."
			echo "    -c                          Install ASA Client Tools."
			echo "    -r                          Set installation branch, default is prod."
			echo "    -p                          Skip detection of TLS inspection web proxy."
			echo "    -h                          Display this help message."
			exit 0
			;;
		\? )
			echo "Invalid option: -$OPTARG" >&2
			exit 1
			;;
		: )
			if [ "$OPTARG" == "s" ]; then
				# The -s option is missing an argument, but it's optional, so just ignore the error
				continue
			else
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

# If something needs to be installed, collect necessary information and update the package manager
if [[ "$INSTALL_SERVER_TOOLS" == "true" ]] || [[ "$INSTALL_GATEWAY" == "true" ]] || [[ "$INSTALL_CLIENT_TOOLS" == "true" ]];then
	setRepoUrl
	getOsData
	updatePackageManager
fi

# Perform necessary steps to install ASA Server Tools
if [[ "$INSTALL_SERVER_TOOLS" == "true" ]];then
	getServerName
	createSftdConfig
	createSftdEnrollmentToken
	installSftd
	INSTALLED_SOMETHING=true
fi

# Perform necessary steps to install ASA gateway
if [[ "$INSTALL_GATEWAY" == "true" ]];then
	createSftGatewaySetupToken
	installSft-Gateway
	INSTALL_CLIENT_TOOLS=true
	INSTALLED_SOMETHING=true
fi

# Perform necessary steps to install ASA Client Tools
if [[ "$INSTALL_CLIENT_TOOLS" == "true" ]];then
	installSft
	INSTALLED_SOMETHING=true
fi

# Perform necessary steps to force sftd created users to have sudo rights
if [[ "$DEFAULT_TO_ADMIN" == "true" ]];then
	setDefaultAdmin
	echo "ScaleFT-Server-Tools lifecycle hooks created to ensure sftd provisioned users have sudo rights."
fi

if [[ "$INSTALLED_SOMETHING" == "false" ]];then
	echo "No module(s) selected for installation, exiting."
	exit 1
fi
exit 0
