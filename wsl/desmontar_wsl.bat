@echo off
setlocal

set "SCRIPT=%~dp0desmontar_wsl.ps1"

cd /d "%SystemRoot%"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

echo.
pause
