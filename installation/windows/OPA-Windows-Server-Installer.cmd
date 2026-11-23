@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Okta Privileged Access (OPA) - Windows Server Enrollment Script
:: ============================================================================
:: This script enrolls a Windows server with Okta OPA (formerly ScaleFT/ASA)
::
:: Usage: OPA-Windows-Server-Installer.cmd [OPTIONS]
::
:: Options:
::   /token:VALUE      - Enrollment token (optional)
::                       If not provided and default is enrollment_token, agent installs
::                       without enrollment (manual enrollment required later)
::   /version:VALUE    - Specific agent version like "1.75.2" (optional, uses latest)
::   /reenroll         - Force re-enrollment: deletes device.token and the enrollment flag
::                       Agent remains installed, only enrollment data is cleared
::   /reinstall        - Force reinstallation: uninstalls and reinstalls the agent
::                       Use with /reenroll to also clear enrollment data
::   /upgrade          - Upgrade an already enrolled agent to the latest version (or to
::                       /version) and keep its enrollment. Does nothing if the installed
::                       version is already at or above the target. /version implies /upgrade
::                       To go back to an older version use /reinstall /version:VALUE
::
:: The downloaded MSI must have a valid Authenticode signature, and is checked against
:: the size and SHA3-512 published in dull.json. SHA3-512 needs PowerShell 7 on
:: Windows 11 / Server 2025; otherwise only the size is checked and a warning is logged.
::
:: Note: You can use either /switch:value or /switch=value syntax for value parameters
::
:: Examples:
::   OPA-Windows-Server-Installer.cmd
::   OPA-Windows-Server-Installer.cmd /token:eyJzIjoi...
::   OPA-Windows-Server-Installer.cmd /version:1.75.2
::   OPA-Windows-Server-Installer.cmd /token:eyJzIjoi... /version:1.75.2
::   OPA-Windows-Server-Installer.cmd /reenroll
::   OPA-Windows-Server-Installer.cmd /reinstall
::   OPA-Windows-Server-Installer.cmd /upgrade
::   OPA-Windows-Server-Installer.cmd /reenroll /reinstall
::   OPA-Windows-Server-Installer.cmd /token:eyJzIjoi... /version:1.75.2 /reenroll /reinstall
:: ============================================================================

set LOG_FILE=C:\sftd_bootstrap.log
set CONFIG_DIR=C:\Windows\System32\config\systemprofile\AppData\Local\ScaleFT
set STATE_DIR=%CONFIG_DIR%\state
set YAML_FILE=%CONFIG_DIR%\sftd.yaml
set TOKEN_FILE=%CONFIG_DIR%\enrollment.token
set DEVICE_TOKEN_FILE=%CONFIG_DIR%\device.token
set STATE_DEVICE_TOKEN_FILE=%STATE_DIR%\device.token
set ENROLLMENT_FLAG=%CONFIG_DIR%\enrollment.complete
set JSON_URL=https://dist.scaleft.com/repos/windows/stable/amd64/server-tools/dull.json
set BASE_URL=https://dist.scaleft.com/repos/windows/stable/amd64/server-tools
set TEMP_JSON=%TEMP%\scaleft_dull.json
:: Service name as registered by the MSI (its display name is "ScaleFT Server Tools")
set SERVICE_NAME=scaleft-server-tools
:: Install folder differs between agent releases; set by :FindSftd
set "SFTD_EXE="

:: Default enrollment token (can be overridden via command line)
set DEFAULT_TOKEN=enrollment_token

:: ============================================================================
:: Parse command line switches
:: ============================================================================

:: Initialize variables
set enrollment_token=%DEFAULT_TOKEN%
set SPECIFIC_VERSION=
set FORCE_REENROLL=0
set FORCE_REINSTALL=0
set TOKEN_PROVIDED=0
set DO_UPGRADE=0
set ALREADY_ENROLLED=0

:: Raw command line: cmd treats = as an argument delimiter, so %~1 loses trailing ==
set "RAW_ARGS=%*"

:: Parse all command line arguments
:parse_args
if "%~1"=="" goto :args_done

set arg=%~1

:: Check for help flags
if /i "!arg!"=="/help" goto :show_help
if /i "!arg!"=="/?" goto :show_help
if /i "!arg!"=="-help" goto :show_help
if /i "!arg!"=="-h" goto :show_help

:: Check for /reenroll flag (case insensitive)
if /i "!arg!"=="/reenroll" (
    set FORCE_REENROLL=1
    shift
    goto :parse_args
)

:: Check for /reinstall flag (case insensitive)
if /i "!arg!"=="/reinstall" (
    set FORCE_REINSTALL=1
    shift
    goto :parse_args
)

:: Check for /upgrade flag (case insensitive)
if /i "!arg!"=="/upgrade" (
    set DO_UPGRADE=1
    shift
    goto :parse_args
)

