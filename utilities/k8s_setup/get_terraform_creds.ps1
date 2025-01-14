# Execute with powershell -ExecutionPolicy Bypass -File .\get_terraform_creds.ps1


# Simulate fetching secrets (replace these lines with actual secret-fetching logic)
$apikey = (sft secrets reveal --resource-group POC-Secrets --project POC-Secrets --path pocSecrets --name terraform-secret --key key-id).Trim()
$apisecret = (sft secrets reveal --resource-group POC-Secrets --project POC-Secrets --path pocSecrets --name terraform-secret --key key-secret).Trim()
# Initialize an array to hold team details
$team_detail = @()

# Execute the `sft list-teams` command and filter for the "default" team
$team_output = sft list-teams | Select-String -Pattern "default"

if ($team_output -eq $null) {
    Write-Output '{"error": "Failed to retrieve OPA team"}'
    exit 1
}

# Parse the team details
$team_detail = $team_output -split '\s+'

# Extract the team name (assuming it's the second field in the output)
$team_name = $team_detail[1]

if (-not $team_name) {
    Write-Output '{"error": "Failed to retrieve OPA team name"}'
    exit 1
}

# Extract the team URL (assuming it's the third field in the output)
$team_raw_url = $team_detail[2]
$team_URL = ($team_raw_url -split '/')[0] + "//" + ($team_raw_url -split '/')[2]

if (-not $team_URL) {
    Write-Output '{"error": "Failed to retrieve OPA URL"}'
    exit 1
}

# Check if all commands succeeded
if (!$apikey -or !$apisecret -or !$team -or !$url) {
    Write-Output '{"error": "Failed to retrieve secrets"}'
    exit 1
}

# Create a JSON object with the secrets
$secrets = @{
    apikey    = $apikey
    apisecret = $apisecret
    team      = $team_name
    url       = $team_URL
}

# Output the JSON object
$secrets | ConvertTo-Json -Depth 1
