<#
.SYNOPSIS
    Test PDF text extraction methods

.DESCRIPTION
    Tests various methods to extract text from a PDF file with detailed logging.
    Shows full extracted text content.

.PARAMETER PdfPath
    Path to the PDF file to test

.PARAMETER OutputFile
    Optional: Save extracted text to this file

.PARAMETER PreviewOnly
    Only show first 500 characters instead of full text

.EXAMPLE
    .\Test-PdfExtract.ps1 -PdfPath "C:\Users\websu\Downloads\RobotRev.fall23.Murphy.pdf"

.EXAMPLE
    .\Test-PdfExtract.ps1 -PdfPath "document.pdf" -OutputFile "extracted.txt"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$PdfPath,

    [string]$OutputFile,

    [switch]$PreviewOnly
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

# Store best extraction result
$bestContent = $null
$bestMethod = $null

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

    # Try multiple extraction modes for best results
    $modes = @(
        @{ Name = "Layout preserved"; Args = @("-layout", "-enc", "UTF-8") },
        @{ Name = "Raw content order"; Args = @("-raw", "-enc", "UTF-8") },
        @{ Name = "Simple extraction"; Args = @("-enc", "UTF-8") }
    )

    foreach ($mode in $modes) {
        Write-Host ""
        Write-Host "[INFO] Trying: $($mode.Name)..." -ForegroundColor Gray

        $tempOutput = Join-Path $env:TEMP "pdftest_$(Get-Random).txt"
        $args = $mode.Args + @($PdfPath, $tempOutput)

        Write-Host "[INFO] Command: $pdftotextPath $($args -join ' ')" -ForegroundColor Gray

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $process = Start-Process -FilePath $pdftotextPath -ArgumentList $args -Wait -NoNewWindow -PassThru
            $stopwatch.Stop()

            if ($process.ExitCode -eq 0 -and (Test-Path $tempOutput)) {
                $content = Get-Content $tempOutput -Raw -Encoding UTF8
                Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue

                if ($content -and $content.Trim().Length -gt 0) {
                    $charCount = $content.Length
                    $lineCount = ($content -split "`n").Count
                    $wordCount = ($content -split '\s+' | Where-Object { $_ }).Count

                    Write-Host "[SUCCESS] $($mode.Name): $charCount chars, $lineCount lines, $wordCount words in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green

                    # Keep best result (most content)
                    if (-not $bestContent -or $content.Length -gt $bestContent.Length) {
                        $bestContent = $content
                        $bestMethod = "pdftotext ($($mode.Name))"
                    }
                } else {
                    Write-Host "[WARN] $($mode.Name): Empty output" -ForegroundColor Yellow
                }
            } else {
                Write-Host "[FAIL] $($mode.Name): Exit code $($process.ExitCode)" -ForegroundColor Red
                if (Test-Path $tempOutput) { Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue }
            }
        } catch {
            $stopwatch.Stop()
            Write-Host "[FAIL] $($mode.Name): $($_.Exception.Message)" -ForegroundColor Red
            if (Test-Path $tempOutput) { Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue }
        }
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
# Method 2: Word COM (skip if pdftotext worked)
# ============================================
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "METHOD 2: Microsoft Word COM" -ForegroundColor Yellow
Write-Host "----------------------------------------" -ForegroundColor Yellow

