pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// readings the bar and the panels share: one timer each, one source
Singleton {
    id: root

    readonly property QtObject cpu: QtObject {
        property real usage: 0
        property var prev: null
        property int temp: 0
        property string load: ""
    }

    // coretemp package sensor; hwmon numbering can move, so it is found by name
    Process {
        running: true
        command: ["sh", "-c", "for h in /sys/class/hwmon/hwmon*; do [ \"$(cat $h/name)\" = coretemp ] && echo $h/temp1_input && break; done"]
        stdout: StdioCollector {
            onStreamFinished: cpuTempFile.path = this.text.trim()
        }
    }

    FileView {
        id: cpuTempFile
        printErrors: false
        onLoaded: root.cpu.temp = Math.round(Number(text()) / 1000)
    }

    FileView {
        id: loadFile
        path: "/proc/loadavg"
        onLoaded: root.cpu.load = text().split(" ").slice(0, 3).join("  ")
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: {
            const line = text().split("\n")[0].split(/\s+/).slice(1).map(Number);
            const total = line.reduce((a, b) => a + b, 0);
            const idle = line[3] + line[4];
            if (root.cpu.prev) {
                const dt = total - root.cpu.prev.total;
                const di = idle - root.cpu.prev.idle;
                root.cpu.usage = dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0;
            }
            root.cpu.prev = { total: total, idle: idle };
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            loadFile.reload();
            if (cpuTempFile.path !== "")
                cpuTempFile.reload();
        }
    }

    readonly property QtObject ram: QtObject {
        property real usage: 0
        property real usedGb: 0
        property real totalGb: 0
    }

    readonly property QtObject gpu: QtObject {
        property int usage: 0
        property real vramUsedGb: 0
        property real vramTotalGb: 0
        property int temp: 0
    }

    readonly property QtObject llm: QtObject {
        property bool loaded: false
        property real vramGb: 0
        // [{ name, vramGb }]
        property var models: []
    }

    property bool netbird: false

    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            const kv = {};
            for (const l of text().split("\n")) {
                const m = l.match(/^(\w+):\s+(\d+)/);
                if (m) kv[m[1]] = Number(m[2]);
            }
            root.ram.usage = 1 - kv.MemAvailable / kv.MemTotal;
            root.ram.usedGb = (kv.MemTotal - kv.MemAvailable) / 1048576;
            root.ram.totalGb = kv.MemTotal / 1048576;
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: memFile.reload()
    }

    Process {
        running: true
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
                  "--format=csv,noheader,nounits", "-l", "2"]
        stdout: SplitParser {
            onRead: data => {
                const v = data.split(",").map(x => Number(x.trim()));
                if (v.length === 4 && !v.some(isNaN)) {
                    root.gpu.usage = v[0];
                    root.gpu.vramUsedGb = v[1] / 1024;
                    root.gpu.vramTotalGb = v[2] / 1024;
                    root.gpu.temp = v[3];
                }
            }
        }
    }

    // one shell round for the two slow checks; each answer sits on its own line
    Process {
        id: probes
        command: ["sh", "-c",
            "netbird status 2>/dev/null | grep -q 'Management: Connected' && echo net;"
            + "curl -s -m 3 http://localhost:11434/api/ps | jq -c '[.models[]? | {name, vramGb: (.size_vram / 1073741824)}]' 2>/dev/null | sed 's/^/llm /'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                root.netbird = lines.indexOf("net") >= 0;
                const l = lines.find(x => x.startsWith("llm "));
                try {
                    const models = l ? JSON.parse(l.slice(4)) : [];
                    root.llm.models = models;
                    root.llm.loaded = models.length > 0;
                    root.llm.vramGb = models.reduce((a, m) => a + m.vramGb, 0);
                } catch (e) {
                    root.llm.models = [];
                    root.llm.loaded = false;
                }
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            probes.running = false;
            probes.running = true;
        }
    }
}
