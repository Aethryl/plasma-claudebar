"""Runs on a remote Orca host (stdlib only): prints a CLAUDEBAR line with live Claude sessions and their subagents.

remote.py starts it in one long-lived Orca terminal per host and reads the lines back with
`orca terminal read`. It prints when the snapshot changes or every HEARTBEAT seconds, and exits
once no input arrived for LEASE seconds, so a probe nobody reads stops on its own.
"""

import glob
import json
import os
import re
import select
import sys
import time
from datetime import datetime

TITLE = "claudebar-probe"
TICK = 5
HEARTBEAT = 30
LEASE = 10 * 60
HOME = os.path.expanduser("~")
PROJECTS = os.path.join(HOME, ".claude", "projects")
SESSIONS = os.path.join(HOME, ".claude", "sessions")
RUNNING_FOR = 30 * 60
PENDING_FOR = 3 * 3600
DONE_FOR = 10 * 60
MAX_SESSIONS = 24
MAX_SUBAGENTS = 8
MAX_LINE = 12000
TAIL = 32768
ORDER = ["waiting", "error", "working", "done"]
FAMILIES = ("opus", "sonnet", "haiku", "fable")
CLK = os.sysconf("SC_CLK_TCK")
cache: dict = {}


def boot_time():
    try:
        with open("/proc/stat") as f:
            for line in f:
                if line.startswith("btime "):
                    return int(line.split()[1])
    except OSError:
        pass
    return 0


BOOT = boot_time()


def read_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def started(pid):
    try:
        with open(f"/proc/{pid}/stat") as f:
            fields = f.read().rsplit(")", 1)[1].split()
        return BOOT + int(fields[19]) / CLK
    except (OSError, IndexError, ValueError):
        return 0


def processes():
    """Claude processes that run in an Orca pane, as (pid, pane, cwd, args, started)."""
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                argv = f.read().split(b"\0")
            if os.path.basename(argv[0]) != b"claude":
                continue
            with open(f"/proc/{pid}/environ", "rb") as f:
                env = f.read().split(b"\0")
            cwd = os.readlink(f"/proc/{pid}/cwd")
        except (OSError, IndexError):
            continue
        pane = next(
            (v[14:].decode() for v in env if v.startswith(b"ORCA_PANE_KEY=")), ""
        )
        if pane:
            args = [a.decode(errors="replace") for a in argv[1:]]
            yield int(pid), pane, cwd, args, started(pid)


def session_of(pid, cwd, args, since, claimed):
    entry = read_json(os.path.join(SESSIONS, f"{pid}.json"))
    folder = os.path.join(PROJECTS, re.sub(r"[^A-Za-z0-9]", "-", cwd))
    if isinstance(entry, dict) and entry.get("sessionId"):
        return entry["sessionId"], str(entry.get("name") or ""), folder
    for flag in ("--resume", "-r", "--session-id"):
        if flag in args[:-1]:
            sid = args[args.index(flag) + 1]
            if os.path.exists(os.path.join(folder, f"{sid}.jsonl")):
                return sid, "", folder
    newest = sorted(
        (
            (os.stat(p).st_mtime, os.path.basename(p)[: -len(".jsonl")])
            for p in glob.glob(os.path.join(folder, "*.jsonl"))
        ),
        reverse=True,
    )
    for mtime, sid in newest:
        if mtime >= since and sid not in claimed:
            return sid, "", folder
    return None, "", folder


def family(model):
    model = str(model or "").lower()
    return next((f for f in FAMILIES if f in model), model or None)


def first_stamp(path):
    key = ("start", path)
    if key not in cache:
        try:
            with open(path) as f:
                stamp = json.loads(f.readline()).get("timestamp")
            cache[key] = datetime.fromisoformat(stamp).timestamp()
        except (OSError, ValueError, TypeError, AttributeError):
            return None
    return cache[key]


def tail(path, stat):
    """Model, pending tool, last tool and API-error flag from the end of a transcript."""
    key = ("tail", path)
    hit = cache.get(key)
    if hit and hit[0] == (stat.st_mtime, stat.st_size):
        return hit[1]
    try:
        with open(path, "rb") as f:
            f.seek(max(0, stat.st_size - TAIL))
            lines = f.read().splitlines()
    except OSError:
        lines = []
    found = {"model": None, "tool": "", "pending": False, "error": False}
    answered = set()
    for raw in reversed(lines):
        try:
            entry = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(entry, dict):
            continue
        content = (entry.get("message") or {}).get("content")
        blocks = content if isinstance(content, list) else []
        if entry.get("type") == "user":
            answered.update(
                b.get("tool_use_id")
                for b in blocks
                if isinstance(b, dict) and b.get("type") == "tool_result"
            )
        elif entry.get("type") == "assistant":
            found["model"] = (entry.get("message") or {}).get("model")
            found["error"] = bool(entry.get("isApiErrorMessage"))
            uses = [
                b for b in blocks if isinstance(b, dict) and b.get("type") == "tool_use"
            ]
            if uses:
                found["tool"] = str(uses[-1].get("name") or "")
                found["pending"] = any(u.get("id") not in answered for u in uses)
            break
    cache[key] = ((stat.st_mtime, stat.st_size), found)
    return found


