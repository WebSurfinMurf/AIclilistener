# Codex CLI Named Pipe Service for Windows

A PowerShell-based persistent service that listens for JSON requests via Windows Named Pipes, invokes OpenAI Codex CLI, and returns JSON responses. Designed for corporate Windows environments with no additional dependencies.

---

## Getting Started

### 1. Clone the repository
```powershell
git clone https://github.com/WebSurfinMurf/AIclilistener.git
cd AIclilistener\codex\windows
```

### 2. Run the demo (recommended first step)
```powershell
.\demo.ps1
```

The demo will:
- Check if the service is running (prompt to start if not)
- Send a request to summarize the project's CLAUDE.md file
- Display the AI-generated executive summary

### 3. Start using it
```powershell
# Terminal 1 - Start the service
.\Start-Service.bat

# Terminal 2 - Send requests
.\CodexClient.ps1 -Prompt "Explain what recursion is"
```

---

## Install as a Codex Skill (Optional)

You can teach Codex CLI to use AIclilistener automatically by installing the skill:

```powershell
# Create the skills directory
mkdir -Force "$env:USERPROFILE\.codex\skills\aiclilistener"

# Copy the skill file
copy skill\SKILL.md "$env:USERPROFILE\.codex\skills\aiclilistener\"
```

Then enable skills in your Codex config (`~/.codex/config.toml`):
```toml
[experimental]
skills = true
```

Or run Codex with: `codex --enable skills`

Now Codex can use AIclilistener to farm out work (e.g., summarizing large files without context pollution).

---

## Context Isolation

**Each request gets fresh, isolated context.** Every call to AIclilistener spawns a new `codex exec` process, meaning:

- No memory of previous calls
- No context pollution between requests
- Clean slate for each task
- Ideal for processing many items independently

This is perfect for batch operations where you want each item processed without influence from previous items.

---

## Quick Test Examples

### Service commands:
```powershell
.\CodexClient.ps1 -Command ping      # Health check
.\CodexClient.ps1 -Command status    # Service info
.\CodexClient.ps1 -Command shutdown  # Stop service
```

### Simple prompts:
```powershell
.\CodexClient.ps1 -Prompt "Explain recursion in Python"
.\CodexClient.ps1 -Prompt "Create hello.py" -Sandbox full-auto
```

### Batch file summarization:
```powershell
# Create a CSV with file paths
@"
FilePath,Category
C:\Windows\System32\drivers\etc\hosts,System
"@ | Out-File files.csv -Encoding UTF8

# Summarize all files
.\Summarize-Files.ps1 -CsvPath files.csv

# Output: files_summarized.csv with Summary column
```

---

## Why Named Pipes?

Named Pipes are the ideal IPC mechanism for corporate Windows laptops:
- **No firewall prompts** - unlike HTTP/TCP listeners
- **No admin required** - works with standard user privileges
- **No network stack** - kernel handles communication directly
- **EDR-friendly** - looks like normal Windows IPC, not a "server"

## Prerequisites

- Windows 10/11
- PowerShell 5.1+ (built-in)
- OpenAI Codex CLI installed and on PATH
  ```powershell
  codex --version  # verify installation
  ```

## Quick Start

### 1. Start the Service

```powershell
# Option A: Direct PowerShell
.\CodexService.ps1

# Option B: Batch file (handles execution policy)
.\Start-Service.bat
```

### 2. Send Requests

From another PowerShell window:

```powershell
# Simple prompt
.\CodexClient.ps1 -Prompt "Explain recursion in Python"

# With working directory and auto-write
.\CodexClient.ps1 -Prompt "Create a hello.py file" -WorkingDirectory "C:\temp" -Sandbox full-auto

# Service commands
.\CodexClient.ps1 -Command ping
.\CodexClient.ps1 -Command status
.\CodexClient.ps1 -Command shutdown
```

## Architecture

```
┌─────────────────┐     Named Pipe        ┌──────────────────────────────┐
│  Your Script    │ ──────────────────►   │  CodexService.ps1            │
│  (any language) │ ◄──────────────────   │  \\.\pipe\codex-service      │
└─────────────────┘     JSON              └──────────────┬───────────────┘
                                                         │
                                                         ▼
                                          ┌──────────────────────────────┐
                                          │  codex exec --json           │
                                          │  --skip-git-repo-check       │
                                          │  --full-auto                 │
                                          └──────────────────────────────┘
```

## Request Format

```json
{
  "id": "optional-job-id",
  "prompt": "Your task description here",
  "working_directory": "C:\\Projects\\MyApp",
  "options": {
    "sandbox": "read-only",
    "timeout_seconds": 300
  }
}
```

### Sandbox Modes

| Mode | Description |
|------|-------------|
| `read-only` | Default. Codex can only read files |
| `workspace-write` | Can write to working directory |
| `full-auto` | Can write files without approval prompts |
| `danger-full-access` | Full system access (use with caution) |

