# codex-monitor

Codex Monitor is a local macOS monitor and menu bar app for tracking PR checks, comments, roadmap alignment, and daily context. It preserves the original `pull-request-ping` CLI and library for compatibility.

## Packages

- **PullRequestPing** (library) + `pull-request-ping` CLI
- **CodexMonitorCore** (storage + models)
- **codex-monitor** (daemon + MCP server)
- **codex-monitor-app** (menu bar SwiftUI app)

## Features

- PR comment fetching across GitHub/GitLab/Azure (via `pull-request-ping`)
- Scheduled monitoring every 15 minutes
- SQLite storage with SQLData
- Menu bar status + notifications
- Daily context ingestion (TimeStory MCP)
- Local build step screenshots (planned via devtools-daemon tools)

## Installation

### CLI

```bash
swift package experimental-install --product codex-monitor
swift package experimental-install --product pull-request-ping
```

### Menu Bar App

```bash
swift run codex-monitor-app
```

## Usage

### Monitor daemon

```bash
codex-monitor monitor --interval 15
codex-monitor monitor --once
```

### MCP server

```bash
codex-monitor mcp
```

### Build wrapper (local screenshots)

```bash
codex-monitor build -- swift test
```

## pull-request-ping (compat)

```bash
pull-request-ping 29
pull-request-ping --current
pull-request-ping 29 --unresolved
```
