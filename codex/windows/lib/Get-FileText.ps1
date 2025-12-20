<#
.SYNOPSIS
    Extract text content from various file types

.DESCRIPTION
    Extracts readable text from:
    - Text files (.txt, .md, .ps1, .py, .js, .json, .xml, .csv, etc.)
    - Excel files (.xlsx, .xls) - requires Excel installed
    - PowerPoint files (.pptx, .ppt) - requires PowerPoint installed
    - Word files (.docx, .doc) - requires Word installed
    - PDF files (.pdf) - uses Windows built-in or falls back to metadata

.PARAMETER FilePath
    Path to the file to extract text from

.PARAMETER MaxChars
    Maximum characters to return (default: 10000)

.EXAMPLE
    . .\lib\Get-FileText.ps1
    $content = Get-FileText -FilePath "C:\data\report.xlsx"

.NOTES
    Uses COM automation for Office files (requires Office installed)
    No additional packages required
#>

function Get-FileText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [int]$MaxChars = 10000
    )

    if (-not (Test-Path $FilePath)) {
        return $null
    }

    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    $content = ""

    try {
        switch -Regex ($extension) {
            # Text-based files
            '^\.(txt|md|ps1|psm1|psd1|py|js|ts|jsx|tsx|json|xml|yaml|yml|csv|log|ini|cfg|conf|sh|bash|bat|cmd|sql|html|htm|css|scss|sass|less|java|cs|cpp|c|h|hpp|go|rs|rb|php|pl|r|swift|kt|scala|vb|lua|awk|sed|makefile|dockerfile|gitignore|env)$' {
                $content = Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
            }

            # Excel files
            '^\.(xlsx|xls|xlsm)$' {
                $content = Get-ExcelText -FilePath $FilePath
            }

            # PowerPoint files
            '^\.(pptx|ppt|pptm)$' {
                $content = Get-PowerPointText -FilePath $FilePath
            }

            # Word files
            '^\.(docx|doc|docm)$' {
                $content = Get-WordText -FilePath $FilePath
            }

            # PDF files
            '^\.(pdf)$' {
                $content = Get-PdfText -FilePath $FilePath
            }

            # RTF files
            '^\.(rtf)$' {
                $content = Get-RtfText -FilePath $FilePath
            }

            default {
                # Try reading as text, fall back to file info
                try {
                    $content = Get-Content -Path $FilePath -Raw -Encoding UTF8 -ErrorAction Stop
                } catch {
                    $fileInfo = Get-Item $FilePath
                    $content = "[Binary file: $($fileInfo.Name), Size: $($fileInfo.Length) bytes, Modified: $($fileInfo.LastWriteTime)]"
                }
            }
        }
    } catch {
        $content = "[ERROR reading file: $($_.Exception.Message)]"
    }

    # Truncate if needed
    if ($content -and $content.Length -gt $MaxChars) {
        $content = $content.Substring(0, $MaxChars) + "`n`n... [truncated at $MaxChars characters]"
    }

    return $content
}

