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

    # Get all domain controllers
    $domainControllers = @()
    try {
        $domainControllers = Get-ADDomainController -Filter * | Select-Object -ExpandProperty HostName
        Write-Verbose "Found $($domainControllers.Count) domain controllers: $($domainControllers -join ', ')"
    }
    catch {
        Write-Warning "Failed to enumerate domain controllers, using local machine: $_"
        $domainControllers = @($env:COMPUTERNAME)
    }

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

    foreach ($dc in $domainControllers) {
        Write-Verbose "Querying event log on $dc..."
        try {
            $events = Get-WinEvent -ComputerName $dc -FilterXml $filterXml -ErrorAction SilentlyContinue

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
                    DomainController = $dc
                    SubjectUserName = $eventData['SubjectUserName']
                    SubjectDomainName = $eventData['SubjectDomainName']
                    TargetUserName = $eventData['TargetUserName']
                    TargetDomainName = $eventData['TargetDomainName']
                }
            }

            $dcEventCount = ($events | Measure-Object).Count
            if ($dcEventCount -gt 0) {
                Write-Verbose "  Found $dcEventCount events on $dc"
            }
        }
        catch {
            Write-Warning "Failed to query event log on $dc : $_"
        }
    }

    # Remove duplicate events (same event may be logged on multiple DCs via replication)
    $uniqueEvents = $passwordEvents | Sort-Object TimeCreated, EventId, SubjectUserName -Unique

    Write-Verbose "Found $($uniqueEvents.Count) unique password change events (4723/4724) for $samAccountName in last $Days days"

    return [PSCustomObject]@{
        UserPrincipalName = $UserPrincipalName
        SamAccountName = $samAccountName
        AdUserFound = ($null -ne $adUser)
        PasswordLastSet = $passwordLastSet
        PasswordEvents = $uniqueEvents
        EventCount = $uniqueEvents.Count
        DomainControllersQueried = $domainControllers
    }
}
