Powershell-Script to migrate creds to Okta Privileged Access Vault

**_These scripts are not supported by Okta, are experimental, and are not intended for production use.  No warranty is expressed or implied.  Please review and understand all scripts before using.  Use at your own risk._**

This is a basic script that demonstrates adding credentials to the OPA Vault using the sft command line tool. 
Preferred way is to use an API endpoint to read credentials from the source and adding it to OPA vault. 


Usage
This project provides an example PowerShell script to the following actions:
- Read credentials from a csv.
- call sft secrets command to add credentials to OPA vault.


Prerequisites
The base prerequisite for these script is Microsoft Powershell

Built With
Microsoft Powershell