if ($bestContent -and $bestContent.Length -gt 100) {
    Write-Host "[SKIP] pdftotext succeeded, skipping Word method (slow and unreliable)" -ForegroundColor Gray
} else {
    $word = $null
    $doc = $null
    $timeoutSeconds = 30

    Write-Host "[WARN] Word can hang on PDFs - using $timeoutSeconds second timeout" -ForegroundColor Yellow

    try {
        $job = Start-Job -ScriptBlock {
            param($pdfPath)
            try {
                $w = New-Object -ComObject Word.Application
                $w.Visible = $false
                $w.DisplayAlerts = 0
                $d = $w.Documents.Open($pdfPath, $false, $true, $false)
                $text = $d.Content.Text
                $d.Close($false)
                $w.Quit()
                return $text
            } catch {
                return "ERROR: $($_.Exception.Message)"
            }
        } -ArgumentList $PdfPath

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $completed = Wait-Job -Job $job -Timeout $timeoutSeconds
        $stopwatch.Stop()

        if ($completed) {
            $text = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            if ($text -and -not $text.StartsWith("ERROR:") -and $text.Trim().Length -gt 0) {
                $charCount = $text.Length
                $lineCount = ($text -split "`n").Count

                Write-Host "[SUCCESS] Extracted $charCount chars, $lineCount lines in $($stopwatch.ElapsedMilliseconds)ms" -ForegroundColor Green

                if (-not $bestContent -or $text.Length -gt $bestContent.Length) {
                    $bestContent = $text
                    $bestMethod = "Word COM"
                }
            } else {
                Write-Host "[FAIL] Word returned: $text" -ForegroundColor Red
            }
        } else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

            # Kill orphaned Word processes
            Get-Process -Name "WINWORD" -ErrorAction SilentlyContinue | Where-Object {
                $_.StartTime -gt (Get-Date).AddSeconds(-$timeoutSeconds - 10)
            } | Stop-Process -Force -ErrorAction SilentlyContinue

            Write-Host "[FAIL] Word timed out after $timeoutSeconds seconds" -ForegroundColor Red
        }
    } catch {
        Write-Host "[FAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""

# ============================================
# Method 3: Shell metadata
# ============================================
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Host "METHOD 3: Shell Metadata" -ForegroundColor Yellow
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
    Write-Host "[NOTE] This method only extracts metadata, not text content" -ForegroundColor Yellow

} catch {
    Write-Host "[FAIL] Error: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# ============================================
# Results Summary
# ============================================
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  EXTRACTION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($bestContent) {
    $charCount = $bestContent.Length
    $lineCount = ($bestContent -split "`n").Count
    $wordCount = ($bestContent -split '\s+' | Where-Object { $_ }).Count

    Write-Host "[BEST METHOD] $bestMethod" -ForegroundColor Green
    Write-Host "[STATS] $charCount characters, $lineCount lines, $wordCount words" -ForegroundColor Green
    Write-Host ""

    # Save to file if requested
    if ($OutputFile) {
        $bestContent | Out-File -FilePath $OutputFile -Encoding UTF8
        Write-Host "[SAVED] Full text written to: $OutputFile" -ForegroundColor Green
        Write-Host ""
    }

    # Display content
    if ($PreviewOnly) {
        Write-Host "--- PREVIEW (first 500 chars) ---" -ForegroundColor Cyan
        Write-Host ($bestContent.Substring(0, [Math]::Min(500, $bestContent.Length))) -ForegroundColor White
        Write-Host "--- END PREVIEW ---" -ForegroundColor Cyan
    } else {
        Write-Host "--- FULL EXTRACTED TEXT ---" -ForegroundColor Cyan
        Write-Host ""
        Write-Host $bestContent -ForegroundColor White
        Write-Host ""
        Write-Host "--- END OF TEXT ---" -ForegroundColor Cyan
    }
} else {
    Write-Host "[FAIL] No text could be extracted from this PDF" -ForegroundColor Red
    Write-Host ""
    Write-Host "Possible reasons:" -ForegroundColor Yellow
    Write-Host "  - PDF contains only scanned images (needs OCR)" -ForegroundColor Gray
    Write-Host "  - PDF is encrypted or protected" -ForegroundColor Gray
    Write-Host "  - PDF uses unusual encoding" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Try:" -ForegroundColor Yellow
    Write-Host "  - Install pdftotext: .\Install-PdfToText.ps1" -ForegroundColor Gray
    Write-Host "  - Use OCR software for scanned PDFs" -ForegroundColor Gray
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