:: Check for legacy /force flag (backward compatibility - acts as both reenroll and reinstall)
if /i "!arg!"=="/force" (
    set FORCE_REENROLL=1
    set FORCE_REINSTALL=1
    call :Log "WARNING: /force is deprecated - use /reenroll and/or /reinstall instead"
    shift
    goto :parse_args
)

:: Check for /token switch (support both : and = separators)
echo !arg! | findstr /i "^/token[:=]" >nul
if !errorlevel! equ 0 (
    :: Extract value after /token: or /token= (both are 7 chars)
    set enrollment_token=!arg:~7!
    :: Recover trailing = padding (base64) that cmd strips from arguments
    set "RAW_AFTER=!RAW_ARGS:*/token=!"
    set "RAW_AFTER=!RAW_AFTER:~1!"
    set "RAW_TOKEN="
    for /f "tokens=1" %%t in ("!RAW_AFTER!") do set "RAW_TOKEN=%%~t"
    if defined RAW_TOKEN set "enrollment_token=!RAW_TOKEN!"
    set TOKEN_PROVIDED=1
    shift
    goto :parse_args
)

:: Check for /version switch (support both : and = separators)
echo !arg! | findstr /i "^/version[:=]" >nul
if !errorlevel! equ 0 (
    :: Extract value after /version: or /version= (both are 9 chars)
    set SPECIFIC_VERSION=!arg:~9!
    :: Asking for a specific version also counts as a request to upgrade
    set DO_UPGRADE=1
    shift
    goto :parse_args
)

:: Unknown parameter
call :Log "WARNING: Unknown parameter ignored: !arg!"
shift
goto :parse_args

:args_done

:: Log parsed parameters and check if enrollment token is available
set SKIP_ENROLLMENT=0
if "!enrollment_token!"=="enrollment_token" (
    set SKIP_ENROLLMENT=1
    call :Log "INFO: No enrollment token provided - agent will be installed without enrollment"
    call :Log "INFO: You can enroll the agent manually after installation"
) else (
    if !TOKEN_PROVIDED! equ 1 (
        call :Log "INFO: Using provided enrollment token"
    ) else (
        call :Log "INFO: Using default enrollment token"
    )
)

if not "!SPECIFIC_VERSION!"=="" (
    call :Log "INFO: Specific version requested: !SPECIFIC_VERSION!"
)

if !FORCE_REENROLL! equ 1 (
    call :Log "WARNING: Force re-enrollment requested"
    call :Log "WARNING: Will delete device.token and the enrollment flag"
)

if !FORCE_REINSTALL! equ 1 (
    call :Log "WARNING: Force reinstallation requested"
    call :Log "WARNING: Will uninstall and reinstall the agent"
)

:: ============================================================================
:: Handle force re-enrollment if requested
:: ============================================================================
if !FORCE_REENROLL! equ 1 (
    call :Log "INFO: Force re-enrollment mode - clearing enrollment data..."

    :: Stop the service if running (only if not doing full reinstall)
    if !FORCE_REINSTALL! equ 0 (
        call :Log "INFO: Attempting to stop %SERVICE_NAME% service..."
        sc query %SERVICE_NAME% 2>nul | find "RUNNING" >nul
        if !errorlevel! equ 0 (
            sc stop %SERVICE_NAME% >nul 2>&1
            timeout /t 5 /nobreak >nul
            call :Log "INFO: Service stopped"
        ) else (
            call :Log "INFO: Service not running"
        )
    )

    :: Delete enrollment flag
    if exist "%ENROLLMENT_FLAG%" (
        call :Log "INFO: Deleting enrollment flag: %ENROLLMENT_FLAG%"
        del /f /q "%ENROLLMENT_FLAG%" 2>nul
        if !errorlevel! equ 0 (
            call :Log "INFO: Enrollment flag deleted"
        ) else (
            call :Log "WARNING: Failed to delete enrollment flag"
        )
    )

    :: Delete device.token (state folder on current agents, config folder on others)
    for %%F in ("%STATE_DEVICE_TOKEN_FILE%" "%DEVICE_TOKEN_FILE%") do (
        if exist "%%~F" (
            call :Log "INFO: Deleting device token: %%~F"
            del /f /q "%%~F" 2>nul
            if !errorlevel! equ 0 (
                call :Log "INFO: Device token deleted"
            ) else (
                call :Log "WARNING: Failed to delete device token %%~F"
            )
        )
    )

    call :Log "INFO: Enrollment data cleared - will re-enroll with existing or new agent"
)

