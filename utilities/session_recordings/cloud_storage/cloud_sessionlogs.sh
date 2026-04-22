#!/usr/bin/env bash
# Watch for new session logs and convert them to asciinema (ssh) and mkv (rdp).
# Intended to run as a systemd service.

set -euo pipefail

WATCHPATH="${WATCHPATH:-/var/log/sft/sessions}"
DESTPATH="${DESTPATH:-/mnt/cloud/sessions}"
RETENTION_DAYS="${RETENTION_DAYS:-0}"
CLEANUP_INTERVAL="${CLEANUP_INTERVAL:-3600}"
SSH_MODE="${SSH_MODE:-convert}"
RDP_MODE="${RDP_MODE:-convert}"

process_ssh() {
    local file="$1"
    if [[ "$SSH_MODE" == "convert" ]]; then
        sft session-logs export --insecure --format asciinema \
            --output "$DESTPATH/${file}.cast" "$WATCHPATH/$file"
    elif [[ "$SSH_MODE" == "copy" ]]; then
        cp "$WATCHPATH/$file" "$DESTPATH/$file"
    else
        echo "Unknown SSH_MODE: $SSH_MODE (expected 'convert' or 'copy')" >&2
        return 1
    fi
}

process_rdp() {
    local file="$1"
    if [[ "$RDP_MODE" == "convert" ]]; then
        sft session-logs export --insecure --format mkv \
            --output "$DESTPATH" "$WATCHPATH/$file"
    elif [[ "$RDP_MODE" == "copy" ]]; then
        cp "$WATCHPATH/$file" "$DESTPATH/$file"
    else
        echo "Unknown RDP_MODE: $RDP_MODE (expected 'convert' or 'copy')" >&2
        return 1
    fi
}

cleanup_old_files() {
    if [[ "$RETENTION_DAYS" -gt 0 ]]; then
        echo "Cleaning up source files older than $RETENTION_DAYS days..."
        find "$WATCHPATH" -type f -mtime +"$RETENTION_DAYS" -delete
        echo "Cleanup complete"
    fi
}

start_cleanup_timer() {
    if [[ "$RETENTION_DAYS" -gt 0 ]]; then
        echo "Retention policy enabled: $RETENTION_DAYS days (cleanup every ${CLEANUP_INTERVAL}s)"
        while true; do
            sleep "$CLEANUP_INTERVAL"
            cleanup_old_files
        done &
        CLEANUP_PID=$!
        trap "kill $CLEANUP_PID 2>/dev/null" EXIT
    else
        echo "Retention policy disabled (RETENTION_DAYS=0)"
    fi
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
echo "Output files will be written to $DESTPATH"
echo "SSH mode: $SSH_MODE | RDP mode: $RDP_MODE"

start_cleanup_timer
cleanup_old_files

inotifywait -m "$WATCHPATH" -e create 2>/dev/null |
while read -r dirpath action file; do
    if [[ $file == *ssh~* ]]; then
        echo "SSH session capture found: $file"
        if process_ssh "$file"; then
            echo "SSH session processed successfully (mode: $SSH_MODE)"
        else
            echo "Error processing SSH session: $file" >&2
        fi
    elif [[ $file == *rdp~* ]]; then
        echo "RDP session capture found: $file"
        if process_rdp "$file"; then
            echo "RDP session processed successfully (mode: $RDP_MODE)"
        else
            echo "Error processing RDP session: $file" >&2
        fi
    else
        echo "Skipping unknown file type: $file"
    fi
done