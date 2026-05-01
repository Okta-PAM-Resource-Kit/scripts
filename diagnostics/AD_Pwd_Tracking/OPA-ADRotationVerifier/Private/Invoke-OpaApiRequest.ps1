function Get-OpaToken {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [hashtable]$Credential
    )

    # Check for valid cached token first
    if ($script:BearerToken -and $script:TokenExpiresAt) {
        $bufferTime = (Get-Date).AddSeconds(60)
        if ($script:TokenExpiresAt -gt $bufferTime) {
            Write-Verbose "Using cached bearer token (expires at $script:TokenExpiresAt)"
            return $script:BearerToken
        }
    }

    # Need new token - get config and credentials
    if (-not $Config) {
        $Config = Initialize-OpaConfig
    }
    if (-not $Credential) {
        $Credential = Get-OpaCredential -Config $Config
    }

    $tokenUrl = "$($Config.opa_url)/v1/teams/$($Config.team_name)/service_token"
    $body = @{
        key_id = $Credential.KeyId
        key_secret = $Credential.KeySecret
    } | ConvertTo-Json

    Write-Verbose "Requesting new bearer token from $tokenUrl"
    Write-Host "Authenticating to OPA API..." -ForegroundColor Yellow

    try {
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

        [switch]$IncludeHeaders
    )

    # Get token - will use cached token or prompt for credentials if needed
    $token = Get-OpaToken -Config $Config

    $url = if ($Endpoint -match '^https?://') { $Endpoint } else { "$($Config.opa_url)$Endpoint" }
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
        if ($IncludeHeaders) {
            $response = Invoke-WebRequest @params -TimeoutSec 30
            $content = $response.Content | ConvertFrom-Json
            return @{
                Content = $content
                Headers = $response.Headers
            }
        }
        else {
            $response = Invoke-RestMethod @params -TimeoutSec 30
            return $response
        }
    }
    catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        $errorBody = $_.ErrorDetails.Message
        throw "API request failed ($statusCode): $errorBody"
    }
}
