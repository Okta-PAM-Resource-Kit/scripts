@echo off
setlocal enabledelayedexpansion

set VERBOSE=
if "%~1"=="-v" set VERBOSE=-v

:: Define the output file
set OUTPUT_FILE=%COMPUTERNAME%_certificates_output.txt

:: Delete the output file if it already exists
if exist %OUTPUT_FILE% del %OUTPUT_FILE%

:: Check if the server is a domain controller using PowerShell
for /f "delims=" %%i in ('powershell -command "if(Get-WindowsFeature -Name 'AD-Domain-Services' | Where-Object { $_.InstallState -eq 'Installed' }) { Write-Output 'DC' } else { Write-Output 'Member' }"') do set SERVER_TYPE=%%i

if "%SERVER_TYPE%"=="DC" (
    set SERVER_ROLE=domain controller
) else (
    set SERVER_ROLE=member server
)

echo ################################################################ >> %OUTPUT_FILE%
echo ## Certificate store report for %SERVER_ROLE%: %COMPUTERNAME% ## >> %OUTPUT_FILE% 
echo ################################################################ >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%

:: Print the Enterprise Root, CA, and NTAuth stores
echo ############################## >> %OUTPUT_FILE%
echo ### Enterprise Root store: ### >> %OUTPUT_FILE%
echo ############################## >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
certutil -enterprise -store %VERBOSE% Root >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo ############################## >> %OUTPUT_FILE%
echo #### Enterprise CA store: #### >> %OUTPUT_FILE%
echo ############################## >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
certutil -enterprise -store %VERBOSE% CA >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo ############################## >> %OUTPUT_FILE%
echo ## Enterprise NTAuth store: ## >> %OUTPUT_FILE%
echo ############################## >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
certutil -enterprise -store %VERBOSE% NTAuth >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%

:: Print the local Root, CA, and NTAuth stores
echo ######################### >> %OUTPUT_FILE%
echo ### Local Root store: ### >> %OUTPUT_FILE%
echo ######################### >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
certutil -store %VERBOSE% Root >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo ######################### >> %OUTPUT_FILE%
echo #### Local CA store: #### >> %OUTPUT_FILE%
echo ######################### >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
certutil -store %VERBOSE% CA >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
echo ############################### >> %OUTPUT_FILE%
echo #### Local Personal store: #### >> %OUTPUT_FILE%
echo ############################### >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%
certutil -store %VERBOSE% My >> %OUTPUT_FILE%
echo. >> %OUTPUT_FILE%


if "%SERVER_TYPE%"=="DC" (
    :: Get the local domain DN (Distinguished Name) using PowerShell
    for /f "delims=" %%i in ('powershell -command "$d = (Get-ADDomain).DistinguishedName; Write-Output $d"') do set DOMAIN_DN=%%i

    :: Server is a domain controller
    echo. >> %OUTPUT_FILE%
    :: Print the ldap NTAuthCertificates store for the local domain
    echo ######################################## >> %OUTPUT_FILE%
    echo ## This is a Domain Controller.       ## >> %OUTPUT_FILE%
    echo ## ldap NTAuthCertificates store      ## >> %OUTPUT_FILE%
    echo ## for domain !DOMAIN_DN!: ## >> %OUTPUT_FILE%
    echo ######################################## >> %OUTPUT_FILE%
    echo. >> %OUTPUT_FILE%
    certutil -store %VERBOSE% "ldap:///CN=NTAuthCertificates,CN=Public Key Services,CN=Services,CN=Configuration,!DOMAIN_DN!" >> %OUTPUT_FILE%
    echo. >> %OUTPUT_FILE%
    :: Print the ldap Certificateion Authorities store for the local domain
    echo ######################################## >> %OUTPUT_FILE%
    echo ## This is a Domain Controller.       ## >> %OUTPUT_FILE%
    echo ## ldap Certificate Authorities store ## >> %OUTPUT_FILE%
    echo ## for domain !DOMAIN_DN!: ## >> %OUTPUT_FILE%
    echo ######################################## >> %OUTPUT_FILE%
    echo. >> %OUTPUT_FILE%
    :: Set LDAP Path
    set "LDAP_PATH=LDAP://CN=Certification Authorities,CN=Public Key Services,CN=Services,CN=Configuration,!DOMAIN_DN!"
    :: Set Output List File
    set "LIST_FILE=.\dn_list.txt"

    :: Run PowerShell Command to Enumerate DNs
    powershell -Command "& { $de = New-Object System.DirectoryServices.DirectoryEntry('!LDAP_PATH!'); $de.Children | ForEach-Object { $dn = $_.distinguishedName; Write-Output $dn | Out-File -Encoding ascii -Append -FilePath '!LIST_FILE!' } }"

    :: Iterate over DNs and call certutil
    for /f "tokens=*" %%i in (!LIST_FILE!) do (
       certutil -store %VERBOSE% "%%i" >> "%OUTPUT_FILE%"
       echo. >> %OUTPUT_FILE%
    )    
    echo. >> %OUTPUT_FILE%
    :: Clean up
    if exist "!LIST_FILE!" del "!LIST_FILE!"

) else (
    :: Server is a member server
    echo ################################### >> %OUTPUT_FILE%
    echo #### This is a Member Server.  #### >> %OUTPUT_FILE%
    echo ################################### >> %OUTPUT_FILE%
    echo. >> %OUTPUT_FILE%

)

echo Information has been written to %OUTPUT_FILE%
endlocal
