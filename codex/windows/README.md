# Codex CLI Named Pipe Service for Windows

A PowerShell-based service that wraps OpenAI Codex CLI, allowing JSON requests via Windows Named Pipes. Designed for corporate Windows environments with no additional dependencies.

---

## Prerequisites

- Windows 10/11
- PowerShell 5.1+ (built-in)
- OpenAI Codex CLI installed and on PATH
  ```powershell
  codex --version  # verify installation
  ```

---

## Setup

### 1. Clone the Repository
```powershell
git clone https://github.com/WebSurfinMurf/AIclilistener.git
cd AIclilistener\codex\windows
```

### 2. Install Skill (Optional)
Teach Codex to use AIclilistener automatically for context-isolated tasks:
```powershell
.\Install-Skill.ps1
```
This copies the skill to `~/.codex/skills/aiclilistener/` and enables skills in your config.

### 3. Install PDF Support (Optional)
To extract text from PDF files (for Summarize-Files.ps1):
```powershell
.\Install-PdfToText.ps1
```
Downloads Poppler to `$HOME\Tools\poppler\` - no admin required.

---

## Quick Start (GUI Menu)

Double-click `Menu.bat` or run:
```powershell
.\Menu.ps1
```

This opens a graphical menu with buttons to launch any script. CodexService opens in a new window so the menu stays available.

---

## Start Codex (Direct Mode)

Launch Codex CLI directly with a directory picker:
```powershell
.\StartCodex.ps1
```

This will:
1. Show a permissions explanation dialog
2. Let you select a working directory
3. Launch Codex with full disk read access and write access to the selected folder

Use this for interactive Codex sessions. For programmatic/batch access, use CodexService instead.

---

## Running the Service

### Start the Service

**Important:** Start from a project directory, not from a drive root (C:\, D:\).

```powershell
# Navigate to your project folder first
cd C:\Projects\MyApp

# Option A: Batch file (handles execution policy)
.\path\to\Start-Service.bat

# Option B: Direct PowerShell
.\path\to\CodexService.ps1

# Option C: With verbose logging
.\path\to\CodexService.ps1 -Verbose
```

The service will display:
```
[CONFIG] Read Access: Entire drive (read-only)
[CONFIG] Write Access: C:\Projects\MyApp (no prompts)
```

### Access Permissions

| Access | Scope | Description |
|--------|-------|-------------|
| **Read** | Entire drive | Can read any file on the machine |
| **Write** | Working directory only | Can only write to the folder where service started |

This design allows Codex to analyze files anywhere while restricting writes to your project folder.

### Test with Demo
```powershell
.\demo.ps1
```
The demo will:
- Check if the service is running (prompt to start if not)
- Send a request to summarize the project's CLAUDE.md file
- Display the AI-generated summary

---

## Using CodexClient.ps1

Send requests to the service from scripts or command line.

### Service Commands
```powershell
.\CodexClient.ps1 -Command ping      # Health check
.\CodexClient.ps1 -Command status    # Service info
.\CodexClient.ps1 -Command shutdown  # Stop service
```

### Send Prompts
```powershell
# Simple prompt
.\CodexClient.ps1 -Prompt "Explain recursion in Python"

# With working directory
.\CodexClient.ps1 -Prompt "Analyze this project" -WorkingDirectory "C:\Projects\MyApp"

# Raw JSON output (for scripting)
$result = .\CodexClient.ps1 -Prompt "Hello" -Raw
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-Prompt` | - | Task/question to send |
| `-Command` | - | Service command: ping, status, shutdown |
| `-TimeoutSeconds` | 300 | Request timeout |
| `-WorkingDirectory` | - | Working directory for Codex |
| `-Raw` | false | Output raw JSON |

---

## Summarize-Files.ps1

Batch process files using a CSV input. Each file gets summarized with fresh, isolated context.

### Basic Usage
```powershell
# Create CSV with file paths
@"
FilePath,Category
C:\docs\report.docx,Reports
C:\code\app.py,Code
C:\data\analysis.xlsx,Excel
"@ | Out-File files.csv -Encoding UTF8

# Run summarizer
.\Summarize-Files.ps1 -CsvPath files.csv

