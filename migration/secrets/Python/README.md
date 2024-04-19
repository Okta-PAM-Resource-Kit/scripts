This codes are not pruduction ready code and do not supported by Okta Support desk.

This Python script is to give guidance on how to interact with Okta Vault to create/update/reveal the secrets.
This script can be extended or modified to make additional calls to third party vault to read the secret and migrate to Okta vault without exporting credential in a file.

To run: 

Within OPA: 
1.  Create a service account user and record the client key and secret key.
2.  Set up a resource group, project, and top-level secret folder and record the ids for each of them.
3.  Set up a security policy to allow the service account to create secrets within the secret-folder you created.

 Required Parameters:

host = "https://<<Okta Subdomain>>.pam.oktapreview.com"
team = "<<OPA TEAM Name"
client = "<<Service Account Key ID>>"
secret = "OPA Service Account Key Secret>>"
resource_group_id = "<<REsource Group ID>>"
project_id = "<<Project ID>>"
secret_id = "<<Secret ID for updates>>" #hardcoded for this script as demo here but can be dynamic
parent_secret_folder_id = "<<Secret Parent folder ID>>"
 
1.  Run: `./setup.sh`
2.  Run: `source .venv/bin/activate`
3.  Edit opa_secrets.py file to update the parameter values.
4.  Run: `python opa_secrets.py`