:: ============================================================================
:: Handle force reinstallation if requested
:: ============================================================================
if !FORCE_REINSTALL! equ 1 (
    call :Log "INFO: Force reinstallation mode - removing existing agent..."

    :: Stop the service if running
    call :Log "INFO: Attempting to stop %SERVICE_NAME% service..."
    sc query %SERVICE_NAME% 2>nul | find "RUNNING" >nul
    if !errorlevel! equ 0 (
        sc stop %SERVICE_NAME% >nul 2>&1
        timeout /t 5 /nobreak >nul
        call :Log "INFO: Service stopped"
    ) else (
        call :Log "INFO: Service not running"
    )

    :: Uninstall existing agent (located via the Uninstall registry key, not a fixed sftd.exe path)
    call :IsAgentInstalled
    if !errorlevel! equ 0 (
        call :Log "INFO: Uninstalling existing OPA agent..."
        powershell -NoProfile -Command "$e = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*ScaleFT*' } | Select-Object -First 1; if ($e -and $e.PSChildName -match '^\{.*\}$') { $p = Start-Process msiexec -ArgumentList '/x',$e.PSChildName,'/qn' -Wait -PassThru; if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) { exit 0 } else { exit $p.ExitCode } } else { exit 1 }" >nul 2>&1
        set UNINSTALL_RC=!errorlevel!
        if !UNINSTALL_RC! neq 0 (
            call :Log "WARNING: msiexec uninstall returned !UNINSTALL_RC! - trying Win32_Product"
            powershell -Command "Get-CimInstance -ClassName Win32_Product | Where-Object { $_.Name -like '*ScaleFT*' } | ForEach-Object { $_.Uninstall() }" >nul 2>&1
            timeout /t 10 /nobreak >nul
        )
        call :IsAgentInstalled
        if !errorlevel! equ 0 (
            call :Log "WARNING: Agent still appears to be installed after uninstall attempt"
            call :Log "WARNING: Proceeding with fresh installation attempt"
        ) else (
            call :Log "INFO: Agent uninstalled successfully"
        )
    ) else (
        call :Log "INFO: No existing agent installation found"
    )
    call :Log "INFO: Proceeding with fresh installation"
)

:: ============================================================================
:: Check if already enrolled (prevent duplicate enrollments on reboot)
:: ============================================================================
:: Skip checks if force flags are set
if !FORCE_REENROLL! equ 0 if !FORCE_REINSTALL! equ 0 (
    call :Log "INFO: Checking if OPA agent is already installed and enrolled..."

    :: Check if enrollment completion flag exists
    if exist "%ENROLLMENT_FLAG%" (
        :: Enrollment is only confirmed when device.token exists and enrollment.token is absent
        call :CheckDeviceToken
        if not exist "%TOKEN_FILE%" (
            if "!DEVICE_TOKEN_PRESENT!"=="1" (
                call :Log "INFO: Enrollment verified - device.token present, enrollment.token absent"
                set ALREADY_ENROLLED=1
            )
        )
        if !ALREADY_ENROLLED! equ 0 (
            call :Log "WARNING: Enrollment flag found but enrollment is not confirmed"
            if exist "%TOKEN_FILE%" call :Log "WARNING: enrollment.token still present - enrollment may be in progress or failed"
            if not "!DEVICE_TOKEN_PRESENT!"=="1" call :Log "WARNING: device.token not found - enrollment has not completed"
            call :Log "WARNING: Clearing enrollment flag and proceeding with re-enrollment"
            del /f /q "%ENROLLMENT_FLAG%" 2>nul
        )
    )

    :: Check if service is already running and enrollment is confirmed
    if !ALREADY_ENROLLED! equ 0 (
        sc query %SERVICE_NAME% 2>nul | find "RUNNING" >nul
        if !errorlevel! equ 0 (
            call :Log "INFO: %SERVICE_NAME% service is running"
            call :CheckDeviceToken
            if not exist "%TOKEN_FILE%" (
                if "!DEVICE_TOKEN_PRESENT!"=="1" (
                    call :Log "INFO: Enrollment confirmed - device.token present, enrollment.token absent"

                    :: Create enrollment flag for future boots
                    if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" 2>nul
                    echo Enrolled on %date% at %time% > "%ENROLLMENT_FLAG%"
                    set ALREADY_ENROLLED=1
                )
            )
            if !ALREADY_ENROLLED! equ 0 call :Log "INFO: Service is running but enrollment not yet confirmed - enrollment may still be in progress"
        )
    )

    :: Check if the agent is installed (but maybe not running yet)
    if !ALREADY_ENROLLED! equ 0 (
        call :IsAgentInstalled
        if !errorlevel! equ 0 (
            call :Log "WARNING: OPA agent is installed but service is not running"
            call :Log "WARNING: Attempting to start the service..."

            sc start %SERVICE_NAME% 2>nul
            if !errorlevel! equ 0 (
                call :Log "INFO: Successfully started %SERVICE_NAME% service"
                call :Log "INFO: Waiting for enrollment to complete..."
                call :WaitForEnrollment
                if !errorlevel! equ 0 (
                    :: Create enrollment flag only after enrollment is confirmed
                    if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" 2>nul
                    echo Enrolled on %date% at %time% > "%ENROLLMENT_FLAG%"
                    set ALREADY_ENROLLED=1
                ) else (
                    call :Log "WARNING: Service started but enrollment did not complete - will attempt reinstallation"
                )
            ) else (
                call :Log "WARNING: Failed to start service - will attempt reinstallation"
            )
        )
    )

    :: Leftover enrollment data without an installed agent (for example after an uninstall)
    :: is not an enrolled agent
    if !ALREADY_ENROLLED! equ 1 (
        call :IsAgentInstalled
        if !errorlevel! neq 0 (
            call :Log "WARNING: Enrollment data found but the agent is not installed - installing it"
            set ALREADY_ENROLLED=0
        )
    )

    if !ALREADY_ENROLLED! equ 1 (
        if !DO_UPGRADE! equ 0 (
            call :Log "INFO: Skipping enrollment to prevent duplicate registration"
            echo.
            echo ============================================================================
            echo OPA agent is already enrolled. Skipping installation.
            echo To upgrade the agent, run with /upgrade ^(or /version^)
            echo To force re-enrollment, run with /reenroll flag
            echo To force reinstallation, run with /reinstall flag
            echo ============================================================================
            exit /b 0
        )
        call :Log "INFO: Agent is enrolled and an upgrade was requested - keeping the existing enrollment"
        set SKIP_ENROLLMENT=1
    ) else (
        call :Log "INFO: No existing installation found - proceeding with enrollment"
    )
)

