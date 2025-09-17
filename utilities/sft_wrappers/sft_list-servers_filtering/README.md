# Okta OPA/ASA Installation, Diagnostic, and Advance Usage Scripts

**_These scripts are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Overview

opals.sh (OPA List Servers) is a bash script wrapper for the sft list-servers command, allowing a user to filter the list output based on OS type, OS name, zone, sftd version, or custom label.  

```bash
Usage:
  opals.sh [filters]

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
```
Notes:
  • All filters are optional. With no arguments, the script prints all servers.
  • Same-field includes are OR’d; excludes are AND’d; different fields are AND’d.
  • Label filters are AND’d. Output shows only labels whose keys start with "sftd.".

Examples:
```bash
  # Only DB nodes, exclude apphosts
  opals.sh --label sftd.db=true --not-label sftd.apphost=true
```
```bash
  # Ubuntu 24.04 in us-west1-b, with specific agent version
  opals.sh --os "Ubuntu 24.04" --zone us-west1-b --sftd-version 1.95.0
```
```bash
  # Exclude Windows and an old agent
  opals.sh --not-os-type windows --not-sftd-version 1.80.0
```

After downloading, make the script executable.  And for ease of use, place it in the PATH, then create an alias in .bashrc or .zshrc to allow execution without including the .sh extension:
```bash
#create the alias
echo 'alias opals="opals.sh $@"' >> ~/.zshrc
#reload the environment
source ~/.zshrc  
```