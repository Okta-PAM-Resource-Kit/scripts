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
::                       If not provided and default is <enrollment_token>, agent installs
::                       without enrollment (manual enrollment required later)
::   /version:VALUE    - Specific agent version like "1.75.2" (optional, uses latest)
::   /reenroll         - Force re-enrollment: deletes enrollment flag and state directory
::                       Agent remains installed, only enrollment data is cleared
::   /reinstall        - Force reinstallation: uninstalls and reinstalls the agent
::                       Use with /reenroll to also clear enrollment data
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
::   OPA-Windows-Server-Installer.cmd /reenroll /reinstall
::   OPA-Windows-Server-Installer.cmd /token:eyJzIjoi... /version:1.75.2 /reenroll /reinstall
:: ============================================================================

set LOG_FILE=C:\sftd_bootstrap.log
set CONFIG_DIR=C:\Windows\System32\config\systemprofile\AppData\Local\ScaleFT
set STATE_DIR=%CONFIG_DIR%\state
set YAML_FILE=%CONFIG_DIR%\sftd.yaml
set TOKEN_FILE=%CONFIG_DIR%\enrollment.token
set ENROLLMENT_FLAG=%CONFIG_DIR%\enrollment.complete
set JSON_URL=https://dist.scaleft.com/repos/windows/stable/amd64/server-tools/dull.json
set BASE_URL=https://dist.scaleft.com/repos/windows/stable/amd64/server-tools
set TEMP_JSON=%TEMP%\scaleft_dull.json
set SFTD_EXE=C:\Program Files\ScaleFT\Server Agent\sftd.exe

:: Default enrollment token (can be overridden via command line)
set DEFAULT_TOKEN=<enrollment_token>

:: ============================================================================
:: Parse command line switches
:: ============================================================================

:: Initialize variables
set enrollment_token=%DEFAULT_TOKEN%
set SPECIFIC_VERSION=
set FORCE_REENROLL=0
set FORCE_REINSTALL=0
set TOKEN_PROVIDED=0

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
    :: Extract value after /token: or /token=
    set temp_arg=!arg!
    set temp_arg=!temp_arg:/token:=!
    set temp_arg=!temp_arg:/token=!
    set temp_arg=!temp_arg:/TOKEN:=!
    set temp_arg=!temp_arg:/TOKEN=!
    set enrollment_token=!temp_arg!
    set TOKEN_PROVIDED=1
    shift
    goto :parse_args
)

