#!/usr/bin/env python3
"""Scan Claude Code session JSONL files for recent token usage not yet in stats-cache.json.
Outputs JSON with daily activity/tokens for dates after lastComputedDate."""

import json, os, sys
from datetime import datetime, timedelta, timezone

def long_path(p):
    """On Windows, prefix paths to handle >260 char limit."""
    if sys.platform == "win32" and not p.startswith("\\\\?\\"):
        return "\\\\?\\" + os.path.abspath(p)
    return p

def main():
    home = os.path.expanduser("~")
    claude_dir = os.path.join(home, ".claude")
    cache_path = os.path.join(claude_dir, "stats-cache.json")
    projects_dir = os.path.join(claude_dir, "projects")

    # Read lastComputedDate from stats-cache
    last_computed = None
    try:
        with open(cache_path) as f:
            cache = json.load(f)
        last_computed = cache.get("lastComputedDate")
    except Exception:
        pass

    if last_computed:
        cutoff = datetime.strptime(last_computed, "%Y-%m-%d").date()
    else:
        cutoff = (datetime.now() - timedelta(days=3)).date()

    cutoff_str = cutoff.strftime("%Y-%m-%d")

    daily_tokens = {}   # date -> {model: tokens}
    daily_msgs = {}     # date -> count
    daily_sessions = {} # date -> set of session ids

    if not os.path.isdir(projects_dir):
        json.dump({"dailyActivity": [], "dailyModelTokens": []}, sys.stdout)
        return

    for project_name in os.listdir(projects_dir):
        project_path = os.path.join(projects_dir, project_name)
        try:
            if not os.path.isdir(project_path):
                continue
        except Exception:
            continue

        # Walk directories - don't use \\?\ prefix here (breaks os.walk on some Windows versions)
        try:
            walker = list(os.walk(project_path))
        except Exception:
            # Fall back to long-path walk for problematic directories
            try:
                walker = list(os.walk(long_path(project_path)))
            except Exception:
                continue

        for dirpath, dirnames, filenames in walker:
            for fname in filenames:
                if not fname.endswith(".jsonl"):
                    continue

                fpath = os.path.join(dirpath, fname)

                try:
                    mtime = datetime.fromtimestamp(os.path.getmtime(fpath)).date()
                except Exception:
                    try:
                        mtime = datetime.fromtimestamp(os.path.getmtime(long_path(fpath))).date()
                    except Exception:
                        continue

                if mtime < cutoff:
                    continue

                session_id = fname[:-6]  # strip .jsonl

                try:
                    fh = open(fpath, encoding="utf-8", errors="replace")
                except Exception:
                    try:
                        fh = open(long_path(fpath), encoding="utf-8", errors="replace")
                    except Exception:
                        continue

                try:
                    for line in fh:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except json.JSONDecodeError:
                            continue

                        # Extract timestamp
                        ts = None
                        if "timestamp" in obj:
                            ts = obj["timestamp"]
                        elif "data" in obj and isinstance(obj["data"], dict):
                            ts = obj["data"].get("timestamp")

                        if ts:
                            try:
                                dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
                                # Convert UTC to local time for correct date attribution
                                dt_local = dt.astimezone()
                                date_str = dt_local.date().strftime("%Y-%m-%d")
                            except Exception:
                                date_str = None
                        else:
                            date_str = None

                        # Extract usage
                        usage = None
                        model = None
                        if "message" in obj and isinstance(obj["message"], dict):
                            msg = obj["message"]
                            usage = msg.get("usage")
                            model = msg.get("model")
                        elif "data" in obj and isinstance(obj["data"], dict):
                            data = obj["data"]
                            if "message" in data and isinstance(data["message"], dict):
                                inner = data["message"]
                                if "message" in inner and isinstance(inner["message"], dict):
                                    usage = inner["message"].get("usage")
                                    model = inner["message"].get("model")

                        if not usage or not isinstance(usage, dict):
                            continue

                        inp = usage.get("input_tokens", 0)
                        out = usage.get("output_tokens", 0)
                        if inp == 0 and out == 0:
                            continue

                        # Use file mtime date as fallback
                        if not date_str:
                            date_str = mtime.strftime("%Y-%m-%d")

                        if date_str < cutoff_str:
                            continue

                        daily_tokens.setdefault(date_str, {})
                        if model:
                            daily_tokens[date_str][model] = daily_tokens[date_str].get(model, 0) + inp + out

                        daily_msgs[date_str] = daily_msgs.get(date_str, 0) + 1
                        daily_sessions.setdefault(date_str, set()).add(session_id)
                except Exception:
                    pass
                finally:
                    fh.close()

    result = {
        "dailyActivity": [
            {"date": d, "messageCount": daily_msgs.get(d, 0),
             "sessionCount": len(daily_sessions.get(d, set()))}
            for d in sorted(daily_tokens.keys())
        ],
        "dailyModelTokens": [
            {"date": d, "tokensByModel": daily_tokens[d]}
            for d in sorted(daily_tokens.keys())
        ]
    }
    json.dump(result, sys.stdout)

if __name__ == "__main__":
    main()
