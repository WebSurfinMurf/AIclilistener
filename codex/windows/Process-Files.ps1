<#
.SYNOPSIS
    Process files listed in a CSV using Codex CLI with custom prompts

.DESCRIPTION
    Reads a CSV file where column 1 contains file paths, sends each file to Codex
    with a customizable prompt, and adds the result to a new column in the CSV.

.PARAMETER CsvPath
    Path to the input CSV file

.PARAMETER Prompt
    The prompt template to send to the AI. Use placeholders:
    {fileName} - File name (e.g., "report.xlsx")
    {extension} - File extension (e.g., ".xlsx")
    {filePath} - Full file path
    {fileContent} - Extracted file content
    Default is a summarization prompt.

.PARAMETER OutputPath
    Path for the output CSV (default: adds _processed to input filename)

.PARAMETER PipeName
    Named pipe to connect to (default: codex-service)

.PARAMETER FileColumn
    Name of the column containing file paths (default: first column)

.PARAMETER ResultColumn
    Name for the new result column (default: Result)

.PARAMETER MaxChars
    Maximum characters to read from each file (default: 50000)

.EXAMPLE
    .\Process-Files.ps1 -CsvPath "C:\files.csv"

.EXAMPLE
    .\Process-Files.ps1 -CsvPath "files.csv" -Prompt "Extract all dates from: {fileContent}"

.EXAMPLE
    .\Process-Files.ps1 -CsvPath "files.csv" -FileColumn "FilePath" -ResultColumn "Description"

.EXAMPLE
    .\Process-Files.ps1 -CsvPath "files.csv" -Resume

.EXAMPLE
    .\Process-Files.ps1
    # Opens file picker dialog to select CSV

.NOTES
    Requires CodexService.ps1 to be running
    Version: 2.0.0 - Parameterized prompt support
#>

param(
    [string]$CsvPath,

    [string]$Prompt,

    [string]$OutputPath,

    [string]$PipeName = "codex-service",

    [string]$FileColumn,

    [string]$ResultColumn = "Result",

    [int]$MaxChars = 50000,

    [switch]$Resume
)

# Default prompt template if not provided
if (-not $Prompt) {
    $Prompt = @"
Please read and summarize the following file.

FILE: {fileName}
TYPE: {extension}
PATH: {filePath}

--- FILE CONTENTS BEGIN ---
{fileContent}
--- FILE CONTENTS END ---

Provide a concise summary (2-4 sentences) describing:
1. What this file is/does
2. Key functionality or content
3. Any notable patterns or dependencies

Keep the summary brief and technical.
"@
}

# If no CSV path provided, show file picker dialog
if (-not $CsvPath) {
    Add-Type -AssemblyName System.Windows.Forms

    # Show explanation dialog first
    $explanation = @"
This tool reads a CSV and processes each file using AI with your custom prompt.

REQUIRED:
- First column must contain FULL PATHS to files
  (e.g., C:\Documents\report.docx)

OPTIONAL:
- Additional columns (Category, Notes, etc.) are kept as-is

OUTPUT:
- A new "Result" column will be added to your CSV

EXAMPLE INPUT:
FilePath,Category
C:\Documents\report.docx,Reports
C:\Code\app.py,Code

EXAMPLE OUTPUT:
FilePath,Category,Result
C:\Documents\report.docx,Reports,"AI response here..."
C:\Code\app.py,Code,"AI response here..."

Click OK to select your CSV file.
"@

    $infoResult = [System.Windows.Forms.MessageBox]::Show(
        $explanation,
        "Process Files - CSV Format",
        [System.Windows.Forms.MessageBoxButtons]::OKCancel,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($infoResult -ne [System.Windows.Forms.DialogResult]::OK) {
        Write-Host "[INFO] Cancelled. Exiting." -ForegroundColor Yellow
        exit 0
    }

    # Now show file picker
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select CSV file with file paths to process"
    $dialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $dialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')

    $result = $dialog.ShowDialog()

    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $CsvPath = $dialog.FileName
        Write-Host "[INFO] Selected: $CsvPath" -ForegroundColor Green
    } else {
        Write-Host "[INFO] No file selected. Exiting." -ForegroundColor Yellow
        exit 0
    }
}

# Ensure UTF-8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Colors for output
$Colors = @{
    Info = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Request = "Blue"
    Response = "Magenta"
}

function Write-Log {
    param([string]$Message, [string]$Level = "Info")
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = $Colors[$Level]
    if (-not $color) { $color = "White" }
    Write-Host "[$timestamp] $Message" -ForegroundColor $color
}

