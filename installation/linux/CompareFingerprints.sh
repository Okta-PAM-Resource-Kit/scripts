#!/bin/bash

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
    echo "Both server and intermediate certificate fingerprints match the known values"
else
    if [[ "$server_cert_sha256_fingerprint" != "$known_server_cert_sha256_fingerprint" ]]; then
        echo "The server certificate fingerprint does NOT match the known value"
        echo "Expected: $known_server_cert_sha256_fingerprint"
        echo "Actual: $server_cert_sha256_fingerprint"
    fi
    if [[ "$intermediate_cert_sha256_fingerprint" != "$known_intermediate_cert_sha256_fingerprint" ]]; then
        echo "The intermediate certificate fingerprint does NOT match the known value"
        echo "Expected: $known_intermediate_cert_sha256_fingerprint"
        echo "Actual: $intermediate_cert_sha256_fingerprint"
    fi
fi
