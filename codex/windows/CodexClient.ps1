<#
.SYNOPSIS
    Codex CLI Client - Send requests to the Codex Named Pipe Service

.DESCRIPTION
    A PowerShell client that connects to the Codex Named Pipe Service and sends
    JSON requests. Can be used for testing or as a template for integration.

.PARAMETER PipeName
    Name of the named pipe to connect to (default: codex-service)

.PARAMETER Prompt
    The prompt/task to send to Codex

.PARAMETER Command
    Service command to execute (ping, status, shutdown)

.PARAMETER WorkingDirectory
    Working directory for Codex operations

.PARAMETER Sandbox
    Sandbox mode: read-only, workspace-write, full-auto, danger-full-access

.PARAMETER TimeoutSeconds
    Timeout for the operation in seconds

.PARAMETER Raw
    Output raw JSON without formatting

.EXAMPLE
    .\CodexClient.ps1 -Prompt "Write a hello world in Python"

.EXAMPLE
    .\CodexClient.ps1 -Command ping

.EXAMPLE
    .\CodexClient.ps1 -Prompt "Fix the bug" -WorkingDirectory "C:\Projects\MyApp" -Sandbox full-auto

.NOTES
    Author: AI CLI Listener Project
    Version: 1.0.0
#>

param(
    [string]$PipeName = "codex-service",
    [string]$Prompt,
    [ValidateSet("ping", "status", "shutdown")]
    [string]$Command,
    [string]$WorkingDirectory,
    [ValidateSet("read-only", "workspace-write", "full-auto", "danger-full-access")]
    [string]$Sandbox = "read-only",
    [int]$TimeoutSeconds = 300,
    [switch]$Raw
)

# Ensure UTF-8 encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Send-CodexRequest {
    param(
        [string]$PipeName,
        [string]$RequestJson
    )

    try {
        # Connect to named pipe
        $pipeClient = New-Object System.IO.Pipes.NamedPipeClientStream(
            ".",
            $PipeName,
            [System.IO.Pipes.PipeDirection]::InOut
        )

        Write-Host "[CLIENT] Connecting to \\.\pipe\$PipeName..." -ForegroundColor Gray

        # Try to connect with timeout
        $pipeClient.Connect(5000)  # 5 second connection timeout

        Write-Host "[CLIENT] Connected" -ForegroundColor Green

        # Setup streams
        $reader = New-Object System.IO.StreamReader($pipeClient, [System.Text.Encoding]::UTF8)
        $writer = New-Object System.IO.StreamWriter($pipeClient, [System.Text.Encoding]::UTF8)
        $writer.AutoFlush = $true

        try {
            # Send request
            Write-Host "[CLIENT] Sending request..." -ForegroundColor Cyan
            $writer.WriteLine($RequestJson)
            $writer.Flush()  # Explicit flush for PS 5.1 compatibility
            Write-Host "[CLIENT] Request sent, waiting for response..." -ForegroundColor Cyan

            # Read all responses until pipe closes
            $responses = @()
            while ($true) {
                $line = $reader.ReadLine()
                if ($null -eq $line) { break }

                $responses += $line

                # Parse and display
                try {
                    $json = $line | ConvertFrom-Json

                    if ($Raw) {
                        Write-Output $line
                    } else {
                        # Pretty display based on status
                        switch ($json.status) {
                            "processing" {
                                Write-Host "[PROCESSING] $($json.message)" -ForegroundColor Yellow
                            }
                            "streaming" {
                                if ($json.event.type -eq "item.completed" -and $json.event.item.type -eq "agent_message") {
                                    Write-Host "[AGENT] $($json.event.item.content)" -ForegroundColor Cyan
                                } elseif ($json.event.type) {
                                    Write-Host "[EVENT] $($json.event.type)" -ForegroundColor Gray
                                }
                            }
                            "success" {
                                Write-Host ""
                                Write-Host "========== RESULT ==========" -ForegroundColor Green
                                if ($json.result.message) {
                                    Write-Host $json.result.message -ForegroundColor White
                                }
                                Write-Host ""
                                Write-Host "[DONE] Duration: $($json.duration_ms)ms" -ForegroundColor Green
                            }
                            "error" {
                                Write-Host ""
                                Write-Host "========== ERROR ==========" -ForegroundColor Red
                                Write-Host $json.error -ForegroundColor Red
                                if ($json.duration_ms) {
                                    Write-Host "[FAILED] Duration: $($json.duration_ms)ms" -ForegroundColor Red
                                }
                            }
                            "ok" {
                                # Service command response
                                Write-Host ($json | ConvertTo-Json -Depth 5) -ForegroundColor Green
                            }
                            default {
                                Write-Host $line -ForegroundColor Gray
                            }
                        }
                    }
                } catch {
                    # Not valid JSON
                    Write-Host $line
                }
            }

            return $responses

        } finally {
            $reader.Dispose()
            $writer.Dispose()
            $pipeClient.Dispose()
        }

    } catch [TimeoutException] {
        Write-Host "[ERROR] Connection timeout - is the service running?" -ForegroundColor Red
        Write-Host "        Start the service with: .\CodexService.ps1" -ForegroundColor Yellow
        return $null
    } catch [System.IO.FileNotFoundException] {
        Write-Host "[ERROR] Pipe not found - is the service running?" -ForegroundColor Red
        Write-Host "        Start the service with: .\CodexService.ps1" -ForegroundColor Yellow
        return $null
    } catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Build request
$request = @{}

if ($Command) {
    # Service command
    $request.command = $Command
} elseif ($Prompt) {
    # Codex prompt request
    $request.id = [guid]::NewGuid().ToString("N").Substring(0, 12)
    $request.prompt = $Prompt
    $request.options = @{
        sandbox = $Sandbox
        timeout_seconds = $TimeoutSeconds
    }
    if ($WorkingDirectory) {
        $request.working_directory = $WorkingDirectory
    }
} else {
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\CodexClient.ps1 -Prompt `"Your task here`"" -ForegroundColor White
    Write-Host "  .\CodexClient.ps1 -Command ping" -ForegroundColor White
    Write-Host "  .\CodexClient.ps1 -Command status" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -PipeName         Named pipe to connect to (default: codex-service)" -ForegroundColor Gray
    Write-Host "  -WorkingDirectory Working directory for Codex" -ForegroundColor Gray
    Write-Host "  -Sandbox          read-only, workspace-write, full-auto, danger-full-access" -ForegroundColor Gray
    Write-Host "  -TimeoutSeconds   Operation timeout (default: 300)" -ForegroundColor Gray
    Write-Host "  -Raw              Output raw JSON" -ForegroundColor Gray
    exit 1
}

$requestJson = $request | ConvertTo-Json -Depth 5 -Compress

# Send request
Send-CodexRequest -PipeName $PipeName -RequestJson $requestJson