function Send-CodexRequest {
    param(
        [string]$PipeName,
        [string]$Prompt,
        [int]$TimeoutSeconds = 120
    )

    # Get the script directory to find CodexClient.ps1
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    $clientPath = Join-Path $scriptDir "CodexClient.ps1"

    if (-not (Test-Path $clientPath)) {
        Write-Log "CodexClient.ps1 not found at: $clientPath" "Error"
        return @{ Success = $false; Summary = "[ERROR] CodexClient.ps1 not found"; Response = $null }
    }

    Write-Log "Sending request via CodexClient.ps1..." "Request"

    try {
        # Call CodexClient.ps1 with -Raw to get JSON output
        $output = & $clientPath -PipeName $PipeName -Prompt $Prompt -Sandbox "read-only" -TimeoutSeconds $TimeoutSeconds -Raw 2>&1

        # Find the final success/error response
        $finalResult = $null
        $summary = ""

        foreach ($line in $output) {
            if ($line -match '^\{') {
                try {
                    $response = $line | ConvertFrom-Json
                    if ($response.status -eq "success") {
                        $finalResult = $response
                        if ($response.result.message) {
                            $summary = $response.result.message
                        }
                    } elseif ($response.status -eq "error") {
                        $finalResult = $response
                        $summary = "[ERROR] $($response.error)"
                    }
                } catch {
                    # Not valid JSON, skip
                }
            }
        }

        return @{
            Success = ($finalResult -and $finalResult.status -eq "success")
            Summary = $summary
            Response = $finalResult
        }

    } catch {
        Write-Log "Error calling CodexClient.ps1: $($_.Exception.Message)" "Error"
        return @{ Success = $false; Summary = "[ERROR] $($_.Exception.Message)"; Response = $null }
    }
}

# Load the file text extraction helper
$libPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "lib\Get-FileText.ps1"
if (Test-Path $libPath) {
    . $libPath
}

function Get-FilePreview {
    param(
        [string]$FilePath,
        [int]$MaxChars
    )

    if (-not (Test-Path $FilePath)) {
        return $null
    }

    try {
        # Use Get-FileText if available (handles xlsx, pptx, docx, pdf, etc.)
        if (Get-Command Get-FileText -ErrorAction SilentlyContinue) {
            return Get-FileText -FilePath $FilePath -MaxChars $MaxChars
        }

        # Fallback to simple text reading
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        if ($content.Length -gt $MaxChars) {
            $content = $content.Substring(0, $MaxChars) + "`n... [truncated at $MaxChars chars]"
        }
        return $content
    } catch {
        return $null
    }
}

# Main script
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  File Processor using Codex CLI" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Validate input
if (-not (Test-Path $CsvPath)) {
    Write-Log "CSV file not found: $CsvPath" "Error"
    exit 1
}

# Read CSV (with explicit UTF8 encoding to handle BOM)
Write-Log "Reading CSV: $CsvPath" "Info"
$csv = Import-Csv -Path $CsvPath -Encoding UTF8

if ($csv.Count -eq 0) {
    Write-Log "CSV is empty" "Error"
    exit 1
}

# Get actual column names from CSV
$rawColumns = @($csv[0].PSObject.Properties.Name)

# Clean column names - strip BOM (U+FEFF = char 65279) and other invisible chars
function Clean-ColumnName {
    param([string]$Name)
    # Remove BOM (U+FEFF), zero-width chars, and trim whitespace
    $cleaned = $Name -replace '[\uFEFF\uFFFE\u200B-\u200D\u2060]', ''
    return $cleaned.Trim()
}

$cleanColumns = $rawColumns | ForEach-Object { Clean-ColumnName $_ }

# Debug: show what we found
Write-Log "Raw column names: $($rawColumns -join ', ') (lengths: $($rawColumns | ForEach-Object { $_.Length }))" "Info"
Write-Log "Clean column names: $($cleanColumns -join ', ')" "Info"

# Determine file column
if (-not $FileColumn) {
    # Use the cleaned name for display, but we need the raw name to access data
    $FileColumn = $cleanColumns[0]
    Write-Log "Using first column for file paths: '$FileColumn'" "Info"
}

# Find the actual raw column name that matches our clean column name
$actualColumnName = $null
for ($i = 0; $i -lt $rawColumns.Count; $i++) {
    if ($cleanColumns[$i] -eq $FileColumn) {
        $actualColumnName = $rawColumns[$i]
        break
    }
}

if (-not $actualColumnName) {
    Write-Log "Column '$FileColumn' not found. Available: $($cleanColumns -join ', ')" "Error"
    exit 1
}

if ($actualColumnName -ne $FileColumn) {
    Write-Log "Note: Using raw column name '$actualColumnName' (has hidden chars)" "Info"
}

# Use the actual raw column name to access CSV data
$FileColumnRaw = $actualColumnName
# Use clean column names for display/output
$columns = $cleanColumns

# Set output path
if (-not $OutputPath) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $dir = [System.IO.Path]::GetDirectoryName($CsvPath)
    if (-not $dir) { $dir = "." }
    $OutputPath = Join-Path $dir "${baseName}_processed.csv"
}

Write-Log "Output will be saved to: $OutputPath" "Info"

# Check for resume capability
$alreadyProcessed = @{}
$outputColumns = $columns + @($ResultColumn)
$isFirstWrite = $true