# Output: files_summarized.csv with Summary column added
```

### Resume After Interruption
```powershell
.\Summarize-Files.ps1 -CsvPath files.csv -Resume
```

### Supported File Types

| Format | Extensions | Requirement |
|--------|------------|-------------|
| Text | .txt, .md, .ps1, .py, .js, .json, .csv, .xml, etc. | None |
| Excel | .xlsx, .xls | Excel installed |
| PowerPoint | .pptx, .ppt | PowerPoint installed |
| Word | .docx, .doc | Word installed |
| PDF | .pdf | Run `.\Install-PdfToText.ps1` |
| RTF | .rtf | None |

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-CsvPath` | - | Input CSV file |
| `-OutputPath` | {input}_summarized.csv | Output file |
| `-FileColumn` | First column | Column with file paths |
| `-SummaryColumn` | Summary | Name for summary column |
| `-MaxChars` | 50000 | Max chars to read per file |
| `-Resume` | false | Skip already-processed files |

---

## Architecture

```
┌─────────────────┐                        ┌──────────────────┐
│  Your Script    │      Named Pipe        │ CodexService.ps1 │
│  or             │ ────────────────────►  │                  │
│  CodexClient.ps1│      JSON Request      │ Listening on:    │
│                 │ ◄────────────────────  │ \\.\pipe\codex-  │
└─────────────────┘      JSON Response     │ service          │
                                           └────────┬─────────┘
                                                    │
                                                    ▼
                                           ┌──────────────────┐
                                           │ codex exec       │
                                           │ --json           │
                                           │ --full-auto      │
                                           │                  │
                                           │ (fresh process   │
                                           │  per request)    │
                                           └──────────────────┘
```

### Why Named Pipes?

Named Pipes are ideal for corporate Windows laptops:
- **No firewall prompts** - unlike HTTP/TCP listeners
- **No admin required** - works with standard user privileges
- **No network stack** - kernel handles IPC directly
- **EDR-friendly** - normal Windows IPC, not flagged as a "server"

### Context Isolation

Each request spawns a **fresh codex process**:
- No memory of previous calls
- No context pollution between requests
- Clean slate for each task
- Ideal for batch operations

---

## JSON Protocol

### Request
```json
{
  "prompt": "Your task here",
  "working_directory": "C:\\Projects",
  "options": {
    "sandbox": "read-only",
    "timeout_seconds": 120
  }
}
```

### Response
```json
{
  "id": "job-id",
  "status": "success",
  "result": {
    "message": "The AI response...",
    "events": [...]
  },
  "duration_ms": 1234
}
```

### Permissions Model

The service runs with fixed permissions (not configurable per-request):

| Permission | Value |
|------------|-------|
| Read | Entire drive |
| Write | Working directory only (where service started) |
| Approval | Never (autonomous operation) |

This ensures consistent, secure behavior for all requests.

---

## Files

```
codex/windows/
├── Menu.ps1              # GUI menu to launch scripts
├── Menu.bat              # Menu launcher (double-click)
├── StartCodex.ps1        # Launch Codex CLI with directory picker
├── CodexService.ps1      # Named Pipe service for JSON requests
├── CodexClient.ps1       # Client for sending requests to service
├── Summarize-Files.ps1   # Batch file summarizer via CSV
├── Start-Service.bat     # Service launcher with execution policy bypass
├── demo.ps1              # Interactive demo (in Setup menu)
├── Install-Skill.ps1     # Deploy skill to Codex
├── Install-PdfToText.ps1 # Install PDF text extraction
├── Test-PdfExtract.ps1   # Test PDF extraction
├── lib/
│   └── Get-FileText.ps1  # Multi-format text extraction
└── skill/
    └── SKILL.md          # Codex skill definition
```

---

## Troubleshooting

### "Pipe not found"
Start the service: `.\Start-Service.bat`

### "Codex CLI not found"
Ensure codex is on PATH: `codex --version`

### Execution Policy Errors
Use the batch file, or: `powershell -ExecutionPolicy Bypass -File .\CodexService.ps1`

### PDF extraction returns empty
The PDF may be scanned images. Run `.\Test-PdfExtract.ps1 -PdfPath "file.pdf"` to diagnose.

---

## License

MIT
