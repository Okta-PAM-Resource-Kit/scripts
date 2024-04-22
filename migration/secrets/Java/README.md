Java program to migrate credentials from Hashicorp vault to Okta vault has been developed using Springboot framework.

Following Environment details are required to run this program.

#Okta PAM URL
register.oktapam.host=https://<<Okta Subdomain>>.pam.oktapreview.com
#Relative URI with OPA Team NAme
register.oktapam.apiuri=/v1/teams/<<PAM Team Name>>
#Create OPA Service User in OPA and copy the Key ID
register.oktapam.clientID=<<OPA Service user Key ID>>
#Create OPA Service User in OPA and copy the Key Secret
register.oktapam.clientSecret=<<OPA Service user Key Secret>>
#Resource Group ID of the resource where secret will be migrated
register.oktapam.resourceGroupId=<<Resource Group ID>>
#Project Group ID of the resource where secret will be migrated
register.oktapam.projectId=<<Project ID>>
# Parent folder where Secret will be migrated. Service user must have full access to the folder by policy
register.oktapam.parentSecretFolderId=<<Secret Folder ID where child folder will be created and Secret will be migrated>>
# Generic Description addedd to secret and child folders during secret migration
register.oktapam.secretFolderDesc=Migrated from Hashicorp vault

#Get OPA Token api Endpoint (Do not change)
register.oktapam.tokenendpoint=/service_token
register.oktapam.jwksEndpoint=/vault/jwks.json
register.oktapam.createSecretEndpoint=/secrets
register.oktapam.createFolderEndpoint=/secret_folders

#Get Hashicorp environment details
# Hashicorp Vault host ip
register.hashicorp.host=<<Host IP>>
# Hashicorp Vault host port
register.hashicorp.port=<<Vault Service Port>>
register.hashicorp.scheme=http
# Hashicorp Vault access token
register.hashicorp.token=<<Hashicorp token to read all secret engines and its metadata>>
# List of secret engines to be migrated
register.hashicorp.secretengine=<<Comma separated Secret engines name>> 
register.hashicorp.metadata=metadata

**Note**: Must have Java 1.8.x and Maven on the machine to build and run the Java program.

**Execurion Steps**: 

1. Download the code
2. navigate to the folder /OPASecretMigration/src/main/resources (assuming you downloaded the code into OPASecretMigration folder)
3. Edit the properties file (application-dev.properties) to set the environment variable  
4. open command shell
5. Execute: "mvn clean"
6. Execute: "mvn install"
7. Execute: "mvn package"
8. Execute: "java -jar target/OPASecretMigration-0.1.jar to start migration
