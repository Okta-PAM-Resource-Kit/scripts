#!/usr/bin/env bash

# Expected environment variable:
#   SFT_HOOK_USERNAME - the user to evaluate

GROUP_A="sft-admin"
GROUP_B="wheel"

if [ -z "$SFT_HOOK_USERNAME" ]; then
    echo "Error: SFT_HOOK_USERNAME environment variable is not set."
    exit 1
fi

# Check if user exists
if ! id -u "$SFT_HOOK_USERNAME" >/dev/null 2>&1; then
    echo "Error: User $SFT_HOOK_USERNAME does not exist."
    exit 1
fi

# Check if user is a member of GROUP_A
if id -nG "$SFT_HOOK_USERNAME" | grep -qw "$GROUP_A"; then
    echo "User $SFT_HOOK_USERNAME is in $GROUP_A. Adding to $GROUP_B..."
    sudo usermod -aG "$GROUP_B" "$SFT_HOOK_USERNAME"
    echo "User $SFT_HOOK_USERNAME added to $GROUP_B successfully."
else
    echo "User $SFT_HOOK_USERNAME is not in $GROUP_A. No action taken."
fi
