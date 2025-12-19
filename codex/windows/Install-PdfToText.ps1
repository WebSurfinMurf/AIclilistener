<#
.SYNOPSIS
    Install pdftotext (Poppler) without admin privileges

.DESCRIPTION
    Downloads and extracts Poppler Windows binaries to user folder.
    No admin rights required.

.PARAMETER InstallPath
    Where to install (default: $HOME\Tools\poppler)

.EXAMPLE
    .\Install-PdfToText.ps1
#>

param(
    [string]$InstallPath = "$HOME\Tools\poppler"
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  pdftotext (Poppler) Portable Install" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# GitHub API to get latest release
$repoOwner = "oschwartz10612"
$repoName = "poppler-windows"
$apiUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"

Write-Host "[1/5] Getting latest release info..." -ForegroundColor Yellow

try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "PowerShell" }
    Write-Host "[INFO] Latest version: $($release.tag_name)" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to get release info: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Find the zip asset (not the source code)
$zipAsset = $release.assets | Where-Object { $_.name -like "Release-*.zip" } | Select-Object -First 1

if (-not $zipAsset) {
    Write-Host "[ERROR] Could not find release zip in assets" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Download URL: $($zipAsset.browser_download_url)" -ForegroundColor Gray
Write-Host "[INFO] File size: $([math]::Round($zipAsset.size / 1MB, 2)) MB" -ForegroundColor Gray

# Create install directory
Write-Host ""
Write-Host "[2/5] Creating install directory..." -ForegroundColor Yellow
Write-Host "[INFO] Install path: $InstallPath" -ForegroundColor Gray

if (Test-Path $InstallPath) {
    Write-Host "[WARN] Directory exists, will overwrite" -ForegroundColor Yellow
    Remove-Item -Path $InstallPath -Recurse -Force
}

New-Item -Path $InstallPath -ItemType Directory -Force | Out-Null
Write-Host "[OK] Directory created" -ForegroundColor Green

# Download
Write-Host ""
Write-Host "[3/5] Downloading Poppler..." -ForegroundColor Yellow

$zipPath = Join-Path $env:TEMP "poppler-download.zip"

try {
    $ProgressPreference = 'SilentlyContinue'  # Speed up download
    Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing
    Write-Host "[OK] Downloaded to: $zipPath" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Download failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Extract
Write-Host ""
Write-Host "[4/5] Extracting..." -ForegroundColor Yellow

try {
    Expand-Archive -Path $zipPath -DestinationPath $InstallPath -Force
    Write-Host "[OK] Extracted" -ForegroundColor Green

    # Clean up zip
    Remove-Item $zipPath -Force
} catch {
    Write-Host "[ERROR] Extraction failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Find pdftotext.exe
Write-Host ""
Write-Host "[5/5] Verifying installation..." -ForegroundColor Yellow

$pdftotext = Get-ChildItem -Path $InstallPath -Recurse -Filter "pdftotext.exe" | Select-Object -First 1

if (-not $pdftotext) {
    Write-Host "[ERROR] pdftotext.exe not found in extracted files" -ForegroundColor Red
    exit 1
}

$pdftotextPath = $pdftotext.FullName
$binDir = Split-Path $pdftotextPath

Write-Host "[OK] Found: $pdftotextPath" -ForegroundColor Green

# Test it
Write-Host ""
Write-Host "[TEST] Running pdftotext --help..." -ForegroundColor Yellow

try {
    $testOutput = & $pdftotextPath --help 2>&1 | Select-Object -First 3
    Write-Host $testOutput -ForegroundColor Gray
    Write-Host "[OK] pdftotext is working!" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] pdftotext test failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Installation Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "pdftotext location:" -ForegroundColor Cyan
Write-Host "  $pdftotextPath" -ForegroundColor White
Write-Host ""
Write-Host "To use manually:" -ForegroundColor Cyan
Write-Host "  & `"$pdftotextPath`" `"input.pdf`" `"output.txt`"" -ForegroundColor White
Write-Host ""
Write-Host "To add to PATH for this session:" -ForegroundColor Cyan
Write-Host "  `$env:PATH += `";$binDir`"" -ForegroundColor White
Write-Host ""
Write-Host "To add to PATH permanently (user level):" -ForegroundColor Cyan
Write-Host "  [Environment]::SetEnvironmentVariable('PATH', `$env:PATH + ';$binDir', 'User')" -ForegroundColor White
Write-Host ""

# Offer to add to PATH
$addToPath = Read-Host "Add to PATH for this session? (Y/n)"
if ($addToPath -ne 'n' -and $addToPath -ne 'N') {
    $env:PATH += ";$binDir"
    Write-Host "[OK] Added to PATH for this session" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now run: pdftotext --help" -ForegroundColor Cyan
}

# Save path to a config file for other scripts to find
$configPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path) ".pdftotext-path"
$pdftotextPath | Out-File -FilePath $configPath -Encoding UTF8 -NoNewline
Write-Host ""
Write-Host "[INFO] Path saved to $configPath for other scripts" -ForegroundColor Gray