:: ============================================================================
:: Begin enrollment process
:: ============================================================================

:: Get hostname for canonical name
call :Log "INFO: Retrieving hostname..."
for /f %%i in ('hostname') do (set canonical_name=%%i)
if "!canonical_name!"=="" (
    call :Log "ERROR: Failed to retrieve hostname"
    exit /b 1
)
call :Log "INFO: Hostname: !canonical_name!"

:: Create configuration directory
call :Log "INFO: Creating configuration directory..."
if not exist "%CONFIG_DIR%" (
    mkdir "%CONFIG_DIR%" 2>nul
    if !errorlevel! neq 0 (
        call :Log "ERROR: Failed to create directory %CONFIG_DIR%"
        exit /b 1
    )
    call :Log "INFO: Created directory %CONFIG_DIR%"
) else (
    call :Log "INFO: Directory already exists: %CONFIG_DIR%"
)

:: Create sftd.yaml configuration file (an upgrade keeps the existing one)
if !ALREADY_ENROLLED! equ 1 if exist "%YAML_FILE%" (
    call :Log "INFO: Existing sftd.yaml found - leaving it unchanged"
    goto :yaml_done
)
call :Log "INFO: Creating sftd.yaml configuration file..."
echo CanonicalName: !canonical_name! > "%YAML_FILE%"
if !errorlevel! neq 0 (
    call :Log "ERROR: Failed to create sftd.yaml file"
    exit /b 1
)
echo BrokeredLoginGracePeriodInSeconds: 60 >> "%YAML_FILE%"
if !errorlevel! neq 0 (
    call :Log "ERROR: Failed to append to sftd.yaml file"
    exit /b 1
)
call :Log "INFO: Successfully created sftd.yaml file"
:yaml_done

:: Write enrollment token (if provided)
if !SKIP_ENROLLMENT! equ 0 (
    call :Log "INFO: Writing enrollment token..."
    echo !enrollment_token! > "%TOKEN_FILE%"
    if !errorlevel! neq 0 (
        call :Log "ERROR: Failed to write enrollment token"
        exit /b 1
    )
    call :Log "INFO: Successfully wrote enrollment token"
) else (
    call :Log "INFO: Skipping enrollment token creation - agent will install without auto-enrollment"
)

:: ============================================================================
:: Determine MSI download URL
:: ============================================================================

