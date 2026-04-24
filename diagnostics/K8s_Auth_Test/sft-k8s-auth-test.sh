#!/usr/bin/env bash

# This script is intended to validate your ASA/OPA Kubernetes configuration.
# Review and understand what the script is doing before executing!

# This script is provided as-is, with no support or warranty expressed or implied, use at your own risk!

# Define the required executables and their minimum versions
required_executables=(kubectl yq cut base64 jq curl)

# Check if the required executables are installed and if their versions are sufficient
check_required_executables() {
  for (( i=0; i<${#required_executables[@]}; i++ )); do
    executable=${required_executables[i]}
    version=${required_versions[i]}
    if ! command -v "$executable" &> /dev/null; then
      echo "ERROR: $executable is not installed"
      exit 1
    fi
  done
}

# Check for required executables and their versions
check_required_executables

provider=asa.okta.com
context_name=""
context_user=""
context_cluster=""
sft_cluster_id=""
asa_team_name=""

# Get a list of available contexts
contexts=$(kubectl config get-contexts -o name | cut -d'/' -f2)
num_contexts=$(echo "$contexts" | wc -l)
if [[ $num_contexts -eq 0 ]]; then
  echo "No contexts found"
  exit 1
fi

# Print out the numbered list of contexts
echo "Available contexts:"
echo "$contexts" | nl -w 3 -s ")  "

# Prompt the user to select a context from the list
read -p "Enter the number of the context to use: " context_num
if ! [[ "$context_num" =~ ^[0-9]+$ ]]; then
  echo "Invalid input: $context_num"
  exit 1
fi
if (( context_num < 1 || context_num > num_contexts )); then
  echo "Invalid context number: $context_num"
  exit 1
fi
context_name=$(echo "$contexts" | sed "${context_num}q;d")

# Get the current Kubernetes configuration and extract the relevant information for the selected context
config=$(kubectl config view -o yaml)
context=$(echo "$config" | yq -r ".contexts[] | select(.name == \"$context_name\")")
if [[ -z $context ]]; then
  echo "Invalid context name: $context_name"
  exit 1
fi
context_user=$(echo "$context" | yq -r ".context.user")
context_cluster=$(echo "$context" | yq -r ".context.cluster")
cluster_server=$(echo "$config" | yq -r ".clusters[] | select(.name == \"$context_cluster\") | .cluster.server")
extensions=$(echo "$context" | yq -r ".context.extensions[] | select(.extension.provider == \"$provider\")")

# Extract the sft-cluster-id and asa_team_name from the extensions section (if available)
if [[ -n $extensions ]]; then
  sft_cluster_id=$(echo "$extensions" | yq -r ".extension.\"sft-cluster-id\"")
  asa_team_name=$(echo "$context_user" | cut -d'@' -f2)
fi

# Print out the extracted information
echo "Context: $context_name"
echo "User: $context_user"
echo "Cluster: $context_cluster"
if [[ -n $sft_cluster_id ]]; then
  echo 
  echo "sft-cluster-id: $sft_cluster_id"
  echo
  echo "Running command: $SFT_COMMAND"
  SFT_COMMAND="sft k8s auth --cluster-id $sft_cluster_id"

  # Call the API using curl and extract the token using jq
  TOKEN=$($SFT_COMMAND | jq -r '.status.token')

  # Display the token
  echo
  echo "The returned JWT is:"
  echo $TOKEN
  echo 
  TOKEN_JSON=$(jq -R 'split(".") |.[0:2] | map(@base64d) | map(fromjson)' <<< $TOKEN)
  echo "JWT raw JSON output:"
  echo $TOKEN_JSON
  
  exp=$(echo "$TOKEN_JSON" | jq -r '.[1].exp')
  iat=$(echo "$TOKEN_JSON" | jq -r '.[1].iat')
  nbf=$(echo "$TOKEN_JSON" | jq -r '.[1].nbf')

  exp_date=$(date -r "$exp" +"%Y-%m-%d %H:%M:%S %Z")
  iat_date=$(date -r "$iat" +"%Y-%m-%d %H:%M:%S %Z")
  nbf_date=$(date -r "$nbf" +"%Y-%m-%d %H:%M:%S %Z")

  aud=$(echo "$TOKEN_JSON" | jq -r '.[1].aud[0]')
  iss=$(echo "$TOKEN_JSON" | jq -r '.[1].iss')
  groups=$(echo "$TOKEN_JSON" | jq -r '.[1].groups[0]')
  sub=$(echo "$TOKEN_JSON" | jq -r '.[1].sub')
  
  # Print the extracted fields in human-readable format
  echo
  echo "JWT issuer: $iss"
  echo "JWT aud: $aud"
  echo "JWT groups: $groups"
  echo "JWT sub: $sub"
  echo "JWT Expiration: $exp_date"
  echo "JWT Issued: $iat_date"
  echo "JWT Not Valid Before: $nbf_date"
  echo
  echo "Testing authentication against kubernetes API server at $cluster_server..."
  echo
  curl -k -v -H "Authorization: Bearer $TOKEN" "$cluster_server/api/v1/namespaces/default/pods" 2> /dev/null
  case $? in
    0)
        echo
        echo "Kubernetes API authentication for $cluster_server successful!"
        ;;
    7)
        echo 
        echo "Error: Unable to connect to Kubernetes API server."
        echo "Check that the endpoint $cluster_server is reachable."
        exit 1
        ;;
    22)
        echo
        echo "Error: Authentication Failure"
        echo
        echo "Your apiserver manifest (typically /etc/kubernetes/manifests/kube-apiserver.yaml)"
        echo "should include the following lines:"
        echo
        echo "spec:"
        echo "  containers:"
        echo "  - command:"
        echo "    - kube-apiserver"
        echo "    - --authorization-mode=Node,RBAC"
        echo "    - --oidc-issuer-url=$iss"
        echo "    - --oidc-client-id=${aud[0]}"
        echo "    - --oidc-username-claim=sub"
        echo "    - --oidc-groups-claim=groups"
        echo
        echo "Your cluster must have a roll binding associated to group:  ${groups[0]}"
        echo
        echo "Your kubernetes master node must have accurate time.  The node clock must"
        echo "be between $nbf_date and $exp_date."
        echo 
        echo "Your kubernetes master must be able to connect to:"
        echo "$iss/.well-known/openid-configuration"
        echo
        echo "Be sure you've included the correct certificate in the ASA cluster setup."
        echo "From the master node, correct certificate is typically /etc/kubernetes/pki/ca.crt"
        echo 
        ;;
    *)
        echo "Unknown error"
        exit 1
        ;;
  esac
else
  echo "No extensions found for provider: $provider"
fi

