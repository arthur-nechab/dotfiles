#!/usr/bin/env python3
"""
  sidebar.py            start the daemon in the background (no-op if one runs or if stopped)
  sidebar.py --start    clear the stop mark, then start
  sidebar.py --stop     stop it, clear every token it wrote, and keep it stopped
  sidebar.py --focus N  focus the agent at place N in the panel
  sidebar.py --selftest
"""
import fcntl
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time

SOURCE = "local.sidebar"
SOCK = os.environ.get("HERDR_SOCKET_PATH") or os.path.expanduser("~/.config/herdr/herdr.sock")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "herdr-sidebar")
ACTIVITY = os.path.join(STATE, "activity.json")
SINCE = os.path.join(STATE, "since.json")
PID = os.path.join(STATE, "pid")
STOPPED = os.path.join(STATE, "stopped")
FRAMES = "⣷⣯⣟⡿⢿⣻⣽⣾"
BRANCH = ""  # nerd font git branch
FRESH_S = 15 * 60
TICK_S = 0.5      # spinner cadence, 2 fps: each write redraws every attached terminal
RELIST_S = 2      # while animating, re-read herdr's lists this often for new titles
GIT_S = 10        # refresh the git line of each space this often, events aside
GIT_MIN_S = 2     # and never more often than this
# Our own sort key keeps each header above its rows and each worktree under its checkout.
# A "plugin:" source lets herdr drop the view when the plugin is disabled or unlinked.
VIEW = {"source": "plugin:" + SOURCE, "label": "groups", "sort": [{"field": {"token": "sort_key"}}]}
STATES = ("working", "done", "blocked", "fresh", "idle", "unknown")
# Groups sort by their most urgent agent, then by their most recent work.
URGENCY = {"blocked": 0, "working": 1, "done": 2}
TOKENS = ("group", "group_alert", "sort_key") + tuple(f"line_{s}" for s in STATES)
SPACE_TOKENS = ("git_clean", "git_dirty", "git_conflict")
# Structural events only (metadata ones echo our writes); status changes need a pane_id each.
EVENTS = (
    "pane.agent_detected", "pane.created", "pane.closed",
    "pane.exited", "pane.moved", "workspace.created", "workspace.closed",
    "workspace.renamed", "workspace.moved", "workspace.reordered", "tab.renamed",
    "tab.moved", "tab.closed", "worktree.created", "worktree.opened", "worktree.removed",
)


def indent(depth):
    # herdr trims leading whitespace off a token; a zero-width space protects the indent.
    return "​" + "  " * depth if depth else ""


def request(method, params):
    """An open socket to herdr, and its first reply to `method`."""
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(4)
    s.connect(SOCK)
    s.sendall((json.dumps({"id": SOURCE, "method": method, "params": params}) + "\n").encode())
    buf = b""
    while b"\n" not in buf:
        chunk = s.recv(65536)
        if not chunk:
            raise OSError("closed before the reply")
        buf += chunk
    return s, json.loads(buf.split(b"\n", 1)[0])


def call(method, params):
    """The result of one request, or None when herdr refused it."""
    s, reply = request(method, params)
    s.close()
    return None if "error" in reply else reply.get("result", {})


def listing(method, key):
    return (call(method, {}) or {}).get(key, [])


def activity_key(agent):
    # The agent's session id outlives a herdr restart; a pane id may not.
    return (agent.get("agent_session") or {}).get("value") or agent["pane_id"]


def display_state(agent, last_work, now):
    status = agent.get("agent_status") or "unknown"
    if status == "idle":
        age = now - last_work
        return "fresh" if age < FRESH_S else "idle"
    return status if status in STATES else "unknown"


def lead(state, step):
    return {"working": FRAMES[step % len(FRAMES)], "done": "✓", "blocked": "?", "fresh": "○", "idle": "·", "unknown": "◌"}.get(state, "")


def resumed_since(saved, last_work, now):
    """Work start times saved by a previous daemon, kept only for agents still working when it stopped."""
    # activity.json is saved every 30 s: an agent seen working within 2 min was still working at the restart.
    return {k: t for k, t in saved.items() if now - last_work.get(k, 0) < 120}