if not "!SPECIFIC_VERSION!"=="" (
    :: Use specific version provided on command line
    :: URL format: https://dist.scaleft.com/.../server-tools/v1.100.2/ScaleFT-Server-Tools-1.100.2.msi
    call :Log "INFO: Using specific version: !SPECIFIC_VERSION!"
    set MSI_URL=%BASE_URL%/v!SPECIFIC_VERSION!/ScaleFT-Server-Tools-!SPECIFIC_VERSION!.msi
    call :Log "INFO: Constructed MSI URL: !MSI_URL!"
    set TARGET_VERSION=!SPECIFIC_VERSION!

    :: Version metadata is still needed to verify the download (best effort here)
    if exist "%TEMP_JSON%" del "%TEMP_JSON%" 2>nul
    powershell -Command "try { Invoke-WebRequest -Uri '%JSON_URL%' -OutFile '%TEMP_JSON%' -UseBasicParsing -ErrorAction Stop } catch { exit 1 }"
    if !errorlevel! neq 0 (
        call :Log "WARNING: Could not download version metadata - the download cannot be verified"
    )
) else (
    :: Fetch latest version information from JSON metadata
    call :Log "INFO: Fetching latest version information from %JSON_URL%..."
    powershell -Command "try { Invoke-WebRequest -Uri '%JSON_URL%' -OutFile '%TEMP_JSON%' -UseBasicParsing -ErrorAction Stop } catch { exit 1 }"
    if !errorlevel! neq 0 (
        call :Log "ERROR: Failed to download version metadata from %JSON_URL%"
        call :Log "ERROR: Check network connectivity and URL availability"
        exit /b 1
    )
    call :Log "INFO: Successfully downloaded version metadata"

    :: Parse JSON to extract relative MSI path using PowerShell
    :: JSON structure: { "releases": [{ "links": [{ "href": "v1.100.2/ScaleFT-Server-Tools-1.100.2.msi" }] }] }
    call :Log "INFO: Parsing version metadata..."
    for /f "delims=" %%i in ('powershell -Command "$json = Get-Content '%TEMP_JSON%' | ConvertFrom-Json; Write-Output $json.releases[0].links[0].href"') do set MSI_RELATIVE_PATH=%%i
    if "!MSI_RELATIVE_PATH!"=="" (
        call :Log "ERROR: Failed to parse MSI path from JSON metadata"
        call :Log "ERROR: JSON file may be malformed or structure has changed"
        call :Log "ERROR: Dumping JSON content to log for debugging..."
        if exist "%TEMP_JSON%" type "%TEMP_JSON%" >> "%LOG_FILE%"
        exit /b 1
    )

    :: Construct full MSI URL from base URL and relative path
    :: Path format is like "v1.100.2/ScaleFT-Server-Tools-1.100.2.msi"
    set MSI_URL=%BASE_URL%/!MSI_RELATIVE_PATH!
    call :Log "INFO: Relative path from JSON: !MSI_RELATIVE_PATH!"
    call :Log "INFO: Full MSI URL: !MSI_URL!"

    :: Extract version for logging
    for /f "tokens=1 delims=/" %%v in ("!MSI_RELATIVE_PATH!") do set DETECTED_VERSION=%%v
    call :Log "INFO: Latest available version: !DETECTED_VERSION!"
    set TARGET_VERSION=!DETECTED_VERSION:v=!
)

:: An enrolled agent that is already at or above the target version needs no upgrade
if !ALREADY_ENROLLED! equ 1 (
    call :CompareVersion
    if "!COMPARE_RESULT!"=="CURRENT" (
        call :Log "INFO: Installed version is already at or above !TARGET_VERSION! - nothing to do"
        call :Log "INFO: To install an older version, run with /reinstall /version:!TARGET_VERSION!"
        if exist "%TEMP_JSON%" del "%TEMP_JSON%" 2>nul
        exit /b 0
    )
)

:: Download MSI to temp file (msiexec /i does not support HTTP URLs on modern Windows)
set TEMP_MSI=C:\Okta\sftd_installer.msi
if not exist "C:\Okta" mkdir "C:\Okta"
call :Log "INFO: Downloading OPA Server Agent MSI to !TEMP_MSI!..."
call :Log "INFO: Source URL: !MSI_URL!"
powershell -Command "try { Invoke-WebRequest -Uri '!MSI_URL!' -OutFile '!TEMP_MSI!' -UseBasicParsing -ErrorAction Stop } catch { exit 1 }"
if !errorlevel! neq 0 (
    call :Log "ERROR: Failed to download MSI from !MSI_URL!"
    call :Log "ERROR: Check network connectivity and URL availability"
    exit /b 1
)
if not exist "!TEMP_MSI!" (
    call :Log "ERROR: Download appeared to succeed but MSI file not found at !TEMP_MSI!"
    exit /b 1
)
for %%A in ("!TEMP_MSI!") do set MSI_SIZE=%%~zA
if !MSI_SIZE! lss 1000000 (
    call :Log "ERROR: Downloaded file is too small (!MSI_SIZE! bytes) - may be an error page, not an MSI"
    if exist "!TEMP_MSI!" del "!TEMP_MSI!" 2>nul
    exit /b 1
)
call :Log "INFO: MSI downloaded successfully (!MSI_SIZE! bytes)"

:: Verify the Authenticode signature, then the size and SHA3-512 published in dull.json
set VERIFY_MSI=!TEMP_MSI!
call :VerifySignature
if "!SIG_FAILED!"=="1" (
    call :Log "ERROR: The downloaded MSI does not have a valid Authenticode signature - not installing it"
    if exist "!TEMP_MSI!" del "!TEMP_MSI!" 2>nul
    if exist "%TEMP_JSON%" del "%TEMP_JSON%" 2>nul
    exit /b 1
)
set VERIFY_VERSION=!TARGET_VERSION!
set VERIFY_JSON=%TEMP_JSON%
call :VerifyDownload
if exist "%TEMP_JSON%" del "%TEMP_JSON%" 2>nul
if "!VERIFY_FAILED!"=="1" (
    call :Log "ERROR: The downloaded MSI does not match dull.json - not installing it"
    if exist "!TEMP_MSI!" del "!TEMP_MSI!" 2>nul
    exit /b 1
)