:: Check for /version switch (support both : and = separators)
echo !arg! | findstr /i "^/version[:=]" >nul
if !errorlevel! equ 0 (
    :: Extract value after /version: or /version=
    set temp_arg=!arg!
    set temp_arg=!temp_arg:/version:=!
    set temp_arg=!temp_arg:/version=!
    set temp_arg=!temp_arg:/VERSION:=!
    set temp_arg=!temp_arg:/VERSION=!
    set SPECIFIC_VERSION=!temp_arg!
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
if "!enrollment_token!"=="<enrollment_token>" (
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
    call :Log "WARNING: Will delete enrollment flag and state directory"
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
        call :Log "INFO: Attempting to stop ScaleFT Server Agent service..."
        sc query "ScaleFT Server Agent" 2>nul | find "RUNNING" >nul
        if !errorlevel! equ 0 (
            sc stop "ScaleFT Server Agent" >nul 2>&1
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

    :: Delete state directory recursively
    if exist "%STATE_DIR%" (
        call :Log "INFO: Deleting state directory: %STATE_DIR%"
        rd /s /q "%STATE_DIR%" 2>nul
        if !errorlevel! equ 0 (
            call :Log "INFO: State directory deleted"
        ) else (
            call :Log "WARNING: Failed to delete state directory"
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
    call :Log "INFO: Attempting to stop ScaleFT Server Agent service..."
    sc query "ScaleFT Server Agent" 2>nul | find "RUNNING" >nul
    if !errorlevel! equ 0 (
        sc stop "ScaleFT Server Agent" >nul 2>&1
        timeout /t 5 /nobreak >nul
        call :Log "INFO: Service stopped"
    ) else (
        call :Log "INFO: Service not running"
    )

    :: Uninstall existing agent
    if exist "%SFTD_EXE%" (
        call :Log "INFO: Uninstalling existing OPA agent..."
        wmic product where "name like '%%ScaleFT%%'" call uninstall /nointeractive >nul 2>&1
        timeout /t 10 /nobreak >nul
        if exist "%SFTD_EXE%" (
            call :Log "WARNING: Agent executable still exists after uninstall attempt"
        ) else (
            call :Log "INFO: Agent uninstalled successfully"
        )
    )

    call :Log "INFO: Agent uninstalled - will proceed with fresh installation"
)

:: ============================================================================
:: Check if already enrolled (prevent duplicate enrollments on reboot)
:: ============================================================================
:: Skip checks if force flags are set
if !FORCE_REENROLL! equ 0 if !FORCE_REINSTALL! equ 0 (
    call :Log "INFO: Checking if OPA agent is already installed and enrolled..."

    :: Check if enrollment completion flag exists
    if exist "%ENROLLMENT_FLAG%" (
        call :Log "INFO: Enrollment flag found - OPA agent already enrolled"
        call :Log "INFO: Skipping enrollment to prevent duplicate registration"
        echo.
        echo ============================================================================
        echo OPA agent is already enrolled. Skipping installation.
        echo To force re-enrollment, run with /reenroll flag
        echo To force reinstallation, run with /reinstall flag
        echo Enrollment flag: %ENROLLMENT_FLAG%
        echo ============================================================================
        exit /b 0
    )

    :: Check if service is already running
    sc query "ScaleFT Server Agent" 2>nul | find "RUNNING" >nul
    if !errorlevel! equ 0 (
        call :Log "INFO: ScaleFT Server Agent service is running"
        call :Log "INFO: Skipping enrollment to prevent duplicate registration"

        :: Create enrollment flag for future boots
        if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" 2>nul
        echo Enrolled > "%ENROLLMENT_FLAG%"

        echo.
        echo ============================================================================
        echo OPA agent is already enrolled and running. Skipping installation.
        echo ============================================================================
        exit /b 0
    )

    :: Check if agent executable exists (installed but maybe not running yet)
    if exist "%SFTD_EXE%" (
        call :Log "WARNING: OPA agent is installed but service is not running"
        call :Log "WARNING: Attempting to start the service..."

        sc start "ScaleFT Server Agent" 2>nul
        if !errorlevel! equ 0 (
            call :Log "INFO: Successfully started ScaleFT Server Agent service"

            :: Create enrollment flag for future boots
            if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%" 2>nul
            echo Enrolled > "%ENROLLMENT_FLAG%"

            echo.
            echo ============================================================================
            echo OPA agent was already installed. Service has been started.
            echo ============================================================================
            exit /b 0
        ) else (
            call :Log "WARNING: Failed to start service - will attempt reinstallation"
        )
    )

    call :Log "INFO: No existing installation found - proceeding with enrollment"
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

:: Create sftd.yaml configuration file
call :Log "INFO: Creating sftd.yaml configuration file..."
echo CanonicalName: !canonical_name! > "%YAML_FILE%"
if !errorlevel! neq 0 (
    call :Log "ERROR: Failed to create sftd.yaml file"
    exit /b 1
)
echo BrokeredLoginGracePeriodInSeconds: 30 >> "%YAML_FILE%"
if !errorlevel! neq 0 (
    call :Log "ERROR: Failed to append to sftd.yaml file"
    exit /b 1
)
call :Log "INFO: Successfully created sftd.yaml file"

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

    :: Clean up temporary JSON file
    if exist "%TEMP_JSON%" del "%TEMP_JSON%" 2>nul
)

:: Install OPA Server Agent
call :Log "INFO: Installing Okta OPA Server Agent from %MSI_URL%..."
call :Log "INFO: This may take several minutes..."
msiexec /qn /i "%MSI_URL%" /L*V "C:\sftd_install.log"
if !errorlevel! neq 0 (
    call :Log "ERROR: Failed to install OPA Server Agent (Exit Code: !errorlevel!)"
    call :Log "ERROR: Check C:\sftd_install.log for details"
    exit /b 1
)
call :Log "INFO: Successfully installed Okta OPA Server Agent"

:: Verify installation
call :Log "INFO: Verifying installation..."
if exist "%SFTD_EXE%" (
    call :Log "INFO: Installation verified - sftd.exe found"
) else (
    call :Log "WARNING: sftd.exe not found at expected location"
)

:: Create enrollment completion flag to prevent re-enrollment on reboot
call :Log "INFO: Creating enrollment completion flag..."
echo Enrolled on %date% at %time% > "%ENROLLMENT_FLAG%"
if !errorlevel! equ 0 (
    call :Log "INFO: Enrollment flag created at: %ENROLLMENT_FLAG%"
) else (
    call :Log "WARNING: Failed to create enrollment flag - script may re-run on reboot"
)

if !SKIP_ENROLLMENT! equ 0 (
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
echo                       If not provided and default is ^<enrollment_token^>, agent installs
echo                       without enrollment (manual enrollment required later)
echo   /version:VALUE    - Specific agent version like "1.75.2" (optional, uses latest)
echo   /reenroll         - Force re-enrollment: deletes enrollment flag and state directory
echo                       Agent remains installed, only enrollment data is cleared
echo   /reinstall        - Force reinstallation: uninstalls and reinstalls the agent
echo                       Use with /reenroll to also clear enrollment data
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
echo   %~nx0 /reenroll /reinstall
echo   %~nx0 /token:eyJzIjoi... /version:1.75.2 /reenroll /reinstall
echo.
echo ============================================================================
exit /b 0

:: ============================================================================
:: Logging function with timestamp
:: ============================================================================
:Log
set msg=%~1
for /f "tokens=1-3 delims=/" %%a in ('echo %date%') do set current_date=%%c-%%a-%%b
for /f "tokens=1-2 delims=: " %%a in ('echo %time%') do set current_time=%%a:%%b
echo [%current_date% %current_time%] %msg%
echo [%current_date% %current_time%] %msg% >> "%LOG_FILE%"
goto :eof
