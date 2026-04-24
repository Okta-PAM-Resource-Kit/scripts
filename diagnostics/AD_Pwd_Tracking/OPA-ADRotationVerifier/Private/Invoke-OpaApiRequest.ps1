function Get-OpaToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OpaUrl,

        [Parameter(Mandatory)]
        [string]$TeamName,

        [Parameter(Mandatory)]
        [string]$KeyId,

        [Parameter(Mandatory)]
        [string]$KeySecret
    )

    if ($script:BearerToken -and $script:TokenExpiresAt) {
        $bufferTime = (Get-Date).AddSeconds(60)
        if ($script:TokenExpiresAt -gt $bufferTime) {
            Write-Verbose "Using cached bearer token (expires at $script:TokenExpiresAt)"
            return $script:BearerToken
        }
    }

    $tokenUrl = "$OpaUrl/v1/teams/$TeamName/service_token"
    $body = @{
        key_id = $KeyId
        key_secret = $KeySecret
    } | ConvertTo-Json

    Write-Verbose "Requesting new bearer token from $tokenUrl"
    Write-Host "Authenticating to OPA API..." -ForegroundColor Yellow

    try {
        # Ensure TLS 1.2 is enabled
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
        $script:BearerToken = $response.bearer_token
        $script:TokenExpiresAt = [DateTime]::Parse($response.expires_at)
        Write-Host "Authentication successful." -ForegroundColor Green
        Write-Verbose "Obtained bearer token, expires at $script:TokenExpiresAt"
        return $script:BearerToken
    }
    catch {
        Write-Host "Authentication failed." -ForegroundColor Red
        throw "Failed to obtain bearer token: $_"
    }
}

function Invoke-OpaApiRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Endpoint,

        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [object]$Body,

        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [hashtable]$Credential
    )

    $token = Get-OpaToken -OpaUrl $Config.opa_url `
                          -TeamName $Config.team_name `
                          -KeyId $Credential.KeyId `
                          -KeySecret $Credential.KeySecret

    $url = "$($Config.opa_url)$Endpoint"
    $headers = @{
        'Authorization' = "Bearer $token"
        'Accept' = 'application/json'
    }

    Write-Verbose "API Request: $Method $url"

    $params = @{
        Uri = $url
        Method = $Method
        Headers = $headers
        ContentType = 'application/json'
    }

    if ($Body) {
        $params.Body = $Body | ConvertTo-Json -Depth 10
    }

    try {
        $response = Invoke-RestMethod @params -TimeoutSec 30
        return $response
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message
        throw "API request failed ($statusCode): $errorBody"
    }
}
