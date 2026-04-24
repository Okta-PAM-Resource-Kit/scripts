function Get-OpaAdConnection {
    [CmdletBinding()]
    param(
        [string]$Domain
    )

    $config = Initialize-OpaConfig
    $credential = Get-OpaCredential

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        try {
            $Domain = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
            Write-Verbose "Auto-detected domain: $Domain"
        }
        catch {
            throw "Failed to detect local domain. Please specify -Domain parameter."
        }
    }

    $endpoint = "/v1/teams/$($config.team_name)/connections/active_directory"
    Write-Verbose "Fetching AD connections from $endpoint"

    $response = Invoke-OpaApiRequest -Endpoint $endpoint -Config $config -Credential $credential

    $connections = @()
    if ($response.list) {
        $connections = $response.list
    }
    elseif ($response -is [array]) {
        $connections = $response
    }

    $matchingConnection = $connections | Where-Object {
        $_.domain -eq $Domain -or
        $_.domain -like "*$Domain*" -or
        $Domain -like "*$($_.domain)*"
    } | Select-Object -First 1

    if (-not $matchingConnection) {
        Write-Warning "No AD connection found matching domain '$Domain'"
        Write-Verbose "Available connections:"
        $connections | ForEach-Object { Write-Verbose "  - $($_.domain) (ID: $($_.id))" }
        return $null
    }

    Write-Verbose "Found matching AD connection: $($matchingConnection.domain) (ID: $($matchingConnection.id))"
    return $matchingConnection
}
