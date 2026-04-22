#!/usr/bin/env bash
# Watch for new session logs and convert them to asciinema (ssh) and mkv (rdp).
# Intended to run as a systemd service.

set -euo pipefail

WATCHPATH="${WATCHPATH:-/var/log/sft/sessions}"
DESTPATH="${DESTPATH:-/mnt/cloud/sessions}"

process_logs_ssh() {
    local file="$1"
    sft session-logs export --insecure --format asciinema \
        --output "$DESTPATH/${file}.cast" "$WATCHPATH/$file"
}

process_logs_rdp() {
    local file="$1"
    sft session-logs export --insecure --format mkv \
        --output "$DESTPATH" "$WATCHPATH/$file"
}

if [[ ! -d "$WATCHPATH" ]]; then
    echo "Error: Watch path $WATCHPATH does not exist" >&2
    exit 1
fi

if [[ ! -d "$DESTPATH" ]]; then
    echo "Error: Destination path $DESTPATH does not exist" >&2
    exit 1
fi

echo "Watching $WATCHPATH for new session logs..."
echo "Converted files will be written to $DESTPATH"

inotifywait -m "$WATCHPATH" -e create 2>/dev/null |
while read -r dirpath action file; do
    if [[ $file == *ssh~* ]]; then
        echo "SSH session capture found: $file"
        if process_logs_ssh "$file"; then
            echo "SSH session converted successfully"
        else
            echo "Error converting SSH session: $file" >&2
        fi
    elif [[ $file == *rdp~* ]]; then
        echo "RDP session capture found: $file"
        if process_logs_rdp "$file"; then
            echo "RDP session converted successfully"
        else
            echo "Error converting RDP session: $file" >&2
        fi
    else
        echo "Skipping unknown file type: $file"
    fi
done