## Response Format

### Processing Acknowledgment
```json
{"id":"abc123","status":"processing","message":"Request received, invoking Codex..."}
```

### Streaming Events
```json
{"id":"abc123","status":"streaming","event":{"type":"turn.started",...}}
{"id":"abc123","status":"streaming","event":{"type":"item.completed","item":{"type":"agent_message",...}}}
```

### Final Result
```json
{
  "id": "abc123",
  "status": "success",
  "timestamp": "2025-12-19T10:30:00.000Z",
  "duration_ms": 5432,
  "result": {
    "message": "Here's the Python code...",
    "events": [...],
    "exit_code": 0
  }
}
```

### Error Response
```json
{
  "id": "abc123",
  "status": "error",
  "timestamp": "2025-12-19T10:30:00.000Z",
  "duration_ms": 1234,
  "error": "Operation timed out after 300 seconds"
}
```

## Service Commands

| Command | Description |
|---------|-------------|
| `ping` | Health check - returns "pong" |
| `status` | Service status and configuration |
| `shutdown` | Gracefully stop the service |

## Integration Examples

### Python Client

```python
import json

def send_codex_request(prompt, pipe_name="codex-service"):
    import win32pipe, win32file

    pipe_path = f"\\\\.\\pipe\\{pipe_name}"

    request = json.dumps({
        "prompt": prompt,
        "options": {"sandbox": "read-only"}
    })

    handle = win32file.CreateFile(
        pipe_path,
        win32file.GENERIC_READ | win32file.GENERIC_WRITE,
        0, None,
        win32file.OPEN_EXISTING,
        0, None
    )

    win32file.WriteFile(handle, (request + "\n").encode())

    responses = []
    while True:
        try:
            _, data = win32file.ReadFile(handle, 65536)
            if not data:
                break
            responses.append(json.loads(data.decode()))
        except:
            break

    win32file.CloseHandle(handle)
    return responses
```

### C# Client

```csharp
using System.IO.Pipes;
using System.Text.Json;

async Task<string> SendCodexRequest(string prompt)
{
    using var client = new NamedPipeClientStream(".", "codex-service", PipeDirection.InOut);
    await client.ConnectAsync(5000);

    using var reader = new StreamReader(client);
    using var writer = new StreamWriter(client) { AutoFlush = true };

    var request = JsonSerializer.Serialize(new { prompt, options = new { sandbox = "read-only" } });
    await writer.WriteLineAsync(request);

    var responses = new List<string>();
    string line;
    while ((line = await reader.ReadLineAsync()) != null)
    {
        responses.Add(line);
    }

    return responses.Last(); // Final result
}
```

### Node.js Client

```javascript
const net = require('net');

function sendCodexRequest(prompt) {
    return new Promise((resolve, reject) => {
        const client = net.createConnection('\\\\.\\pipe\\codex-service');
        const responses = [];

        client.on('connect', () => {
            const request = JSON.stringify({ prompt, options: { sandbox: 'read-only' } });
            client.write(request + '\n');
        });

        client.on('data', (data) => {
            data.toString().split('\n').filter(Boolean).forEach(line => {
                responses.push(JSON.parse(line));
            });
        });

        client.on('end', () => resolve(responses));
        client.on('error', reject);
    });
}
```

## Configuration

### Service Parameters

```powershell
.\CodexService.ps1 -PipeName "my-codex" -TimeoutSeconds 600 -WorkingDirectory "C:\Projects"
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-PipeName` | `codex-service` | Named pipe identifier |
| `-TimeoutSeconds` | `300` | Default operation timeout |
| `-WorkingDirectory` | Current dir | Default working directory |

### Client Parameters

```powershell
.\CodexClient.ps1 -Prompt "task" -Sandbox full-auto -TimeoutSeconds 120
```

## Troubleshooting

### "Pipe not found" Error
The service isn't running. Start it with `.\CodexService.ps1`

### "Codex CLI not found"
Ensure `codex` is installed and on your PATH:
```powershell
$env:PATH += ";C:\path\to\codex"
```

### Execution Policy Errors
Use the batch file or run:
```powershell
powershell -ExecutionPolicy Bypass -File .\CodexService.ps1
```

### Connection Timeout
The service handles one request at a time. Wait for the current request to complete.

## Files

```
codex/windows/
├── CodexService.ps1      # Main service (run this first)
├── CodexClient.ps1       # Client for single requests
├── Summarize-Files.ps1   # CSV batch processor for file summaries
├── Start-Service.bat     # Batch launcher for service
├── README.md             # This file
├── CLAUDE.md             # Testing notes for Claude on Windows
└── examples/
    ├── example-requests.json  # Request/response schema
    └── sample-files.csv       # Sample CSV for testing
```

## License

MIT
