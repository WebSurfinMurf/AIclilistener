<#
.SYNOPSIS
    Demo script showing how to use the Codex Named Pipe Service

.DESCRIPTION
    1. Prompts user to start the service
    2. Waits for confirmation
    3. Sends a request to summarize the CLAUDE.md file
    4. Displays the result

.EXAMPLE
    .\demo.ps1
#>

# Get the script's directory (where demo.ps1 is located)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Find the CLAUDE.md file (go up to AIclilistener root)
$ProjectRoot = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$ClaudeMdPath = Join-Path $ProjectRoot "CLAUDE.md"

# Verify file exists
if (-not (Test-Path $ClaudeMdPath)) {
    Write-Host "ERROR: Could not find CLAUDE.md at: $ClaudeMdPath" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Codex Named Pipe Service - DEMO" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This demo will:" -ForegroundColor White
Write-Host "  1. Connect to the Codex service" -ForegroundColor Gray
Write-Host "  2. Ask Codex to read and summarize: $ClaudeMdPath" -ForegroundColor Gray
Write-Host "  3. Display the executive summary" -ForegroundColor Gray
Write-Host ""

# Check if service is already running by trying ping
Write-Host "Checking if service is running..." -ForegroundColor Yellow
$pingResult = & "$ScriptDir\CodexClient.ps1" -Command ping -Raw 2>&1

if ($pingResult -like "*pong*") {
    Write-Host "Service is already running!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host "  SERVICE NOT RUNNING" -ForegroundColor Yellow
    Write-Host "========================================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Please start the service in a NEW PowerShell window:" -ForegroundColor White
    Write-Host ""
    Write-Host "  cd `"$ScriptDir`"" -ForegroundColor Cyan
    Write-Host "  .\Start-Service.bat" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Press ENTER when the service shows 'Waiting for client...' " -ForegroundColor Yellow -NoNewline
    Read-Host

    # Verify service is now running
    Write-Host "Verifying service..." -ForegroundColor Yellow
    $pingResult = & "$ScriptDir\CodexClient.ps1" -Command ping -Raw 2>&1

    if ($pingResult -notlike "*pong*") {
        Write-Host "ERROR: Service still not responding. Please check the service window." -ForegroundColor Red
        exit 1
    }
    Write-Host "Service is running!" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  SENDING REQUEST TO CODEX" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "File to summarize: $ClaudeMdPath" -ForegroundColor White
Write-Host ""

# Read the file content
$fileContent = Get-Content -Path $ClaudeMdPath -Raw

# Build the prompt
$prompt = @"
Please read the following CLAUDE.md file and provide an EXECUTIVE SUMMARY.

FILE: CLAUDE.md
PATH: $ClaudeMdPath

--- FILE CONTENTS ---
$fileContent
--- END OF FILE ---

Provide a brief executive summary (3-5 bullet points) covering:
- What this project does
- Key components/files
- Main use cases
- Any important configuration notes

Keep it concise and suitable for a manager or new team member.
"@

Write-Host "Sending request to Codex..." -ForegroundColor Yellow
Write-Host "(This may take 30-60 seconds)" -ForegroundColor Gray
Write-Host ""

# Send the request using CodexClient.ps1
& "$ScriptDir\CodexClient.ps1" -Prompt $prompt -Sandbox "read-only" -TimeoutSeconds 120

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  DEMO COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "You can now try your own prompts:" -ForegroundColor White
Write-Host ""
Write-Host "  .\CodexClient.ps1 -Prompt `"Your question here`"" -ForegroundColor Cyan
Write-Host "  .\CodexClient.ps1 -Command status" -ForegroundColor Cyan
Write-Host "  .\CodexClient.ps1 -Command shutdown" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Yellow
Read-Host
