<#
.SYNOPSIS
    Codex CLI Named Pipe Service - Persistent listener for JSON requests

.DESCRIPTION
    A PowerShell-based persistent service that listens on a named pipe for JSON requests,
    invokes OpenAI Codex CLI, and returns JSON responses. Designed for corporate Windows
    environments with no additional dependencies.

.PARAMETER PipeName
    Name of the named pipe (default: codex-service)

.PARAMETER TimeoutSeconds
    Default timeout for Codex operations in seconds (default: 300)

.PARAMETER WorkingDirectory
    Default working directory for Codex operations (default: current directory)

.EXAMPLE
    .\CodexService.ps1

.EXAMPLE
    .\CodexService.ps1 -PipeName "my-codex" -TimeoutSeconds 600

.NOTES
    Author: AI CLI Listener Project
    Version: 1.0.0
    Requires: OpenAI Codex CLI installed and on PATH
#>

param(
    [string]$PipeName = "codex-service",
    [int]$TimeoutSeconds = 300,
    [string]$WorkingDirectory = $PWD.Path
)

# Ensure UTF-8 encoding for JSON handling
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Handle Ctrl+C gracefully
$script:ExitRequested = $false
[Console]::TreatControlCAsInput = $false

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:ExitRequested = $true
    $script:Running = $false
}

# Also try to catch Ctrl+C via trap
trap {
    Write-Host "`n[INFO] Interrupt received, shutting down..." -ForegroundColor Yellow
    $script:Running = $false
    $script:ExitRequested = $true
    continue
}

# Configuration
$script:Config = @{
    PipeName = $PipeName
    TimeoutSeconds = $TimeoutSeconds
    WorkingDirectory = $WorkingDirectory
    TempRoot = Join-Path $env:TEMP "codex-sessions"
    Version = "1.1.0"
}

# Ensure temp directory exists
if (-not (Test-Path $script:Config.TempRoot)) {
    New-Item -Path $script:Config.TempRoot -ItemType Directory -Force | Out-Null
}

# Verify Codex is available and authenticated
function Test-CodexInstallation {
    # Check if codex command exists
    try {
        $version = & codex --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Codex CLI not found. Ensure 'codex' is on PATH." -ForegroundColor Red
            return $false
        }
        Write-Host "[INFO] Codex CLI found: $version" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] Codex CLI not found. Ensure 'codex' is on PATH." -ForegroundColor Red
        return $false
    }

    # Check auth status
    Write-Host "[INFO] Checking Codex authentication..." -ForegroundColor Yellow
    try {
        $authStatus = & codex auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "[INFO] Codex auth: $authStatus" -ForegroundColor Green
        } else {
            Write-Host "[WARN] Codex auth issue: $authStatus" -ForegroundColor Yellow
            Write-Host "[WARN] You may need to run: codex auth login" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[WARN] Could not check Codex auth status" -ForegroundColor Yellow
    }

    return $true
}

# Strip ANSI escape codes from output
function Remove-AnsiCodes {
    param([string]$Text)
    return $Text -replace '\x1b\[[0-9;]*m', '' -replace '\x1b\[[0-9;]*[A-Za-z]', ''
}

# Generate unique job ID
function New-JobId {
    return [guid]::NewGuid().ToString("N").Substring(0, 12)
}

# Create JSON response
function New-JsonResponse {
    param(
        [string]$Id,
        [string]$Status,
        [object]$Result = $null,
        [string]$Error = $null,
        [long]$DurationMs = 0
    )

    $response = @{
        id = $Id
        status = $Status
        timestamp = (Get-Date).ToString("o")
        duration_ms = $DurationMs
    }

    if ($Result) { $response.result = $Result }
    if ($Error) { $response.error = $Error }

    return $response | ConvertTo-Json -Depth 10 -Compress
}

