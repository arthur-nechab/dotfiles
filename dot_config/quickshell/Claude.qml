pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ── Limits ───────────────────────────────────────────────────────────
    // [{ key, label, pct, resetsAt }], the session window first
    property var limits: []
    // the endpoint answered nothing usable: no token, or an expired one
    property bool authError: false
    // dollars, -1 when the plan has no extra usage
    property real extraUsed: -1
    property real extraLimit: -1
    readonly property real fiveHour: limits.length > 0 && limits[0].key === "five_hour" ? limits[0].pct : -1

    property string plan: ""

    // set by the homelab panel; the limits are only read when it opens
    property bool panelOpen: false
    onPanelOpenChanged: if (panelOpen) refreshUsage()

    function refreshUsage() {
        usage.running = false;
        usage.running = true;
    }

    function tierColor(pct) {
        return pct > 80 ? Theme.red : (pct > 50 ? Theme.yellow : Theme.green);
    }

    // "2h 13m" or "3d 4h" until an iso timestamp, "" when it has passed
    function until(iso) {
        if (!iso)
            return "";
        const ms = new Date(iso) - Theme.now;
        if (ms <= 0)
            return "";
        const m = Math.floor(ms / 60000);
        if (m < 60)
            return m + "m";
        const h = Math.floor(m / 60);
        if (h < 24)
            return h + "h " + (m % 60) + "m";
        return Math.floor(h / 24) + "d " + (h % 24) + "h";
    }

    Process {
        id: usage
        command: [Quickshell.env("HOME") + "/.config/scripts/claude-usage"]
        // a transient failure keeps the last reading; only a refused token flags
        onExited: (code, status) => {
            root.authError = code === 3;
            // the first call after a start can fail while the network settles
            if (code !== 0 && code !== 3 && root.limits.length === 0)
                retry.restart();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const names = {
                    five_hour: "Session (5h)",
                    seven_day: "Weekly (7d)",
                    seven_day_sonnet: "Weekly Sonnet (7d)",
                    seven_day_opus: "Weekly Opus (7d)"
                };
                const order = ["five_hour", "seven_day"];
                if (this.text.trim() === "")
                    return;
                try {
                    const j = JSON.parse(this.text);
                    const out = [];
                    for (const k of Object.keys(j)) {
                        const w = j[k];
                        // the answer also carries codename windows; only the documented ones show
                        if (!(k in names) || !w || typeof w.utilization !== "number")
                            continue;
                        out.push({ key: k, label: names[k], pct: w.utilization, resetsAt: w.resets_at ?? "" });
                    }
                    out.sort((a, b) => (order.indexOf(a.key) + 1 || 99) - (order.indexOf(b.key) + 1 || 99));
                    root.limits = out;
                    const e = j.extra_usage;
                    root.extraUsed = e && e.is_enabled ? (e.used_credits ?? 0) / 100 : -1;
                    root.extraLimit = e && e.is_enabled ? (e.monthly_limit ?? 0) / 100 : -1;
                } catch (err) {}
            }
        }
    }

    Timer {
        id: retry
        interval: 20000
        onTriggered: root.refreshUsage()
    }

    // the plan sits next to the token; only these two fields leave the file
    Process {
        running: true
        command: ["jq", "-r", ".claudeAiOauth | [.subscriptionType, .rateLimitTier] | @tsv",
                  Quickshell.env("HOME") + "/.claude/.credentials.json"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split("\t");
                const m = (f[1] ?? "").match(/max_(\d+x)/);
                const t = f[0] ?? "";
                root.plan = m ? "Max " + m[1] : (t === "" ? "" : t.charAt(0).toUpperCase() + t.slice(1));
            }
        }
    }
}
