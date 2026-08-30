import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import QtQuick.Controls

PanelWindow {
    id: bar

    // test position; flip to true to move the bar back to the top
    property bool atTop: true

    signal notificationsToggle
    signal dndToggle
    signal audioToggle
    signal bluetoothToggle
    signal networkToggle
    signal clipboardToggle
    signal nightlightChanged(int temp, bool warm)
    signal mediaToggle
    signal homelabToggle

    property int nlTemp: 6500
    // bound to Notifications.dnd in shell.qml, never written here
    property bool dnd: false
    // mirrors the wf-recorder probe for the shell
    readonly property bool recording: rec.active

    screen: Theme.mainScreen
    color: "transparent"
    implicitHeight: 44

    // 5px less than the bar, so windows sit a touch closer
    exclusiveZone: 38

    // a tray menu needs the surface to be able to take input
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors {
        left: true
        right: true
        top: bar.atTop
        bottom: !bar.atTop
    }

    // gaps_out 10 plus the 1px border: windows sit at 11 and end at 2549
    margins {
        left: 11
        right: 11
        top: 5
        bottom: 5
    }

    // ── Building blocks ──────────────────────────────────────────────────

    component Pill: Rectangle {
        default property alias content: row.data
        readonly property alias row: row

        implicitWidth: row.implicitWidth + 20
        implicitHeight: 34
        radius: 10
        color: Qt.alpha(Theme.bg, Theme.opacity)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 4
        }
    }

    component Btn: MouseArea {
        id: btn

        property string label: ""
        property color fg: Theme.fg
        property int size: 15
        property bool hoverBg: true
        // shown under the pointer after a short rest
        property string tip: ""

        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        implicitWidth: txt.implicitWidth + 12
        implicitHeight: 28
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onContainsMouseChanged: containsMouse && tip !== "" ? tipDelay.show(btn) : tipDelay.hide(btn)

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: btn.hoverBg && btn.containsMouse ? Theme.surface : "transparent"
        }

        Label {
            id: txt
            anchors.centerIn: parent
            text: btn.label
            color: btn.fg
            font.pixelSize: btn.size
            font.bold: true
        }
    }

    component Sep: Text {
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: 13
        horizontalAlignment: Text.AlignHCenter
        text: "|"
        color: Qt.alpha(Theme.gray, 0.4)
        font.pixelSize: 15
        font.bold: true
    }

    // ── Tooltip ──────────────────────────────────────────────────────────

    Timer {
        id: tipDelay

        property var owner: null

        interval: 500
        onTriggered: tooltip.visible = true

        function show(item) {
            owner = item;
            restart();
        }

        function hide(item) {
            if (owner !== item)
                return;
            stop();
            owner = null;
            tooltip.visible = false;
        }
    }

    PopupWindow {
        id: tooltip

        anchor.item: tipDelay.owner
        anchor.edges: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.gravity: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.margins.top: 4
        implicitWidth: tipText.implicitWidth + 28
        implicitHeight: tipText.implicitHeight + 18
        color: "transparent"
        visible: false

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.surface

            Label {
                id: tipText
                anchors.centerIn: parent
                text: tipDelay.owner ? tipDelay.owner.tip : ""
                font.family: tipDelay.owner && tipDelay.owner.monoTip ? Theme.monoFont : Theme.uiFont
                font.pixelSize: 13
                lineHeight: 1.35
            }
        }
    }

    function openTrayMenu(handle, item) {
        trayMenu.handle = handle;
        trayMenu.source = item;
        trayMenu.visible = true;
    }

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
    }

    // ── System readings ──────────────────────────────────────────────────

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    QtObject {
        id: cpu
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
        onLoaded: cpu.temp = Math.round(Number(text()) / 1000)
    }

    FileView {
        id: loadFile
        path: "/proc/loadavg"
        onLoaded: cpu.load = text().split(" ").slice(0, 3).join("  ")
    }

    FileView {
        id: statFile
        path: "/proc/stat"
        onLoaded: {
            const line = text().split("\n")[0].split(/\s+/).slice(1).map(Number);
            const total = line.reduce((a, b) => a + b, 0);
            const idle = line[3] + line[4];
            if (cpu.prev) {
                const dt = total - cpu.prev.total;
                const di = idle - cpu.prev.idle;
                cpu.usage = dt > 0 ? Math.max(0, Math.min(1, 1 - di / dt)) : 0;
            }
            cpu.prev = { total: total, idle: idle };
        }
    }

    FileView {
        id: memFile
        path: "/proc/meminfo"
        onLoaded: {
            const kv = {};
            for (const l of text().split("\n")) {
                const m = l.match(/^(\w+):\s+(\d+)/);
                if (m) kv[m[1]] = Number(m[2]);
            }
            ram.usage = 1 - kv.MemAvailable / kv.MemTotal;
            ram.usedGb = (kv.MemTotal - kv.MemAvailable) / 1048576;
            ram.totalGb = kv.MemTotal / 1048576;
        }
    }

    QtObject {
        id: usb
        property var devices: []
    }

    Process {
        id: usbProbe
        command: ["lsblk", "-J", "-o", "PATH,LABEL,SIZE,MOUNTPOINT,HOTPLUG,TYPE,FSTYPE"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const out = [];
                    const walk = d => {
                        // hotplug, not rm: a USB disk often reports rm=false
                        if (d.hotplug && d.type === "part" && d.fstype)
                            out.push(d);
                        for (const c of d.children ?? [])
                            walk(c);
                    };
                    for (const d of JSON.parse(this.text).blockdevices)
                        walk(d);
                    usb.devices = out;
                } catch (e) {}
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            usbProbe.running = false;
            usbProbe.running = true;
        }
    }

    QtObject {
        id: net
        property string iface: ""
        property string ip: ""
        property bool netbird: false
    }

    // one shell round for the three slow checks, instead of three processes
    // on three timers; each answer sits on its own line
    Process {
        id: probes
        command: ["sh", "-c",
            "netbird status 2>/dev/null | grep -q 'Management: Connected' && echo net;"
            + "pgrep -x wf-recorder >/dev/null && echo rec;"
            + "ip -4 -o route get 1.1.1.1 2>/dev/null | sed -n 's/.* src \\([0-9.]*\\).*/ip \\1/p';"
            + "curl -s -m 3 http://localhost:11434/api/ps | jq -c '[.models[]?.size_vram] | {n: length, vram: add}' 2>/dev/null | sed 's/^/llm /'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                net.netbird = lines.indexOf("net") >= 0;
                net.ip = (lines.find(x => x.startsWith("ip ")) ?? "ip ").slice(3);
                rec.active = lines.indexOf("rec") >= 0;
                const l = lines.find(x => x.startsWith("llm "));
                try {
                    const j = l ? JSON.parse(l.slice(4)) : { n: 0, vram: 0 };
                    llm.loaded = j.n > 0;
                    llm.vramGb = (j.vram ?? 0) / 1073741824;
                } catch (e) {
                    llm.loaded = false;
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

    QtObject {
        id: llm
        property bool loaded: false
        property real vramGb: 0
    }


    QtObject {
        id: gpu
        property int usage: 0
        property real vramUsedGb: 0
        property real vramTotalGb: 0
        property int temp: 0
    }

    QtObject {
        id: rec
        property bool active: false
    }

    Process {
        id: cava
        running: media.player !== null && media.player.isPlaying
        command: ["cava", "-p", Quickshell.shellDir + "/assets/cava.conf"]
        stdout: SplitParser {
            onRead: data => {
                const v = data.split(";").filter(x => x.length > 0).map(Number);
                if (v.length === 18) cava.levels = v;
            }
        }
        property var levels: new Array(18).fill(0)

        onRunningChanged: if (!running) levels = new Array(18).fill(0)
    }

    Process {
        running: true
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu",
                  "--format=csv,noheader,nounits", "-l", "2"]
        stdout: SplitParser {
            onRead: data => {
                const v = data.split(",").map(x => Number(x.trim()));
                if (v.length === 4 && !v.some(isNaN)) {
                    gpu.usage = v[0];
                    gpu.vramUsedGb = v[1] / 1024;
                    gpu.vramTotalGb = v[2] / 1024;
                    gpu.temp = v[3];
                }
            }
        }
    }

    FileView {
        id: routeFile
        path: "/proc/net/route"
        onLoaded: {
            for (const l of text().split("\n").slice(1)) {
                const f = l.split(/\s+/);
                if (f[1] === "00000000") {
                    net.iface = f[0];
                    return;
                }
            }
            net.iface = "";
        }
    }

    QtObject {
        id: ram
        property real usage: 0
        property real usedGb: 0
        property real totalGb: 0
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            statFile.reload();
            memFile.reload();
            routeFile.reload();
            loadFile.reload();
            if (cpuTempFile.path !== "")
                cpuTempFile.reload();
        }
    }

    Process {
        id: weather
        command: [Quickshell.env("HOME") + "/.config/scripts/weather"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.trim().split("|");
                weather.value = parts[0] ?? "";
                weather.condition = parts[1] ?? "";
            }
        }
        property string value: ""
        property string condition: ""
    }

    Process {
        id: nightlight
        command: [Quickshell.env("HOME") + "/.config/scripts/nightlight"]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = this.text.trim().split(" ");
                if (f.length !== 2)
                    return;
                nightlight.temp = f[0] + "K";
                nightlight.warm = f[1] === "warm";
            }
        }
        readonly property string icon: warm ? "\u{f0594}" : "\u{f05a8}"
        property string temp: ""
        property bool warm: false

        onTempChanged: {
            bar.nlTemp = parseInt(temp);
            bar.nightlightChanged(bar.nlTemp, warm);
        }

    }

    Timer {
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            weather.running = false;
            weather.running = true;
            refreshTimer.restart();
        }
    }

    // warm from 21:00 to 08:00; acts only when the window opens or closes, so a
    // manual toggle holds until the next boundary
    Timer {
        property var wanted: null

        interval: 60000
        running: nightlight.temp !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const h = new Date().getHours();
            const want = h >= 21 || h < 8;
            if (want === wanted)
                return;
            wanted = want;
            if (nightlight.warm !== want) {
                bar.run("~/.config/scripts/nightlight --toggle");
                refreshTimer.restart();
            }
        }
    }

    // ── Left ─────────────────────────────────────────────────────────────

    Pill {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Btn {
            label: "\u{f048b}"
            fg: Theme.aqua
            size: 15
            onClicked: bar.homelabToggle()
        }

        Sep {}

        MouseArea {

            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: wsRow.implicitWidth
            implicitHeight: wsRow.implicitHeight

            function go(delta) {
                const target = Math.max(1, Math.min(4, Hyprland.focusedWorkspace.id + delta));
                const l = Hyprland.workspaces.values;
                for (let i = 0; i < l.length; i++) if (l[i].id === target) return l[i].activate();
                Hyprland.dispatch("workspace " + target);
            }

            onWheel: wheel => go(wheel.angleDelta.y > 0 ? -1 : 1)

            Row {
                id: wsRow
                spacing: 4

                Repeater {
                    model: 4

                    MouseArea {
                        id: ws

                        required property int index
                        readonly property int wsId: index + 1
                        readonly property var obj: {
                            Hyprland.focusedWorkspace;
                            const l = Hyprland.workspaces.values;
                            for (let i = 0; i < l.length; i++) if (l[i].id === wsId) return l[i];
                            return null;
                        }
                        width: 22
                        height: 28
                        hoverEnabled: true
                        onClicked: obj ? obj.activate() : Hyprland.dispatch("workspace " + wsId)

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: ws.containsMouse ? Theme.surface : "transparent"
                        }

                        Label {
                            anchors.centerIn: parent
                            text: ws.wsId
                            color: ws.obj && ws.obj.focused ? Theme.yellow : (ws.obj && ws.obj.active ? Theme.fg : Theme.gray)
                            font.pixelSize: 14
                            font.bold: true
                        }
                    }
                }
            }
        }

        Sep {}

        MouseArea {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: metrics.implicitWidth
            implicitHeight: metrics.implicitHeight
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: bar.run("ghostty -e btop")
            property bool monoTip: true
            property string tip: "CPU  " + Math.round(cpu.usage * 100) + "%  \u00b7  " + cpu.temp + "\u00b0C  \u00b7  load " + cpu.load
                + "\nGPU  " + gpu.usage + "%  \u00b7  " + gpu.temp + "\u00b0C  \u00b7  VRAM " + gpu.vramUsedGb.toFixed(1) + " / " + gpu.vramTotalGb.toFixed(0) + " GB"
                + (llm.loaded ? "  (" + llm.vramGb.toFixed(1) + " GB model)" : "")
                + "\nRAM  " + ram.usedGb.toFixed(1) + " / " + ram.totalGb.toFixed(0) + " GB  \u00b7  " + Math.round(ram.usage * 100) + "%"
            onContainsMouseChanged: containsMouse ? tipDelay.show(this) : tipDelay.hide(this)

            Row {
                id: metrics

                spacing: 13

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f0ee0}"
                        color: Theme.green
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(cpu.usage * 100) + "%"
                        color: Theme.green
                        font.pixelSize: 14
                        font.bold: true
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: llm.loaded ? "\u{f06a9}" : "\u{f08ae}"
                        color: Theme.purple
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: llm.loaded
                            ? gpu.usage + "% \u00b7 " + llm.vramGb.toFixed(1) + "G"
                            : gpu.usage + "%"
                        color: Theme.purple
                        font.pixelSize: 14
                        font.bold: true
                    }
                }

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{f035b}"
                        color: Theme.blue
                        font.pixelSize: 16
                        font.bold: true
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ram.usedGb.toFixed(1) + "G"
                        color: Theme.blue
                        font.pixelSize: 14
                        font.bold: true
                    }
                }
            }
        }


        Sep {}

        MouseArea {
            id: media

            readonly property var player: {
                const l = Mpris.players.values;
                for (let i = 0; i < l.length; i++) if (l[i].isPlaying) return l[i];
                return l.length > 0 ? l[0] : null;
            }

            anchors.verticalCenter: parent.verticalCenter
            visible: player !== null
            implicitWidth: visible ? mediaRow.implicitWidth + 12 : 0
            implicitHeight: 28
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            property string tip: player
                ? [player.trackTitle, player.trackArtist, player.identity].filter(x => x !== "").join("  \u00b7  ")
                : ""
            onContainsMouseChanged: containsMouse && tip !== "" ? tipDelay.show(this) : tipDelay.hide(this)
            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    bar.mediaToggle();
                    return;
                }
                if (player && player.canTogglePlaying)
                    player.togglePlaying();
            }
            onWheel: wheel => {
                if (!player) return;
                if (wheel.angleDelta.y > 0) {
                    if (player.canGoPrevious) player.previous();
                } else if (player.canGoNext) {
                    player.next();
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: media.containsMouse ? Theme.surface : "transparent"
            }

            Row {
                id: mediaRow
                anchors.centerIn: parent
                spacing: 6

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 18
                    spacing: 2

                    Repeater {
                        model: 18

                        Rectangle {
                            required property int index
                            anchors.bottom: parent.bottom
                            width: 3
                            height: 2 + (cava.levels[index] / 7) * 16
                            radius: 1
                            color: Theme.orange
                        }
                    }
                }
            }
        }

        // recording in progress; a click stops it
        MouseArea {
            anchors.verticalCenter: parent.verticalCenter
            visible: rec.active
            width: 22
            height: 28
            cursorShape: Qt.PointingHandCursor
            onClicked: bar.run("~/.config/scripts/record")

            Rectangle {
                anchors.centerIn: parent
                width: 10
                height: 10
                radius: 5
                color: Theme.red
            }
        }
    }

    // ── Center ───────────────────────────────────────────────────────────

    Pill {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        Btn {
            id: dateBtn
            label: Qt.formatDateTime(Theme.now, "dd MMM  HH:mm")
            fg: Theme.fg
            size: 14
            onClicked: calendar.visible = !calendar.visible
        }
    }

    PopupWindow {
        id: calendar
        anchor.item: dateBtn
        anchor.edges: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.gravity: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.margins.top: 7
        implicitWidth: 260
        implicitHeight: calContent.implicitHeight + 45
        color: "transparent"
        visible: false

        ClickAway {
            target: calendar
            screen: bar.screen
        }

        property string selected: Qt.formatDate(Theme.now, "yyyy-MM-dd")

        onVisibleChanged: if (visible) selected = Qt.formatDate(Theme.now, "yyyy-MM-dd")

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 10
            radius: 10
            color: Theme.bg

            Column {
                id: calContent

                anchors.centerIn: parent
                spacing: 4

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(Theme.now, "MMMM yyyy")
                    color: Theme.yellow
                    font.pixelSize: 14
                    font.bold: true
                }

                DayOfWeekRow {
                    width: 224
                    locale: Qt.locale()
                    delegate: Label {
                        text: model.shortName
                        color: Theme.gray
                        font.pixelSize: 12
                        font.bold: true
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                MonthGrid {

                    width: 224
                    height: 170
                    month: Theme.now.getMonth()
                    year: Theme.now.getFullYear()
                    locale: Qt.locale()
                    onClicked: date => calendar.selected = Qt.formatDate(date, "yyyy-MM-dd")

                    delegate: Item {
                        required property var model

                        readonly property string day: Qt.formatDate(model.date, "yyyy-MM-dd")

                        Rectangle {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            radius: 6
                            visible: parent.day === calendar.selected
                            color: Theme.surface
                        }

                        Label {
                            anchors.centerIn: parent
                            text: model.day
                            color: model.today ? Theme.red : (model.month === Theme.now.getMonth() ? Theme.fg : Theme.gray)
                            opacity: model.month === Theme.now.getMonth() ? 1 : 0.4
                            font.pixelSize: 14
                            font.bold: true
                        }

                    }
                }
            }
        }
    }

    // ── Tray menu ────────────────────────────────────────────────────────

    PopupWindow {
        id: trayMenu

        property var handle: null
        property Item source: null

        anchor.item: source
        anchor.edges: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.gravity: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.margins.top: 7
        implicitWidth: 230
        implicitHeight: menuColumn.implicitHeight + 32
        color: "transparent"
        visible: false
        grabFocus: true


        QsMenuOpener {
            id: menuOpener

            menu: trayMenu.handle
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: 10
            color: Theme.bg

            Column {
                id: menuColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 6
                spacing: 1

                Repeater {
                    model: menuOpener.children

                    MouseArea {
                        required property var modelData

                        width: menuColumn.width
                        height: modelData.isSeparator ? 7 : 26
                        hoverEnabled: !modelData.isSeparator
                        enabled: modelData.enabled && !modelData.isSeparator
                        onClicked: {
                            modelData.triggered();
                            trayMenu.visible = false;
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            visible: !modelData.isSeparator
                            color: parent.containsMouse ? Theme.surface : "transparent"
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            visible: modelData.isSeparator
                            height: 1
                            color: Theme.surface
                        }

                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 16
                            elide: Text.ElideRight
                            visible: !modelData.isSeparator
                            text: modelData.text
                            color: modelData.enabled ? Theme.fg : Theme.gray
                            font.pixelSize: 13
                        }
                    }
                }
            }
        }
    }

    // ── Weather popup ────────────────────────────────────────────────────

    PopupWindow {
        id: weatherPopup

        anchor.item: weatherBtn
        anchor.edges: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.gravity: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.margins.top: 7
        implicitWidth: 240
        implicitHeight: 38 + column.implicitHeight
        color: "transparent"
        visible: false

        ClickAway {
            target: weatherPopup
            screen: bar.screen
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            anchors.topMargin: 10
            radius: 10
            color: Theme.bg

            Column {
                id: column

                anchors.centerIn: parent
                // the gap between indoor and outdoor is the only structure here
                spacing: 16

                Label {
                    visible: Homelab.sensors.length === 0
                    text: Homelab.hasHass ? "No sensors" : "Not configured"
                    color: Theme.gray
                    font.pixelSize: 11
                }

                Repeater {
                    model: Homelab.sensorGroups

                    Column {
                        id: sensorGroup

                        required property var modelData
                        required property int index
                        readonly property string groupName: modelData

                        width: 196
                        spacing: 2

                        Rectangle {
                            width: 196
                            height: 1
                            visible: sensorGroup.index > 0
                            color: Theme.surface
                        }

                        Label {
                            text: sensorGroup.groupName
                            color: Theme.gray
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            font.bold: true
                            topPadding: 4
                            bottomPadding: 1
                        }

                        Repeater {
                            model: Homelab.sensors

                            Item {
                                required property var modelData

                                // each unit gets the range that makes a bar meaningful
                                readonly property real value: Number(modelData.state)
                                readonly property real ratio: {
                                    const u = modelData.unit;
                                    if (u === "%")
                                        return value / 100;
                                    if (u === "\u00b0C")
                                        return (value + 10) / 55;
                                    if (u === "ppm")
                                        return (value - 400) / 1600;
                                    if (u === "mm")
                                        return value / 20;
                                    return -1;
                                }
                                readonly property color tint: {
                                    const u = modelData.unit;
                                    if (u === "ppm")
                                        return value > 1400 ? Theme.red : (value > 900 ? Theme.yellow : Theme.green);
                                    if (u === "\u00b0C")
                                        return value > 28 ? Theme.orange : (value < 5 ? Theme.blue : Theme.yellow);
                                    if (u === "mm")
                                        return Theme.aqua;
                                    return Theme.blue;
                                }

                                visible: modelData.group === sensorGroup.groupName
                                width: 196
                                height: visible ? (ratio >= 0 ? 28 : 19) : 0

                                Label {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    width: parent.width * 0.6
                                    elide: Text.ElideRight
                                    text: modelData.name
                                    color: Theme.fg
                                    font.pixelSize: 12
                                }

                                Label {
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    width: parent.width * 0.38
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                    text: modelData.state + " " + modelData.unit
                                    color: parent.tint
                                    font.pixelSize: 12
                                    font.bold: true
                                }

                                Gauge {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 2
                                    visible: parent.ratio >= 0
                                    height: 5
                                    value: parent.ratio
                                    accent: parent.tint
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Removable volumes ────────────────────────────────────────────────

    PopupWindow {
        id: usbPopup

        anchor.item: usbBtn
        anchor.edges: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.gravity: bar.atTop ? Edges.Bottom : Edges.Top
        anchor.margins.top: 7
        implicitWidth: 300
        implicitHeight: 36 + Math.max(1, usbColumn.implicitHeight)
        color: "transparent"
        visible: false

        ClickAway {
            target: usbPopup
            screen: bar.screen
        }

        // the button hides itself once the last device is gone
        onVisibleChanged: if (visible && usb.devices.length === 0) visible = false

        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: 10
            color: Theme.bg

            Column {
                id: usbColumn

                anchors.centerIn: parent
                width: parent.width - 16
                spacing: 4

                Repeater {
                    model: usb.devices

                    MouseArea {
                        id: dev

                        required property var modelData
                        readonly property bool mounted: (modelData.mountpoint ?? "") !== ""

                        width: usbColumn.width
                        height: 38
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            bar.run("udisksctl " + (mounted ? "unmount" : "mount")
                                    + " -b " + modelData.path
                                    + " || notify-send -u critical 'Volume' '"
                                    + modelData.path + "'");
                            usbProbe.running = false;
                            usbProbe.running = true;
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: parent.containsMouse ? Theme.surface : "transparent"
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: dev.mounted ? "" : ""
                                color: dev.mounted ? Theme.green : Theme.gray
                                font.pixelSize: 16
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 32
                                spacing: 1

                                Label {
                                    width: parent.width
                                    text: (modelData.label ?? "") !== ""
                                        ? modelData.label
                                        : modelData.path
                                    color: Theme.fg
                                    font.pixelSize: 13
                                    font.bold: true
                                    elide: Text.ElideRight
                                }

                                Label {
                                    width: parent.width
                                    text: modelData.size + " \u00b7 " + modelData.fstype
                                        + (dev.mounted
                                           ? " \u00b7 " + modelData.mountpoint
                                           : " \u00b7 not mounted")
                                    color: Theme.gray
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Right ────────────────────────────────────────────────────────────

    Pill {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Btn {
            id: weatherBtn

            // the script already puts the glyph first; the extra spaces are the gap
            label: weather.value.replace(" ", "   ")
            fg: Theme.yellow
            visible: weather.value !== ""
            size: 14
            tip: weather.condition
            onClicked: weatherPopup.visible = !weatherPopup.visible
        }

        Sep {}

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            visible: SystemTray.items.values.length > 0

            Repeater {
                model: SystemTray.items

                MouseArea {
                    id: trayItem

                    required property var modelData
                    width: 29
                    height: 28
                    anchors.verticalCenter: parent.verticalCenter
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (modelData.hasMenu)
                                bar.openTrayMenu(modelData.menu, trayItem);
                        } else if (mouse.button === Qt.LeftButton) {
                            const menuOnly = modelData.onlyMenu || modelData.id === "steam";
                            if (menuOnly && modelData.hasMenu)
                                bar.openTrayMenu(modelData.menu, trayItem);
                            else
                                modelData.activate();
                        } else {
                            modelData.secondaryActivate();
                        }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        // steam hands over a 16px pixmap; implicitSize scales it like a themed icon
                        implicitSize: 18
                        source: modelData.icon
                    }
                }
            }
        }

        Sep {}

        Btn {
            label: "󰅌"
            fg: Theme.yellow
            onClicked: bar.clipboardToggle()
        }

        Btn {
            readonly property var src: Pipewire.defaultAudioSource
            readonly property bool muted: src && src.audio ? src.audio.muted : false

            label: muted ? "󰍭" : "󰍬"
            tip: (src ? (src.description || src.nickname || src.name) : "No input device") + (muted ? "  \u00b7  Muted" : "")
            fg: muted ? Theme.red : Theme.orange
            onClicked: if (src && src.audio) src.audio.muted = !src.audio.muted
        }

        Btn {
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property real vol: sink && sink.audio ? sink.audio.volume : 0
            readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

            label: muted ? "\U000f0581" : (vol > 0.66 ? "\uf028" : (vol > 0.33 ? "\uf027" : "\uf026"))
            fg: muted ? Theme.red : Theme.purple
            tip: (sink ? (sink.description || sink.nickname || sink.name) : "No output device") + "  \u00b7  " + Math.round(vol * 100) + "%"
            onClicked: mouse => mouse.button === Qt.RightButton
                ? bar.run("pwvucontrol")
                : bar.audioToggle()
            onWheel: wheel => {
                if (!sink || !sink.audio) return;
                const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + step));
            }
        }

        Btn {
            readonly property var adapter: Bluetooth.defaultAdapter
            readonly property var device: {
                const l = Bluetooth.devices.values;
                for (let i = 0; i < l.length; i++) if (l[i].connected) return l[i];
                return null;
            }

            label: !adapter || !adapter.enabled ? "󰂲" : (device ? "󰂱" : "󰂯")
            fg: Theme.aqua
            tip: !adapter || !adapter.enabled ? "Bluetooth off"
                : (device ? device.name + (device.batteryAvailable ? "  \u00b7  " + Math.round(device.battery * 100) + "%" : "") : "Not connected")
            onClicked: mouse => mouse.button === Qt.RightButton
                ? bar.run("ghostty -e bluetuith")
                : bar.bluetoothToggle()
        }

        Btn {
            label: {
                if (net.netbird)
                    return "\u{f0582}";
                if (net.iface === "")
                    return "󰖪";
                return net.iface.startsWith("wl") ? "󰤨" : "󰈀";
            }
            fg: net.netbird ? Theme.aqua : Theme.blue
            tip: net.iface === "" ? "No network" : net.iface + "  \u00b7  " + net.ip + (net.netbird ? "  \u00b7  NetBird" : "")
            onClicked: bar.networkToggle()
        }

        Btn {
            label: nightlight.icon
            fg: nightlight.warm ? Theme.purple : Theme.yellow
            tip: "Night Light  \u00b7  " + nightlight.temp
            onClicked: {
                bar.run("~/.config/scripts/nightlight --toggle");
                refreshTimer.restart();
            }
            onWheel: wheel => {
                const up = wheel.angleDelta.y > 0;
                bar.nlTemp = Math.max(1000, Math.min(6500, bar.nlTemp + (up ? 200 : -200)));
                bar.nightlightChanged(bar.nlTemp, bar.nlTemp <= 4500);
                bar.run("~/.config/scripts/nightlight " + (up ? "--up" : "--down"));
                refreshTimer.restart();
            }
        }

        Btn {
            id: usbBtn

            label: ""
            fg: usbPopup.visible ? Theme.yellow : Theme.green
            visible: usb.devices.length > 0
            onClicked: usbPopup.visible = !usbPopup.visible
        }

        Sep {}

        Btn {
            label: bar.dnd ? "󰂛" : "󱅫"
            fg: bar.dnd ? Theme.gray : Theme.red
            onClicked: mouse => mouse.button === Qt.RightButton
                ? bar.dndToggle()
                : bar.notificationsToggle()
        }
    }

    IpcHandler {
        target: "weather"

        function toggle(): void {
            weatherPopup.visible = !weatherPopup.visible;
        }
    }

    IpcHandler {
        target: "nightlight"

        function toggle(): void {
            bar.run("~/.config/scripts/nightlight --toggle");
            refreshTimer.restart();
        }

        function up(): void {
            bar.run("~/.config/scripts/nightlight --up");
            refreshTimer.restart();
        }

        function down(): void {
            bar.run("~/.config/scripts/nightlight --down");
            refreshTimer.restart();
        }
    }

    // hyprsunset needs a moment before its state reflects the change
    Timer {
        id: refreshTimer
        interval: 250
        onTriggered: {
            nightlight.running = false;
            nightlight.running = true;
        }
    }
}