if ($Resume -and (Test-Path $OutputPath)) {
    Write-Log "Resume mode: Loading previously processed files..." "Info"
    $existing = Import-Csv -Path $OutputPath -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($existing) {
        foreach ($row in $existing) {
            # Try both raw and clean column names
            $fp = $row.$FileColumnRaw
            if (-not $fp) { $fp = $row.$FileColumn }
            if ($fp) {
                $fp = $fp.Trim('"', "'", ' ')
                if ($fp -and $row.$ResultColumn -and $row.$ResultColumn -notlike "[ERROR]*" -and $row.$ResultColumn -notlike "[FILE NOT FOUND]*") {
                    $alreadyProcessed[$fp] = $row.$ResultColumn
                }
            }
        }
        Write-Log "Found $($alreadyProcessed.Count) already processed files" "Success"
        $isFirstWrite = $false
    }
} elseif (Test-Path $OutputPath) {
    # Not resume mode, clear existing output
    Remove-Item $OutputPath -Force
}

$toProcess = $csv.Count - $alreadyProcessed.Count
Write-Log "Processing $toProcess of $($csv.Count) rows..." "Info"
Write-Host ""

# Process each row
$rowNum = 0
$processedCount = 0
$skippedCount = 0

foreach ($row in $csv) {
    $rowNum++
    # Use raw column name to access data (handles BOM in column name)
    $filePath = $row.$FileColumnRaw

    # Handle null/empty file paths
    if (-not $filePath) {
        Write-Log "ROW $rowNum / $($csv.Count): Empty file path, skipping" "Warning"
        continue
    }

    # Trim quotes from file path if present (CSV sometimes double-quotes values)
    $filePath = $filePath.Trim('"', "'", ' ')

    # Check if already processed (resume mode)
    if ($filePath -and $alreadyProcessed.ContainsKey($filePath)) {
        $skippedCount++
        Write-Log "SKIP $rowNum / $($csv.Count): $filePath (already processed)" "Info"
        continue
    }

    Write-Host "========================================" -ForegroundColor Yellow
    Write-Log "ROW $rowNum / $($csv.Count): $filePath" "Info"
    Write-Host "========================================" -ForegroundColor Yellow

    # Create result row with all original columns - use actual column names from CSV
    $resultRow = [ordered]@{}
    foreach ($col in $csv[0].PSObject.Properties.Name) {
        $resultRow[$col] = $row.$col
    }

    # Check if file exists
    if (-not $filePath -or -not (Test-Path $filePath)) {
        Write-Log "File not found: $filePath" "Warning"
        $resultRow[$ResultColumn] = "[FILE NOT FOUND]"
        # Save incrementally
        [PSCustomObject]$resultRow | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Append:(-not $isFirstWrite)
        $isFirstWrite = $false
        $processedCount++
        continue
    }

    # Read file content
    $fileContent = Get-FilePreview -FilePath $filePath -MaxChars $MaxChars
    if (-not $fileContent) {
        Write-Log "Could not read file: $filePath" "Warning"
        $resultRow[$ResultColumn] = "[COULD NOT READ FILE]"
        # Save incrementally
        [PSCustomObject]$resultRow | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Append:(-not $isFirstWrite)
        $isFirstWrite = $false
        $processedCount++
        continue
    }

    # Get file info
    $fileInfo = Get-Item $filePath
    $extension = $fileInfo.Extension
    $fileName = $fileInfo.Name

    # Build Codex prompt using template with placeholder substitution
    $actualPrompt = $Prompt -replace '\{fileName\}', $fileName `
                           -replace '\{extension\}', $extension `
                           -replace '\{filePath\}', $filePath `
                           -replace '\{fileContent\}', $fileContent

    # Send to Codex via CodexClient.ps1
    $result = Send-CodexRequest -PipeName $PipeName -Prompt $actualPrompt -TimeoutSeconds 120

    if ($result.Success) {
        # Clean up result (remove extra whitespace)
        $resultText = $result.Summary -replace '\r?\n', ' ' -replace '\s+', ' '
        $resultRow[$ResultColumn] = $resultText.Trim()
        Write-Log "Result added successfully" "Success"
    } else {
        $resultRow[$ResultColumn] = $result.Summary
        Write-Log "Failed to get result" "Error"
    }

    # Save incrementally (crash-safe)
    [PSCustomObject]$resultRow | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Append:(-not $isFirstWrite)
    $isFirstWrite = $false
    $processedCount++

    # Small delay between requests
    Start-Sleep -Milliseconds 500

    Write-Host ""
}

# Final summary
Write-Host "========================================" -ForegroundColor Green
Write-Log "COMPLETE" "Success"
Write-Log "  Processed: $processedCount" "Success"
Write-Log "  Skipped (already done): $skippedCount" "Info"
Write-Log "  Total rows: $($csv.Count)" "Info"
Write-Host "========================================" -ForegroundColor Green

Write-Log "Results saved to: $OutputPath" "Success"
Write-Host ""

# Show preview of output
if (Test-Path $OutputPath) {
    Write-Log "Preview of output:" "Info"
    Import-Csv $OutputPath | Select-Object -First 3 | Format-Table -AutoSize
}

Write-Log "TIP: Use -Resume flag to continue from where you left off if interrupted" "Info"
