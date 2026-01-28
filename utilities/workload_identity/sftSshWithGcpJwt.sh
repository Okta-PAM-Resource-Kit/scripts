#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Exit immediately if a pipeline returns a non-zero status.
set -o pipefail

################################################################################
# Fetches the ScaleFT team name from the local sftd agent.
# Exits script on failure.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes the team name to stdout.
################################################################################
get_sft_team() {
  local sftd_output
  local sftd_exit_code
  local sft_team
  # mktemp is safer than a hardcoded temp file path
  local error_log
  error_log=$(mktemp)
  # Ensure the temp file is cleaned up on script exit
  trap 'rm -f "$error_log"' EXIT

  sftd_output=$(sudo sftd --debug-device-token 2> "$error_log")
  sftd_exit_code=$?

  if [ $sftd_exit_code -ne 0 ]; then
    echo "Error: 'sudo sftd --debug-device-token' failed with exit code $sftd_exit_code." >&2
    echo "sftd error output:" >&2
    cat "$error_log" >&2
    exit 1
  fi

  sft_team=$(echo "$sftd_output" | awk -F': *' '/^ScaleFT Team:/ {print $2}' | xargs)

  if [ -z "$sft_team" ]; then
    echo "Error: Command was successful, but failed to parse SFT_TEAM from 'sftd --debug-device-token' output." >&2
    exit 1
  fi

  echo "$sft_team"
}

################################################################################
# Safely decodes a Base64URL string and extracts a JSON value.
# This function is designed to not exit on error, even with 'set -e'.
# It handles differences between macOS and Linux base64 commands.
# Globals:
#   None
# Arguments:
#   $1: The Base64URL encoded string.
#   $2: The JSON key to extract (e.g., '.exp').
# Outputs:
#   Writes the extracted value to stdout. Returns a non-zero status on failure.
################################################################################
safe_b64url_decode_jq() {
    local input="$1"
    local key="$2"
    local decoded
    local b64_command

    # Accommodate for macOS vs. Linux base64 command
    if command -v gbase64 >/dev/null; then
        b64_command="gbase64 --decode"
    elif [[ "$(uname -s)" == "Darwin" ]]; then
        b64_command="base64 --decode"
    else
        b64_command="base64 -d"
    fi

    # The `|| true` prevents the script from exiting if a command fails
    decoded=$($b64_command <<< "$input" 2>/dev/null || true)

    if [[ -z "$decoded" ]]; then
        return 1 # Indicate failure
    fi

    # The `|| true` prevents the script from exiting if jq fails
    jq -r "$key" <<< "$decoded" 2>/dev/null || true
}

################################################################################
# Fetches a GCP JWT from the metadata service.
# Exits script on failure.
# Globals:
#   GCP_TOKEN (exported)
# Arguments:
#   $1: The audience for the JWT.
################################################################################
get_gcp_jwt() {
  local audience=$1
  log "-------------------------------------------------------"
  log "STEP 1: Setting Identity (GCP_TOKEN)"
  log "-------------------------------------------------------"
  
  # Added &format=full - this is often required for third-party integrations
  local metadata_url="http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=$audience&format=full"

  # Fetch and strip both newlines AND carriage returns
  local id_token
  id_token=$(curl -s -H "Metadata-Flavor: Google" "$metadata_url" | tr -d '\n\r')

  if [[ "$id_token" != eyJ* ]]; then
      echo "Error: Failed to fetch JWT." >&2
      exit 1
  fi
  
  export GCP_TOKEN="$id_token"
  
  # Verify validity window
  local exp now diff
  local payload
  payload=$(echo "$GCP_TOKEN" | cut -d. -f2)
  exp=$(safe_b64url_decode_jq "$payload" '.exp')
  if ! [[ "$exp" =~ ^[0-9]+$ ]]; then
      echo "Error: Failed to decode JWT or extract expiration time." >&2
      exit 1
  fi
  now=$(date +%s)  
  diff=$((exp - now))

  log "Success: JWT exported."
  log "Token is valid for another $diff seconds (approx $((diff / 60)) minutes)."
  log "VALUE OF GCP_TOKEN:"
  log "$GCP_TOKEN"
  log ""
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

This script fetches a GCP JWT, exchanges it for an OPA token, and establishes an SSH session.
***These values can also be set directly as environment variables in the main() function.***
Options:
  -t <team>          Specify the SFT_TEAM. (Default: auto-discovered via sftd agent)
  -o <address>       Specify the OPA_ADDR (Default: assembled from SFT_TEAM and OPA_ENVIRONMENT)
  -s <server>        Specify the SFT_SERVER to connect to.
  -c <connection>    Specify the Workload Identity connection name.
  -r <role>          Specify the Workload Identity role.
  -a <audience>      Specify the JWT audience.
  -e <env>           Specify the OPA environment: prod, preview, or trex.
  -v                 Enable verbose output.
  -h                 Display this help message and exit.
EOF
  exit 0
}

