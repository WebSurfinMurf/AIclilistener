@echo off
REM Start Codex Named Pipe Service
REM This batch file launches the PowerShell service with execution policy bypass

echo Starting Codex Named Pipe Service...
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0CodexService.ps1" %*

pause
