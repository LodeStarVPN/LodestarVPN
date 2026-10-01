set LodestarPath=%~dp0
echo %LodestarPath%

rem Define directories for logs
set "ORG_DIR=%AppData%\Lodestar"
set "USER_APP_DIR=%ORG_DIR%\Lodestar"
set "USER_LOG_DIR=%USER_APP_DIR%\log"
set "SYS_APP_DIR=%ProgramData%\Lodestar"
set "SYS_LOG_DIR=%SYS_APP_DIR%\log"
set "SYS_LOG_FILE=%SYS_LOG_DIR%\lodestar-service.log"

timeout /t 1
sc stop lodestar-service
sc delete lodestar-service
rem only our own tunnel service; never touch AmneziaVPN's or Dopamine's
sc stop AmneziaWGTunnel$Lodestar
sc delete AmneziaWGTunnel$Lodestar
taskkill /IM "lodestar-service.exe" /F
taskkill /IM "Lodestar.exe" /F

rem Delete the service log file under ProgramData
if exist "%SYS_LOG_FILE%" del /F /Q "%SYS_LOG_FILE%"
if exist "%SYS_LOG_DIR%" rmdir /S /Q "%SYS_LOG_DIR%"
rem Try to remove application dir if empty
rd "%SYS_APP_DIR%" 2>nul

rem Delete client logs under current user's AppData\Roaming (Organization\Application)
if exist "%USER_LOG_DIR%" rmdir /S /Q "%USER_LOG_DIR%"
rem Try to remove app and org directories if empty
rd "%USER_APP_DIR%" 2>nul
rd "%ORG_DIR%" 2>nul

rem Remove lodestar:// URL scheme registration
reg delete "HKCU\Software\Classes\lodestar" /f 2>nul

exit /b 0
