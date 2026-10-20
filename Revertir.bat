@echo off
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0framework\install.ps1" -Revert %*
echo.
pause
