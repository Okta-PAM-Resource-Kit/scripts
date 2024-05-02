#!/bin/bash

# Set target website and known fingerprints
website="dist.scaleft.com"
known_server_cert_sha256_fingerprint="52472EFADBD13DD93CC5F5E57F7F6808D64C5C691F79554BF3FA8252745BA10A"
known_intermediate_cert_sha256_fingerprint="BF8A69027BCC8D2D42A6E6D25BDD4873F6A34B8F90EDF07E86C5D6916DA0B933"

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
