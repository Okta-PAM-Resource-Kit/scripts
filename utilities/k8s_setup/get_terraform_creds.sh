#!/usr/bin/env bash
# Fetch the API key using the `sft` command and return it in JSON format
apikey=$(sft secrets reveal --resource-group POC-Secrets --project POC-Secrets --path pocSecrets --name terraform-secret --key key-id | sed 's/[[:space:]]*$//')
if [ $? -ne 0 ]; then
  echo "{\"error\": \"Failed to retrieve API key\"}"
  exit 1
fi
apisecret=$(sft secrets reveal --resource-group POC-Secrets --project POC-Secrets --path pocSecrets --name terraform-secret --key key-secret | sed 's/[[:space:]]*$//')
if [ $? -ne 0 ]; then
  echo "{\"error\": \"Failed to retrieve API secret\"}"
  exit 1
fi
team_detail=()
team_detail+=($(sft list-teams | grep default))
team_name="${team_detail[1]}"
if [ $? -ne 0 ]; then
  echo "{\"error\": \"Failed to retrieve OPA team\"}"
  exit 1
fi
team_URL=$(echo "${team_detail[2]}" | awk -F/ '{print $1 "//" $3}')
if [ $? -ne 0 ]; then
  echo "{\"error\": \"Failed to retrieve OPA URL\"}"
  exit 1
fi

cat <<EOF
{
  "apikey": "$apikey",
  "apisecret": "$apisecret",
  "team": "$team_name",
  "url": "$team_URL"
}
EOF