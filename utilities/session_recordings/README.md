# Session Recording Utilities

## Overview

These scripts are intended to help facilitate recorded SSH session playback.

**_These scripts are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Capabilities

asciinema.sh -- installs/uninstalls the most current version of asciinema via direct Github download if possible, or via Python3 pip as a fallback.

ssh_playback.sh -- lists all interactive SSH session recordings with numerical index, allowing the user to easily select the recording they wish to view, exports to ascinnema format, then plays the session in the local terminal session.

## Usage

```bash
asciinema.sh [install|uninstall|help] 
  install    (default) Install the latest asciinema (default if no action is given).
             Prefers GitHub prebuilt binary; falls back to pip if unavailable.

  uninstall  Remove asciinema (binary or pip install) and config files.

  help       Show this help message.
```

```bash
ssh_playback.sh [inactive|active|help]
  inactive  (default) List sessions already closed for user playback
  active    List sessions currently open for user playback
  help      Show this help message

```
To use the scripts:

asciinema.sh
```bash
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/utilities/session_recordings/asciinema.sh
chmod +x asciinema.sh
./asciinema install
```

ssh_playback.sh
```bash
curl -O https://raw.githubusercontent.com/Okta-PAM-Resource-Kit/scripts/main/utilities/session_recordings/ssh_playback.sh
chmod +x ssh_playback.sh
./ssh_playback.sh inactive
```
