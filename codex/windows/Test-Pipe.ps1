<#
.SYNOPSIS
    Minimal pipe test - isolates the communication issue
#>

param(
    [switch]$Server,
    [switch]$Client
)

$PipeName = "test-pipe"

if ($Server) {
    Write-Host "=== PIPE SERVER ===" -ForegroundColor Cyan
    Write-Host "Creating pipe: $PipeName"

    $pipe = New-Object System.IO.Pipes.NamedPipeServerStream(
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut,
        1,
        [System.IO.Pipes.PipeTransmissionMode]::Byte,
        [System.IO.Pipes.PipeOptions]::None
    )

    Write-Host "Waiting for connection..."
    $pipe.WaitForConnection()
    Write-Host "Client connected!" -ForegroundColor Green

    # Read using raw bytes instead of StreamReader
    Write-Host "Reading data..."
    $buffer = New-Object byte[] 4096
    $bytesRead = $pipe.Read($buffer, 0, $buffer.Length)

    if ($bytesRead -gt 0) {
        $data = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
        Write-Host "Received ($bytesRead bytes): $data" -ForegroundColor Green

        # Send response
        $response = '{"status":"ok","message":"pong"}'
        $responseBytes = [System.Text.Encoding]::UTF8.GetBytes($response + "`n")
        $pipe.Write($responseBytes, 0, $responseBytes.Length)
        $pipe.Flush()
        Write-Host "Sent response: $response" -ForegroundColor Cyan
    } else {
        Write-Host "No data received!" -ForegroundColor Red
    }

    $pipe.Dispose()
    Write-Host "Done."
}
elseif ($Client) {
    Write-Host "=== PIPE CLIENT ===" -ForegroundColor Cyan
    Write-Host "Connecting to pipe: $PipeName"

    $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(
        ".",
        $PipeName,
        [System.IO.Pipes.PipeDirection]::InOut
    )

    $pipe.Connect(5000)
    Write-Host "Connected!" -ForegroundColor Green

    # Write using raw bytes
    $request = '{"command":"ping"}'
    Write-Host "Sending: $request"
    $requestBytes = [System.Text.Encoding]::UTF8.GetBytes($request + "`n")
    $pipe.Write($requestBytes, 0, $requestBytes.Length)
    $pipe.Flush()
    Write-Host "Sent! Waiting for response..."

    # Read response
    $buffer = New-Object byte[] 4096
    $bytesRead = $pipe.Read($buffer, 0, $buffer.Length)

    if ($bytesRead -gt 0) {
        $response = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $bytesRead)
        Write-Host "Received: $response" -ForegroundColor Green
    } else {
        Write-Host "No response!" -ForegroundColor Red
    }

    $pipe.Dispose()
    Write-Host "Done."
}
else {
    Write-Host "Usage:"
    Write-Host "  Terminal 1: .\Test-Pipe.ps1 -Server"
    Write-Host "  Terminal 2: .\Test-Pipe.ps1 -Client"
}
