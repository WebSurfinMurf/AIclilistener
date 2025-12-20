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
    Version: 1.5.0 - Read entire drive, write to working directory only
    Requires: OpenAI Codex CLI installed and on PATH

    IMPORTANT: PowerShell 5.1 has a known bug where multiline strings passed
    as command-line arguments to native executables get word-split incorrectly.
    This service works around the bug by piping prompts via stdin instead of
    passing them as arguments. See CLAUDE.md for details.

    TROUBLESHOOTING: Run with -Verbose to see detailed diagnostic output:
        .\CodexService.ps1 -Verbose
#>

param(
    [string]$PipeName = "codex-service",
    [int]$TimeoutSeconds = 300,
    [string]$WorkingDirectory = $PWD.Path,
    [switch]$Verbose
)

# Diagnostic logging helper
function Write-DiagLog {
    param([string]$Message, [string]$Level = "DEBUG")
    if ($script:VerboseLogging) {
        $timestamp = Get-Date -Format "HH:mm:ss.fff"
        $color = switch ($Level) {
            "DEBUG" { "Gray" }
            "INFO"  { "White" }
            "WARN"  { "Yellow" }
            "ERROR" { "Red" }
            default { "Gray" }
        }
        Write-Host "[$timestamp][$Level] $Message" -ForegroundColor $color
    }
}

$script:VerboseLogging = $Verbose

# Ensure UTF-8 encoding for JSON handling
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Handle Ctrl+C gracefully
$script:ExitRequested = $false
# Treat Ctrl+C as input so we can detect it in our polling loop
[Console]::TreatControlCAsInput = $true

$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:ExitRequested = $true
    $script:Running = $false
}

# Configuration
$script:Config = @{
    PipeName = $PipeName
    TimeoutSeconds = $TimeoutSeconds
    WorkingDirectory = $WorkingDirectory
    TempRoot = Join-Path $env:TEMP "codex-sessions"
    Version = "1.5.0"
}

