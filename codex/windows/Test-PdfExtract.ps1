<#
.SYNOPSIS
    Test PDF text extraction methods

.DESCRIPTION
    Tests various methods to extract text from a PDF file with detailed logging.

.PARAMETER PdfPath
    Path to the PDF file to test

.EXAMPLE
    .\Test-PdfExtract.ps1 -PdfPath "C:\Users\websu\Downloads\RobotRev.fall23.Murphy.pdf"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PdfPath
)

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PDF Text Extraction Test" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Validate file exists
if (-not (Test-Path $PdfPath)) {
    Write-Host "[ERROR] File not found: $PdfPath" -ForegroundColor Red
    exit 1
}

$fileInfo = Get-Item $PdfPath
Write-Host "[INFO] File: $($fileInfo.Name)" -ForegroundColor Green
Write-Host "[INFO] Size: $([math]::Round($fileInfo.Length / 1KB, 2)) KB" -ForegroundColor Green
Write-Host "[INFO] Path: $PdfPath" -ForegroundColor Green
Write-Host ""

# ============================================
# Method 1: pdftotext (Poppler)
# ============================================
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "METHOD 1: pdftotext (Poppler)" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

# Look for pdftotext in multiple locations
$pdftotextPath = $null

# Check 1: PATH
$pdftotextCmd = Get-Command pdftotext -ErrorAction SilentlyContinue
if ($pdftotextCmd) {
    $pdftotextPath = $pdftotextCmd.Source
    Write-Host "[INFO] Found in PATH: $pdftotextPath" -ForegroundColor Green
}

# Check 2: .pdftotext-path config file (created by Install-PdfToText.ps1)
if (-not $pdftotextPath) {
    $configPath = Join-Path (Split-Path $MyInvocation.MyCommand.Path) ".pdftotext-path"
    if (Test-Path $configPath) {
        $savedPath = Get-Content $configPath -Raw
        if ($savedPath -and (Test-Path $savedPath.Trim())) {
            $pdftotextPath = $savedPath.Trim()
            Write-Host "[INFO] Found via config file: $pdftotextPath" -ForegroundColor Green
        }
    }
}

# Check 3: Common portable locations
if (-not $pdftotextPath) {
    $portableLocations = @(
        "$HOME\Tools\poppler\Library\bin\pdftotext.exe",
        "$HOME\Tools\poppler\bin\pdftotext.exe",
        "$HOME\poppler\Library\bin\pdftotext.exe",
        "$HOME\poppler\bin\pdftotext.exe",
        "$env:LOCALAPPDATA\poppler\Library\bin\pdftotext.exe",
        "$(Split-Path $MyInvocation.MyCommand.Path)\poppler\Library\bin\pdftotext.exe"
    )

    foreach ($loc in $portableLocations) {
        Write-Host "[INFO] Checking: $loc" -ForegroundColor Gray
        if (Test-Path $loc) {
            $pdftotextPath = $loc
            Write-Host "[INFO] Found at portable location: $pdftotextPath" -ForegroundColor Green
            break
        }
    }
}

if ($pdftotextPath) {
    Write-Host "[INFO] pdftotext found: $pdftotextPath" -ForegroundColor Green

    $tempOutput = Join-Path $env:TEMP "pdftest_$(Get-Random).txt"
    Write-Host "[INFO] Running: $pdftotextPath `"$PdfPath`" `"$tempOutput`"" -ForegroundColor Gray

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        & $pdftotextPath $PdfPath $tempOutput 2>&1
        $stopwatch.Stop()

        if (Test-Path $tempOutput) {
            $content = Get-Content $tempOutput -Raw
            Remove-Item $tempOutput -Force

            Write-Host "[SUCCESS] Extracted $($content.Length) characters in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green
            Write-Host "[PREVIEW] First 500 chars:" -ForegroundColor Cyan
            Write-Host ($content.Substring(0, [Math]::Min(500, $content.Length))) -ForegroundColor White
            Write-Host ""
        } else {
            Write-Host "[FAIL] No output file created" -ForegroundColor Red
        }
    } catch {
        $stopwatch.Stop()
        Write-Host "[FAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "[SKIP] pdftotext not found in:" -ForegroundColor Yellow
    Write-Host "  - PATH" -ForegroundColor Gray
    Write-Host "  - .pdftotext-path config file" -ForegroundColor Gray
    Write-Host "  - $HOME\Tools\poppler\" -ForegroundColor Gray
    Write-Host "  - $HOME\poppler\" -ForegroundColor Gray
    Write-Host "[TIP] Run: .\Install-PdfToText.ps1" -ForegroundColor Gray
}

