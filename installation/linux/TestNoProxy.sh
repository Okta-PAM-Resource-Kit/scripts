#!/usr/bin/env bash

# This script is intended as a POC preparedness validation to ensure there are no transparent
# web proxies performing TLS inspection that will cause the certificate pinning use by ASA/OPA
# agents to fail, resulting in MITM detection.

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
checkNoProxy
