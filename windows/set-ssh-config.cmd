:: This script creates a properly formated .ssh/config file to facilitate
:: native SSH command use of sft.exe for authentication to ASA protected servers.
:: No warranty expressed or implied, use at your own risk.

:: suppress console output
@echo off


::get 8.8 name for userprofile
for %%i in ("%USERPROFILE%") do set USERPROFILE-SHORT=%%~si

::get 8.3 name for ScaleFT Client Tools if installed
if exist "C:\Program Files (x86)\ScaleFT\bin\sft.exe" (
	for %%i in ("C:\Program Files (x86)\ScaleFT\bin\sft.exe") do set SFT-Path=%%~si
	Echo Found system-wide installation of ScaleFT Client Tools.
) else (
	if exist "%USERPROFILE%\AppData\Local\Apps\ScaleFT\bin\sft.exe" (
		for %%i in ("%USERPROFILE%\AppData\Local\Apps\ScaleFT\bin\sft.exe") do set SFT-Path=%%~si
		Echo Found user specific installation of ScaleFT Client Tools.
	) else (
		Echo ScaleFT Client Tools is not installed.  Download them from 
		Echo https://dist.scaleft.com/client-tools/windows/latest/ 
		Echo and run this script again.
	)
)

if defined SFT-Path (
	:: create the .ssh directory if it does not exist.
	mkdir "%USERPROFILE%\.ssh" 2> nul
	:: write Match stanza to .ssh/config
	echo # This Match stanza allows SSH to leverage sft.exe for server name resolution and authentication.  >> "%USERPROFILE%\.ssh\config"
	echo Match exec "%SFT-path% resolve -q  %%h" >> "%USERPROFILE%\.ssh\config"
	echo     ProxyCommand %SFT-Path% proxycommand  %%h >> "%USERPROFILE%\.ssh\config"
	echo     UserKnownHostsFile %USERPROFILE-SHORT%\AppData\Local\ScaleFT\proxycommand_known_hosts >> "%USERPROFILE%\.ssh\config"
)
