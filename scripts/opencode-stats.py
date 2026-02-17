#!/usr/bin/env python3
"""Aggregate OpenCode token usage stats into JSON.
Supports both SQLite (v1.2+) and legacy JSON storage formats.
Outputs JSON to stdout for Token Bar to consume locally or via SSH.
"""
import json
import os
import sys
import sqlite3
from datetime import datetime
from pathlib import Path
from collections import defaultdict

DATA_DIR = Path.home() / ".local" / "share" / "opencode"
STORAGE = DATA_DIR / "storage"
DB_PATH = DATA_DIR / "opencode.db"


def aggregate(messages):
    """Aggregate a list of message dicts into stats."""
    model_usage = defaultdict(lambda: {"input": 0, "output": 0, "reasoning": 0, "cacheRead": 0, "cacheWrite": 0})
    daily_tokens = defaultdict(lambda: defaultdict(int))
    daily_activity = defaultdict(lambda: {"messages": 0, "sessions": set()})
    total_messages = 0
    total_sessions = set()
    provider_set = set()

    for data, session_id in messages:
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
        total_sessions.add(session_id)

        model_usage[model]["input"] += inp
        model_usage[model]["output"] += out
        model_usage[model]["reasoning"] += reasoning
        model_usage[model]["cacheRead"] += cache_read
        model_usage[model]["cacheWrite"] += cache_write

        created = data.get("time", {}).get("created", 0)
        if created > 0:
            dt = datetime.fromtimestamp(created / 1000.0)
            date_str = dt.strftime("%Y-%m-%d")
            daily_tokens[date_str][model] += inp + out
            daily_activity[date_str]["messages"] += 1
            daily_activity[date_str]["sessions"].add(session_id)

        total_messages += 1

    return {
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


def read_sqlite():
    """Read messages from SQLite database (OpenCode v1.2+)."""
    conn = sqlite3.connect(str(DB_PATH))
    cursor = conn.execute("SELECT data, session_id FROM message")
    messages = []
    for row in cursor:
        try:
            data = json.loads(row[0])
            messages.append((data, row[1]))
        except (json.JSONDecodeError, TypeError):
            continue
    conn.close()
    return messages


def read_json_storage():
    """Read messages from legacy JSON file storage (OpenCode v1.1.x)."""
    msg_dir = STORAGE / "message"
    if not msg_dir.exists():
        return []

    messages = []
    for session_dir in sorted(msg_dir.iterdir()):
        if not session_dir.is_dir():
            continue
        sid = session_dir.name
        for msg_file in sorted(session_dir.iterdir()):
            if msg_file.suffix != ".json":
                continue
            try:
                data = json.loads(msg_file.read_text(encoding="utf-8"))
                messages.append((data, sid))
            except (json.JSONDecodeError, UnicodeDecodeError):
                continue
    return messages


def main():
    messages = []

    # Try SQLite first (v1.2+), fall back to JSON storage (v1.1.x)
    if DB_PATH.exists():
        messages = read_sqlite()
    elif STORAGE.exists():
        messages = read_json_storage()
    else:
        json.dump({"error": "no opencode data"}, sys.stdout)
        return

    if not messages:
        json.dump({"error": "no opencode messages"}, sys.stdout)
        return

    result = aggregate(messages)
    json.dump(result, sys.stdout, indent=2)


if __name__ == "__main__":
    main()
