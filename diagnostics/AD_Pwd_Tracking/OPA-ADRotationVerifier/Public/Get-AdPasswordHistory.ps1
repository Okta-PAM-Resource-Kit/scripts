function Get-AdPasswordHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserPrincipalName,

        [int]$Days = 7
    )

    $samAccountName = $UserPrincipalName.Split('@')[0]

    $adUser = $null
    $passwordLastSet = $null

    try {
        $adUser = Get-ADUser -Filter "UserPrincipalName -eq '$UserPrincipalName'" -Properties PasswordLastSet, SamAccountName
        if ($adUser) {
            $passwordLastSet = $adUser.PasswordLastSet
            Write-Verbose "Found AD user: $($adUser.SamAccountName), PasswordLastSet: $passwordLastSet"
        }
        else {
            $adUser = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'" -Properties PasswordLastSet, SamAccountName
            if ($adUser) {
                $passwordLastSet = $adUser.PasswordLastSet
                Write-Verbose "Found AD user by SAM: $($adUser.SamAccountName), PasswordLastSet: $passwordLastSet"
            }
        }
    }
    catch {
        Write-Warning "Failed to query AD for user $UserPrincipalName : $_"
    }

    $passwordEvents = @()
    $startTime = (Get-Date).AddDays(-$Days)

    try {
        $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4724) and TimeCreated[@SystemTime &gt;= '$($startTime.ToUniversalTime().ToString("o"))']]]
      and
      *[EventData[Data[@Name='TargetUserName']='$samAccountName']]
    </Select>
  </Query>
</QueryList>
"@
        $events = Get-WinEvent -FilterXml $filterXml -ErrorAction SilentlyContinue

        foreach ($event in $events) {
            $eventXml = [xml]$event.ToXml()
            $eventData = @{}
            $eventXml.Event.EventData.Data | ForEach-Object {
                $eventData[$_.Name] = $_.'#text'
            }

            $passwordEvents += [PSCustomObject]@{
                TimeCreated = $event.TimeCreated
                SubjectUserName = $eventData['SubjectUserName']
                SubjectDomainName = $eventData['SubjectDomainName']
                TargetUserName = $eventData['TargetUserName']
                TargetDomainName = $eventData['TargetDomainName']
            }
        }

        Write-Verbose "Found $($passwordEvents.Count) password reset events (4724) for $samAccountName in last $Days days"
    }
    catch {
        Write-Warning "Failed to query Security Event Log: $_"
    }

    return [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        SamAccountName = $samAccountName
        AdUserFound = ($null -ne $adUser)
        PasswordLastSet = $passwordLastSet
        PasswordEvents = $passwordEvents
        EventCount = $passwordEvents.Count
    }
}
