# This file contains functions with sample code. To use one, call it.
# Read secrets from CSV and create in Okta Vault


<# Call API endpoint from source vault to extract creds real-time... (preferred)
OR
CSV
Sample CSV file. Make sure you include the header line as the first record.
resourceGroup,project,path,key,value,name,description
Jo_DevelopmentResources,Secrets,OktaApiKeys,apikey1,testIng001,devopskeys,creds for deveops script1
#>
function CreateSecrets() {

    $secrets = Import-Csv Secrets.csv
    foreach ($secret in $secrets) {
		
         $secretProfile = @{resourceGroup = $secret.resourceGroup; project = $secret.project; path = $secret.path; key = $secret.key; value = $secret.value; name = $secret.name; description = $secret.description}
        #$groupIds = $user.groupIds -split ";"
		Write-Output $SecretProfile
		sft secrets create --resource-group $secretProfile.resourceGroup --project $secretProfile.project --path $secretProfile.path --key $secretProfile.key --value $secretProfile.value --name $secretProfile.name  --description $secretProfile.description

    }
	
	Write-Output "Completed Secrets Mangement at $(Get-Date)"

}

CreateSecrets