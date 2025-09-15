#!/usr/bin/env bash
set -euo pipefail

# Filter Okta Privileged Access "sft list-servers -o json" output with jq
# All filters are optional; with no args, prints all servers in a tabular format.

# ----------------------------
# Dependency checks
# ----------------------------
need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: '$1' is not installed or not on PATH." >&2; exit 1; }; }
need sft
need jq
need column  # usually part of bsdmainutils/util-linux; present on macOS too

# ----------------------------
# Ensure current device token without noisy output; fail fast if login fails
# ----------------------------
if ! sft login >/dev/null 2>&1; then
  echo "Error: sft login failed. Please check your Okta ASA configuration." >&2
  exit 1
fi

# ----------------------------
# Args
# ----------------------------
declare -a inc_os_type=()
declare -a exc_os_type=()
declare -a inc_os=()
declare -a exc_os=()
declare -a inc_zone=()
declare -a exc_zone=()
declare -a inc_ver=()
declare -a exc_ver=()
declare -a inc_label=()   # KEY=VALUE
declare -a exc_label=()   # KEY=VALUE
input_file=""             # --input file.json
dry_run=false

usage() {
  local script_name
  script_name=$(basename "$0")
  cat <<USAGE
Usage:
  $script_name [filters]

Filters (repeat flags to add multiple values):
  --os-type VALUE           Include os_type == VALUE
  --not-os-type VALUE       Exclude os_type == VALUE

  --os VALUE                Include os == VALUE (e.g. "Ubuntu 24.04")
  --not-os VALUE            Exclude os == VALUE

  --zone VALUE              Include zone_id == VALUE (e.g. "us-west1-b")
  --not-zone VALUE          Exclude zone_id == VALUE

  --sftd-version VALUE      Include sftd_version == VALUE (e.g. "1.95.0")
  --not-sftd-version VALUE  Exclude sftd_version == VALUE

  --label KEY=VALUE         Include label KEY == VALUE (e.g. "sftd.db=true")
  --not-label KEY=VALUE     Exclude label KEY == VALUE

Other:
  --input FILE.json         Read JSON from file instead of running "sft list-servers -o json"
  --dry-run                 Print the jq program that will be executed
  -h | --help               Show this help

Notes:
  • All filters are optional. With no arguments, the script prints all servers.
  • Same-field includes are OR’d; excludes are AND’d; different fields are AND’d.
  • Label filters are AND’d. Output shows only labels whose keys start with "sftd.".

Examples:
  # Only DB nodes, exclude apphosts
  $script_name --label sftd.db=true --not-label sftd.apphost=true

  # Ubuntu 24.04 in us-west1-b, with specific agent version
  $script_name --os "Ubuntu 24.04" --zone us-west1-b --sftd-version 1.95.0

  # Exclude Windows and an old agent
  $script_name --not-os-type windows --not-sftd-version 1.80.0
USAGE
}

# Parse args (all optional)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --os-type)           inc_os_type+=("$2"); shift 2;;
    --not-os-type)       exc_os_type+=("$2"); shift 2;;
    --os)                inc_os+=("$2"); shift 2;;
    --not-os)            exc_os+=("$2"); shift 2;;
    --zone)              inc_zone+=("$2"); shift 2;;
    --not-zone)          exc_zone+=("$2"); shift 2;;
    --sftd-version)      inc_ver+=("$2"); shift 2;;
    --not-sftd-version)  exc_ver+=("$2"); shift 2;;
    --label)             inc_label+=("$2"); shift 2;;
    --not-label)         exc_label+=("$2"); shift 2;;
    --input)             input_file="$2"; shift 2;;
    --dry-run)           dry_run=true; shift;;
    -h|--help)           usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 1;;
  esac
done

# ----------------------------
# Helpers to build jq predicates (default to true -> no filtering)
# ----------------------------
# Clean empty elements first so we don't generate .field=="" or .field!=""

# ----------------------------
# Helpers to build jq predicates (default to true -> no filtering)
# Compatible with Bash 3.2+ (no mapfile)
# ----------------------------