Write-Host ""

# ============================================
# Method 2: Word COM
# ============================================
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "METHOD 2: Microsoft Word COM" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

$word = $null
$doc = $null

try {
    Write-Host "[INFO] Creating Word application..." -ForegroundColor Gray
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $word = New-Object -ComObject Word.Application -ErrorAction Stop
    Write-Host "[INFO] Word application created" -ForegroundColor Green

    $word.Visible = $false
    $word.DisplayAlerts = 0  # wdAlertsNone = 0
    Write-Host "[INFO] Word visibility=false, alerts=disabled" -ForegroundColor Gray

    Write-Host "[INFO] Opening PDF in Word (this may take a while)..." -ForegroundColor Gray
    Write-Host "[INFO] Word will convert PDF to editable format internally" -ForegroundColor Gray

    # Try to open with more specific parameters to suppress dialogs
    # Open(FileName, ConfirmConversions, ReadOnly, AddToRecentFiles, PasswordDocument,
    #      PasswordTemplate, Revert, WritePasswordDocument, WritePasswordTemplate, Format)
    $doc = $word.Documents.Open(
        $PdfPath,    # FileName
        $false,      # ConfirmConversions = false (don't ask)
        $true,       # ReadOnly = true
        $false,      # AddToRecentFiles = false
        "",          # PasswordDocument
        "",          # PasswordTemplate
        $false,      # Revert
        "",          # WritePasswordDocument
        "",          # WritePasswordTemplate
        0            # Format = wdOpenFormatAuto
    )

    $stopwatch.Stop()
    Write-Host "[INFO] PDF opened in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green

    Write-Host "[INFO] Extracting text content..." -ForegroundColor Gray
    $text = $doc.Content.Text

    Write-Host "[SUCCESS] Extracted $($text.Length) characters" -ForegroundColor Green
    Write-Host "[PREVIEW] First 500 chars:" -ForegroundColor Cyan
    Write-Host ($text.Substring(0, [Math]::Min(500, $text.Length))) -ForegroundColor White

} catch {
    Write-Host "[FAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[DETAIL] $($_.Exception.GetType().Name)" -ForegroundColor Red
} finally {
    Write-Host "[INFO] Cleaning up Word..." -ForegroundColor Gray
    if ($doc) {
        try {
            $doc.Close($false)
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
            Write-Host "[INFO] Document closed" -ForegroundColor Gray
        } catch {
            Write-Host "[WARN] Error closing document: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    if ($word) {
        try {
            $word.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
            Write-Host "[INFO] Word quit" -ForegroundColor Gray
        } catch {
            Write-Host "[WARN] Error quitting Word: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

Write-Host ""

# ============================================
# Method 3: Shell metadata
# ============================================
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "METHOD 3: Shell Metadata (fallback)" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

try {
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.Namespace((Split-Path $PdfPath))
    $file = $folder.ParseName((Split-Path $PdfPath -Leaf))

    $title = $folder.GetDetailsOf($file, 21)
    $author = $folder.GetDetailsOf($file, 20)
    $pages = $folder.GetDetailsOf($file, 156)

    Write-Host "[INFO] Title: $title" -ForegroundColor Green
    Write-Host "[INFO] Author: $author" -ForegroundColor Green
    Write-Host "[INFO] Pages: $pages" -ForegroundColor Green
    Write-Host "[NOTE] This method only gets metadata, not full text" -ForegroundColor Yellow

} catch {
    Write-Host "[FAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
