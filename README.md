# AIclilistener

Persistent listener services for AI CLI tools. Provides JSON-based IPC interfaces to invoke AI assistants programmatically.

## Supported AI CLIs

| AI | Platform | Status | Path |
|----|----------|--------|------|
| OpenAI Codex | Windows | Ready | `codex/windows/` |
| Claude Code | Linux | Planned | `claude/linux/` |
| Gemini CLI | Cross-platform | Planned | `gemini/` |

## Purpose

AI CLI tools like Codex, Claude Code, and others are designed for interactive terminal use. This project wraps them in persistent listener services that:

- Accept JSON requests via IPC (Named Pipes, HTTP, etc.)
- Invoke the underlying AI CLI
- Stream events and return JSON responses
- Handle session management, timeouts, and errors

## Use Cases

- **Automation**: Integrate AI assistants into scripts and workflows
- **Multi-agent systems**: Coordinate multiple AI instances
- **IDE plugins**: Backend for editor integrations
- **CI/CD**: Automated code review and generation

## Quick Start (Codex on Windows)

```powershell
# Terminal 1: Start service
cd codex/windows
.\CodexService.ps1

# Terminal 2: Send requests
.\CodexClient.ps1 -Prompt "Write a hello world in Python"
```

## Architecture

```
┌──────────────────┐       IPC        ┌─────────────────────┐
│  Your App/Script │ ◄──────────────► │  AIclilistener      │
│  (any language)  │      JSON        │  (PowerShell/Bash)  │
└──────────────────┘                  └──────────┬──────────┘
                                                 │
                                                 ▼
                                      ┌─────────────────────┐
                                      │  AI CLI             │
                                      │  (codex/claude/etc) │
                                      └─────────────────────┘
```

## IPC Mechanisms by Platform

| Platform | Primary | Fallback |
|----------|---------|----------|
| Windows | Named Pipes | HTTP localhost |
| Linux | Unix Socket | HTTP localhost |
| macOS | Unix Socket | HTTP localhost |

## Project Structure

```
AIclilistener/
├── README.md
├── CLAUDE.md
├── codex/
│   └── windows/
│       ├── CodexService.ps1
│       ├── CodexClient.ps1
│       ├── Start-Service.bat
│       └── README.md
├── claude/
│   └── linux/
│       └── (planned)
└── gemini/
    └── (planned)
```

## License

MIT
