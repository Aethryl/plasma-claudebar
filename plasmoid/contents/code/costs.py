#!/usr/bin/env python3
"""Emit one JSON line with API-equivalent Claude Code costs from local transcripts."""

import json
import os
import time
import urllib.request
from datetime import date, datetime, timedelta
from functools import cache
from pathlib import Path

PROJECTS = Path.home() / ".claude" / "projects"
CACHE_DIR = Path.home() / ".cache" / "claude-bar"
STATE = CACHE_DIR / "costs.json"
PRICES = CACHE_DIR / "prices.json"
PRICES_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICES_MAX_AGE = 24 * 3600
LIMITS = CACHE_DIR / "limits.json"
KEEP_DAYS = 35
SLOT = 300
SLOT_KEEP = 8 * 86400
HALF_HOUR = 30 * 60
WEEK = 7 * 86400
WEB_SEARCH_COST = 0.01


def load(path: Path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def save(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".{os.getpid()}.tmp")
    tmp.write_text(json.dumps(data))
    tmp.replace(path)


def prices() -> dict:
    try:
        fresh = time.time() - PRICES.stat().st_mtime < PRICES_MAX_AGE
    except OSError:
        fresh = False
    if not fresh:
        try:
            with urllib.request.urlopen(PRICES_URL, timeout=10) as response:
                table = json.loads(response.read())
            save(PRICES, {k: v for k, v in table.items() if k.startswith("claude-")})
        except (OSError, ValueError):
            pass
    return load(PRICES, {})


def price_for(model: str, table: dict) -> dict | None:
    if model in table:
        return table[model]
    stem = model.rsplit("-", 1)[0] if model[-8:].isdigit() else model
    if stem in table:
        return table[stem]
    candidates = [key for key in table if key.startswith(stem)]
    return table[min(candidates, key=len)] if candidates else None


def cost_of(usage: dict, price: dict) -> float:
    creation = usage.get("cache_creation") or {}
    long_cache = creation.get("ephemeral_1h_input_tokens") or 0
    short_cache = (usage.get("cache_creation_input_tokens") or 0) - long_cache
    write_price = price.get("cache_creation_input_token_cost") or 0
    long_price = price.get("cache_creation_input_token_cost_above_1hr") or write_price
    searches = (usage.get("server_tool_use") or {}).get("web_search_requests") or 0
    return (
        (usage.get("input_tokens") or 0) * (price.get("input_cost_per_token") or 0)
        + (usage.get("output_tokens") or 0) * (price.get("output_cost_per_token") or 0)
        + short_cache * write_price
        + long_cache * long_price
        + (usage.get("cache_read_input_tokens") or 0)
        * (price.get("cache_read_input_token_cost") or 0)
        + searches * WEB_SEARCH_COST
    )


def moment_of(timestamp: str) -> datetime | None:
    try:
        return datetime.fromisoformat(timestamp).astimezone()
    except (AttributeError, TypeError, ValueError):
        return None


@cache
def project_of(cwd: str) -> str:
    parts = cwd.rstrip("/").split("/")
    if "Worktrees" in parts[:-2]:
        return parts[parts.index("Worktrees") + 1]
    for depth in range(len(parts), 1, -1):
        if os.path.exists("/".join(parts[:depth] + [".git"])):
            return parts[depth - 1]
    return parts[-1] or "~"


def scan(state: dict, table: dict) -> None:
    cutoff = time.time() - KEEP_DAYS * 86400
    files = state.setdefault("files", {})
    seen = state.setdefault("seen", {})
    days = state.setdefault("days", {})
    slots = state.setdefault("slots", {})
    slot_cutoff = time.time() - SLOT_KEEP
    for path in PROJECTS.glob("**/*.jsonl"):
        try:
            stat = path.stat()
        except OSError:
            continue
        if stat.st_mtime < cutoff:
            continue
        key = str(path)
        offset = files.get(key, 0)
        if stat.st_size < offset:
            offset = 0
        if stat.st_size == offset:
            continue
        with path.open("rb") as handle:
            handle.seek(offset)
            chunk = handle.read()
        end = chunk.rfind(b"\n") + 1
        for line in chunk[:end].splitlines():
            if b'"usage"' not in line:
                continue
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            message = entry.get("message") or {}
            usage = message.get("usage")
            model = message.get("model")
            moment = moment_of(entry.get("timestamp"))
            if not usage or not model or not moment or model.startswith("<"):
                continue
            ident = f"{message.get('id')}:{entry.get('requestId')}"
            if ident in seen:
                continue
            day = moment.date().isoformat()
            seen[ident] = day
            price = price_for(model, table)
            if price is None:
                continue
            cost = cost_of(usage, price)
            bucket = days.setdefault(day, {})
            bucket[model] = bucket.get(model, 0) + cost
            stamp = moment.timestamp()
            if stamp >= slot_cutoff:
                per = slots.setdefault(str(int(stamp // SLOT * SLOT)), {})
                name = project_of(entry.get("cwd") or "")
                per[name] = per.get(name, 0) + cost
        files[key] = offset + end
    oldest = (date.today() - timedelta(days=KEEP_DAYS)).isoformat()
    state["days"] = {d: v for d, v in days.items() if d >= oldest}
    state["seen"] = {k: d for k, d in seen.items() if d >= oldest}
    state["files"] = {k: v for k, v in files.items() if Path(k).exists()}
    state["slots"] = {k: v for k, v in slots.items() if int(k) >= slot_cutoff}


def projects_since(slots: dict, since: float) -> list[dict]:
    totals: dict[str, float] = {}
    for key, per in slots.items():
        if int(key) + SLOT > since:
            for name, cost in per.items():
                totals[name] = totals.get(name, 0) + cost
    return [
        {"name": n, "cost": round(c, 4)}
        for n, c in sorted(totals.items(), key=lambda kv: -kv[1])
        if c > 0
    ]


def week_start(now: float) -> float:
    week = (load(LIMITS, {}).get("rate_limits") or {}).get("seven_day") or {}
    resets_at = week.get("resets_at") or 0
    return resets_at - WEEK if resets_at > now else now - WEEK


def summary(state: dict) -> dict:
    today = date.today()
    days = state["days"]

    def total(day: date) -> float:
        return sum(days.get(day.isoformat(), {}).values())

    now = time.time()
    week = [today - timedelta(days=n) for n in range(6, -1, -1)]
    month = [today - timedelta(days=n) for n in range(30)]
    models: dict[str, float] = {}
    for day in week:
        for model, cost in days.get(day.isoformat(), {}).items():
            models[model] = models.get(model, 0) + cost
    return {
        "today": round(total(today), 2),
        "week": round(sum(total(d) for d in week), 2),
        "month": round(sum(total(d) for d in month), 2),
        "daily": [{"day": d.isoformat(), "cost": round(total(d), 2)} for d in week],
        "models": [
            {"model": m, "cost": round(c, 2)}
            for m, c in sorted(models.items(), key=lambda kv: -kv[1])
        ],
        "projects": {
            "half_hour": projects_since(state["slots"], now - HALF_HOUR),
            "week": projects_since(state["slots"], week_start(now)),
        },
        "updated": now,
    }


def main() -> None:
    state = load(STATE, {})
    if "slots" not in state:
        state = {}
    scan(state, prices())
    save(STATE, state)
    print(json.dumps(summary(state)))


if __name__ == "__main__":
    main()
