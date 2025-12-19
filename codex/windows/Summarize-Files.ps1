<#
.SYNOPSIS
    Summarize files listed in a CSV using Codex CLI

.DESCRIPTION
    Reads a CSV file where column 1 contains file paths, sends each file to Codex
    for summarization, and adds the summary to a new column in the CSV.

.PARAMETER CsvPath
    Path to the input CSV file

.PARAMETER OutputPath
    Path for the output CSV (default: adds _summarized to input filename)

.PARAMETER PipeName
    Named pipe to connect to (default: codex-service)

.PARAMETER FileColumn
    Name of the column containing file paths (default: first column)

.PARAMETER SummaryColumn
    Name for the new summary column (default: Summary)

.PARAMETER MaxChars
    Maximum characters to read from each file (default: 10000)

.EXAMPLE
    .\Summarize-Files.ps1 -CsvPath "C:\files.csv"

.EXAMPLE
    .\Summarize-Files.ps1 -CsvPath "files.csv" -FileColumn "FilePath" -SummaryColumn "Description"

.NOTES
    Requires CodexService.ps1 to be running
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$CsvPath,

    [string]$OutputPath,

    [string]$PipeName = "codex-service",

    [string]$FileColumn,

    [string]$SummaryColumn = "Summary",

    [int]$MaxChars = 10000
)

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

function Format-JsonPretty {
    param([string]$Json)
    try {
        $obj = $Json | ConvertFrom-Json
        return $obj | ConvertTo-Json -Depth 10
    } catch {
        return $Json
    }
}

function Send-CodexRequest {
    param(
        [string]$PipeName,
        [hashtable]$Request
    )

    # Format request as pretty JSON for display
    $requestJson = $Request | ConvertTo-Json -Depth 5
    $requestJsonCompact = $Request | ConvertTo-Json -Depth 5 -Compress

    Write-Log "REQUEST:" "Request"
    Write-Host $requestJson -ForegroundColor Blue
    Write-Host ""

    try {
        # Connect to named pipe
        $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".",
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut
        )

        $pipeClient.Connect(10000)  # 10 second timeout

        $reader = New-Object System.IO.StreamReader($pipeClient, [System.Text.Encoding]::UTF8)
        $writer = New-Object System.IO.StreamWriter($pipeClient, [System.Text.Encoding]::UTF8)
        $writer.AutoFlush = $true

        # Send request
        $writer.WriteLine($requestJsonCompact)

        # Collect responses
        $finalResult = $null
        $summary = ""

        while ($true) {
            $line = $reader.ReadLine()
            if ($null -eq $line) { break }

            try {
                $response = $line | ConvertFrom-Json

                # Display response
                Write-Log "RESPONSE ($($response.status)):" "Response"
                Write-Host (Format-JsonPretty $line) -ForegroundColor Magenta
                Write-Host ""

                # Extract summary from final result
                if ($response.status -eq "success") {
                    $finalResult = $response
                    if ($response.result.message) {
                        $summary = $response.result.message
                    }
                } elseif ($response.status -eq "error") {
                    $summary = "[ERROR] $($response.error)"
                }

            } catch {
                Write-Log "Raw: $line" "Warning"
            }
        }

        $reader.Dispose()
        $writer.Dispose()
        $pipeClient.Dispose()

        return @{
            Success = ($finalResult.status -eq "success")
            Summary = $summary
            Response = $finalResult
        }

    } catch [TimeoutException] {
        Write-Log "Connection timeout - is CodexService.ps1 running?" "Error"
        return @{ Success = $false; Summary = "[ERROR] Service not available"; Response = $null }
    } catch [System.IO.FileNotFoundException] {
        Write-Log "Pipe not found - start CodexService.ps1 first" "Error"
        return @{ Success = $false; Summary = "[ERROR] Service not running"; Response = $null }
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "Error"
        return @{ Success = $false; Summary = "[ERROR] $($_.Exception.Message)"; Response = $null }
    }
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
Write-Host "  File Summarizer using Codex CLI" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# Validate input
if (-not (Test-Path $CsvPath)) {
    Write-Log "CSV file not found: $CsvPath" "Error"
    exit 1
}

