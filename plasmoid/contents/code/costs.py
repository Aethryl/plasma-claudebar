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
FLEET = CACHE_DIR / "fleet.json"
KEEP_DAYS = 35
SLOT = 300
SLOT_KEEP = 8 * 86400
HALF_HOUR = 30 * 60
WEEK = 7 * 86400
SESSION = 5 * 3600
FLEET_STALE = 45 * 60
WEB_SEARCH_COST = 0.01
TOKEN_FIELDS = (
    "input_tokens",
    "output_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)
TOKEN_KINDS = ("in", "out", "cache_w", "cache_r")


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


def parse(line: bytes) -> tuple[dict, dict, str, datetime, str] | None:
    if b'"usage"' not in line:
        return None
    try:
        entry = json.loads(line)
    except ValueError:
        return None
    message = entry.get("message") or {}
    usage = message.get("usage")
    model = message.get("model")
    moment = moment_of(entry.get("timestamp"))
    if not usage or not model or not moment or model.startswith("<"):
        return None
    return entry, usage, model, moment, f"{message.get('id')}:{entry.get('requestId')}"


def add_tokens(token_days: dict, day: str, usage: dict) -> None:
    row = token_days.setdefault(day, [0] * len(TOKEN_FIELDS))
    for i, field in enumerate(TOKEN_FIELDS):
        row[i] += usage.get(field) or 0


def backfill_tokens(state: dict) -> None:
    """One-time token pass over the transcripts still on disk; never touches cost days, offsets or seen."""
    cutoff = time.time() - KEEP_DAYS * 86400
    oldest = (date.today() - timedelta(days=KEEP_DAYS)).isoformat()
    token_days: dict = {}
    counted: set[str] = set()
    for path in PROJECTS.glob("**/*.jsonl"):
        try:
            if path.stat().st_mtime < cutoff:
                continue
            data = path.read_bytes()
        except OSError:
            continue
        for line in data[: data.rfind(b"\n") + 1].splitlines():
            parsed = parse(line)
            if parsed is None:
                continue
            _, usage, _, moment, ident = parsed
            day = moment.date().isoformat()
            if ident in counted or day < oldest:
                continue
            counted.add(ident)
            add_tokens(token_days, day, usage)
    state["token_days"] = token_days


def scan(state: dict, table: dict) -> None:
    fresh_tokens = "token_days" not in state
    if fresh_tokens:
        backfill_tokens(state)
    cutoff = time.time() - KEEP_DAYS * 86400
    token_days = state["token_days"]
    files = state.setdefault("files", {})
    seen = state.setdefault("seen", {})
    days = state.setdefault("days", {})
    slots = state.setdefault("slots", {})
    model_slots = state.setdefault("model_slots", {})
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
            parsed = parse(line)
            if parsed is None:
                continue
            entry, usage, model, moment, ident = parsed
            if ident in seen:
                continue
            day = moment.date().isoformat()
            seen[ident] = day
            if not fresh_tokens:
                add_tokens(token_days, day, usage)
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
                by_model = model_slots.setdefault(str(int(stamp // SLOT * SLOT)), {})
                by_model[model] = by_model.get(model, 0) + cost
        files[key] = offset + end
    oldest = (date.today() - timedelta(days=KEEP_DAYS)).isoformat()
    state["days"] = {d: v for d, v in days.items() if d >= oldest}
    state["token_days"] = {d: v for d, v in token_days.items() if d >= oldest}
    state["seen"] = {k: d for k, d in seen.items() if d >= oldest}
    state["files"] = {k: v for k, v in files.items() if Path(k).exists()}
    state["slots"] = {k: v for k, v in slots.items() if int(k) >= slot_cutoff}
    state["model_slots"] = {
        k: v for k, v in model_slots.items() if int(k) >= slot_cutoff
    }


def totals_since(slots: dict, since: float) -> dict[str, float]:
    totals: dict[str, float] = {}
    for key, per in slots.items():
        if int(key) + SLOT > since:
            for name, cost in per.items():
                totals[name] = totals.get(name, 0) + cost
    return totals


def ranked(totals: dict[str, float], field: str, **extra) -> list[dict]:
    return [
        {field: n, "cost": round(c, 4), **extra}
        for n, c in sorted(totals.items(), key=lambda kv: -kv[1])
        if c > 0
    ]


def projects_since(slots: dict, since: float) -> list[dict]:
    return ranked(totals_since(slots, since), "name")


def remote_share(cost: dict, start: float, now: float) -> float:
    """Host spend inside the window, assuming each day's cost is spread evenly over its elapsed hours."""
    total = 0.0
    for day, amount in (cost.get("days") or {}).items():
        try:
            midnight = datetime.fromisoformat(day).timestamp()
        except ValueError:
            continue
        end = min(midnight + 86400, now)
        overlap = min(end, now) - max(midnight, start)
        if overlap > 0:
            total += amount * overlap / max(end - midnight, 3600)
    return total


def remote_window(start: float, now: float) -> tuple[list[dict], list[dict]]:
    projects: list[dict] = []
    models: list[dict] = []
    hosts = (load(FLEET, {}).get("hosts") or {}).items()
    for host, stats in hosts:
        cost = (stats or {}).get("cost") or {}
        stale = bool(stats.get("stale")) or now - stats.get("at", 0) > FLEET_STALE
        spent = remote_share(cost, start, now)
        for rows, field, out in (
            (cost.get("projects") or [], "name", projects),
            (cost.get("models") or [], "model", models),
        ):
            basis = sum(r["cost"] for r in rows)
            if spent <= 0 or basis <= 0:
                continue
            out.extend(
                {
                    field: r[field],
                    "cost": round(spent * r["cost"] / basis, 4),
                    "host": host,
                    "stale": stale,
                }
                for r in rows
                if r["cost"] > 0
            )
    return projects, models


def window_start(key: str, span: int, now: float) -> float | None:
    window = (load(LIMITS, {}).get("rate_limits") or {}).get(key) or {}
    resets_at = window.get("resets_at") or 0
    return resets_at - span if resets_at > now else None


def window_breakdown(state: dict, start: float | None, now: float) -> dict | None:
    if start is None:
        return None
    local_projects = ranked(totals_since(state["slots"], start), "name")
    local_models = ranked(totals_since(state["model_slots"], start), "model")
    remote_projects, remote_models = remote_window(start, now)
    return {
        "start": start,
        "projects": sorted(local_projects + remote_projects, key=lambda r: -r["cost"]),
        "models": sorted(local_models + remote_models, key=lambda r: -r["cost"]),
    }


def week_start(now: float) -> float:
    week = (load(LIMITS, {}).get("rate_limits") or {}).get("seven_day") or {}
    resets_at = week.get("resets_at") or 0
    return resets_at - WEEK if resets_at > now else now - WEEK


def token_summary(token_days: dict, today: date) -> dict:
    def window(n: int) -> list[int]:
        rows = [
            token_days.get((today - timedelta(days=i)).isoformat()) for i in range(n)
        ]
        return [sum(r[k] for r in rows if r) for k in range(len(TOKEN_FIELDS))]

    return {
        "today": sum(window(1)[:3]),
        "week": sum(window(7)[:3]),
        "month": sum(window(30)[:3]),
        "kinds": dict(zip(TOKEN_KINDS, window(30))),
    }


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
        "window": {
            "five_hour": window_breakdown(
                state, window_start("five_hour", SESSION, now), now
            ),
            "seven_day": window_breakdown(
                state, window_start("seven_day", WEEK, now), now
            ),
        },
        "tokens": token_summary(state["token_days"], today),
        "updated": now,
    }


def main() -> None:
    state = load(STATE, {})
    if "slots" not in state or "model_slots" not in state:
        state = {}
    scan(state, prices())
    save(STATE, state)
    print(json.dumps(summary(state)))


if __name__ == "__main__":
    main()