# Prevent starting from root directory (security measure)
function Test-IsRootDirectory {
    param([string]$Path)
    $resolved = (Resolve-Path $Path).Path.TrimEnd('\', '/')
    # Check if it's a drive root like "C:" or "D:"
    if ($resolved -match '^[A-Za-z]:$') {
        return $true
    }
    # Check if it's the root of a UNC path
    if ($resolved -match '^\\\\[^\\]+\\[^\\]+$') {
        return $true
    }
    return $false
}

if (Test-IsRootDirectory $WorkingDirectory) {
    Write-Host ""
    Write-Host "[ERROR] Cannot start from root directory: $WorkingDirectory" -ForegroundColor Red
    Write-Host "[ERROR] Please run from a project folder, not from a drive root (C:\, D:\, etc.)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Example:" -ForegroundColor Yellow
    Write-Host "  cd C:\Projects\MyApp" -ForegroundColor White
    Write-Host "  .\CodexService.ps1" -ForegroundColor White
    Write-Host ""
    exit 1
}

# Ensure temp directory exists
if (-not (Test-Path $script:Config.TempRoot)) {
    New-Item -Path $script:Config.TempRoot -ItemType Directory -Force | Out-Null
}

# Write response to pipe using raw bytes
function Write-PipeResponse {
    param(
        [System.IO.Pipes.NamedPipeServerStream]$Pipe,
        [string]$JsonResponse
    )
    $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($JsonResponse + "`n")
    $Pipe.Write($responseBytes, 0, $responseBytes.Length)
    $Pipe.Flush()
}

# Verify Codex is available and authenticated
function Test-CodexInstallation {
    Write-Host "[CHECK] Verifying Codex installation..." -ForegroundColor Yellow

    # Check if codex command exists and get full path
    try {
        $codexCmd = Get-Command codex -ErrorAction Stop
        $script:CodexPath = $codexCmd.Source

        # Log detailed info about the codex executable
        Write-Host "[INFO] Codex CLI found" -ForegroundColor Green
        Write-Host "[INFO]   Path: $script:CodexPath" -ForegroundColor Green
        Write-Host "[INFO]   Type: $($codexCmd.CommandType)" -ForegroundColor Green

        # If it's a .ps1 wrapper, check for .cmd alternative (better stdin handling)
        if ($codexCmd.CommandType -eq "Application") {
            $ext = [System.IO.Path]::GetExtension($script:CodexPath).ToLower()
            Write-Host "[INFO]   Extension: $ext" -ForegroundColor Green

            if ($ext -eq ".ps1") {
                # .ps1 shims have issues with stdin piping in subprocesses
                # Check if there's a .cmd alternative
                $cmdPath = [System.IO.Path]::ChangeExtension($script:CodexPath, ".cmd")
                if (Test-Path $cmdPath) {
                    Write-Host "[INFO]   Found .cmd alternative: $cmdPath" -ForegroundColor Green
                    Write-Host "[INFO]   Switching to .cmd (better stdin piping support)" -ForegroundColor Green
                    $script:CodexPath = $cmdPath
                } else {
                    Write-Host "[WARN]   .ps1 wrapper may have stdin piping issues in subprocesses" -ForegroundColor Yellow
                }
            } elseif ($ext -in @(".cmd", ".bat")) {
                Write-Host "[INFO]   .cmd/.bat wrapper - stdin piping should work" -ForegroundColor Green
            }
        }

        # Get version
        Write-Host "[CHECK] Getting Codex version..." -ForegroundColor Yellow
        $version = & $script:CodexPath --version 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Codex CLI not responding. Exit code: $LASTEXITCODE" -ForegroundColor Red
            Write-Host "[ERROR] Output: $version" -ForegroundColor Red
            return $false
        }
        Write-Host "[INFO]   Version: $version" -ForegroundColor Green

    } catch {
        Write-Host "[ERROR] Codex CLI not found. Ensure 'codex' is on PATH." -ForegroundColor Red
        Write-Host "[ERROR] Exception: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    # Check auth status (codex login status returns 0 if logged in)
    Write-Host "[CHECK] Checking Codex authentication..." -ForegroundColor Yellow
    try {
        $authOutput = & codex login status 2>&1
        Write-DiagLog "Auth check exit code: $LASTEXITCODE"
        Write-DiagLog "Auth check output: $authOutput"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "[INFO] Codex: Authenticated" -ForegroundColor Green
            if ($authOutput) {
                Write-Host "[INFO]   $authOutput" -ForegroundColor Green
            }
        } else {
            Write-Host "[WARN] Codex: Not authenticated (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
            Write-Host "[WARN] Run 'codex' interactively to login, or set OPENAI_API_KEY environment variable" -ForegroundColor Yellow
            if ($authOutput) {
                Write-Host "[WARN]   Output: $authOutput" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Host "[WARN] Could not check Codex auth status: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Test stdin piping capability
    Write-Host "[CHECK] Testing stdin piping to Codex..." -ForegroundColor Yellow
    try {
        $testResult = "test" | & $script:CodexPath --version 2>&1
        Write-Host "[INFO] Stdin pipe test: OK (codex accepts piped input)" -ForegroundColor Green
        Write-DiagLog "Stdin test output: $testResult"
    } catch {
        Write-Host "[WARN] Stdin pipe test failed: $($_.Exception.Message)" -ForegroundColor Yellow
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
        [System.IO.Pipes.NamedPipeServerStream]$Pipe
    )

    $jobId = if ($Request.id) { $Request.id } else { New-JobId }
    $startTime = Get-Date

    # Validate request
    if (-not $Request.prompt) {
        $response = New-JsonResponse -Id $jobId -Status "error" -Error "Missing required field: prompt"
        Write-PipeResponse -Pipe $Pipe -JsonResponse $response
        return
    }

    # Send acknowledgment
    $ackResponse = @{
        id = $jobId
        status = "processing"
        message = "Request received, invoking Codex..."
    } | ConvertTo-Json -Compress
    Write-PipeResponse -Pipe $Pipe -JsonResponse $ackResponse

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

    # Sandbox mode - full-auto allows writing without prompts
    $codexArgs += "--full-auto"

    # Permissions:
    # - disk-full-read-access: Read any file on the machine
    # - writable_roots: Allow writing to the service's working directory
    # - approval_policy: Never ask for approval (autonomous operation)
    $escapedWorkDir = $script:Config.WorkingDirectory -replace '\\', '\\\\'
    $codexArgs += "-c"
    $codexArgs += 'sandbox_permissions=["disk-full-read-access"]'
    $codexArgs += "-c"
    $codexArgs += "writable_roots=[`"$escapedWorkDir`"]"
    $codexArgs += "-c"
    $codexArgs += 'approval_policy="never"'

    # Set working root to the service's working directory
    $codexArgs += "-C"
    $codexArgs += $script:Config.WorkingDirectory

    # Save prompt to temp file
    $promptText = $Request.prompt
    Write-DiagLog "Prompt length: $($promptText.Length) chars"
    Write-DiagLog "Prompt preview: $($promptText.Substring(0, [Math]::Min(100, $promptText.Length)))..."

    # Timeout
    $timeout = if ($options.timeout_seconds) { $options.timeout_seconds } else { $script:Config.TimeoutSeconds }
    Write-DiagLog "Timeout set to: $timeout seconds"

    # Write prompt to temp file (will be piped via stdin to avoid PS 5.1 arg bug)
    $promptFile = Join-Path $env:TEMP "codex-prompt-$(New-JobId).txt"
    Write-DiagLog "Writing prompt to temp file: $promptFile"
    [System.IO.File]::WriteAllText($promptFile, $promptText, [System.Text.Encoding]::UTF8)

    # Verify the file was written correctly
    if (Test-Path $promptFile) {
        $fileInfo = Get-Item $promptFile
        Write-DiagLog "Prompt file created: $($fileInfo.Length) bytes"
        $fileContent = [System.IO.File]::ReadAllText($promptFile, [System.Text.Encoding]::UTF8)
        Write-DiagLog "Prompt file content length: $($fileContent.Length) chars"
        if ($fileContent.Length -eq 0) {
            Write-Host "[ERROR] Prompt file is empty!" -ForegroundColor Red
        }
    } else {
        Write-Host "[ERROR] Failed to create prompt file: $promptFile" -ForegroundColor Red
    }

    try {
        # Build args string (prompt will be piped via stdin, not passed as argument)
        $codexArgsStr = ($codexArgs | ForEach-Object {
            if ($_ -match '\s') { "`"$_`"" } else { $_ }
        }) -join " "

        Write-DiagLog "Codex args: $codexArgsStr"
        Write-DiagLog "Codex path: $script:CodexPath"

        # Build a PowerShell script that reads file and pipes to codex via stdin
        # This bypasses PS 5.1's known bug with multiline args to native executables
        $psScript = @"
Get-Content -Path '$promptFile' -Raw -Encoding UTF8 | & '$script:CodexPath' $codexArgsStr
"@
        Write-DiagLog "Inner PS script: $psScript"

        # Encode script as base64 to avoid all escaping issues
        $scriptBytes = [System.Text.Encoding]::Unicode.GetBytes($psScript)
        $encodedScript = [Convert]::ToBase64String($scriptBytes)
        Write-DiagLog "Encoded script length: $($encodedScript.Length) chars"

        # Setup process
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        $psi.Arguments = "-ExecutionPolicy Bypass -NoProfile -EncodedCommand $encodedScript"

        Write-DiagLog "Process: powershell.exe $($psi.Arguments.Substring(0, [Math]::Min(100, $psi.Arguments.Length)))..."

        $psi.WorkingDirectory = $workDir
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8

        Write-DiagLog "Working directory: $workDir"
        Write-Host "[JOB $jobId] Starting: codex $($codexArgs -join ' ')" -ForegroundColor Cyan

        $process = [System.Diagnostics.Process]::Start($psi)
        Write-DiagLog "Process started: PID $($process.Id)"

        # Collect all events
        $events = @()
        $lastMessage = ""
        $lineCount = 0

        # Stream JSONL events as they arrive
        Write-DiagLog "Reading stdout from Codex process..."
        while (-not $process.StandardOutput.EndOfStream) {
            $line = $process.StandardOutput.ReadLine()
            $lineCount++
            if ($line) {
                $cleanLine = Remove-AnsiCodes $line
                Write-DiagLog "Line $lineCount (${$cleanLine.Length} chars): $($cleanLine.Substring(0, [Math]::Min(80, $cleanLine.Length)))..."

                # Try to parse as JSON event
                try {
                    $event = $cleanLine | ConvertFrom-Json
                    $events += $event
                    Write-DiagLog "Parsed event type: $($event.type)"

                    # Extract agent message if present
                    if ($event.type -eq "item.completed" -and $event.item.type -eq "agent_message") {
                        $lastMessage = if ($event.item.text) { $event.item.text } else { $event.item.content }
                        Write-DiagLog "Got agent message: $($lastMessage.Substring(0, [Math]::Min(50, $lastMessage.Length)))..."
                    }

                    # Stream event to client (wrapped)
                    $streamEvent = @{
                        id = $jobId
                        status = "streaming"
                        event = $event
                    } | ConvertTo-Json -Depth 10 -Compress
                    Write-PipeResponse -Pipe $Pipe -JsonResponse $streamEvent
                } catch {
                    # Not JSON, treat as raw output
                    Write-DiagLog "Non-JSON line: $cleanLine"
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
        Write-DiagLog "Waiting for process to exit..."
        $process.WaitForExit()
        Write-DiagLog "Process exited with code: $($process.ExitCode)"

        # Capture any stderr
        $stderr = $process.StandardError.ReadToEnd()
        if ($stderr) {
            $stderr = Remove-AnsiCodes $stderr
            Write-DiagLog "Stderr ($($stderr.Length) chars): $stderr"
        } else {
            Write-DiagLog "No stderr output"
        }

        $duration = [long]((Get-Date) - $startTime).TotalMilliseconds
        Write-DiagLog "Total events received: $($events.Count)"
        Write-DiagLog "Total lines processed: $lineCount"
        Write-DiagLog "Final message length: $($lastMessage.Length) chars"

        # Build final response
        if ($process.ExitCode -eq 0) {
            $result = @{
                message = $lastMessage
                events = $events
                exit_code = $process.ExitCode
            }
            if ($stderr) { $result.stderr = $stderr }

            if ($lastMessage.Length -eq 0 -and $events.Count -le 2) {
                Write-Host "[WARN] Codex returned success but no meaningful response!" -ForegroundColor Yellow
                Write-Host "[WARN] Events: $($events | ConvertTo-Json -Compress)" -ForegroundColor Yellow
                Write-Host "[WARN] This usually means Codex didn't receive the prompt or there's an auth issue" -ForegroundColor Yellow
            }

            $response = New-JsonResponse -Id $jobId -Status "success" -Result $result -DurationMs $duration
        } else {
            $errorMsg = if ($stderr) { $stderr } else { "Codex exited with code $($process.ExitCode)" }
            Write-Host "[ERROR] Codex failed with exit code $($process.ExitCode)" -ForegroundColor Red
            Write-Host "[ERROR] $errorMsg" -ForegroundColor Red
            $response = New-JsonResponse -Id $jobId -Status "error" -Error $errorMsg -DurationMs $duration
        }

        Write-PipeResponse -Pipe $Pipe -JsonResponse $response
        Write-Host "[JOB $jobId] Completed in ${duration}ms" -ForegroundColor Green

    } catch {
        $duration = [long]((Get-Date) - $startTime).TotalMilliseconds
        $response = New-JsonResponse -Id $jobId -Status "error" -Error $_.Exception.Message -DurationMs $duration
        Write-PipeResponse -Pipe $Pipe -JsonResponse $response
        Write-Host "[JOB $jobId] Failed: $($_.Exception.Message)" -ForegroundColor Red
    } finally {
        # Cleanup temp prompt file
        if ($promptFile -and (Test-Path $promptFile)) {
            Remove-Item -Path $promptFile -Force -ErrorAction SilentlyContinue
        }

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
        [System.IO.Pipes.NamedPipeServerStream]$Pipe
    )

    switch ($Request.command) {
        "ping" {
            $response = @{
                status = "ok"
                message = "pong"
                version = $script:Config.Version
                timestamp = (Get-Date).ToString("o")
            } | ConvertTo-Json -Compress
            Write-PipeResponse -Pipe $Pipe -JsonResponse $response
        }
        "status" {
            $response = @{
                status = "ok"
                service = "CodexService"
                version = $script:Config.Version
                pipe_name = $script:Config.PipeName
                working_directory = $script:Config.WorkingDirectory
                writable_directory = $script:Config.WorkingDirectory
                read_access = "entire drive"
                temp_root = $script:Config.TempRoot
                uptime_seconds = [int]((Get-Date) - $script:StartTime).TotalSeconds
            } | ConvertTo-Json -Compress
            Write-PipeResponse -Pipe $Pipe -JsonResponse $response
        }
        "shutdown" {
            $response = @{
                status = "ok"
                message = "Shutting down..."
            } | ConvertTo-Json -Compress
            Write-PipeResponse -Pipe $Pipe -JsonResponse $response
            $script:Running = $false
        }
        default {
            $response = @{
                status = "error"
                error = "Unknown command: $($Request.command)"
            } | ConvertTo-Json -Compress
            Write-PipeResponse -Pipe $Pipe -JsonResponse $response
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
    Write-Host "[CONFIG] Read Access: Entire drive (read-only)" -ForegroundColor Yellow
    Write-Host "[CONFIG] Write Access: $($script:Config.WorkingDirectory) (no prompts)" -ForegroundColor Yellow
    Write-Host "[CONFIG] Temp Root: $($script:Config.TempRoot)" -ForegroundColor Yellow
    if ($script:VerboseLogging) {
        Write-Host "[CONFIG] Verbose Logging: ENABLED" -ForegroundColor Magenta
    } else {
        Write-Host "[CONFIG] Verbose Logging: disabled (use -Verbose to enable)" -ForegroundColor Gray
    }
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

                # Wait for connection using async with polling (allows Ctrl+C to work)
                $asyncResult = $pipeServer.BeginWaitForConnection($null, $null)

                # Poll until connected or exit requested
                while (-not $asyncResult.IsCompleted -and $script:Running) {
                    Start-Sleep -Milliseconds 100

                    # Check for Ctrl+C
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq 'C' -and $key.Modifiers -eq 'Control') {
                            Write-Host "`n[INFO] Ctrl+C detected, shutting down..." -ForegroundColor Yellow
                            $script:Running = $false
                            break
                        }
                    }
                }

                # If we're shutting down, clean up and exit
                if (-not $script:Running) {
                    $pipeServer.Dispose()
                    $pipeServer = $null
                    break
                }

                # Complete the connection
                $pipeServer.EndWaitForConnection($asyncResult)

                Write-Host "[CONNECT] Client connected" -ForegroundColor Green

                try {
                    # Read request using raw bytes (StreamReader has buffering issues in PS 5.1)
                    Write-Host "[DEBUG] Waiting for request data..." -ForegroundColor Gray
                    $buffer = New-Object byte[] 65536
                    $bytesRead = $pipeServer.Read($buffer, 0, $buffer.Length)

                    if ($bytesRead -gt 0) {
                        $requestLine = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead).Trim()

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
                                Invoke-ServiceCommand -Request $request -Pipe $pipeServer
                            } elseif ($request.prompt) {
                                Invoke-CodexRequest -Request $request -Pipe $pipeServer
                            } else {
                                $response = @{
                                    status = "error"
                                    error = "Invalid request: must contain 'prompt' or 'command'"
                                } | ConvertTo-Json -Compress
                                Write-PipeResponse -Pipe $pipeServer -JsonResponse $response
                            }
                        } catch {
                            Write-Host "[ERROR] JSON parse failed: $($_.Exception.Message)" -ForegroundColor Red
                            $response = @{
                                status = "error"
                                error = "Failed to parse JSON: $($_.Exception.Message)"
                            } | ConvertTo-Json -Compress
                            Write-PipeResponse -Pipe $pipeServer -JsonResponse $response
                        }
                    } else {
                        Write-Host "[WARN] Empty request received (0 bytes)" -ForegroundColor Yellow
                    }
                } finally {
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
        # Restore console settings
        [Console]::TreatControlCAsInput = $false
        Write-Host ""
        Write-Host "[INFO] Service stopped" -ForegroundColor Yellow
    }
}

# Run the service
try {
    Start-CodexService
} finally {
    # Ensure console is restored even if service crashes
    [Console]::TreatControlCAsInput = $false
}