def meta_of(path):
    try:
        mtime = os.stat(path).st_mtime
    except OSError:
        return None
    key = ("meta", path)
    hit = cache.get(key)
    if hit and hit[0] == mtime:
        return hit[1]
    meta = read_json(path)
    cache[key] = (mtime, meta)
    return meta


def subagents(folder, sid, since, now):
    found = []
    for transcript in glob.glob(
        os.path.join(folder, sid, "subagents", "agent-*.jsonl")
    ):
        try:
            stat = os.stat(transcript)
        except OSError:
            continue
        age = now - stat.st_mtime
        if age > PENDING_FOR:
            continue
        meta = meta_of(transcript[: -len(".jsonl")] + ".meta.json")
        if not isinstance(meta, dict):
            continue
        last = tail(transcript, stat)
        need = ""
        if meta.get("finished") or meta.get("stoppedByUser"):
            if last["error"]:
                status, need = "error", "failed"
            elif age <= DONE_FOR:
                status = "done"
            else:
                continue
        elif stat.st_mtime < since:
            continue
        elif last["pending"] and last["tool"] == "AskUserQuestion":
            status, need = "waiting", "question"
        elif age <= RUNNING_FOR or last["pending"]:
            status = "working"
        else:
            continue
        start = first_stamp(transcript)
        found.append(
            (
                ORDER.index(status),
                -(start or 0),
                {
                    "id": os.path.basename(transcript)[len("agent-") : -len(".jsonl")],
                    "type": meta.get("agentType"),
                    "model": family(meta.get("model") or last["model"]),
                    "description": str(meta.get("description") or "")[:80],
                    "status": status,
                    "need": need,
                    "tool": last["tool"] if status in ("working", "waiting") else "",
                    "ask": "",
                    "depth": meta.get("spawnDepth") or 1,
                    "started_at": start,
                    "updated_at": round(stat.st_mtime),
                },
            )
        )
    found.sort(key=lambda f: f[:2])
    return [f[2] for f in found[:MAX_SUBAGENTS]]


def snapshot(version):
    now = time.time()
    sessions = []
    claimed: set = set()
    for pid, pane, cwd, args, since in processes():
        sid, name, folder = session_of(pid, cwd, args, since, claimed)
        if not sid:
            continue
        claimed.add(sid)
        sessions.append(
            {
                "pane": pane,
                "session": sid,
                "name": name,
                "cwd": cwd,
                "subagents": subagents(folder, sid, since, now),
            }
        )
    sessions.sort(key=lambda s: -len(s["subagents"]))
    data = {"v": version, "sessions": sessions[:MAX_SESSIONS]}
    line = json.dumps(data, separators=(",", ":"))
    while len(line) > MAX_LINE and any(s["subagents"] for s in data["sessions"]):
        for s in data["sessions"]:
            s["subagents"] = s["subagents"][: max(0, len(s["subagents"]) - 1)]
        line = json.dumps(data, separators=(",", ":"))
    return line


def quiet():
    try:
        import termios
    except ImportError:
        return
    try:
        attrs = termios.tcgetattr(0)
        attrs[3] &= ~termios.ECHO
        termios.tcsetattr(0, termios.TCSANOW, attrs)
    except (termios.error, OSError, ValueError):
        pass


def main():
    version = sys.argv[1] if len(sys.argv) > 1 else ""
    quiet()
    sys.stdout.write(f"\033]0;{TITLE}\007")
    fed = printed = time.time()
    last = None
    while time.time() - fed < LEASE:
        try:
            line = snapshot(version)
        except (
            OSError,
            ValueError,
            KeyError,
            TypeError,
            IndexError,
            AttributeError,
        ) as e:
            line = json.dumps({"v": version, "error": type(e).__name__, "sessions": []})
        now = time.time()
        if line != last or now - printed >= HEARTBEAT:
            sys.stdout.write(f"CLAUDEBAR {line}\n")
            sys.stdout.flush()
            last, printed = line, now
        ready, _, _ = select.select([0], [], [], TICK)
        if ready:
            if not os.read(0, 4096):
                return
            fed = time.time()


if __name__ == "__main__":
    main()
