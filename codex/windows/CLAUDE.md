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
├── Menu.ps1              # GUI menu to launch scripts
├── Menu.bat              # Menu launcher (double-click)
├── StartCodex.ps1        # Launch Codex CLI with directory picker
├── CodexService.ps1      # Named Pipe service for JSON requests
├── CodexClient.ps1       # Client for sending requests to service
├── Process-Files.ps1     # CSV batch processor with custom prompts
├── demo.ps1              # Interactive demo (in Setup menu)
├── Start-Service.bat     # Launcher with execution policy bypass
├── Install-Skill.ps1     # Deploy skill to Codex
├── Install-PdfToText.ps1 # Install PDF text extraction
├── Test-PdfExtract.ps1   # Test PDF extraction
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

## Testing

### Start the Service (Terminal 1)
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

### Test Basic Commands (Terminal 2)
```powershell
cd AIclilistener\codex\windows

# Health check
.\CodexClient.ps1 -Command ping

# Service status
.\CodexClient.ps1 -Command status
```

### Send a Prompt
```powershell
.\CodexClient.ps1 -Prompt "Explain what Docker is in 2 sentences"
```

### Run the Demo
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

## Processing Files (CSV Batch Processing)

### Basic Usage
```powershell
# Create a CSV with file paths
@"
FilePath,Category
C:\Projects\app.py,Code
C:\Docs\report.xlsx,Excel
C:\Presentations\deck.pptx,PowerPoint
"@ | Out-File files.csv -Encoding UTF8

# Run with default summarization prompt
.\Process-Files.ps1 -CsvPath files.csv

# Run with custom prompt
.\Process-Files.ps1 -CsvPath files.csv -Prompt "Extract all function names from: {fileContent}"

# Output: files_processed.csv with Result column added
```

### Custom Prompts
Use placeholders in your prompt:
- `{fileName}` - File name (e.g., "report.xlsx")
- `{extension}` - File extension (e.g., ".xlsx")
- `{filePath}` - Full file path
- `{fileContent}` - Extracted file content

### Resume After Interruption
```powershell
# If script crashes or is interrupted, resume where you left off
.\Process-Files.ps1 -CsvPath files.csv -Resume
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

### Enable Verbose Logging (v1.3.0+)

Run the service with `-Verbose` to see detailed diagnostic output:

```powershell
.\CodexService.ps1 -Verbose
```

This will show:
- Codex executable path, type, and extension
- Authentication check results
- Stdin piping test results
- Prompt file creation and content verification
- Exact commands being executed
- Each event received from Codex
- Warnings when responses are empty

### "Codex returned success but no meaningful response"

This warning appears when Codex exits with code 0 but returns no actual response. Common causes:
1. **Authentication issue**: Run `codex` interactively to login, or set `OPENAI_API_KEY`
2. **Stdin not received**: The prompt didn't reach Codex (check verbose logs)
3. **API error**: Codex may have encountered an API-side issue

Run with `-Verbose` to see the exact events received.

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
- [ ] CSV processor processes text files
- [ ] CSV processor processes Office files (if Office installed)
- [ ] `-Resume` flag skips already-processed files
- [ ] Custom prompts work with placeholders

---

## Known Issues & Workarounds

### PowerShell 5.1 Multiline Argument Bug

**Issue**: PowerShell 5.1 has a known bug where multiline strings passed as command-line arguments to native executables (like Node.js, which powers Codex CLI) get incorrectly word-split, causing the receiving process to see each line as a separate argument.

**Symptom**: Error like `unexpected argument 'world' found` when sending prompts containing newlines or special characters.

**Solution**: Pipe the prompt via stdin instead of passing as a command-line argument:
```powershell
# BAD - breaks with multiline prompts
& codex exec --json "multi`nline`nprompt"

# GOOD - pipe via stdin
$prompt | & codex exec --json
```

**Reference**: This is a well-documented limitation of PS 5.1's process spawning. The fix is implemented in CodexService.ps1 v1.2.2+.

---

## Version History

### v2.0.0
- **Breaking**: Renamed `Summarize-Files.ps1` to `Process-Files.ps1`
- **Feature**: Custom prompt support with placeholders (`{fileName}`, `{extension}`, `{filePath}`, `{fileContent}`)
- **Feature**: Menu now shows prompt configuration dialog before processing
- Renamed `-SummaryColumn` parameter to `-ResultColumn`
- Output files now use `_processed.csv` suffix instead of `_summarized.csv`

### v1.4.0
- **Feature**: Full disk read access enabled by default
- Adds `sandbox_permissions=["disk-full-read-access"]` to allow reading any file
- Adds `-a never` to run without approval prompts
- Codex can now read files from any location on the machine

### v1.3.1
- **Fix**: Auto-switch from `.ps1` to `.cmd` shim when both exist
- `.ps1` npm shims break stdin piping in PowerShell subprocesses
- `.cmd` shims call node directly, preserving stdin flow
- Startup now logs which shim is being used and any auto-switching

### v1.3.0
- Added `-Verbose` flag for detailed diagnostic logging
- Enhanced startup checks: shows codex executable type, extension, and warns about wrapper scripts
- Logs prompt file creation, content verification, and exact commands being executed
- Logs each event received from Codex with type information
- Warns when Codex returns success but no meaningful response (helps diagnose auth/stdin issues)
- Added stdin pipe test during startup verification

### v1.2.2
- Fixed PS 5.1 multiline argument bug by piping prompt via stdin
- Thanks to Gemini peer review for identifying the root cause

### v1.2.1
- Refactored Summarize-Files.ps1 to use CodexClient.ps1 for consistent pipe I/O
- demo.ps1 already uses CodexClient.ps1 (no changes needed)
- Single source of truth for pipe communication

### v1.2.0
- **Critical Fix**: Raw byte I/O instead of StreamReader/StreamWriter
- Fixes PS 5.1 buffering issue that caused ReadLine() to block indefinitely
- Both service and client now use direct pipe.Read()/Write() with UTF-8 encoding
- Auto-detect codex executable path (handles .ps1/.cmd/.exe wrappers)
- Extract agent message from `.text` field (Codex CLI format)

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
