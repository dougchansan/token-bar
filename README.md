# Token Bar

A native macOS menu bar app for monitoring AI coding assistant token usage at a glance.

<p align="center">
  <img src="screenshots/panel.png" alt="Token Bar" width="420">
</p>

## Features

- **Live Token Counting** — Scans active session files for real-time today stats, not just cached data
- **Activity Heatmap** — 16-week GitHub-style calendar with hover tooltips showing per-day metrics
- **Cost Estimation** — Calculates approximate USD spend per model using Anthropic API pricing (click for full breakdown)
- **Model Breakdown** — All-time token usage by model with relative progress bars and cost per model
- **Streak Counter** — Consecutive days with coding activity
- **Peak Hours** — 24-hour session distribution chart highlighting your most productive time
- **Launch at Login** — Toggle to start automatically on boot
- **Dark Theme** — Designed to look clean alongside your menu bar

## Data Source

Reads from `~/.claude/stats-cache.json` (written by Claude Code) and scans session JSONL files under `~/.claude/projects/` for live token counts.

**Currently supports:**
- Claude Code (all models: Opus, Sonnet, Haiku)

**Planned:**
- OpenCode
- Ollama (local and remote GPU)

## Requirements

- macOS 14+
- Swift 5.9+
- Claude Code installed (`~/.claude/` directory)

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

## Cost Calculation

Estimated costs are computed from token counts using Anthropic's published API pricing:

| | Input | Output | Cache Read | Cache Write |
|---|---|---|---|---|
| **Opus** | $15/M | $75/M | $1.50/M | $3.75/M |
| **Sonnet** | $3/M | $15/M | $0.30/M | $0.75/M |
| **Haiku** | $0.80/M | $4/M | $0.08/M | $0.20/M |

Click the cost pill in the app for a per-model line-by-line breakdown.

## Architecture

- **SwiftUI** with `MenuBarExtra` (`.window` style)
- **No external dependencies** — pure Swift + AppKit/SwiftUI
- Polls `stats-cache.json` every 30 seconds (skips re-parse if file unchanged)
- Scans session JSONL files for live today metrics
- Background-only app (`LSUIElement = true`)

## License

MIT
