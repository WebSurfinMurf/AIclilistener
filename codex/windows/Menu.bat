@echo off
REM AIclilistener Menu Launcher
REM Bypasses execution policy restrictions

powershell -ExecutionPolicy Bypass -File "%~dp0Menu.ps1"