function Get-ExcelText {
    param([string]$FilePath)

    $excel = $null
    $workbook = $null
    $text = New-Object System.Text.StringBuilder

    try {
        $excel = New-Object -ComObject Excel.Application -ErrorAction Stop
        $excel.Visible = $false
        $excel.DisplayAlerts = $false

        $workbook = $excel.Workbooks.Open($FilePath, $false, $true)  # ReadOnly=true

        [void]$text.AppendLine("=== EXCEL FILE: $([System.IO.Path]::GetFileName($FilePath)) ===")
        [void]$text.AppendLine("Sheets: $($workbook.Sheets.Count)")
        [void]$text.AppendLine("")

        foreach ($sheet in $workbook.Sheets) {
            [void]$text.AppendLine("--- Sheet: $($sheet.Name) ---")

            $usedRange = $sheet.UsedRange
            if ($usedRange) {
                $rowCount = [Math]::Min($usedRange.Rows.Count, 100)  # Limit rows
                $colCount = [Math]::Min($usedRange.Columns.Count, 20)  # Limit columns

                for ($row = 1; $row -le $rowCount; $row++) {
                    $rowData = @()
                    for ($col = 1; $col -le $colCount; $col++) {
                        $cell = $usedRange.Cells.Item($row, $col)
                        $value = if ($cell.Value2) { $cell.Value2.ToString() } else { "" }
                        $rowData += $value
                    }
                    [void]$text.AppendLine(($rowData -join "`t"))
                }

                if ($usedRange.Rows.Count -gt 100) {
                    [void]$text.AppendLine("... [$($usedRange.Rows.Count - 100) more rows]")
                }
            }
            [void]$text.AppendLine("")
        }

        return $text.ToString()

    } catch {
        if ($_.Exception.Message -like "*Cannot create*" -or $_.Exception.Message -like "*80040154*") {
            return "[Excel not installed - cannot read .xlsx file]"
        }
        return "[ERROR reading Excel: $($_.Exception.Message)]"
    } finally {
        if ($workbook) {
            $workbook.Close($false)
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) | Out-Null
        }
        if ($excel) {
            $excel.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

function Get-PowerPointText {
    param([string]$FilePath)

    $ppt = $null
    $presentation = $null
    $text = New-Object System.Text.StringBuilder

    try {
        $ppt = New-Object -ComObject PowerPoint.Application -ErrorAction Stop
        # Note: PowerPoint.Application doesn't have a Visible property that can be set to false easily

        $presentation = $ppt.Presentations.Open($FilePath, $true, $false, $false)  # ReadOnly, Untitled, WithWindow=false

        [void]$text.AppendLine("=== POWERPOINT FILE: $([System.IO.Path]::GetFileName($FilePath)) ===")
        [void]$text.AppendLine("Slides: $($presentation.Slides.Count)")
        [void]$text.AppendLine("")

        foreach ($slide in $presentation.Slides) {
            [void]$text.AppendLine("--- Slide $($slide.SlideIndex) ---")

            foreach ($shape in $slide.Shapes) {
                if ($shape.HasTextFrame -eq -1) {  # msoTrue = -1
                    if ($shape.TextFrame.HasText -eq -1) {
                        $shapeText = $shape.TextFrame.TextRange.Text
                        if ($shapeText.Trim()) {
                            [void]$text.AppendLine($shapeText)
                        }
                    }
                }
            }

            # Get notes if present
            if ($slide.HasNotesPage -eq -1) {
                try {
                    $notesText = $slide.NotesPage.Shapes | Where-Object {
                        $_.PlaceholderFormat.Type -eq 2  # ppPlaceholderBody
                    } | ForEach-Object {
                        if ($_.HasTextFrame -eq -1 -and $_.TextFrame.HasText -eq -1) {
                            $_.TextFrame.TextRange.Text
                        }
                    }
                    if ($notesText) {
                        [void]$text.AppendLine("[Notes: $notesText]")
                    }
                } catch {
                    # Notes extraction failed, continue
                }
            }

            [void]$text.AppendLine("")
        }

        return $text.ToString()

    } catch {
        if ($_.Exception.Message -like "*Cannot create*" -or $_.Exception.Message -like "*80040154*") {
            return "[PowerPoint not installed - cannot read .pptx file]"
        }
        return "[ERROR reading PowerPoint: $($_.Exception.Message)]"
    } finally {
        if ($presentation) {
            $presentation.Close()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation) | Out-Null
        }
        if ($ppt) {
            $ppt.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt) | Out-Null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

function Get-WordText {
    param([string]$FilePath)

    $word = $null
    $doc = $null

    try {
        $word = New-Object -ComObject Word.Application -ErrorAction Stop
        $word.Visible = $false

        $doc = $word.Documents.Open($FilePath, $false, $true)  # ReadOnly=true

        $text = $doc.Content.Text

        return "=== WORD FILE: $([System.IO.Path]::GetFileName($FilePath)) ===`n`n$text"

    } catch {
        if ($_.Exception.Message -like "*Cannot create*" -or $_.Exception.Message -like "*80040154*") {
            return "[Word not installed - cannot read .docx file]"
        }
        return "[ERROR reading Word: $($_.Exception.Message)]"
    } finally {
        if ($doc) {
            $doc.Close($false)
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($doc) | Out-Null
        }
        if ($word) {
            $word.Quit()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null
        }
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
    }
}

function Get-PdfText {
    param([string]$FilePath)

    # Method 1: Try pdftotext (Poppler) - fast and reliable
    $pdftotextPath = Find-PdfToText
    if ($pdftotextPath) {
        $bestText = $null

        # Try multiple extraction modes for best results
        $modes = @(
            @("-layout", "-enc", "UTF-8"),   # Layout preserved
            @("-raw", "-enc", "UTF-8"),       # Raw content order
            @("-enc", "UTF-8")                # Simple extraction
        )

        foreach ($modeArgs in $modes) {
            try {
                $tempOutput = Join-Path $env:TEMP "pdfextract_$(Get-Random).txt"
                $cmdArgs = $modeArgs + @($FilePath, $tempOutput)

                $process = Start-Process -FilePath $pdftotextPath -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru

                if ($process.ExitCode -eq 0 -and (Test-Path $tempOutput)) {
                    $text = Get-Content $tempOutput -Raw -Encoding UTF8
                    Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue

                    if ($text -and $text.Trim().Length -gt 10) {
                        # Keep best result (most content)
                        if (-not $bestText -or $text.Length -gt $bestText.Length) {
                            $bestText = $text
                        }
                    }
                }
                if (Test-Path $tempOutput) { Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue }
            } catch {
                if (Test-Path $tempOutput) { Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue }
            }
        }

        if ($bestText) {
            return "=== PDF FILE: $([System.IO.Path]::GetFileName($FilePath)) ===`n`n$bestText"
        }
    }

    # Method 2: Fall back to metadata only
    try {
        $shell = New-Object -ComObject Shell.Application
        $folder = $shell.Namespace((Split-Path $FilePath))
        $file = $folder.ParseName((Split-Path $FilePath -Leaf))

        # Get PDF metadata
        $title = $folder.GetDetailsOf($file, 21)  # Title
        $author = $folder.GetDetailsOf($file, 20)  # Authors
        $pages = $folder.GetDetailsOf($file, 156)  # Pages

        $info = "=== PDF FILE: $([System.IO.Path]::GetFileName($FilePath)) ===`n"
        if ($title) { $info += "Title: $title`n" }
        if ($author) { $info += "Author: $author`n" }
        if ($pages) { $info += "Pages: $pages`n" }

        $info += "`n[PDF text extraction failed - only metadata available]"
        $info += "`n[Install pdftotext (Poppler) via Install-PdfToText.ps1 for full extraction]"

        return $info

    } catch {
        $fileInfo = Get-Item $FilePath
        return "[PDF file: $($fileInfo.Name), Size: $($fileInfo.Length) bytes - text extraction not available]"
    }
}

function Find-PdfToText {
    # Check 1: PATH
    $cmd = Get-Command pdftotext -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    # Check 2: .pdftotext-path config file (created by Install-PdfToText.ps1)
    $scriptDir = Split-Path -Parent $PSScriptRoot
    $configPath = Join-Path $scriptDir ".pdftotext-path"
    if (Test-Path $configPath) {
        $savedPath = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
        if ($savedPath -and (Test-Path $savedPath.Trim())) {
            return $savedPath.Trim()
        }
    }

    # Check 3: Common portable locations
    $locations = @(
        "$HOME\Tools\poppler\Library\bin\pdftotext.exe",
        "$HOME\Tools\poppler\bin\pdftotext.exe",
        "$HOME\poppler\Library\bin\pdftotext.exe",
        "$HOME\poppler\bin\pdftotext.exe",
        "$env:LOCALAPPDATA\poppler\Library\bin\pdftotext.exe",
        "$scriptDir\poppler\Library\bin\pdftotext.exe"
    )

    foreach ($loc in $locations) {
        if (Test-Path $loc) { return $loc }
    }

    return $null
}

function Get-RtfText {
    param([string]$FilePath)

    try {
        # Use RichTextBox to extract plain text from RTF
        Add-Type -AssemblyName System.Windows.Forms
        $rtb = New-Object System.Windows.Forms.RichTextBox
        $rtb.Rtf = Get-Content -Path $FilePath -Raw
        return $rtb.Text
    } catch {
        # Fall back to raw content
        return Get-Content -Path $FilePath -Raw
    }
}

# Function is available after dot-sourcing this file
