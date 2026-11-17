#!/usr/bin/env python3
"""Fetch the 5h/7d rate limits from `claude /usage` and share them with the claude bar cache."""

import fcntl
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime

CACHE_DIR = os.path.expanduser("~/.cache/claude-bar")
LIMITS_CACHE = os.path.join(CACHE_DIR, "limits.json")
PACE_CACHE = os.path.join(CACHE_DIR, "pace.json")
PACE7_CACHE = os.path.join(CACHE_DIR, "pace-7d.json")
LOCK = os.path.join(CACHE_DIR, "ratepoll.lock")
KINDS = {"session": "five_hour", "weekly_all": "seven_day"}
TIMEOUT = 30


def write_json(target, payload):
    tmp = f"{target}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f)
    os.replace(tmp, target)


def fetch():
    claude = shutil.which("claude") or os.path.expanduser("~/.local/bin/claude")
    try:
        out = subprocess.run(
            [
                claude,
                "-p",
                "/usage",
                "--output-format",
                "stream-json",
                "--verbose",
                "--no-session-persistence",
            ],
            cwd=CACHE_DIR,
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            stdin=subprocess.DEVNULL,
            check=False,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return {}
    found = {}
    for line in out.splitlines():
        try:
            rows = json.loads(line)["usage_report"]["rate_limits"]["limits"]
        except (ValueError, KeyError, TypeError):
            continue
        for row in rows:
            key = KINDS.get(row.get("kind"))
            try:
                resets = round(datetime.fromisoformat(row["resets_at"]).timestamp())
                found[key] = {
                    "used_percentage": int(row["percent"]),
                    "resets_at": resets,
                }
            except (KeyError, TypeError, ValueError):
                continue
    found.pop(None, None)
    return found


def store_limits(found):
    with open(f"{LIMITS_CACHE}.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(LIMITS_CACHE) as f:
                cache = json.load(f)
        except (OSError, ValueError):
            cache = {}
        merged = cache.get("rate_limits") or {}
        for key, window in found.items():
            if window["resets_at"] >= ((merged.get(key) or {}).get("resets_at") or 0):
                merged[key] = window
        write_json(LIMITS_CACHE, {"updated_at": time.time(), "rate_limits": merged})


def record_pace(pct, resets_at, path, min_gap):
    now = time.time()
    with open(f"{path}.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            with open(path) as f:
                pace = json.load(f)
        except (OSError, ValueError):
            pace = {}
        if pace.get("resets_at") != resets_at:
            if resets_at < (pace.get("resets_at") or 0):
                return
            pace = {"resets_at": resets_at, "samples": []}
        samples = pace["samples"]
        if not samples or (now - samples[-1][0] >= min_gap and pct >= samples[-1][1]):
            samples.append([now, pct])
            write_json(path, pace)


def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    with open(LOCK, "w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            return
        found = fetch()
        if not found:
            return
        store_limits(found)
        for key, path, gap in (
            ("five_hour", PACE_CACHE, 60),
            ("seven_day", PACE7_CACHE, 900),
        ):
            if key in found:
                record_pace(
                    found[key]["used_percentage"], found[key]["resets_at"], path, gap
                )


if __name__ == "__main__":
    try:
        main()
    except (OSError, TypeError, ValueError):
        sys.exit(1)
