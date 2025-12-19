# Codex Windows Service - Complete Guide

## What This Does

A PowerShell-based service that wraps OpenAI Codex CLI, allowing you to send JSON requests via Windows Named Pipes and receive JSON responses. Designed for corporate Windows laptops with no additional dependencies.

---

## Quick Start (Run the Demo)

```powershell
git clone https://github.com/WebSurfinMurf/AIclilistener.git
cd AIclilistener\codex\windows
.\demo.ps1
```

The demo will:
1. Check if service is running (pings it)
2. Prompt you to start the service if needed
3. Send a request to summarize the project's CLAUDE.md file
4. Display the executive summary from Codex

---

## Files Overview

```
codex/windows/
├── CodexService.ps1      # Named Pipe listener - START THIS FIRST
├── CodexClient.ps1       # Client for sending requests
├── Summarize-Files.ps1   # CSV batch processor
├── demo.ps1              # Interactive demo script
├── Start-Service.bat     # Launcher with execution policy bypass
├── CLAUDE.md             # This file
├── README.md             # Full documentation
└── lib/
    └── Get-FileText.ps1  # Multi-format file text extraction
```

---

## How Communication Works

```
┌─────────────┐      JSON Request       ┌─────────────────┐      subprocess      ┌─────────┐
│ Your Script │ ───────────────────────>│ CodexService.ps1│ ──────────────────>  │  codex  │
│             │      Named Pipe         │ (listening)     │                      │  exec   │
│             │ <───────────────────────│                 │ <──────────────────  │         │
└─────────────┘   JSON Response(s)      └─────────────────┘      JSONL events    └─────────┘
```

**Named Pipe**: `\\.\pipe\codex-service`

---

## Step-by-Step Testing

### Step 1: Start the Service (Terminal 1)
```powershell
cd AIclilistener\codex\windows
.\Start-Service.bat
```

You should see:
```
========================================
  Codex CLI Named Pipe Service v1.1.0
========================================

[CONFIG] Pipe Name: \\.\pipe\codex-service
[SECURITY] Pipe restricted to: YOURPC\username
[INFO] Service started. Waiting for connections...
```

### Step 2: Test Basic Commands (Terminal 2)
```powershell
cd AIclilistener\codex\windows

# Health check
.\CodexClient.ps1 -Command ping

# Service status
.\CodexClient.ps1 -Command status
```

### Step 3: Send a Prompt
```powershell
.\CodexClient.ps1 -Prompt "Explain what Docker is in 2 sentences"
```

### Step 4: Run the Demo
```powershell
.\demo.ps1
```

---

## Using CodexClient.ps1

### Basic Usage
```powershell
# Simple prompt
.\CodexClient.ps1 -Prompt "Your question here"

# With options
.\CodexClient.ps1 -Prompt "Analyze this code" -Sandbox "read-only" -TimeoutSeconds 120

# Service commands
.\CodexClient.ps1 -Command ping
.\CodexClient.ps1 -Command status
.\CodexClient.ps1 -Command shutdown

# Raw JSON output (for scripting)
$result = .\CodexClient.ps1 -Prompt "Hello" -Raw
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Prompt` | - | Task/question to send to Codex |
| `-Command` | - | Service command: ping, status, shutdown |
| `-Sandbox` | read-only | read-only, workspace-write, full-auto, danger-full-access |
| `-TimeoutSeconds` | 300 | Request timeout |
| `-WorkingDirectory` | - | Working dir for Codex operations |
| `-PipeName` | codex-service | Named pipe to connect to |
| `-Raw` | false | Output raw JSON instead of formatted |

---

## Summarizing Files (CSV Batch Processing)

### Basic Usage
```powershell
# Create a CSV with file paths
@"
FilePath,Category
C:\Projects\app.py,Code
C:\Docs\report.xlsx,Excel
C:\Presentations\deck.pptx,PowerPoint
"@ | Out-File files.csv -Encoding UTF8

# Run summarizer
.\Summarize-Files.ps1 -CsvPath files.csv

# Output: files_summarized.csv with Summary column added
```

### Resume After Interruption
```powershell
# If script crashes or is interrupted, resume where you left off
.\Summarize-Files.ps1 -CsvPath files.csv -Resume
```

### Supported File Formats

| Format | Extensions | Requirement |
|--------|------------|-------------|
| Text | .txt, .md, .ps1, .py, .js, .json, .csv, .xml, etc. | None |
| Excel | .xlsx, .xls, .xlsm | Excel installed |
| PowerPoint | .pptx, .ppt, .pptm | PowerPoint installed |
| Word | .docx, .doc, .docm | Word installed |
| PDF | .pdf | Metadata only (full text needs external tools) |
| RTF | .rtf | None |

### How File Extraction Works

For Office files, the script uses COM automation:
```powershell
# Example: Excel extraction
=== EXCEL FILE: report.xlsx ===
Sheets: 3

--- Sheet: Summary ---
Date        Sales    Region
2024-01-01  1000     North
2024-01-02  1500     South
...
```

---

## JSON Request/Response Format

### Request (sent to service)
```json
{
  "id": "optional-custom-id",
  "prompt": "Your task description here",
  "options": {
    "sandbox": "read-only",
    "timeout_seconds": 120
  }
}
```

### Response (from service)
```json
{
  "id": "job-id",
  "status": "success",
  "timestamp": "2025-12-19T15:30:00.000Z",
  "duration_ms": 3456,
  "result": {
    "message": "The response from Codex...",
    "events": [...],
    "exit_code": 0
  }
}
```

### Status Values
- `processing` - Request received, working
- `streaming` - Events arriving from Codex
- `success` - Completed successfully
- `error` - Failed with error message

---

## Security Features (v1.1.0)

- **Pipe ACLs**: Named pipe restricted to current user only
- **No network exposure**: Uses local IPC, not HTTP/TCP
- **No firewall prompts**: Named pipes don't trigger Windows Firewall
- **Clean shutdown**: Proper disposal on Ctrl+C

---

## Troubleshooting

### "Pipe not found" or "Service not available"
```powershell
# Start the service first
.\Start-Service.bat
```

### "Codex CLI not found"
```powershell
# Check if codex is installed
codex --version

# If not on PATH, add it
$env:PATH += ";C:\path\to\codex"
```

### Execution Policy Errors
```powershell
# Use the batch file, or:
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Office Files Not Extracting
- Ensure Microsoft Office is installed
- Excel/PowerPoint/Word must be available for COM automation

---

## Testing Checklist

- [ ] `.\Start-Service.bat` starts without errors
- [ ] `.\CodexClient.ps1 -Command ping` returns "pong"
- [ ] `.\CodexClient.ps1 -Command status` shows service info
- [ ] `.\CodexClient.ps1 -Prompt "Hello"` returns a response
- [ ] `.\demo.ps1` completes successfully
- [ ] CSV summarizer processes text files
- [ ] CSV summarizer processes Office files (if Office installed)
- [ ] `-Resume` flag skips already-processed files

---

## Version History

### v1.1.0
- Security: Pipe ACLs restrict to current user
- Robustness: try/finally cleanup prevents zombie pipes
- Resume: `-Resume` flag for interrupted CSV processing
- Incremental: Results saved after each file (crash-safe)
- Multi-format: Support for xlsx, pptx, docx, pdf

### v1.0.0
- Initial release
- Named Pipe service
- CodexClient for requests
- CSV batch summarizer