main() {
  # Configuration
  # Set default values. These can be overridden by command-line arguments.
  SFT_TEAM=""
  OPA_ADDR=""
  SFT_SERVER=""
  VERBOSE=false
  OPA_ENVIRONMENT="preview"
  wl_connection=""
  wl_role=""
  audience=""

  log() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo "$@"
    fi
  }

  # Parse command-line options
  while getopts "t:o:s:c:r:a:e:vh" opt; do
    case ${opt} in
      t) SFT_TEAM=$OPTARG ;;
      o) OPA_ADDR=$OPTARG ;;
      s) SFT_SERVER=$OPTARG ;;
      c) wl_connection=$OPTARG ;;
      r) wl_role=$OPTARG ;;
      a) audience=$OPTARG ;;
      e) OPA_ENVIRONMENT=$OPTARG ;;
      v) VERBOSE=true ;;
      h) usage ;;
      \?)
        echo "Invalid option: -$OPTARG" >&2
        exit 1
        ;;
      :)
        echo "Option -$OPTARG requires an argument." >&2
        exit 1
        ;;
    esac
  done

  # If SFT_TEAM was not provided via command line, discover it.
  if [ -z "$SFT_TEAM" ]; then
    SFT_TEAM=$(get_sft_team)
  fi
  
  # Set OPA_ADDR based on environment, unless explicitly overridden by -o
  if [ -z "$OPA_ADDR" ]; then
    case "$OPA_ENVIRONMENT" in
      prod)
        OPA_ADDR="https://${SFT_TEAM}.pam.okta.com" 
        ;;
      preview)
        OPA_ADDR="https://${SFT_TEAM}.pam.oktapreview.com"
        ;;
      trex)
        OPA_ADDR="https://${SFT_TEAM}.pam.trexcloud.com"
        ;;
    esac
  fi

  export SFT_TEAM
  export OPA_ADDR
  export SFT_FEATURE_NHI=1

  # --- STEP 1: IDENTITY ---
  get_gcp_jwt "$audience"

  # --- STEP 2: EXCHANGE ---
  log "-------------------------------------------------------"
  log "STEP 2: Authenticating Workload with OPA to get OPA_TOKEN"
  log "-------------------------------------------------------"
  log "RUNNING: sft wl authenticate --team ${SFT_TEAM} --connection ${wl_connection} --role-hint ${wl_role} --jwt-env GCP_TOKEN"
  export OPA_TOKEN=$(sft wl authenticate --team "${SFT_TEAM}" --connection "${wl_connection}" --role-hint "${wl_role}" --jwt-env GCP_TOKEN 2>&1 | tr -d '\n\r')

  # --- STEP 3: RESULTS ---
  if [[ "$OPA_TOKEN" == *"error"* ]] || [[ -z "$OPA_TOKEN" ]]; then
      echo "ERROR: Failed to obtain OPA_TOKEN." >&2
      echo "Detail: $OPA_TOKEN" >&2
      exit 1
  else
      log "SUCCESS: OPA_TOKEN obtained and exported."
      log ""
      log "VALUE OF OPA_TOKEN:"
      log "$OPA_TOKEN"
  fi
  
  log "-------------------------------------------------------"
  log "STEP 3: Establishing SSH session to ${SFT_SERVER} with OPA token"
  log "-------------------------------------------------------"

  sft ssh "$SFT_SERVER"
}

main "$@"