# Process a Codex request
function Invoke-CodexRequest {
    param(
        [hashtable]$Request,
        [System.IO.StreamWriter]$Writer
    )

    $jobId = if ($Request.id) { $Request.id } else { New-JobId }
    $startTime = Get-Date

    # Validate request
    if (-not $Request.prompt) {
        $response = New-JsonResponse -Id $jobId -Status "error" -Error "Missing required field: prompt"
        $Writer.WriteLine($response)
        return
    }

    # Send acknowledgment
    $ackResponse = @{
        id = $jobId
        status = "processing"
        message = "Request received, invoking Codex..."
    } | ConvertTo-Json -Compress
    $Writer.WriteLine($ackResponse)
    $Writer.Flush()

    # Setup working directory
    $workDir = if ($Request.working_directory -and (Test-Path $Request.working_directory)) {
        $Request.working_directory
    } elseif ($Request.options.working_directory -and (Test-Path $Request.options.working_directory)) {
        $Request.options.working_directory
    } else {
        # Create isolated temp directory
        $tempDir = Join-Path $script:Config.TempRoot $jobId
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
        $tempDir
    }

    # Build Codex command arguments
    $codexArgs = @("exec")

    # Add flags based on options
    $options = $Request.options
    if (-not $options) { $options = @{} }

    # Always use JSON output for machine parsing
    $codexArgs += "--json"

    # Skip git check for temp directories
    if ($workDir -like "$($script:Config.TempRoot)*") {
        $codexArgs += "--skip-git-repo-check"
    }

    # Sandbox mode
    $sandbox = if ($options.sandbox) { $options.sandbox } else { "read-only" }
    switch ($sandbox) {
        "full-auto" { $codexArgs += "--full-auto" }
        "workspace-write" { $codexArgs += "--sandbox"; $codexArgs += "workspace-write" }
        "danger-full-access" { $codexArgs += "--sandbox"; $codexArgs += "danger-full-access" }
        default { $codexArgs += "--sandbox"; $codexArgs += "read-only" }
    }

    # Add the prompt (must be last)
    $codexArgs += $Request.prompt

    # Timeout
    $timeout = if ($options.timeout_seconds) { $options.timeout_seconds } else { $script:Config.TimeoutSeconds }

    try {
        # Setup process
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "codex"
        $psi.Arguments = ($codexArgs | ForEach-Object {
            if ($_ -match '\s') { "`"$_`"" } else { $_ }
        }) -join " "
        $psi.WorkingDirectory = $workDir
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        Write-Host "[JOB $jobId] Starting: codex $($codexArgs -join ' ')" -ForegroundColor Cyan

        $process = [System.Diagnostics.Process]::Start($psi)

        # Collect all events
        $events = @()
        $lastMessage = ""

        # Stream JSONL events as they arrive
        while (-not $process.StandardOutput.EndOfStream) {
            $line = $process.StandardOutput.ReadLine()
            if ($line) {
                $cleanLine = Remove-AnsiCodes $line

                # Try to parse as JSON event
                try {
                    $event = $cleanLine | ConvertFrom-Json
                    $events += $event

                    # Extract agent message if present
                    if ($event.type -eq "item.completed" -and $event.item.type -eq "agent_message") {
                        $lastMessage = $event.item.content
                    }

                    # Stream event to client (wrapped)
                    $streamEvent = @{
                        id = $jobId
                        status = "streaming"
                        event = $event
                    } | ConvertTo-Json -Depth 10 -Compress
                    $Writer.WriteLine($streamEvent)
                    $Writer.Flush()
                } catch {
                    # Not JSON, treat as raw output
                    if ($cleanLine.Trim()) {
                        $events += @{ type = "raw"; content = $cleanLine }
                    }
                }
            }

            # Check timeout
            if (((Get-Date) - $startTime).TotalSeconds -gt $timeout) {
                $process.Kill()
                throw "Operation timed out after $timeout seconds"
            }
        }

        # Wait for process to complete
        $process.WaitForExit()

        # Capture any stderr
        $stderr = $process.StandardError.ReadToEnd()
        if ($stderr) {
            $stderr = Remove-AnsiCodes $stderr
        }

        $duration = [long]((Get-Date) - $startTime).TotalMilliseconds

        # Build final response
        if ($process.ExitCode -eq 0) {
            $result = @{
                message = $lastMessage
                events = $events
                exit_code = $process.ExitCode
            }
            if ($stderr) { $result.stderr = $stderr }

            $response = New-JsonResponse -Id $jobId -Status "success" -Result $result -DurationMs $duration
        } else {
            $errorMsg = if ($stderr) { $stderr } else { "Codex exited with code $($process.ExitCode)" }
            $response = New-JsonResponse -Id $jobId -Status "error" -Error $errorMsg -DurationMs $duration
        }

        $Writer.WriteLine($response)
        $Writer.Flush()
        Write-Host "[JOB $jobId] Completed in ${duration}ms" -ForegroundColor Green

    } catch {
        $duration = [long]((Get-Date) - $startTime).TotalMilliseconds
        $response = New-JsonResponse -Id $jobId -Status "error" -Error $_.Exception.Message -DurationMs $duration
        $Writer.WriteLine($response)
        $Writer.Flush()
        Write-Host "[JOB $jobId] Failed: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # Cleanup temp directory if we created one
        if ($workDir -like "$($script:Config.TempRoot)*") {
            Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }

        if ($process -and -not $process.HasExited) {
            $process.Kill()
        }
    }
}

# Handle special commands
function Invoke-ServiceCommand {
    param(
        [hashtable]$Request,
        [System.IO.StreamWriter]$Writer
    )

    switch ($Request.command) {
        "ping" {
            $response = @{
                status = "ok"
                message = "pong"
                version = $script:Config.Version
                timestamp = (Get-Date).ToString("o")
            } | ConvertTo-Json -Compress
            $Writer.WriteLine($response)
            $Writer.Flush()
        }
        "status" {
            $response = @{
                status = "ok"
                service = "CodexService"
                version = $script:Config.Version
                pipe_name = $script:Config.PipeName
                working_directory = $script:Config.WorkingDirectory
                temp_root = $script:Config.TempRoot
                uptime_seconds = [int]((Get-Date) - $script:StartTime).TotalSeconds
            } | ConvertTo-Json -Compress
            $Writer.WriteLine($response)
            $Writer.Flush()
        }
        "shutdown" {
            $response = @{
                status = "ok"
                message = "Shutting down..."
            } | ConvertTo-Json -Compress
            $Writer.WriteLine($response)
            $Writer.Flush()
            $script:Running = $false
        }
        default {
            $response = @{
                status = "error"
                error = "Unknown command: $($Request.command)"
            } | ConvertTo-Json -Compress
            $Writer.WriteLine($response)
            $Writer.Flush()
        }
    }
}

# Create pipe security ACL (restrict to current user only)
function New-PipeSecurity {
    $pipeSecurity = New-Object System.IO.Pipes.PipeSecurity

    # Allow current user full control
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $rule = New-Object System.IO.Pipes.PipeAccessRule(
        $currentUser,
        [System.IO.Pipes.PipeAccessRights]::ReadWrite,
        [System.Security.AccessControl.AccessControlType]::Allow
    )
    $pipeSecurity.AddAccessRule($rule)

    return $pipeSecurity
}

# Main service loop
function Start-CodexService {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Codex CLI Named Pipe Service v$($script:Config.Version)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "[CONFIG] Pipe Name: \\.\pipe\$($script:Config.PipeName)" -ForegroundColor Yellow
    Write-Host "[CONFIG] Timeout: $($script:Config.TimeoutSeconds) seconds" -ForegroundColor Yellow
    Write-Host "[CONFIG] Working Dir: $($script:Config.WorkingDirectory)" -ForegroundColor Yellow
    Write-Host "[CONFIG] Temp Root: $($script:Config.TempRoot)" -ForegroundColor Yellow
    Write-Host ""

    if (-not (Test-CodexInstallation)) {
        return
    }

    # Create pipe security (current user only)
    $pipeSecurity = New-PipeSecurity
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    Write-Host "[SECURITY] Pipe restricted to: $currentUser" -ForegroundColor Yellow
    Write-Host ""

    $script:StartTime = Get-Date
    $script:Running = $true
    $pipeServer = $null

    Write-Host "[INFO] Service started. Waiting for connections..." -ForegroundColor Green
    Write-Host "[INFO] Press Ctrl+C to stop" -ForegroundColor Gray
    Write-Host ""

    try {
        while ($script:Running) {
            try {
                # Create named pipe server with security ACL (current user only)
                $pipeServer = New-Object System.IO.Pipes.NamedPipeServerStream(
                    $script:Config.PipeName,
                    [System.IO.Pipes.PipeDirection]::InOut,
                    1,  # maxNumberOfServerInstances
                    [System.IO.Pipes.PipeTransmissionMode]::Byte,
                    [System.IO.Pipes.PipeOptions]::None,
                    0,  # inBufferSize (default)
                    0,  # outBufferSize (default)
                    $pipeSecurity
                )

                Write-Host "[LISTEN] Waiting for client on \\.\pipe\$($script:Config.PipeName)..." -ForegroundColor Gray

                # Wait for connection
                $pipeServer.WaitForConnection()

                Write-Host "[CONNECT] Client connected" -ForegroundColor Green

                # Setup streams with explicit UTF-8 encoding
                $reader = New-Object System.IO.StreamReader($pipeServer, [System.Text.Encoding]::UTF8)
                $writer = New-Object System.IO.StreamWriter($pipeServer, [System.Text.Encoding]::UTF8)
                $writer.AutoFlush = $true

                try {
                    # Read request (single line JSON)
                    Write-Host "[DEBUG] Waiting for request data..." -ForegroundColor Gray
                    $requestLine = $reader.ReadLine()
                    Write-Host "[DEBUG] ReadLine returned" -ForegroundColor Gray

                    if ($requestLine) {
                        $displayLen = [Math]::Min(100, $requestLine.Length)
                        Write-Host "[REQUEST] Received ($($requestLine.Length) chars): $($requestLine.Substring(0, $displayLen))..." -ForegroundColor Cyan

                        try {
                            # Parse JSON - PS 5.1 compatible (no -AsHashtable)
                            $jsonObj = $requestLine | ConvertFrom-Json

                            # Convert PSObject to hashtable manually for PS 5.1 compatibility
                            $request = @{}
                            $jsonObj.PSObject.Properties | ForEach-Object {
                                $request[$_.Name] = $_.Value
                            }

                            # Convert nested options object if present
                            if ($request.options -and $request.options -is [PSObject]) {
                                $opts = @{}
                                $request.options.PSObject.Properties | ForEach-Object {
                                    $opts[$_.Name] = $_.Value
                                }
                                $request.options = $opts
                            }

                            # Route to appropriate handler
                            if ($request.command) {
                                Invoke-ServiceCommand -Request $request -Writer $writer
                            } elseif ($request.prompt) {
                                Invoke-CodexRequest -Request $request -Writer $writer
                            } else {
                                $response = @{
                                    status = "error"
                                    error = "Invalid request: must contain 'prompt' or 'command'"
                                } | ConvertTo-Json -Compress
                                $writer.WriteLine($response)
                                $writer.Flush()
                            }
                        } catch {
                            Write-Host "[ERROR] JSON parse failed: $($_.Exception.Message)" -ForegroundColor Red
                            $response = @{
                                status = "error"
                                error = "Failed to parse JSON: $($_.Exception.Message)"
                            } | ConvertTo-Json -Compress
                            $writer.WriteLine($response)
                            $writer.Flush()
                        }
                    } else {
                        Write-Host "[WARN] Empty request received" -ForegroundColor Yellow
                    }
                } finally {
                    $reader.Dispose()
                    $writer.Dispose()
                    $pipeServer.Dispose()
                    $pipeServer = $null
                    Write-Host "[DISCONNECT] Client disconnected" -ForegroundColor Gray
                }

            } catch [System.IO.IOException] {
                # Pipe broken, client disconnected unexpectedly
                Write-Host "[WARN] Client disconnected unexpectedly" -ForegroundColor Yellow
                if ($pipeServer) {
                    $pipeServer.Dispose()
                    $pipeServer = $null
                }
            } catch {
                Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
                if ($pipeServer) {
                    $pipeServer.Dispose()
                    $pipeServer = $null
                }
            }
        }
    } finally {
        # Ensure pipe is disposed on exit (Ctrl+C or shutdown)
        if ($pipeServer) {
            $pipeServer.Dispose()
        }
        Write-Host ""
        Write-Host "[INFO] Service stopped" -ForegroundColor Yellow
    }
}

# Run the service
Start-CodexService
