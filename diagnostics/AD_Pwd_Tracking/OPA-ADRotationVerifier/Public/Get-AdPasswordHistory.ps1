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
        # Event ID 4723: User changed their own password
        # Event ID 4724: Password was reset by admin/service account
        $filterXml = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">
      *[System[(EventID=4723 or EventID=4724) and TimeCreated[@SystemTime &gt;= '$($startTime.ToUniversalTime().ToString("o"))']]]
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

            $eventType = switch ($event.Id) {
                4723 { 'SelfChange' }
                4724 { 'Reset' }
                default { 'Unknown' }
            }

            $passwordEvents += [PSCustomObject]@{
                TimeCreated = $event.TimeCreated
                EventId = $event.Id
                EventType = $eventType
                SubjectUserName = $eventData['SubjectUserName']
                SubjectDomainName = $eventData['SubjectDomainName']
                TargetUserName = $eventData['TargetUserName']
                TargetDomainName = $eventData['TargetDomainName']
            }
        }

        Write-Verbose "Found $($passwordEvents.Count) password change events (4723/4724) for $samAccountName in last $Days days"
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