def duration(seconds):
    m = int(seconds // 60)
    return f"{m}m" if m < 60 else f"{m // 60}h{m % 60:02d}"


def tab_titles(agents, tabs):
    """Tabs whose only agent is Claude follow its session title (/rename): tab id -> new label."""
    by_tab = {}
    for a in agents:
        by_tab.setdefault(a.get("tab_id"), []).append(a)
    out = {}
    for t in tabs:
        group = by_tab.get(t["tab_id"], [])
        if len(group) != 1 or group[0].get("agent") != "claude":
            continue
        a = group[0]
        title = (a.get("terminal_title_stripped") or "").strip().lower()
        # Claude leads its own titles with an activity glyph that herdr strips; a title without one
        # is the shell's, seen while a restored session starts, and would rename the tab twice.
        own = (a.get("terminal_title") or "").strip().lower() != title
        if own and title not in ("", "claude", "claude code") and title != t.get("label"):
            out[t["tab_id"]] = title
    return out


def git_tokens(cwd, label="", worktree=False):
    """The git row of a space, or None outside a repository."""
    def git(*args):
        # --no-optional-locks: never take the index lock from under an agent's git.
        return subprocess.run(["git", "--no-optional-locks", "-C", cwd, *args], capture_output=True, text=True, timeout=2)

    try:
        out = git("status", "--porcelain=v2", "--branch", "--show-stash")
        unmerged = None
        if worktree and not out.returncode:
            # A bead branch has no upstream: count what main does not have yet.
            for base in ("main", "master"):
                count = git("rev-list", "--count", f"{base}..HEAD")
                if not count.returncode:
                    unmerged = int(count.stdout)
                    break
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None
    return None if out.returncode else parse_status(out.stdout, label, unmerged)


def parse_status(text, label="", unmerged=None):
    head = oid = ""
    ahead = behind = staged = changed = untracked = conflicts = stash = 0
    for line in text.splitlines():
        if line.startswith("# branch.head "):
            head = line[14:]
        elif line.startswith("# branch.oid "):
            oid = line[13:20]
        elif line.startswith("# branch.ab "):
            a, b = line[12:].split()
            ahead, behind = int(a), -int(b)
        elif line[:2] in ("1 ", "2 "):
            staged += line[2] != "."
            changed += line[3] != "."
        elif line.startswith("# stash "):
            stash = int(line[8:])
        elif line.startswith("u "):
            conflicts += 1
        elif line.startswith("? "):
            untracked += 1
    if unmerged is not None:
        ahead = unmerged  # a worktree counts what main lacks, not what its upstream lacks
    # Three blocks, two spaces apart: the remote, the work tree, the stash.
    blocks = ((("↑", ahead), ("↓", behind)), (("+", staged), ("~", changed), ("?", untracked), ("!", conflicts)), (("≡", stash),))
    parts = [" ".join(f"{s}{n}" for s, n in block if n) for block in blocks]
    branch = oid if head == "(detached)" else head
    # The default branch is the expected case, and a branch named like its space says nothing new.
    named = [] if branch in ("main", "master", label) else [f"{BRANCH} {branch}"]
    text = "  ".join(named + [p for p in parts if p])
    tokens = dict.fromkeys(SPACE_TOKENS)
    if text:
        tokens["git_conflict" if conflicts else "git_dirty" if staged or changed or untracked else "git_clean"] = text
    return tokens


def layout(agents, workspaces, tab_rank, score):
    """Agents in panel order, with each workspace's parent checkout (worktrees only).

    `score` maps a pane to a sort tuple; a family (a checkout and its worktrees)
    sorts by its best member, so the busiest project comes first.
    """
    rank = {w["workspace_id"]: i for i, w in enumerate(workspaces)}
    trees = [(w["workspace_id"], w.get("worktree") or {}) for w in workspaces]
    checkouts = {wt.get("repo_key"): ws for ws, wt in reversed(trees) if wt.get("is_linked_worktree") is False}
    with_agents = {a["workspace_id"] for a in agents}
    # A worktree whose checkout runs no agent has no header to hang under.
    parent = {ws: checkouts[wt["repo_key"]] for ws, wt in trees
              if wt.get("is_linked_worktree") and checkouts.get(wt.get("repo_key")) in with_agents}
    best = {}
    for a in agents:
        family = parent.get(a["workspace_id"], a["workspace_id"])
        best[family] = min(best.get(family, score[a["pane_id"]]), score[a["pane_id"]])

    def key(a):
        ws = a["workspace_id"]
        family = parent.get(ws, ws)
        return (best[family], rank.get(family, 0), family != ws, rank.get(ws, 0), tab_rank.get(a.get("tab_id"), 0))

    return sorted(agents, key=key), parent


def compose(agents, workspaces, parent, states, step, elapsed={}):
    """Tokens per pane. `agents` must be in panel order (see layout)."""
    info = {w["workspace_id"]: w for w in workspaces}
    first, blocked = {}, set()
    for a in agents:
        first.setdefault(a["workspace_id"], a["pane_id"])
        if states[a["pane_id"]] == "blocked":
            blocked.add(a["workspace_id"])
    last_child = {parent[ws]: ws for ws in first if ws in parent}
    out = {}
    for i, a in enumerate(agents):
        pane, ws, state = a["pane_id"], a["workspace_id"], states[a["pane_id"]]
        head, depth = first[ws] == pane, 1 if ws in parent else 0
        w = info.get(ws, {})
        label = w.get("label", ws)
        wt = w.get("worktree") or {}
        if ws in parent:
            corner = "└─ " if last_child[parent[ws]] == ws else "├─ "
            label = f"{indent(1)}{corner}{BRANCH} {label}"
        elif wt.get("is_linked_worktree"):
            label = f"{wt.get('repo_name', '')} {BRANCH} {label}".strip()
        title = a.get("terminal_title_stripped") or a.get("name") or a.get("agent") or pane
        if elapsed.get(pane, 0) >= 60:
            title += " " + duration(elapsed[pane])
        # A head's row sits under its header, a continuation row herdr already indents.
        pad = indent(depth if head else depth + 1)
        tokens = dict.fromkeys(TOKENS)
        tokens["group_alert" if ws in blocked else "group"] = label if head else None
        # One token per row: herdr puts " · " between two tokens.
        tokens[f"line_{state}"] = pad + " ".join(p for p in (lead(state, step), title) if p)
        tokens["sort_key"] = f"{i:05d}"
        out[pane] = tokens
    return out


class Daemon:
    def __init__(self):
        self.wake = threading.Event()
        self.git_wake = threading.Event()
        self.reset = threading.Event()  # set on each (re)connect to herdr
        self.sent = {}       # pane -> tokens last written
        self.ws_sent = {}    # workspace -> git tokens last written
        self.step = 0
        self.lists = None    # (agents, workspaces, parent) from the last re-read
        self.listed_at = 0.0
        self.saved_at = 0.0
        self.panes = frozenset()  # agent panes whose status changes we subscribe to
        try:
            with open(ACTIVITY) as f:
                self.last_work = json.load(f)  # activity key -> wall time last seen working
        except (OSError, ValueError):
            self.last_work = {}
        try:
            with open(SINCE) as f:
                self.since = resumed_since(json.load(f), self.last_work, time.time())  # activity key -> work start
        except (OSError, ValueError):
            self.since = {}

    def subscribe(self):
        lost = True  # first connection, or the server went away since
        while True:
            panes = self.panes
            subs = [{"type": t} for t in EVENTS]
            subs += [{"type": "pane.agent_status_changed", "pane_id": p} for p in sorted(panes)]
            try:
                s, ack = request("events.subscribe", {"subscriptions": subs})
                with s:
                    if "error" in ack:
                        time.sleep(30)  # a refused request would only be refused again
                        continue
                    if lost:
                        self.reset.set()  # a restarted server has forgotten our view and tokens
                        lost = False
                    self.wake.set()
                    s.settimeout(1)
                    while self.panes == panes:  # resubscribe when the agent panes change
                        try:
                            if not s.recv(65536):
                                raise OSError("closed")
                            self.wake.set()
                        except socket.timeout:
                            pass
            except (OSError, ValueError):
                lost = True
                if not os.path.exists(SOCK):
                    os._exit(0)  # herdr server is gone
                time.sleep(2)

    def git_loop(self):
        # Its own thread: a slow `git status` must not stall the spinner.
        while True:
            self.git_wake.wait(GIT_S)
            self.git_wake.clear()
            try:
                self.spaces()
            except Exception:
                pass
            time.sleep(GIT_MIN_S)

    def spaces(self):
        panes = listing("pane.list", "panes")
        for w in listing("workspace.list", "workspaces"):
            ws = w["workspace_id"]
            mine = [p for p in panes if p.get("workspace_id") == ws]
            # The space's directory is the one its active tab is in.
            pane = next((p for p in mine if p.get("tab_id") == w.get("active_tab_id")), mine[0] if mine else None)
            cwd = pane and (pane.get("foreground_cwd") or pane.get("cwd"))
            linked = (w.get("worktree") or {}).get("is_linked_worktree", False)
            tokens = (git_tokens(cwd, w.get("label", ""), linked) if cwd else None) or dict.fromkeys(SPACE_TOKENS)
            if self.ws_sent.get(ws) != tokens:
                if call("workspace.report_metadata", {"workspace_id": ws, "source": SOURCE, "tokens": tokens}) is not None:
                    self.ws_sent[ws] = tokens

    def save_activity(self, now, live):
        self.last_work = {k: t for k, t in self.last_work.items() if k in live or now - t < 7 * 86400}
        for path, data in ((ACTIVITY, self.last_work), (SINCE, self.since)):
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(data, f)
            os.replace(tmp, path)  # a kill mid-write leaves the old file whole
        self.saved_at = now

    def relist(self, now):
        workspaces = listing("workspace.list", "workspaces")
        tabs = listing("tab.list", "tabs")
        tab_rank = {t["tab_id"]: t.get("number", 0) for t in tabs}
        agents = listing("agent.list", "agents")
        for tab_id, label in tab_titles(agents, tabs).items():
            call("tab.rename", {"tab_id": tab_id, "label": label})
        for a in agents:
            key = activity_key(a)
            if a.get("agent_status") == "working" or key not in self.last_work:
                self.last_work[key] = now
        self.since = {k: self.since.get(k, now) for k in (activity_key(a) for a in agents if a.get("agent_status") == "working")}
        score = {}
        for a in agents:
            last = self.last_work[activity_key(a)]
            score[a["pane_id"]] = (URGENCY.get(display_state(a, last, now), 3), -last)
        agents, parent = layout(agents, workspaces, tab_rank, score)
        live = {a["pane_id"] for a in agents}
        for gone in set(self.sent) - live:
            # The pane may outlive its agent as a shell: clear what we wrote on it.
            call("pane.report_metadata", {"pane_id": gone, "source": SOURCE, "tokens": dict.fromkeys(TOKENS)})
            self.sent.pop(gone)
        self.panes = frozenset(live)
        if now - self.saved_at > 30:
            self.save_activity(now, {activity_key(a) for a in agents})
        self.lists = (agents, workspaces, parent)
        self.listed_at = now

    def frame(self, woken):
        now = time.time()
        if self.reset.is_set():
            self.reset.clear()
            self.sent.clear()
            self.ws_sent.clear()
            call("agent.view.set", VIEW)
        if woken:
            self.git_wake.set()  # something moved: the git line may have too
        if woken or self.lists is None or now - self.listed_at >= RELIST_S:
            self.relist(now)
        agents, workspaces, parent = self.lists
        states = {a["pane_id"]: display_state(a, self.last_work.get(activity_key(a), now), now) for a in agents}
        elapsed = {a["pane_id"]: now - self.since[activity_key(a)] for a in agents if activity_key(a) in self.since}
        for pane, tokens in compose(agents, workspaces, parent, states, self.step, elapsed).items():
            # A pane we have not written yet gets every token, so leftovers are cleared.
            old = self.sent.get(pane)
            delta = tokens if old is None else {k: v for k, v in tokens.items() if old.get(k) != v}
            if delta and call("pane.report_metadata", {"pane_id": pane, "source": SOURCE, "tokens": delta}) is not None:
                self.sent[pane] = tokens
        return "working" in states.values()

    def run(self):
        threading.Thread(target=self.subscribe, daemon=True).start()
        threading.Thread(target=self.git_loop, daemon=True).start()
        while True:
            # Clear before drawing, so an event that lands mid-frame cuts the next wait short.
            woken = self.wake.is_set()
            self.wake.clear()
            try:
                animating = self.frame(woken)
            except Exception:
                animating, self.lists = False, None
            self.step += 1
            # Animate while needed, else sleep until an event or the next aging check.
            self.wake.wait(TICK_S if animating else GIT_S)


def our_pid():
    """The daemon's pid, only if that process is still this script."""
    try:
        with open(PID) as f:
            pid = int(f.read())
        # ps works on Linux and macOS; /proc exists only on Linux.
        cmd = subprocess.run(["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True).stdout
        return pid if "sidebar.py" in cmd else None
    except (OSError, ValueError):
        return None


def stop():
    os.makedirs(STATE, exist_ok=True)
    open(STOPPED, "w").close()  # the watchdog hook must not bring it back
    pid = our_pid()
    if pid:
        os.kill(pid, signal.SIGTERM)
        for _ in range(10):  # let it die first, or its last frame lands after the clear
            if not our_pid():
                break
            time.sleep(0.1)
    call("agent.view.clear", {"source": VIEW["source"]})
    for w in listing("workspace.list", "workspaces"):
        call("workspace.report_metadata", {"workspace_id": w["workspace_id"], "source": SOURCE, "tokens": dict.fromkeys(SPACE_TOKENS)})
    for p in listing("pane.list", "panes"):
        if (p.get("tokens") or {}).get("sort_key"):
            call("pane.report_metadata", {"pane_id": p["pane_id"], "source": SOURCE, "tokens": dict.fromkeys(TOKENS)})


def focus(n):
    panes = [p for p in listing("pane.list", "panes") if p.get("agent") and (p.get("tokens") or {}).get("sort_key")]
    panes.sort(key=lambda p: p["tokens"]["sort_key"])
    if 0 < n <= len(panes):
        call("agent.focus", {"target": panes[n - 1]["pane_id"]})


def start(force=False):
    os.makedirs(STATE, exist_ok=True)
    if force and os.path.exists(STOPPED):
        os.remove(STOPPED)
    if os.path.exists(STOPPED) or os.fork():
        return  # stopped on purpose, or the parent: the herdr hook returns at once
    os.setsid()
    lock = open(os.path.join(STATE, "lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        os._exit(0)  # already running
    with open(PID, "w") as f:
        f.write(str(os.getpid()))
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    Daemon().run()


def selftest():
    def ag(pane, ws, status, title, agent="claude"):
        return {"pane_id": pane, "workspace_id": ws, "tab_id": pane, "agent": agent, "agent_status": status, "terminal_title_stripped": title}

    def wt(ws, label, linked):
        return {"workspace_id": ws, "label": label, "worktree": {"repo_key": "r", "repo_name": "core", "is_linked_worktree": linked}}

    workspaces = [wt("a", "homelab", False), {"workspace_id": "b", "label": "claude"}, wt("c", "feat", True)]
    agents = [ag("b:1", "b", "done", "z", "codex"), ag("c:1", "c", "idle", "q"), ag("a:1", "a", "working", "x"), ag("a:2", "a", "idle", "y")]
    flat = {a["pane_id"]: (3, 0) for a in agents}
    ordered, parent = layout(agents, workspaces, {}, flat)
    assert [a["pane_id"] for a in ordered] == ["a:1", "a:2", "c:1", "b:1"] and parent == {"c": "a"}
    # The worktree's urgency lifts its whole family; a done project then beats idle ones.
    urgent = dict(flat, **{"b:1": (2, 0), "c:1": (0, 0)})
    assert [a["pane_id"] for a in layout(agents, workspaces, {}, urgent)[0]] == ["a:1", "a:2", "c:1", "b:1"]
    assert [a["pane_id"] for a in layout(agents, workspaces, {}, dict(flat, **{"b:1": (2, 0)}))[0]][0] == "b:1"
    agents = ordered
    agents[2] = dict(agents[2], agent_status="blocked")
    states = {a["pane_id"]: display_state(a, 0, 1) for a in agents}
    out = compose(agents, workspaces, parent, states, 0)
    assert out["a:1"]["group"] == "homelab" and out["a:1"]["line_working"] == "⣷ x"
    assert out["a:2"]["group"] is None and out["a:2"]["line_fresh"] == indent(1) + "○ y"
    assert out["c:1"]["group_alert"] == indent(1) + "└─ " + BRANCH + " feat" and out["c:1"]["group"] is None
    assert out["c:1"]["line_blocked"] == indent(1) + "? q"
    assert out["b:1"]["group"] == "claude" and out["b:1"]["line_done"] == "✓ z" and out["b:1"]["sort_key"] == "00003"
    timed = compose(agents, workspaces, parent, states, 0, {"a:1": 59, "a:2": 3725})
    assert timed["a:1"]["line_working"] == "⣷ x" and timed["a:2"]["line_fresh"] == indent(1) + "○ y 1h02"
    assert resumed_since({"a": 100, "b": 100}, {"a": 950, "b": 500}, 1000) == {"a": 100}
    tabs = [{"tab_id": "t1", "label": "1"}, {"tab_id": "t2", "label": "old"}, {"tab_id": "t3", "label": "same"}, {"tab_id": "t4", "label": "x"}]
    def ag_t(tab, title, glyph="✳ ", agent="claude"):
        return {"tab_id": tab, "agent": agent, "terminal_title": glyph + title, "terminal_title_stripped": title}
    titled = [ag_t("t1", "Fix Login"), ag_t("t2", "Claude Code"), ag_t("t3", "same"), ag_t("t4", "a"), ag_t("t4", "b", agent="codex"),
              ag_t("t5", "~/src/app", glyph="")]
    tabs.append({"tab_id": "t5", "label": "app"})
    assert tab_titles(titled, tabs) == {"t1": "fix login"}
    status = "# branch.oid abcdef0123\n# branch.head main\n# branch.ab +2 -1\n1 M. N...\n1 .M N...\n? x\n"
    assert parse_status(status + "# stash 2\n")["git_dirty"] == "↑2 ↓1  +1 ~1 ?1  ≡2"
    assert parse_status("# branch.oid abcdef0123\n# branch.head (detached)\n")["git_clean"] == f"{BRANCH} abcdef0"
    assert parse_status("# branch.head main\nu UU N...\n")["git_conflict"]
    assert parse_status("# branch.head main\n") == dict.fromkeys(SPACE_TOKENS)
    assert parse_status("# branch.head proj-a1b\n")["git_clean"] == f"{BRANCH} proj-a1b"
    assert parse_status("# branch.head proj-a1b\n", "proj-a1b") == dict.fromkeys(SPACE_TOKENS)
    assert parse_status("# branch.head proj-a1b\n", "proj-a1b", 3)["git_clean"] == "↑3"
    assert parse_status("# branch.head proj-a1b\n# branch.ab +0 -0\n", "proj-a1b", 2)["git_clean"] == "↑2"
    idle = {"agent_status": "idle"}
    assert [display_state(idle, 0, s) for s in (1, FRESH_S, 30 * 86400)] == ["fresh", "idle", "idle"]
    print("ok")


if __name__ == "__main__":
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        if arg == "--focus":
            sys.exit(focus(int(sys.argv[2])))
        {"--stop": stop, "--start": lambda: start(force=True), "--selftest": selftest}.get(arg, start)()
    except (OSError, ValueError, IndexError) as e:  # herdr down, a bad reply, or --focus without N
        sys.exit(f"sidebar.py: {e}")