:: Install OPA Server Agent
call :Log "INFO: Installing Okta OPA Server Agent..."
call :Log "INFO: This may take several minutes..."
if !ALREADY_ENROLLED! equ 1 (
    call :Log "INFO: Stopping %SERVICE_NAME% service for the upgrade..."
    sc stop %SERVICE_NAME% >nul 2>&1
    timeout /t 5 /nobreak >nul
)
msiexec /qn /i "!TEMP_MSI!" /L*V "C:\sftd_install.log"
set MSI_RC=!errorlevel!
if !MSI_RC! neq 0 (
    call :Log "ERROR: Failed to install OPA Server Agent (Exit Code: !MSI_RC!)"
    if !MSI_RC! equ 1638 call :Log "ERROR: Another version of the agent is already installed - run with /reinstall to replace it (required for a downgrade)"
    call :Log "ERROR: Check C:\sftd_install.log for details"
    if !ALREADY_ENROLLED! equ 1 sc start %SERVICE_NAME% >nul 2>&1
    if exist "!TEMP_MSI!" del "!TEMP_MSI!" 2>nul
    exit /b 1
)
if exist "!TEMP_MSI!" del "!TEMP_MSI!" 2>nul
call :Log "INFO: Successfully installed Okta OPA Server Agent"
if !ALREADY_ENROLLED! equ 1 sc start %SERVICE_NAME% >nul 2>&1

:: Verify installation
call :Log "INFO: Verifying installation..."
call :FindSftd
call :IsAgentInstalled
if !errorlevel! equ 0 (
    if defined SFTD_EXE (
        call :Log "INFO: Installation verified - sftd.exe found at !SFTD_EXE!"
    ) else (
        call :Log "INFO: Installation verified from the Uninstall registry key"
    )
) else (
    call :Log "WARNING: Could not confirm the installation from the registry or sftd.exe"
)

if !ALREADY_ENROLLED! equ 1 (
    call :Log "SUCCESS: Okta OPA agent upgraded to !TARGET_VERSION! - existing enrollment kept"
    echo.
    echo ============================================================================
    echo Upgrade completed successfully!
    echo Log file: %LOG_FILE%
    echo Installation log: C:\sftd_install.log
    echo ============================================================================
    exit /b 0
)

if !SKIP_ENROLLMENT! equ 0 (
    :: Wait for the agent to consume enrollment.token and create device.token
    call :Log "INFO: Waiting for enrollment to complete..."
    call :WaitForEnrollment
    if !errorlevel! equ 0 (
        :: Create enrollment flag only after enrollment is confirmed
        echo Enrolled on %date% at %time% > "%ENROLLMENT_FLAG%"
        call :Log "INFO: Enrollment flag created at: %ENROLLMENT_FLAG%"
        call :Log "SUCCESS: Okta OPA enrollment completed successfully"
        echo.
        echo ============================================================================
        echo Enrollment completed successfully!
        echo Log file: %LOG_FILE%
        echo Installation log: C:\sftd_install.log
        echo Enrollment flag: %ENROLLMENT_FLAG%
        echo.
        echo This script will not run again on future reboots unless the enrollment
        echo flag is deleted or the service is uninstalled.
        echo ============================================================================
    ) else (
        call :Log "ERROR: Enrollment did not complete within the expected time"
        call :Log "ERROR: enrollment.token was not consumed or device.token was not created"
        call :Log "ERROR: Check the OPA agent logs for details"
        echo.
        echo ============================================================================
        echo Installation succeeded but enrollment confirmation timed out.
        echo The agent may still complete enrollment - check logs.
        echo Log file: %LOG_FILE%
        echo ============================================================================
    )
) else (
    call :Log "SUCCESS: Okta OPA agent installed successfully (without enrollment)"
    echo.
    echo ============================================================================
    echo Installation completed successfully!
    echo Log file: %LOG_FILE%
    echo Installation log: C:\sftd_install.log
    echo Enrollment flag: %ENROLLMENT_FLAG%
    echo.
    echo NOTE: Agent was installed WITHOUT enrollment token.
    echo You will need to enroll this agent manually or run this script again
    echo with a valid enrollment token using /token:YOUR_TOKEN
    echo.
    echo This script will not run again on future reboots unless the enrollment
    echo flag is deleted or the service is uninstalled.
    echo ============================================================================
)
exit /b 0