build_inc_pred() {  # OR across values, or true if none
  local field="$1"; shift
  local -a vals=()
  local v
  for v in "$@"; do
    [[ -n "$v" ]] && vals+=("$v")
  done
  if ((${#vals[@]} == 0)); then
    echo "true"
  else
    local -a parts=()
    for v in "${vals[@]}"; do
      parts+=( ".${field}==\"${v//\"/\\\"}\"" )
    done
    local IFS=' or '
    echo "(${parts[*]})"
  fi
}

build_exc_pred() {  # AND across values, or true if none
  local field="$1"; shift
  local -a vals=()
  local v
  for v in "$@"; do
    [[ -n "$v" ]] && vals+=("$v")
  done
  if ((${#vals[@]} == 0)); then
    echo "true"
  else
    local -a parts=()
    for v in "${vals[@]}"; do
      parts+=( ".${field}!=\"${v//\"/\\\"}\"" )
    done
    local IFS=' and '
    echo "(${parts[*]})"
  fi
}

build_label_pred() {  # AND across labels, or true if none
  local mode="$1"; shift
  local -a kvs=()
  local kv
  for kv in "$@"; do
    [[ -n "$kv" ]] && kvs+=("$kv")
  done
  if ((${#kvs[@]} == 0)); then
    echo "true"
    return
  fi
  local -a parts=()
  local k v
  for kv in "${kvs[@]}"; do
    [[ "$kv" == *"="* ]] || { echo "Error: label filter must be KEY=VALUE, got '$kv'" >&2; exit 1; }
    k="${kv%%=*}"
    v="${kv#*=}"
    k="${k//\"/\\\"}"
    v="${v//\"/\\\"}"
    if [[ "$mode" == "inc" ]]; then
      parts+=( ".labels[\"$k\"]==\"$v\"" )
    else
      parts+=( ".labels[\"$k\"]!=\"$v\"" )
    fi
  done
  local IFS=' and '
  echo "(${parts[*]})"
}

# ----------------------------
# Build jq filter program (predicates default to true if arrays empty)
# ----------------------------
inc_os_type_pred=$(build_inc_pred "os_type" "${inc_os_type[@]:-}")
exc_os_type_pred=$(build_exc_pred "os_type" "${exc_os_type[@]:-}")
inc_os_pred=$(build_inc_pred "os" "${inc_os[@]:-}")
exc_os_pred=$(build_exc_pred "os" "${exc_os[@]:-}")
inc_zone_pred=$(build_inc_pred "instance_details.zone_id" "${inc_zone[@]:-}")
exc_zone_pred=$(build_exc_pred "instance_details.zone_id" "${exc_zone[@]:-}")
inc_ver_pred=$(build_inc_pred "sftd_version" "${inc_ver[@]:-}")
exc_ver_pred=$(build_exc_pred "sftd_version" "${exc_ver[@]:-}")
inc_label_pred=$(build_label_pred "inc" "${inc_label[@]:-}")
exc_label_pred=$(build_label_pred "exc" "${exc_label[@]:-}")


jq_program=$(cat <<'JQ'
[
  "HOSTNAME","ACCESS_ADDR","INTERNAL_IP","ZONE","OS","SFTD_VERSION","SFTD_LABELS"
],
(
  .[]
  | select(
      $inc_os_type_pred and $exc_os_type_pred
      and $inc_os_pred and $exc_os_pred
      and $inc_zone_pred and $exc_zone_pred
      and $inc_ver_pred and $exc_ver_pred
      and $inc_label_pred and $exc_label_pred
    )
  | [
      .hostname,
      .access_address,
      (.instance_details.internal_ip // ""),
      (.instance_details.zone_id // ""),
      (.os // ""),
      (.sftd_version // ""),
      (
        .labels
        | to_entries
        | map(select(.key | startswith("sftd.")))  # only sftd.* labels displayed
        | map("\(.key)=\(.value)")
        | join(",")
      )
    ]
)
| @tsv
JQ
)

# Inline substitute predicate strings
jq_program="${jq_program//\$inc_os_type_pred/$inc_os_type_pred}"
jq_program="${jq_program//\$exc_os_type_pred/$exc_os_type_pred}"
jq_program="${jq_program//\$inc_os_pred/$inc_os_pred}"
jq_program="${jq_program//\$exc_os_pred/$exc_os_pred}"
jq_program="${jq_program//\$inc_zone_pred/$inc_zone_pred}"
jq_program="${jq_program//\$exc_zone_pred/$exc_zone_pred}"
jq_program="${jq_program//\$inc_ver_pred/$inc_ver_pred}"
jq_program="${jq_program//\$exc_ver_pred/$exc_ver_pred}"
jq_program="${jq_program//\$inc_label_pred/$inc_label_pred}"
jq_program="${jq_program//\$exc_label_pred/$exc_label_pred}"

if $dry_run; then
  echo "=== jq program ==="
  echo "$jq_program"
  exit 0
fi

# ----------------------------
# Run (no-arg case prints ALL results due to predicates defaulting to true)
# ----------------------------
if [[ -n "$input_file" ]]; then
  jq -r "$jq_program" "$input_file" | column -ts $'\t'
else
  sft list-servers -o json | jq -r "$jq_program" | column -ts $'\t'
fi