# Read CSV
Write-Log "Reading CSV: $CsvPath" "Info"
$csv = Import-Csv -Path $CsvPath

if ($csv.Count -eq 0) {
    Write-Log "CSV is empty" "Error"
    exit 1
}

# Determine file column
$columns = $csv[0].PSObject.Properties.Name
if (-not $FileColumn) {
    $FileColumn = $columns[0]
    Write-Log "Using first column for file paths: '$FileColumn'" "Info"
} elseif ($FileColumn -notin $columns) {
    Write-Log "Column '$FileColumn' not found. Available: $($columns -join ', ')" "Error"
    exit 1
}

# Set output path
if (-not $OutputPath) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $dir = [System.IO.Path]::GetDirectoryName($CsvPath)
    if (-not $dir) { $dir = "." }
    $OutputPath = Join-Path $dir "${baseName}_summarized.csv"
}

Write-Log "Output will be saved to: $OutputPath" "Info"
Write-Log "Processing $($csv.Count) rows..." "Info"
Write-Host ""

# Process each row
$results = @()
$rowNum = 0

foreach ($row in $csv) {
    $rowNum++
    $filePath = $row.$FileColumn

    Write-Host "========================================" -ForegroundColor Yellow
    Write-Log "ROW $rowNum / $($csv.Count): $filePath" "Info"
    Write-Host "========================================" -ForegroundColor Yellow

    # Create result row with all original columns
    $resultRow = [ordered]@{}
    foreach ($col in $columns) {
        $resultRow[$col] = $row.$col
    }

    # Check if file exists
    if (-not $filePath -or -not (Test-Path $filePath)) {
        Write-Log "File not found: $filePath" "Warning"
        $resultRow[$SummaryColumn] = "[FILE NOT FOUND]"
        $results += [PSCustomObject]$resultRow
        continue
    }

    # Read file content
    $fileContent = Get-FilePreview -FilePath $filePath -MaxChars $MaxChars
    if (-not $fileContent) {
        Write-Log "Could not read file: $filePath" "Warning"
        $resultRow[$SummaryColumn] = "[COULD NOT READ FILE]"
        $results += [PSCustomObject]$resultRow
        continue
    }

    # Get file info
    $fileInfo = Get-Item $filePath
    $extension = $fileInfo.Extension
    $fileName = $fileInfo.Name

    # Build Codex request - human readable
    $request = @{
        id = "summary-row-$rowNum"
        prompt = @"
Please read and summarize the following file.

FILE: $fileName
TYPE: $extension
PATH: $filePath

--- FILE CONTENTS BEGIN ---
$fileContent
--- FILE CONTENTS END ---

Provide a concise summary (2-4 sentences) describing:
1. What this file is/does
2. Key functionality or content
3. Any notable patterns or dependencies

Keep the summary brief and technical.
"@
        options = @{
            sandbox = "read-only"
            timeout_seconds = 120
        }
    }

    # Send to Codex
    $result = Send-CodexRequest -PipeName $PipeName -Request $request

    if ($result.Success) {
        # Clean up summary (remove extra whitespace)
        $summary = $result.Summary -replace '\r?\n', ' ' -replace '\s+', ' '
        $resultRow[$SummaryColumn] = $summary.Trim()
        Write-Log "Summary added successfully" "Success"
    } else {
        $resultRow[$SummaryColumn] = $result.Summary
        Write-Log "Failed to get summary" "Error"
    }

    $results += [PSCustomObject]$resultRow

    # Small delay between requests
    Start-Sleep -Milliseconds 500

    Write-Host ""
}

# Export results
Write-Host "========================================" -ForegroundColor Green
Write-Log "COMPLETE - Processed $($csv.Count) rows" "Success"
Write-Host "========================================" -ForegroundColor Green

$results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

Write-Log "Results saved to: $OutputPath" "Success"
Write-Host ""

# Show preview of results
Write-Log "Preview of results:" "Info"
$results | Select-Object -First 3 | Format-Table -AutoSize