:: ============================================================================
:: Display help information
:: ============================================================================
:show_help
echo.
echo ============================================================================
echo Okta Privileged Access (OPA) - Windows Server Enrollment Script
echo ============================================================================
echo.
echo Usage: %~nx0 [OPTIONS]
echo.
echo Options:
echo   /token:VALUE      - Enrollment token (optional)
echo                       If not provided and default is enrollment_token, agent installs
echo                       without enrollment (manual enrollment required later)
echo   /version:VALUE    - Specific agent version like "1.75.2" (optional, uses latest)
echo   /reenroll         - Force re-enrollment: deletes device.token and the enrollment flag
echo                       Agent remains installed, only enrollment data is cleared
echo   /reinstall        - Force reinstallation: uninstalls and reinstalls the agent
echo                       Use with /reenroll to also clear enrollment data
echo   /upgrade          - Upgrade an enrolled agent to the latest version (or /version)
echo                       and keep its enrollment. /version implies /upgrade
echo                       To go back to an older version use /reinstall /version:VALUE
echo   /help, /?         - Display this help message
echo.
echo Note: You can use either /switch:value or /switch=value syntax for value parameters
echo.
echo Examples:
echo   %~nx0
echo   %~nx0 /token:eyJzIjoi...
echo   %~nx0 /version:1.75.2
echo   %~nx0 /token:eyJzIjoi... /version:1.75.2
echo   %~nx0 /reenroll
echo   %~nx0 /reinstall
echo   %~nx0 /upgrade
echo   %~nx0 /reenroll /reinstall
echo   %~nx0 /token:eyJzIjoi... /version:1.75.2 /reenroll /reinstall
echo.
echo ============================================================================
exit /b 0

:: ============================================================================
:: Wait for enrollment: polls until enrollment.token absent AND device.token present
:: Returns 0 on success, 1 on timeout (120 seconds, polling every 5 seconds)
:: ============================================================================
:WaitForEnrollment
setlocal
set /a WAIT_COUNT=0
set /a WAIT_MAX=24
:WaitLoop
if !WAIT_COUNT! geq !WAIT_MAX! (
    endlocal
    exit /b 1
)
call :CheckDeviceToken
if not exist "%TOKEN_FILE%" (
    if "!DEVICE_TOKEN_PRESENT!"=="1" (
        endlocal
        exit /b 0
    )
)
set /a WAIT_COUNT+=1
timeout /t 5 /nobreak >nul
goto :WaitLoop

:: ============================================================================
:: Sets DEVICE_TOKEN_PRESENT=1 when device.token exists in the state folder or the config folder
:: ============================================================================
:CheckDeviceToken
set DEVICE_TOKEN_PRESENT=0
if exist "%STATE_DEVICE_TOKEN_FILE%" set DEVICE_TOKEN_PRESENT=1
if exist "%DEVICE_TOKEN_FILE%" set DEVICE_TOKEN_PRESENT=1
goto :eof

:: ============================================================================
:: Sets SFTD_EXE to the installed sftd.exe, or leaves it undefined. The install
:: folder differs between agent releases.
:: ============================================================================
:FindSftd
set "SFTD_EXE="
for %%D in ("Server Tools" "Server Agent") do (
    if not defined SFTD_EXE if exist "%ProgramFiles%\ScaleFT\%%~D\sftd.exe" set "SFTD_EXE=%ProgramFiles%\ScaleFT\%%~D\sftd.exe"
)
goto :eof

:: ============================================================================
:: Returns 0 when the agent is installed (sftd.exe found or MSI registered), 1 otherwise
:: ============================================================================
:IsAgentInstalled
call :FindSftd
if defined SFTD_EXE exit /b 0
powershell -NoProfile -Command "if (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*ScaleFT*' }) { exit 0 } else { exit 1 }" >nul 2>&1
exit /b !errorlevel!

