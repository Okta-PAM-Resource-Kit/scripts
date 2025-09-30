#!/usr/bin/env bash
# OPA session log playback helper.

set -uo pipefail

# Save current TTY settings and restore on any exit
ORIG_STTY="$(stty -g 2>/dev/null || true)"
cleanup() {
  [ -n "${ORIG_STTY:-}" ] && stty "$ORIG_STTY" 2>/dev/null || true
  tput sgr0 2>/dev/null || true
}
trap cleanup EXIT

# ---- Dependency checks ----
check_deps() {
  local missing=()

  # asciinema (>= v2)
  if ! command -v asciinema >/dev/null 2>&1; then
    echo "Error: asciinema is not installed or not in PATH." >&2
    exit 1
  fi
  ver_str="$(asciinema --version 2>/dev/null | awk '{print $NF}')"
  major="$(printf '%s' "$ver_str" | cut -d. -f1)"
  if ! [[ "$major" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not parse asciinema version string: '$ver_str'" >&2
    exit 1
  fi
  if (( major < 2 )); then
    echo "Error: asciinema v2 or higher required, found $ver_str" >&2
    exit 1
  fi

  # sft
  command -v sft >/dev/null 2>&1 || missing+=("sft")

  # sed
  command -v sed >/dev/null 2>&1 || missing+=("sed")

  if [ "${#missing[@]}" -gt 0 ]; then
    echo "Error: Missing required commands: ${missing[*]}" >&2
    exit 1
  fi
}
check_deps
# --------------------------

ACTION="${1:-inactive}"   # default to inactive if no arg provided

show_help() {
  cat <<EOF
Usage: $0 [inactive|help]

Actions:
  inactive  (default) List sessions already closed for user playback
  help      Show this help message
EOF
}

case "$ACTION" in
  inactive)
    recpath=/var/log/sft/sessions
    cmd="cat"
    prefix="ssh"
    ;;
  -h|--help|help) show_help; exit 0 ;;
  *)
    echo "Usage: $0 {inactive|help}" >&2
    exit 1
    ;;
esac

files=()
filesmeta=()

while IFS= read -r file; do
  full_path="${recpath}/${file}"
  if sudo bash -c "head -c 2048 \"$full_path\" | grep -q 'pty-req'"; then
    size=$(sudo bash -c "stat --format='%s' \"$full_path\"")
    IFS='~' read -r -a fields <<< "$file"
    f1="${fields[1]:-}"
    f4="${fields[4]:-}"
    f5="${fields[5]:-}"
    files+=("$size $file")
    filesmeta+=("$(printf '%-21s %-30s %-30s' "$f1" "$f4" "$f5")")
  fi
done < <(sudo bash -c "cd \"$recpath\"; ls -1trh ${prefix:+$prefix}*.asa 2>/dev/null")

if [ "${#files[@]}" -lt 1 ]; then
  echo "No sessions in $recpath"
  exit 1
fi

echo "Files: ${#files[@]}"
PS3="Enter a session number (0 to quit): "

select entry in "${filesmeta[@]}"; do
  if [[ -z "${REPLY:-}" ]]; then
    continue
  fi
  if [[ "$REPLY" == "0" ]]; then
    echo "Bye."
    break
  fi
  if [[ "$REPLY" =~ ^[0-9]+$ ]] && (( REPLY >= 1 && REPLY <= ${#files[@]} )); then
    picked="${files[$((REPLY-1))]}"
    size="${picked%% *}"
    filename="${picked#* }"
    echo "You selected session ${filename} with a size of ${size}."

    sudo bash -c "$cmd \"$recpath/$filename\"" \
      | sft session-logs export --insecure --format asciinema --stdin \
      | sed --unbuffered 's/}}/}}\n[0.000000001,"o","\\u001b[100m\\r\\nStart\\r\\n\\r\\n"]/g' \
      | sed --unbuffered 's/\[00m\|\[0m\|\[m/\[100m/g' \
      | asciinema play -i 2 -s 2 /dev/stdin

    [ -n "${ORIG_STTY:-}" ] && stty "$ORIG_STTY" 2>/dev/null || true
    tput sgr0 2>/dev/null || true
  else
    echo "Invalid selection: $REPLY"
  fi
done
