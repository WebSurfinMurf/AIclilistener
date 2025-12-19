# Codex Windows Service - Testing Context

## Version 1.1.0 Changes (Gemini Peer Review)

### Security Improvements
- **Pipe ACLs**: Named pipe now restricted to current user only via `PipeSecurity`
- Other users on the machine cannot connect to the service

### Robustness Improvements
- **Better cleanup**: Main loop wrapped in try/finally to ensure pipe disposal on Ctrl+C
- **Zombie pipe prevention**: Explicit disposal in all error paths

### Summarize-Files.ps1 Improvements
- **Resume capability**: Use `-Resume` flag to continue from where you left off
- **Incremental saving**: Results saved to disk after each file (crash-safe)
- **Skip already processed**: Files with valid summaries are skipped on resume

---

## Quick Start for Testing

### 1. Get the Code
```powershell
git clone https://github.com/WebSurfinMurf/AIclilistener.git
cd AIclilistener\codex\windows
```

### 2. Start the Service (Terminal 1)
```powershell
.\Start-Service.bat
```

### 3. Test Basic Connectivity (Terminal 2)
```powershell
.\CodexClient.ps1 -Command ping
.\CodexClient.ps1 -Command status
```

### 4. Test File Summarization
```powershell
# Create a test CSV
@"
FilePath,Category
C:\Windows\System32\drivers\etc\hosts,System
$env:USERPROFILE\Documents\some-file.txt,User
"@ | Out-File -FilePath test-files.csv -Encoding UTF8

# Run summarizer
.\Summarize-Files.ps1 -CsvPath test-files.csv
```

---

## Files Overview

| File | Purpose |
|------|---------|
| `CodexService.ps1` | Named Pipe listener - **run this first** |
| `CodexClient.ps1` | Simple client for single requests |
| `Summarize-Files.ps1` | CSV batch processor for file summaries |
| `Start-Service.bat` | Launches service with execution policy bypass |

---

## Troubleshooting

### "Pipe not found" or "Service not available"
The service isn't running. Start it in a separate terminal:
```powershell
.\Start-Service.bat
```

### "Codex CLI not found"
Verify Codex is installed:
```powershell
codex --version
```

If not on PATH, find it and add:
```powershell
$env:PATH += ";C:\path\to\codex"
```

### Execution Policy Errors
Use the batch file or:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### JSON Parsing Issues
If seeing garbled output, the encoding may be wrong. The scripts set UTF-8, but verify:
```powershell
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```

---

## JSON Message Format

### Request (sent to service)
```json
{
  "id": "summary-row-1",
  "prompt": "Please read and summarize the following file.\n\nFILE: hosts\nTYPE: .txt\nPATH: C:\\Windows\\System32\\drivers\\etc\\hosts\n\n--- FILE CONTENTS BEGIN ---\n# Windows hosts file\n127.0.0.1 localhost\n--- FILE CONTENTS END ---\n\nProvide a concise summary...",
  "options": {
    "sandbox": "read-only",
    "timeout_seconds": 120
  }
}
```

### Response (from service)
```json
{
  "id": "summary-row-1",
  "status": "success",
  "timestamp": "2025-12-19T15:30:00.000Z",
  "duration_ms": 3456,
  "result": {
    "message": "This is the Windows hosts file used for local DNS resolution. It maps hostnames to IP addresses, with localhost mapped to 127.0.0.1. The file is commonly used for blocking websites or creating local development aliases.",
    "events": [...],
    "exit_code": 0
  }
}
```

---

## CSV Summarizer Details

### Input CSV Format
First column should contain full file paths:
```csv
FilePath,Category,Notes
C:\Projects\app.py,Code,Main application
C:\Docs\readme.md,Documentation,Project readme
```

### Output CSV Format
Adds a "Summary" column (or custom name):
```csv
FilePath,Category,Notes,Summary
C:\Projects\app.py,Code,Main application,"Python Flask application with REST endpoints for user management..."
C:\Docs\readme.md,Documentation,Project readme,"Project documentation covering installation, usage, and API reference..."
```

### Parameters
```powershell
.\Summarize-Files.ps1 `
    -CsvPath "input.csv" `
    -OutputPath "output.csv" `        # Optional, defaults to input_summarized.csv
    -FileColumn "FilePath" `          # Optional, defaults to first column
    -SummaryColumn "Description" `    # Optional, defaults to "Summary"
    -MaxChars 10000                    # Optional, max chars to read per file
```

---

## Testing Checklist

- [ ] Service starts without errors
- [ ] `ping` command returns "pong"
- [ ] `status` command shows service info
- [ ] Simple prompt works: `.\CodexClient.ps1 -Prompt "Say hello"`
- [ ] CSV summarizer processes files
- [ ] Output CSV contains summaries
- [ ] JSON is readable in both directions (check terminal output)

---

## Common Test Scenarios

### Test 1: Basic Connectivity
```powershell
.\CodexClient.ps1 -Command ping
# Expected: {"status":"ok","message":"pong",...}
```

### Test 2: Simple Prompt
```powershell
.\CodexClient.ps1 -Prompt "What is 2+2?"
# Expected: Streaming events, then final answer
```

### Test 3: File Summary (single file inline)
```powershell
.\CodexClient.ps1 -Prompt "Summarize this code: function hello() { console.log('Hello'); }"
```

### Test 4: CSV Batch Processing
```powershell
# Create test CSV with real files on your system
$testCsv = @"
FilePath
$env:USERPROFILE\.gitconfig
$env:USERPROFILE\.bashrc
C:\Windows\System32\drivers\etc\hosts
"@
$testCsv | Out-File test.csv -Encoding UTF8

.\Summarize-Files.ps1 -CsvPath test.csv
# Check: test_summarized.csv should have Summary column
```

---

## Architecture

```
┌─────────────────────┐
│  Summarize-Files.ps1│  (reads CSV, sends requests)
└──────────┬──────────┘
           │ JSON via Named Pipe
           ▼
┌─────────────────────┐
│  CodexService.ps1   │  (persistent listener)
└──────────┬──────────┘
           │ subprocess
           ▼
┌─────────────────────┐
│  codex exec --json  │  (OpenAI Codex CLI)
└─────────────────────┘
```

---

## Notes for Claude on Windows

If you're running Claude Code on Windows to help test:

1. Check if service is running: `Get-Process | Where-Object {$_.ProcessName -like "*powershell*"}`
2. Check named pipes: `Get-ChildItem \\.\pipe\ | Where-Object {$_.Name -like "*codex*"}`
3. View service logs in Terminal 1 where it's running
4. JSON should be pretty-printed in both terminals for readability
