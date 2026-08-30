pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // every endpoint and token lives in local.json, outside the public repo
    readonly property bool hasPrometheus: local.prometheus && local.prometheus.url ? true : false
    readonly property bool hasProxmox: local.proxmox && local.proxmox.url ? true : false
    readonly property bool hasScrutiny: local.scrutiny && local.scrutiny.url ? true : false
    readonly property bool hasGatus: local.gatus && local.gatus.url ? true : false
    readonly property string gatusUrl: hasGatus ? local.gatus.url : ""
    readonly property string alertsUrl: hasPrometheus ? local.prometheus.url + "/alerts" : ""
    readonly property bool hasPihole: local.pihole && local.pihole.url ? true : false
    readonly property bool hasHass: local.hass && local.hass.url ? true : false
    // the vps is only scraped through the mesh, so prometheus carries it
    readonly property bool hasOvh: hasPrometheus && local.ovh && local.ovh.host ? true : false

    readonly property bool anyConfigured: hasPrometheus || hasProxmox || hasScrutiny || hasGatus || hasPihole || hasHass

    // ── Prometheus ───────────────────────────────────────────────────────
    property int firing: 0
    property var alerts: []

    // ── Proxmox ──────────────────────────────────────────────────────────
    property var nodes: []
    property double lastUpdate: 0

    // set by the panel; most fetches only run while it shows
    property bool panelOpen: false

    signal refreshAll

    // the browser lives on another workspace; xdg-open only adds a tab there,
    // so the browser window is brought to the front once the tab is in
    function open(url) {
        if (url === "")
            return;
        Quickshell.execDetached(["sh", "-c",
            'xdg-open "$1"; sleep 0.4; '
            + 'b=$(xdg-settings get default-web-browser | sed "s/.desktop$//"); '
            + 'hyprctl eval "hl.dispatch(hl.dsp.focus({ window = \\"class:$b\\" }))"',
            "_", url]);
    }

    // ── Scrutiny ─────────────────────────────────────────────────────────
    property var failedDisks: []

    // ── Gatus ────────────────────────────────────────────────────────────
    property int gatusUp: 0
    property int gatusDown: 0
    property real gatusUptime: -1
    property var gatusList: []

    // ── Pi-hole ──────────────────────────────────────────────────────────
    property real blockedPercent: -1
    property int blockedToday: 0
    property int queriesToday: 0
    property int cachedToday: 0
    property int forwardedToday: 0
    property string piholeSid: ""

    // ── Home Assistant ───────────────────────────────────────────────────
    property var sensors: []
    property var sensorGroups: []

    // ── OVH ──────────────────────────────────────────────────────────────
    readonly property real ovhCpu: ovhCpuQ.value
    readonly property real ovhRam: ovhRamQ.value
    readonly property real ovhDisk: ovhDiskQ.value
    readonly property bool ovhReachable: ovhCpuQ.value >= 0

    FileView {
        path: Quickshell.shellDir + "/local.json"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()

        adapter: JsonAdapter {
            id: local
            property JsonObject prometheus: JsonObject { property string url: "" }
            property JsonObject proxmox: JsonObject {
                property string url: ""
                property string token: ""
                property string token_cmd: ""
            }
            property JsonObject gatus: JsonObject { property string url: "" }
            property JsonObject scrutiny: JsonObject { property string url: "" }
            property JsonObject pihole: JsonObject {
                property string url: ""
                property string password: ""
                property string password_cmd: ""
            }
            property JsonObject hass: JsonObject {
                property string url: ""
                property string token: ""
                property string token_cmd: ""
                property var entities: []
            }
            property JsonObject ovh: JsonObject { property string host: "" }
        }
    }

    // a token_cmd is run once and kept in memory only
    component Secret: Scope {
        id: secret

        property string literal: ""
        property string cmd: ""
        readonly property string value: literal !== "" ? literal : fetched

        property string fetched: ""

        Process {
            running: secret.literal === "" && secret.cmd !== ""
            command: ["sh", "-c", secret.cmd]
            stdout: StdioCollector {
                onStreamFinished: secret.fetched = this.text.trim()
            }
        }
    }

    Secret { id: proxmoxSecret; literal: local.proxmox.token;  cmd: local.proxmox.token_cmd }
    Secret { id: piholeSecret;  literal: local.pihole.password; cmd: local.pihole.password_cmd }
    Secret { id: hassSecret;    literal: local.hass.token;     cmd: local.hass.token_cmd }

    component Fetch: Scope {
        id: fetch

        property string url: ""
        property var headers: []
        property string method: ""
        property string body: ""
        property int interval: 60000
        property bool enabled: url !== ""
        // the bar reads a few of these, those keep polling with the panel closed
        property bool always: false

        signal parsed(var data)
        signal failed

        Process {
            id: proc
            command: {
                const c = ["curl", "-sfk", "-m", "6"];
                for (const h of fetch.headers) {
                    c.push("-H");
                    c.push(h);
                }
                if (fetch.method !== "") {
                    c.push("-X");
                    c.push(fetch.method);
                }
                if (fetch.body !== "") {
                    c.push("-d");
                    c.push(fetch.body);
                }
                c.push(fetch.url);
                return c;
            }
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        fetch.parsed(JSON.parse(this.text));
                    } catch (e) {
                        fetch.failed();
                    }
                }
            }
            onExited: code => { if (code !== 0) fetch.failed(); }
        }

        function refresh() {
            if (!enabled)
                return;
            proc.running = false;
            proc.running = true;
        }

        Connections {
            target: root

            function onRefreshAll(): void {
                fetch.refresh();
            }
        }

        Timer {
            interval: fetch.interval
            running: fetch.enabled && (fetch.always || root.panelOpen)
            repeat: true
            triggeredOnStart: true
            onTriggered: fetch.refresh()
        }
    }

    // one prometheus instant query; value is the first sample, series keeps the
    // whole vector when the query groups by host. HOST stands in for the label
    component Prom: Fetch {
        property string query: ""
        property bool needsHost: true
        property real value: -1
        property var series: []

        url: query !== "" && root.hasPrometheus && (!needsHost || root.hasOvh)
            ? local.prometheus.url + "/api/v1/query?query="
              + encodeURIComponent(query.replace(/HOST/g, local.ovh.host))
            : ""
        onFailed: {
            value = -1;
            series = [];
        }
        onParsed: data => {
            const r = data.data ? data.data.result : [];
            value = r.length > 0 ? Number(r[0].value[1]) : -1;
            series = r.map(x => ({
                host: x.metric.host ?? x.metric.instance ?? "?",
                value: Number(x.value[1])
            })).sort((a, b) => a.host.localeCompare(b.host));
        }
    }

    Prom {
        id: ovhCpuQ
        query: '100 - (avg(rate(node_cpu_seconds_total{host="HOST",mode="idle"}[5m])) * 100)'
    }

    Prom {
        id: ovhRamQ
        query: '100 * (1 - node_memory_MemAvailable_bytes{host="HOST"} / node_memory_MemTotal_bytes{host="HOST"})'
    }

    Prom {
        id: ovhDiskQ
        query: '100 * (1 - node_filesystem_avail_bytes{host="HOST",mountpoint="/"} / node_filesystem_size_bytes{host="HOST",mountpoint="/"})'
    }

    Fetch {
        url: root.hasPrometheus ? local.prometheus.url + "/api/v1/alerts" : ""
        always: true
        onParsed: data => {
            const noise = ["InfoInhibitor"];
            const list = data.data.alerts
                .filter(a => a.state === "firing")
                .filter(a => noise.indexOf(a.labels.alertname) < 0);
            // fifty SensorSilent lines say the same thing once, so collapse by name
            const rank = { critical: 3, warning: 2, none: 1 };
            const groups = {};
            for (const a of list) {
                const name = a.labels.alertname ?? "?";
                const sev = a.labels.severity ?? "none";
                const detail = a.labels.instance ?? a.labels.host ?? a.labels.job ?? "";
                if (!groups[name])
                    groups[name] = { name: name, severity: sev, count: 0, detail: detail };
                groups[name].count += 1;
                if ((rank[sev] ?? 0) > (rank[groups[name].severity] ?? 0))
                    groups[name].severity = sev;
            }
            root.alerts = Object.keys(groups)
                .map(k => groups[k])
                .sort((a, b) => (rank[b.severity] ?? 0) - (rank[a.severity] ?? 0) || b.count - a.count);
            root.firing = list.length;
        }
    }

    Fetch {
        url: root.hasProxmox ? local.proxmox.url + "/api2/json/cluster/resources" : ""
        headers: ["Authorization: PVEAPIToken=" + proxmoxSecret.value]
        enabled: root.hasProxmox && proxmoxSecret.value !== ""
        onParsed: data => {
            const res = data.data;
            root.nodes = res.filter(r => r.type === "node")
                .sort((a, b) => a.node.localeCompare(b.node))
                .map(n => ({
                    name: n.node,
                    online: n.status === "online",
                    cpu: Math.round((n.cpu ?? 0) * 100),
                    memPercent: Math.round((n.mem ?? 0) / (n.maxmem ?? 1) * 100),
                    diskPercent: Math.round((n.disk ?? 0) / (n.maxdisk ?? 1) * 100)
                }));
            root.lastUpdate = Date.now();
        }
    }

    Fetch {
        url: root.hasScrutiny ? local.scrutiny.url + "/api/summary" : ""
        interval: 300000
        onParsed: data => {
            const sum = data.data ? (data.data.summary ?? {}) : {};
            const out = [];
            for (const key in sum) {
                const dev = sum[key].device ?? {};
                const sm = sum[key].smart ?? {};
                out.push({
                    name: dev.device_name ?? "?",
                    host: dev.host_id ?? "",
                    ok: (dev.device_status ?? 0) === 0,
                    temp: sm.temp ?? 0,
                    years: Math.round((sm.power_on_hours ?? 0) / 8760)
                });
            }
            out.sort((a, b) => a.host.localeCompare(b.host) || a.name.localeCompare(b.name));
            root.failedDisks = out.filter(d => !d.ok);
        }
    }

    Fetch {
        url: root.hasGatus ? local.gatus.url + "/api/v1/endpoints/statuses" : ""
        interval: 60000
        onParsed: data => {
            let ok = 0;
            let total = 0;
            root.gatusList = data.map(e => {
                const r = e.results ?? [];
                for (const x of r) {
                    total += 1;
                    if (x.success)
                        ok += 1;
                }
                return {
                    name: e.name,
                    group: e.group ?? "",
                    ok: r.length > 0 ? r[r.length - 1].success : false
                };
            });
            root.gatusUp = root.gatusList.filter(e => e.ok).length;
            root.gatusDown = root.gatusList.length - root.gatusUp;
            root.gatusUptime = total > 0 ? ok / total * 100 : -1;
        }
    }

    Fetch {
        id: piholeAuth
        url: root.hasPihole ? local.pihole.url + "/api/auth" : ""
        always: true
        headers: ["Content-Type: application/json"]
        method: "POST"
        body: JSON.stringify({ password: piholeSecret.value })
        enabled: root.hasPihole && piholeSecret.value !== ""
        interval: 3600000
        onParsed: data => {
            root.piholeSid = data.session ? (data.session.sid ?? "") : "";
        }
    }

    Timer {
        id: piholeReauth
        interval: 60000
        onTriggered: {
            root.piholeSid = "";
            piholeAuth.refresh();
        }
    }

    Fetch {
        url: root.piholeSid === "" ? "" : local.pihole.url + "/api/stats/summary"
        headers: ["sid: " + root.piholeSid]
        onFailed: if (!piholeReauth.running) piholeReauth.start()
        onParsed: data => {
            const q = data.queries ?? {};
            root.blockedPercent = q.percent_blocked ?? -1;
            root.blockedToday = q.blocked ?? 0;
            root.queriesToday = q.total ?? 0;
            root.cachedToday = q.cached ?? 0;
            root.forwardedToday = q.forwarded ?? 0;
        }
    }

    Fetch {
        url: root.hasHass ? local.hass.url + "/api/states" : ""
        always: true
        headers: ["Authorization: Bearer " + hassSecret.value]
        enabled: root.hasHass && hassSecret.value !== ""
        interval: 120000
        onParsed: data => {
            // a QML list<string> is not a JS array, copy before using indexOf
            const wanted = [];
            for (const e of (local.hass.entities ?? []))
                wanted.push(String(e));
            // Netatmo names the room in French, the shell speaks English
            const rename = {
                "Intérieur": "INDOOR",
                "Extérieur": "OUTDOOR",
                "Pluviomètre": "RAIN GAUGE"
            };
            // "Mazet (Intérieur) Temperature" splits into a group and a short label
            root.sensors = data.filter(s => wanted.indexOf(s.entity_id) >= 0).map(s => {
                const full = s.attributes.friendly_name ?? s.entity_id;
                const m = full.match(/^.*?\((.+?)\)\s*(.*)$/);
                const raw = m ? m[1] : "";
                return {
                    group: rename[raw] ?? raw.toUpperCase(),
                    name: m && m[2] !== "" ? m[2] : full,
                    state: s.state,
                    unit: s.attributes.unit_of_measurement ?? ""
                };
            });
            const seen = [];
            for (const x of root.sensors)
                if (seen.indexOf(x.group) < 0)
                    seen.push(x.group);
            root.sensorGroups = seen;
        }
    }
}
