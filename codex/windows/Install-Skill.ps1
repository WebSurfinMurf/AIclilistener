<#
.SYNOPSIS
    Install AIclilistener skill for Codex CLI

.DESCRIPTION
    Copies the skill file to the Codex skills directory and provides
    instructions for enabling skills in Codex.

.EXAMPLE
    .\Install-Skill.ps1
#>

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  AIclilistener Skill Installer" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillSource = Join-Path $scriptDir "skill\SKILL.md"
$skillsDir = Join-Path $env:USERPROFILE ".codex\skills\aiclilistener"
$skillDest = Join-Path $skillsDir "SKILL.md"
$configPath = Join-Path $env:USERPROFILE ".codex\config.toml"

# Check source exists
if (-not (Test-Path $skillSource)) {
    Write-Host "[ERROR] Skill file not found: $skillSource" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Source: $skillSource" -ForegroundColor Gray
Write-Host "[INFO] Destination: $skillDest" -ForegroundColor Gray
Write-Host ""

# Create skills directory
if (-not (Test-Path $skillsDir)) {
    Write-Host "[INFO] Creating skills directory..." -ForegroundColor Yellow
    New-Item -Path $skillsDir -ItemType Directory -Force | Out-Null
    Write-Host "[OK] Created: $skillsDir" -ForegroundColor Green
} else {
    Write-Host "[OK] Skills directory exists" -ForegroundColor Green
}

# Copy skill file
Write-Host "[INFO] Copying skill file..." -ForegroundColor Yellow
Copy-Item -Path $skillSource -Destination $skillDest -Force
Write-Host "[OK] Installed: $skillDest" -ForegroundColor Green
Write-Host ""

# Check/update config
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Configuration" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$configExists = Test-Path $configPath
$skillsEnabled = $false

if ($configExists) {
    $configContent = Get-Content $configPath -Raw
    if ($configContent -match 'skills\s*=\s*true') {
        $skillsEnabled = $true
    }
}

if ($skillsEnabled) {
    Write-Host "[OK] Skills already enabled in config.toml" -ForegroundColor Green
} else {
    Write-Host "[WARN] Skills not enabled in Codex config" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "To enable skills, add this to $configPath :" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [experimental]" -ForegroundColor White
    Write-Host "  skills = true" -ForegroundColor White
    Write-Host ""
    Write-Host "Or run Codex with: codex --enable skills" -ForegroundColor Cyan
    Write-Host ""

    $enable = Read-Host "Add skills config now? (Y/n)"
    if ($enable -ne 'n' -and $enable -ne 'N') {
        $skillsConfig = @"

[experimental]
skills = true
"@
        if ($configExists) {
            Add-Content -Path $configPath -Value $skillsConfig
        } else {
            New-Item -Path (Split-Path $configPath) -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
            Set-Content -Path $configPath -Value $skillsConfig.TrimStart()
        }
        Write-Host "[OK] Skills enabled in config.toml" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "The 'aiclilistener' skill is now available in Codex." -ForegroundColor Cyan
Write-Host ""
Write-Host "Usage:" -ForegroundColor Yellow
Write-Host "  1. Start the service: .\Start-Service.bat" -ForegroundColor White
Write-Host "  2. In Codex, the skill will auto-activate for relevant tasks" -ForegroundColor White
Write-Host ""
