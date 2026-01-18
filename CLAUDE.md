# aiclilistener - Project Context

## Overview

aiclilistener provides persistent listener services for AI CLI tools, enabling JSON-based IPC to invoke AI assistants programmatically.

## Current Implementations

### Codex (Windows)
- **Location**: `codex/windows/`
- **IPC**: Named Pipe (`\\.\pipe\codex-service`)
- **Status**: Implemented

## Architecture Decisions

### Why Named Pipes (Windows)?
1. No firewall prompts - unlike HTTP/TCP
2. No admin required
3. No network stack - kernel handles IPC directly
4. EDR-friendly - normal Windows IPC, not flagged as "server"

### Request/Response Pattern
- Single-threaded queue (Codex CLI has file collision issues with concurrent runs)
- Streaming JSONL events as they arrive
- Async job pattern: POST returns immediately, poll for results

## Key Files

| File | Purpose |
|------|---------|
| `codex/windows/CodexService.ps1` | Main Named Pipe listener service |
| `codex/windows/CodexClient.ps1` | PowerShell client for testing |
| `codex/windows/Start-Service.bat` | Launcher with execution policy bypass |

## Common Tasks

### Testing Codex Service
```powershell
# Start service
.\codex\windows\CodexService.ps1

# In another terminal
.\codex\windows\CodexClient.ps1 -Command ping
.\codex\windows\CodexClient.ps1 -Prompt "Hello world"
```

### Adding New AI CLI Support
1. Create directory: `{ai-name}/{platform}/`
2. Implement listener with same JSON schema
3. Create client script for testing
4. Add README with integration examples

## JSON Schema

### Request
```json
{
  "id": "optional-id",
  "prompt": "task description",
  "command": "alternative: ping|status|shutdown",
  "working_directory": "optional path",
  "options": {
    "sandbox": "read-only|workspace-write|full-auto|danger-full-access",
    "timeout_seconds": 300
  }
}
```

### Response
```json
{
  "id": "job-id",
  "status": "processing|streaming|success|error",
  "result": { "message": "...", "events": [...] },
  "error": "error message if failed",
  "duration_ms": 1234
}
```

## Gotchas

### Service Detection
When checking if the Codex service is running from a script, use the `*pong*` pattern:
```powershell
$pingResult = & .\CodexClient.ps1 -Command ping -Raw 2>&1
if ($pingResult -like "*pong*") {
    # Service is running
}
```
Do NOT use JSON regex patterns like `'"status"\s*:\s*"success"'` - they fail due to PowerShell output handling quirks.

## Dependencies

- PowerShell 5.1+ (Windows built-in)
- AI CLI tools installed and on PATH
- No additional packages required
