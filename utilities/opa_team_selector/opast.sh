#!/usr/bin/env bash
# macOS Bash 3.2+ & Linux Bash 4+ compatible. Safe to run from zsh; shebang invokes bash.
set -euo pipefail

# Requirements: sft, jq
for cmd in sft jq; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "Error: '$cmd' is required but not found in PATH." >&2
    exit 1
  }
done

# Fetch teams JSON
json="$(sft list-teams -o json || true)"

# Validate payload
if [[ -z "${json//[[:space:]]/}" ]]; then
  echo "No data returned by 'sft list-teams -o json'." >&2
  exit 1
fi
count="$(jq 'length' <<<"$json" 2>/dev/null || echo 0)"
if ! [[ "$count" =~ ^[0-9]+$ ]] || [[ "$count" -eq 0 ]]; then
  echo "No teams found." >&2
  exit 1
fi

# First pass: collect fields, determine widths
declare -a IDS TEAMS USERS STARS KINDS
team_w=0
user_w=0

while IFS=$'\t' read -r id team username status url; do
  # ASA/OPA label
  kind="[OPA]"
  [[ "$url" == *"app.scaleft.com"* ]] && kind="[ASA]"

  # Default star (case-insensitive)
  status_lc="$(printf '%s' "$status" | tr '[:upper:]' '[:lower:]')"
  star=""
  [[ "$status_lc" == *"default"* ]] && star="★"

  IDS+=("$id")
  TEAMS+=("$team")
  USERS+=("$username")
  STARS+=("$star")
  KINDS+=("$kind")

  (( ${#team} > team_w )) && team_w=${#team}
  (( ${#username} > user_w )) && user_w=${#username}
done < <(jq -r '.[] | [.id, .team, .username, .status, .url] | @tsv' <<<"$json")

entries=${#IDS[@]}
if (( entries == 0 )); then
  echo "Parsed zero entries from the JSON payload." >&2
  exit 1
fi

# Second pass: build aligned display strings with a fixed 1-char marker column
declare -a DISPLAYS
for (( i=0; i<entries; i++ )); do
  marker="${STARS[$i]}"
  [[ -z "$marker" ]] && marker=" "
  # marker(1) + space + team + two spaces + user + two spaces + kind
  printf -v line "%-1s %-*s  %-*s  %s" \
    "$marker" "$team_w" "${TEAMS[$i]}" \
    "$user_w" "${USERS[$i]}" \
    "${KINDS[$i]}"
  DISPLAYS+=("$line")
done

selected_id=""

if command -v fzf >/dev/null 2>&1; then
  # Build id<TAB>display input; colorize the star without breaking alignment
  fzf_input=""
  for (( i=0; i<entries; i++ )); do
    disp="${DISPLAYS[$i]}"
    if [[ "${STARS[$i]}" == "★" ]]; then
      # Colorize only the first char (the marker), preserve spacing
      disp=$'\x1b[33m★\x1b[0m'"${disp#?}"
    fi
    fzf_input+="${IDS[$i]}\t${disp}\n"
  done
  choice="$(printf "%b" "$fzf_input" \
    | fzf --ansi --delimiter=$'\t' --with-nth=2 \
          --prompt='Select ASA/OPA team> ' --height 40% --reverse || true)"
  [[ -z "$choice" ]] && { echo "No selection made."; exit 0; }
  selected_id="$(printf '%s' "$choice" | awk -F'\t' '{print $1}')"
else
  # Manual, Enter-to-cancel menu (no Bash 'select' so Enter can cancel)
  echo "Available teams:"
  for (( i=0; i<entries; i++ )); do
    printf "%2d) %s\n" "$((i+1))" "${DISPLAYS[$i]}"
  done
  while :; do
    read -r -p $'\nSelect a team by number (press Enter or 0 to cancel): ' ans
    # Enter or 0 cancels
    [[ -z "$ans" || "$ans" == "0" ]] && { echo "No selection made."; exit 0; }
    # Validate numeric and range
    if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= entries )); then
      selected_id="${IDS[$((ans-1))]}"
      break
    else
      echo "Invalid selection: $ans"
    fi
  done
fi

# Safety check and run commands
if [[ -z "$selected_id" ]]; then
  echo "Failed to resolve selection to an ID." >&2
  exit 1
fi

echo "Using team id: ${selected_id}"
sft use "$selected_id"

sft login >/dev/null

