# RoyalTSX Dynamic Folder Script

## Overview
RoyalTSX [Dynamic folders](https://docs.royalapps.com/r2021/royalts/reference/organization/dynamic-folder.html) can be used to automically populate a list of OPA protected servers.  The included script uses OPA's sft command line utility to query the platform for a list of servers the use can access, the creates connection objects within the dynamic folder, allowing the user to connect with a simple double-click directly within RoyalTSX, eliminating the need to use the OPA web UI, or the CLI directly.

**_These scripts are not supported by Okta, and no warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

## Requirements
The sft client needs to be installed and enrolled into an OPA team.  Learn more at [Okta Help Center](https://help.okta.com/oie/en-us/content/topics/privileged-access/clients/pam-clients.htm)
RoyalTSX plugins for RDP and Terminal are also required.

## How to Use
* In RoyalTSX create a Document (*From the menu bar, File -> New Document*)
* Within the new document, create a new *Dynamic Folder*
* Update the *Display Name* 
* Enable *Automatically reload folder contents* if desired.
* Click on the new folder, then *Properties*
* Click *Dynamic Folder Script*
* Set the interpreter to Bash
* Paste the included script into the editor window
* Click **Apply & Close**
