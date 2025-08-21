#!/usr/bin/env bash

#grab the name of the group ASA is modifying
source_group="${SFT_HOOK_GROUPNAME}"

#determine if modified group is the wheel sync group
if ["${source_group}" == "sft-admin"] ; then
  destination_group="wheel"
  # Get a list of members from the source group
  source_members=$(getent group "${source_group}" | cut -d: -f4)
  # Add all source group members to the destination group
  gpasswd -M "${source_members}" "${destination_group}"
  echo "Membership mirrored from ${source_group} to ${destination_group}"
fi