#!/usr/bin/env python3
"""Aggregate OpenCode token usage stats into JSON.
Reads message files from ~/.local/share/opencode/storage/
Outputs JSON to stdout for Token Bar to consume via SSH.
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from collections import defaultdict

STORAGE = Path.home() / ".local" / "share" / "opencode" / "storage"

def main():
    msg_dir = STORAGE / "message"
    session_dir = STORAGE / "session"

    if not msg_dir.exists():
        json.dump({"error": "no opencode data"}, sys.stdout)
        return

    model_usage = defaultdict(lambda: {"input": 0, "output": 0, "reasoning": 0, "cacheRead": 0, "cacheWrite": 0})
    daily_tokens = defaultdict(lambda: defaultdict(int))  # date -> model -> tokens
    daily_activity = defaultdict(lambda: {"messages": 0, "sessions": set()})
    total_messages = 0
    total_sessions = set()
    provider_set = set()

    for session_id in sorted(msg_dir.iterdir()):
        if not session_id.is_dir():
            continue
        sid = session_id.name
        total_sessions.add(sid)

        for msg_file in sorted(session_id.iterdir()):
            if not msg_file.suffix == ".json":
                continue
            try:
                data = json.loads(msg_file.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue

            if data.get("role") != "assistant":
                continue

            tokens = data.get("tokens", {})
            inp = tokens.get("input", 0)
            out = tokens.get("output", 0)
            reasoning = tokens.get("reasoning", 0)
            cache = tokens.get("cache", {})
            cache_read = cache.get("read", 0)
            cache_write = cache.get("write", 0)

            if inp == 0 and out == 0:
                continue

            model = data.get("modelID", "unknown")
            provider = data.get("providerID", "unknown")
            provider_set.add(provider)

            model_usage[model]["input"] += inp
            model_usage[model]["output"] += out
            model_usage[model]["reasoning"] += reasoning
            model_usage[model]["cacheRead"] += cache_read
            model_usage[model]["cacheWrite"] += cache_write

            # Parse date from timestamp
            created = data.get("time", {}).get("created", 0)
            if created > 0:
                dt = datetime.fromtimestamp(created / 1000.0)
                date_str = dt.strftime("%Y-%m-%d")
                daily_tokens[date_str][model] += inp + out
                daily_activity[date_str]["messages"] += 1
                daily_activity[date_str]["sessions"].add(sid)

            total_messages += 1

    # Build output
    result = {
        "source": "opencode",
        "providers": sorted(provider_set),
        "totalSessions": len(total_sessions),
        "totalMessages": total_messages,
        "modelUsage": {k: dict(v) for k, v in model_usage.items()},
        "dailyModelTokens": [
            {"date": d, "tokensByModel": dict(daily_tokens[d])}
            for d in sorted(daily_tokens.keys())
        ],
        "dailyActivity": [
            {"date": d, "messageCount": v["messages"], "sessionCount": len(v["sessions"])}
            for d, v in sorted(daily_activity.items())
        ],
    }

    json.dump(result, sys.stdout, indent=2)

if __name__ == "__main__":
    main()