:: ============================================================================
:: Checks the Authenticode signature of VERIFY_MSI (environment). Sets SIG_FAILED=1
:: unless the signature is valid; failing to check it also counts as a failure.
:: ============================================================================
:VerifySignature
set SIG_FAILED=0
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "$ErrorActionPreference='Stop'; try { $s = Get-AuthenticodeSignature -FilePath $env:VERIFY_MSI; $who = if ($s.SignerCertificate) { $s.SignerCertificate.Subject -replace '[&|<>^%%]','' } else { 'no signer' }; if ($s.Status -eq 'Valid') { 'INFO: Authenticode signature is valid - signed by ' + $who; 'RESULT:OK' } else { 'ERROR: Authenticode signature is not valid: ' + $s.Status + ' - ' + $who; 'RESULT:FAIL' } } catch { 'ERROR: Could not check the Authenticode signature: ' + $_.Exception.Message; 'RESULT:FAIL' }"`) do (
    if "%%L"=="RESULT:FAIL" (
        set SIG_FAILED=1
    ) else if not "%%L"=="RESULT:OK" (
        call :Log "%%L"
    )
)
goto :eof

:: ============================================================================
:: Checks the downloaded MSI against the size and SHA3-512 in dull.json.
:: Inputs (environment): VERIFY_MSI, VERIFY_VERSION, VERIFY_JSON
:: Sets VERIFY_FAILED=1 on a size or hash mismatch. A missing hash, an unlisted
:: version or a PowerShell without SHA3-512 support only logs a warning.
:: pwsh (PowerShell 7) is preferred because Windows PowerShell has no SHA3-512.
:: ============================================================================
:VerifyDownload
set VERIFY_FAILED=0
set PS_VERIFY=powershell
where pwsh >nul 2>&1
if !errorlevel! equ 0 set PS_VERIFY=pwsh
for /f "usebackq delims=" %%L in (`%PS_VERIFY% -NoProfile -Command "$ErrorActionPreference='Stop'; try { if (-not (Test-Path $env:VERIFY_JSON)) { 'WARNING: Version metadata is not available - size and hash cannot be verified'; 'RESULT:OK'; exit }; $j = Get-Content -Raw $env:VERIFY_JSON | ConvertFrom-Json; $r = @($j.releases) | Where-Object { $_.version -eq $env:VERIFY_VERSION } | Select-Object -First 1; if (-not $r) { 'WARNING: Version ' + $env:VERIFY_VERSION + ' is not listed in dull.json - size and hash cannot be verified'; 'RESULT:OK'; exit }; $l = @($r.links) | Where-Object { $_.rel -eq 'installer' } | Select-Object -First 1; $size = (Get-Item $env:VERIFY_MSI).Length; if ($l.length -and $size -ne $l.length) { 'ERROR: Downloaded MSI is ' + $size + ' bytes but dull.json lists ' + $l.length; 'RESULT:FAIL'; exit }; $want = $l.hashes.sha3_512; $t = 'System.Security.Cryptography.SHA3_512' -as [type]; if ($want -and $t -and $t::IsSupported) { $sha = $t::Create(); $s = [System.IO.File]::OpenRead($env:VERIFY_MSI); try { $h = $sha.ComputeHash($s) } finally { $s.Dispose() }; $got = [Convert]::ToBase64String($h).TrimEnd('=').Replace('+','-').Replace('/','_'); if ($got -ne $want) { 'ERROR: SHA3-512 mismatch - expected ' + $want + ' but downloaded file is ' + $got; 'RESULT:FAIL'; exit }; 'INFO: Size and SHA3-512 verified against dull.json' } elseif ($want) { 'WARNING: Size verified. SHA3-512 is not supported by this PowerShell/OS - needs PowerShell 7 on Windows 11 or Server 2025' } else { 'WARNING: Size verified. No hash is published for this version' }; 'RESULT:OK' } catch { 'WARNING: Could not verify the download: ' + $_.Exception.Message; 'RESULT:OK' }"`) do (
    if "%%L"=="RESULT:FAIL" (
        set VERIFY_FAILED=1
    ) else if not "%%L"=="RESULT:OK" (
        call :Log "%%L"
    )
)
goto :eof

:: ============================================================================
:: Compares the installed agent version with TARGET_VERSION.
:: Sets COMPARE_RESULT=CURRENT when the installed version is at or above the target,
:: UPGRADE otherwise (including when the versions cannot be compared).
:: ============================================================================
:CompareVersion
set COMPARE_RESULT=UPGRADE
for /f "usebackq delims=" %%L in (`powershell -NoProfile -Command "$e = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*ScaleFT*' } | Select-Object -First 1; $i = $null; $t = $null; if ($e -and [version]::TryParse($e.DisplayVersion, [ref]$i) -and [version]::TryParse($env:TARGET_VERSION, [ref]$t)) { if ($i.Build -ge 0 -and $i.Revision -le 0) { $i = [version]::new($i.Major, $i.Minor, $i.Build) }; 'INFO: Installed version ' + $i + ', target version ' + $t; if ($i -ge $t) { 'RESULT:CURRENT' } else { 'RESULT:UPGRADE' } } else { 'WARNING: Could not compare installed and target versions - proceeding with the upgrade'; 'RESULT:UPGRADE' }"`) do (
    if "%%L"=="RESULT:CURRENT" (
        set COMPARE_RESULT=CURRENT
    ) else if not "%%L"=="RESULT:UPGRADE" (
        call :Log "%%L"
    )
)
goto :eof

:: ============================================================================
:: Logging function with timestamp
:: ============================================================================
:Log
set msg=%~1
for /f "tokens=2-4 delims=/ " %%a in ('echo %date%') do set current_date=%%c-%%a-%%b
for /f "tokens=1-2 delims=: " %%a in ('echo %time%') do set current_time=%%a:%%b
echo [%current_date% %current_time%] %msg%
echo [%current_date% %current_time%] %msg% >> "%LOG_FILE%"
goto :eof
