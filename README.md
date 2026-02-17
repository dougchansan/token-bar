# Token Bar

A native macOS menu bar app for monitoring AI coding assistant token usage at a glance.

<p align="center">
  <img src="screenshots/panel.png" alt="Token Bar — Claude Code" width="420">
  &nbsp;&nbsp;
  <img src="screenshots/opencode-panel.png" alt="Token Bar — OpenCode" width="420">
</p>

## Features

- **Multi-Provider Support** — Toggle between Claude Code, OpenCode, or combined view
- **Live Token Counting** — Scans active session files for real-time today stats, not just cached data
- **Activity Heatmap** — 16-week GitHub-style calendar with hover tooltips showing per-day metrics
- **Cost Estimation** — Calculates approximate USD spend per model using API pricing (click for full breakdown)
- **Model Breakdown** — All-time token usage by model with relative progress bars and cost per model
- **Streak Counter** — Consecutive days with coding activity
- **Peak Hours** — 24-hour session distribution chart highlighting your most productive time
- **Launch at Login** — Toggle to start automatically on boot
- **Dark Theme** — Designed to look clean alongside your menu bar

## Providers

### Claude Code (Local)

Reads from `~/.claude/stats-cache.json` and scans session JSONL files under `~/.claude/projects/` for live token counts.

- Models: Opus, Sonnet, Haiku (all versions)
- Data: local only, polled every 30 seconds

### OpenCode (Remote via SSH)

Aggregates token usage from OpenCode's message storage on a remote machine via SSH. A Python script (`scripts/opencode-stats.py`) parses message JSON files under `~/.local/share/opencode/storage/message/` and returns aggregated stats.

- Models: Kimi K2 Turbo, Kimi K2.5, Qwen3, Llama 3.1, DeepSeek, Devstral, and any other model used through OpenCode
- Providers: Ollama (local), Moonshot AI, and others
- Data: pulled on-demand via SSH, cached locally

#### OpenCode Setup

OpenCode stores session data at `~/.local/share/opencode/storage/` on the machine where it runs. Token Bar pulls this data over SSH using a small Python script.

**1. Configure the connection**

Edit `TokenBar/TokenBar/OpenCodeReader.swift` and update the defaults at the top of `init()`:

```swift
init(host: String = "YOUR_IP_OR_HOSTNAME",
     user: String = "YOUR_USERNAME",
     scriptPath: String = "opencode-stats.py")
```

**2. Set up SSH key auth** (if not already done)

```bash
# Generate a key if you don't have one
ssh-keygen -t ed25519

# Copy it to the remote machine
ssh-copy-id user@your-host
```

Verify passwordless login works:
```bash
ssh user@your-host "echo connected"
```

**3. Deploy the aggregation script**

```bash
scp scripts/opencode-stats.py user@your-host:opencode-stats.py
```

**4. Test it**

```bash
ssh user@your-host "python opencode-stats.py"
```

You should see JSON output with your OpenCode token usage. If you see `{"error": "no opencode data"}`, OpenCode hasn't been used on that machine yet.

**5. Rebuild the app**

```bash
cd TokenBar
./build.sh
open build/TokenBar.app
```

Click **Open** in the header to see your OpenCode stats.

> **Note:** The remote machine needs Python 3 installed. OpenCode supports any LLM provider (Ollama, Moonshot/Kimi, OpenAI, etc.) — the aggregation script picks up all of them automatically. Local Ollama models show $0 cost; API-based models (Kimi K2 Turbo, K2.5) show estimated costs.

### Provider Toggle

Click **Claude** / **Open** / **All** in the header to switch views:
- **Claude** — Local Claude Code stats only
- **Open** — Remote OpenCode stats only (SSHes to pull data)
- **All** — Merged view combining both sources

## Requirements

- macOS 14+
- Swift 5.9+
- Claude Code installed (`~/.claude/` directory)
- For OpenCode: SSH access to the remote machine with Python 3

## Build & Run

```bash
cd TokenBar
./build.sh
open build/TokenBar.app
```

Or manually:

```bash
cd TokenBar
swift build
mkdir -p build/TokenBar.app/Contents/MacOS
cp .build/debug/TokenBar build/TokenBar.app/Contents/MacOS/
open build/TokenBar.app
```

The app runs in the menu bar only (no dock icon). Click the `◆ Model | Tokens` label to open the panel.

## Menu Bar Display

Shows your most-used model today and total token count:

```
◆ Opus 4.6 | 783.9K
```

When set to OpenCode or All:

```
◆ Kimi K2 Turbo | 98.5M
◆ All | 99.3M
```

## Cost Calculation

Estimated costs are computed from token counts using published API pricing:

**Anthropic (Claude Code)**

| | Input | Output | Cache Read | Cache Write |
|---|---|---|---|---|
| **Opus** | $15/M | $75/M | $1.50/M | $3.75/M |
| **Sonnet** | $3/M | $15/M | $0.30/M | $0.75/M |
| **Haiku** | $0.80/M | $4/M | $0.08/M | $0.20/M |

**Moonshot AI (OpenCode)**

| | Input | Output | Cache Read |
|---|---|---|---|
| **Kimi K2 Turbo** | $1.15/M | $8.00/M | $0.15/M |
| **Kimi K2.5** | $0.60/M | $3.00/M | $0.10/M |

Local Ollama models (Qwen, Llama, etc.) show $0 — they're free.

Click the cost pill in the app for a per-model line-by-line breakdown.

## Architecture

- **SwiftUI** with `MenuBarExtra` (`.window` style)
- **No external dependencies** — pure Swift + AppKit/SwiftUI
- Polls `stats-cache.json` every 30 seconds (skips re-parse if file unchanged)
- Scans session JSONL files for live today metrics
- SSH + Python script for remote OpenCode data aggregation
- Background-only app (`LSUIElement = true`)

## License

MIT
