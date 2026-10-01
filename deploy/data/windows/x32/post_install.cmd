taskkill /IM "lodestar-service.exe" /F
taskkill /IM "Lodestar.exe" /F

rem Register lodestar:// URL scheme
reg add "HKCU\Software\Classes\lodestar" /ve /d "URL:Lodestar Protocol" /f
reg add "HKCU\Software\Classes\lodestar" /v "URL Protocol" /d "" /f
reg add "HKCU\Software\Classes\lodestar\shell\open\command" /ve /d "\"%~dp0Lodestar.exe\" \"%%1\"" /f

exit /b 0
