# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build
swift build                                           # Debug build
swift build -c release                                # Release build

# Test (uses Swift Testing framework, NOT XCTest)
swift test                                            # Run all tests
swift test --filter PullRequestPingTests              # Run specific suite
swift test --filter CodexMonitorCoreTests             # Run monitor core tests

# Lint & Format
swift format lint -s -p -r Sources Tests Package.swift
swift format format -p -r -i Sources Tests Package.swift

# Install CLI tools
swift package experimental-install --product pull-request-ping
swift package experimental-install --product codex-monitor
```

## Products

- `pull-request-ping` (legacy CLI) + `PullRequestPing` library
- `codex-monitor` daemon + MCP server
- `codex-monitor-app` menu bar app
- `CodexMonitorCore` storage + mapping

## Architecture

**Strategy + Factory pattern** for multi-provider PR comment fetching:

```
CLI (PullRequestPingCommand)
         │
         ▼
   ProviderFactory ──auto-detects from git remote──▶ ProviderType enum
         │
         ▼
   PRProvider protocol
         │
    ┌────┴────┬────────────┐
    ▼         ▼            ▼
 GitHub    GitLab       Azure
Provider   Provider    Provider
```

### Key Abstractions

| Type | Purpose |
|------|---------|
| `PRProvider` | Protocol defining `fetchPR()`, `replyToComment()`, `resolveThread()` |
| `ProviderFactory` | Auto-detects provider from git remote URL patterns |
| `PullRequest` | Contains `comments` (top-level) and `reviews` (with inline `ReviewComment`) |
| `CodexMonitorDaemon` | Scheduler that ingests PRs + checks into SQLite |
| `CodexMonitorMCPServer` | MCP tool surface for Codex automation |
| `CodexMonitorApp` | Menu bar app that shows status + daily context |

## CLI Usage

```bash
# View PR comments (auto-detects provider)
pull-request-ping 123                    # By PR number
pull-request-ping --current              # Current branch's PR
pull-request-ping 123 --unresolved       # Only unresolved threads
pull-request-ping 123 --format json      # JSON output for scripting

# Monitor daemon
codex-monitor monitor --interval 15
codex-monitor monitor --once

# MCP server
codex-monitor mcp

# Build wrapper
codex-monitor build -- swift test
```

## Testing Conventions

- Uses **Swift Testing** framework (`@Test`, `#expect`, `@Suite`)
- Test files in `Tests/`
