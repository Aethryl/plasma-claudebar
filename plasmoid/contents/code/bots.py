"""Bots, their Needs-you items and the agents they run, read from the orca CLI."""

import json
import os
import re
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor

ORCA = os.path.expanduser("~/.config/orca/linux-orca-cli-shim/orca")
CACHE = os.path.expanduser("~/.cache/claude-bar/orca-calls")
LOCAL_TTL = 8
REMOTE_TTL = 25
CALL_TIMEOUT = 8
ACTIVE = ("working", "blocked", "waiting")
SESSION_ID = re.compile(r"\b[0-9a-f]{8}\b")
PATH = re.compile(r"/home/[\w./-]+")
SUB_STATE = {"working": "working", "blocked": "waiting", "waiting": "waiting"}
SUB_ORDER = ["waiting", "working"]


def orca_bin():
    return ORCA if os.path.exists(ORCA) else "orca"


def call(args, host, ttl, stale=None):
    """Run an orca CLI call returning JSON, reusing a cached answer younger than ttl.

    When the call fails, the cached answer stands in if it is younger than stale (any age when None).
    """
    key = re.sub(r"[^\w]+", "_", f"{host or 'local'}_{'_'.join(args)}")
    path = os.path.join(CACHE, key + ".json")
    age = None
    try:
        age = time.time() - os.path.getmtime(path)
        if age < ttl:
            with open(path) as f:
                return json.load(f)
    except (OSError, ValueError):
        pass
    cmd = [orca_bin(), *args, "--json"]
    if host:
        cmd += ["--environment", host]
    try:
        out = subprocess.run(
            cmd, check=False, capture_output=True, text=True, timeout=CALL_TIMEOUT
        )
        data = json.loads(out.stdout)
    except (OSError, subprocess.SubprocessError, ValueError):
        data = None
    if not data or not data.get("ok"):
        if stale is not None and (age is None or age > stale):
            return None
        try:
            with open(path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return None
    result = data["result"]
    try:
        os.makedirs(CACHE, exist_ok=True)
        tmp = f"{path}.{os.getpid()}.tmp"
        with open(tmp, "w") as f:
            json.dump(result, f)
        os.replace(tmp, path)
    except OSError:
        pass
    return result


def agent_list(host=None, stale=None):
    return call(["agent", "list"], host, REMOTE_TTL if host else LOCAL_TTL, stale)


def worktree_ps(host=None, stale=None):
    return call(
        ["worktree", "ps", "--since", "2d"],
        host,
        REMOTE_TTL if host else LOCAL_TTL,
        stale,
    )


def native_subagents(agent, now):
    """Subagents Orca observes on an agent, in claudebar's row shape; None when it cannot observe them."""
    if agent.get("subagentObservation") != "live":
        return None
    found = []
    for child in agent.get("children") or []:
        status = SUB_STATE.get(child.get("state"))
        if (
            child.get("kind") == "command"
            or status is None
            or child.get("membership", "live") != "live"
        ):
            continue
        seen = (child.get("observedAt") or 0) / 1000
        tool = str((child.get("operation") or {}).get("toolName") or "")
        need = ""
        if status == "waiting":
            need = "question" if tool == "AskUserQuestion" else "permission"
        started = (child.get("firstObservedAt") or 0) / 1000
        found.append(
            (
                SUB_ORDER.index(status),
                -started,
                {
                    "id": child.get("providerId") or child.get("id") or "",
                    "type": child.get("agentType") or child.get("name"),
                    "model": child.get("model"),
                    "description": str(child.get("description") or ""),
                    "status": status,
                    "need": need,
                    "tool": tool if status in ("working", "waiting") else "",
                    "ask": "",
                    "started_at": started or None,
                    "updated_at": seen or now,
                },
            )
        )
    found.sort(key=lambda f: f[:2])
    return [f[2] for f in found]


def live_subagents(agent):
    """Live and actively working children that are subagents; background commands do not count."""
    if agent.get("subagentObservation") != "live":
        return 0, 0
    live = [
        c
        for c in agent.get("children") or []
        if c.get("kind") != "command"
        and c.get("membership", "live") == "live"
        and c.get("state") not in ("done", "failed")
    ]
    return len(live), sum(c.get("state") == "working" for c in live)


def question_text(question):
    if isinstance(question, dict):
        return str(question.get("gist") or question.get("text") or "")
    return str(question or "")


def host_view(host):
    agents = agent_list(host) or {}
    trees = worktree_ps(host) or {}
    paths, branches, owners, subs, homes = {}, {}, {}, {}, {}
    for tree in trees.get("worktrees") or []:
        paths[tree["worktreeId"]] = tree.get("path") or ""
        branches[tree["worktreeId"]] = (tree.get("branch") or "").replace(
            "refs/heads/", ""
        )
        for agent in tree.get("agents") or []:
            sid = agent.get("orcaSessionId")
            if sid:
                subs[sid] = live_subagents(agent)
                if tree.get("bot"):
                    owners[sid] = tree["bot"]
                    if tree.get("botHome"):
                        homes[sid] = tree["bot"]
    return agents.get("agents") or [], paths, branches, owners, subs, homes


def link(agent, bot_names, owners, descriptions, paths):
    sid = agent["orcaSessionId"]
    if owners.get(sid) in bot_names:
        return owners[sid]
    where = paths.get(agent.get("worktreeId"), "")
    for name, text in descriptions.items():
        ids = set(SESSION_ID.findall(text))
        if any(sid.startswith(i) or sid.replace("-", "").startswith(i) for i in ids):
            return name
        if where and any(where == p.rstrip(".,)") for p in PATH.findall(text)):
            return name
    return None


def collect():
    listing = call(["bot", "list"], None, LOCAL_TTL) or {}
    bots = listing.get("bots") or []
    if not bots:
        return None
    hosts = {b.get("server", {}).get("on") for b in bots}
    with ThreadPoolExecutor(max_workers=8) as pool:
        views = {h: pool.submit(host_view, h) for h in hosts}
        items = {
            b["name"]: pool.submit(
                call,
                ["bot", "item", "list", "--bot", b["name"]],
                b.get("server", {}).get("on"),
                REMOTE_TTL if b.get("server") else LOCAL_TTL,
            )
            for b in bots
        }
        views = {h: f.result() for h, f in views.items()}
        items = {n: f.result() or {} for n, f in items.items()}
    out, other = [], []
    for host in hosts:
        agents, paths, branches, owners, subs, home_bots = views[host]
        mine = [b for b in bots if b.get("server", {}).get("on") == host]
        mine_names = {b["name"] for b in mine}
        homes = {
            home_bots[a["orcaSessionId"]]: a
            for a in agents
            if home_bots.get(a["orcaSessionId"]) in mine_names
        }
        home_ids = {a["orcaSessionId"] for a in homes.values()}
        descriptions = {
            n: " ".join(
                str(i.get("description") or "") for i in items[n].get("items") or []
            )
            for n in mine_names
        }
        linked = {n: [] for n in mine_names}
        for agent in agents:
            if agent["orcaSessionId"] in home_ids or agent.get("state") not in ACTIVE:
                continue
            row = {
                "title": agent.get("title") or "",
                "state": agent["state"],
                "session": agent["orcaSessionId"],
                "repo": agent.get("repo") or agent.get("workspace") or "",
                "branch": branches.get(agent.get("worktreeId"), ""),
                "subagents": subs.get(agent["orcaSessionId"], (0, 0))[0],
                "subagents_working": subs.get(agent["orcaSessionId"], (0, 0))[1],
                "worktree": agent.get("worktreeId") or "",
                "host": host,
            }
            owner = link(agent, mine_names, owners, descriptions, paths)
            (linked[owner] if owner else other).append(row)
        for bot in mine:
            name = bot["name"]
            open_items = items[name].get("items") or []
            needs = [
                {
                    "number": i.get("number"),
                    "title": i.get("title") or "",
                    "question": question_text(i.get("question")),
                    "updated": i.get("updatedAt"),
                }
                for i in open_items
                if i.get("status") == "needs_you"
            ]
            progress = [
                i.get("title") or ""
                for i in open_items
                if i.get("status") == "in_progress"
            ]
            home = homes.get(name) or {}
            working = home.get("state") == "working" or any(
                a["state"] == "working" for a in linked[name]
            )
            state = "blocked" if needs else "working" if working else "idle"
            out.append(
                {
                    "name": name,
                    "host": host or "",
                    "state": state,
                    "needs": needs,
                    "progress": progress,
                    "agents": linked[name],
                    "subagents": sum(a["subagents"] for a in linked[name]),
                }
            )
    order = {"blocked": 0, "working": 1, "idle": 2}
    out.sort(key=lambda b: (order[b["state"]], b["name"].lower()))
    every = [a for b in out for a in b["agents"]] + other
    return {
        "updated": time.time(),
        "bots": out,
        "other": other,
        "totals": {
            "working": sum(b["state"] == "working" for b in out),
            "blocked": sum(b["state"] == "blocked" for b in out),
            "idle": sum(b["state"] == "idle" for b in out),
            "agents": len(every),
            "subagents": sum(a["subagents"] for a in every),
            "subagents_working": sum(a["subagents_working"] for a in every),
            "needs": sum(len(b["needs"]) for b in out),
        },
    }
