import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

PanelWindow {
    id: cc

    // "audio" | "bluetooth" | "network"
    property string tab: "audio"

    // ── Keyboard ─────────────────────────────────────────────────────────
    readonly property var tabs: ["audio", "bluetooth", "network"]
    property int sel: 0
    // the cursor frame only shows once the arrows have been used
    property bool navigating: false

    // the rows arrows walk through, one flat list per tab
    readonly property var rows: {
        if (tab === "audio")
            return sinks.concat(sources);
        if (tab === "bluetooth")
            return devices;
        return networks.slice(0, 10);
    }

    function moveSel(d) {
        if (rows.length === 0)
            return;
        navigating = true;
        sel = Math.max(0, Math.min(rows.length - 1, sel + d));
    }

    function cycleTab(d) {
        tab = tabs[(tabs.indexOf(tab) + d + tabs.length) % tabs.length];
        sel = 0;
    }

    function activateRow() {
        const r = rows[sel];
        if (!r)
            return;
        if (tab === "audio") {
            if (sel < sinks.length)
                Pipewire.preferredDefaultAudioSink = r;
            else
                Pipewire.preferredDefaultAudioSource = r;
        } else if (tab === "bluetooth") {
            if (r.connected)
                r.disconnect();
            else
                r.paired ? r.connect() : r.pair();
        } else {
            if (known[r.ssid] === true)
                wifiRun(["iwctl", "station", wifiDevice, "connect", r.ssid]);
            else
                asking = r.ssid;
        }
    }

    function nudgeVolume(d) {
        const s = Pipewire.defaultAudioSink;
        if (s && s.audio)
            s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + d));
    }

    function toggleMute() {
        // the cursor on a microphone row mutes the mic, anywhere else the output
        const onSource = tab === "audio" && navigating && sel >= sinks.length;
        const s = onSource ? Pipewire.defaultAudioSource : Pipewire.defaultAudioSink;
        if (s && s.audio)
            s.audio.muted = !s.audio.muted;
    }

    // ── Wi-Fi, through iwd ───────────────────────────────────────────────
    property var networks: []
    property var known: ({})
    property string wifiDevice: ""
    property string wifiState: ""
    // network waiting for its passphrase, "" when none
    property string asking: ""
    // the hidden network form is open
    property bool hiddenOpen: false

    function strip(s) {
        return s.replace(/\x1b\[[0-9;]*m/g, "");
    }

    Process {
        id: wifiStation
        // COLUMNS keeps iwctl from eliding a long ssid into its 80 column default
        command: ["sh", "-c", "COLUMNS=200 iwctl station list"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of cc.strip(this.text).split("\n")) {
                    const m = line.match(/^\s+(\S+)\s+(connected|disconnected|connecting|scanning)/);
                    if (m) {
                        cc.wifiDevice = m[1];
                        cc.wifiState = m[2];
                        break;
                    }
                }
            }
        }
    }

    Process {
        id: wifiKnown
        command: ["sh", "-c", "COLUMNS=200 iwctl known-networks list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const k = {};
                for (const line of cc.strip(this.text).split("\n")) {
                    const m = line.match(/^\s{2}(\S.*?)\s{2,}(psk|open|wep|8021x)\s/);
                    if (m)
                        k[m[1].trim()] = true;
                }
                cc.known = k;
            }
        }
    }

    Process {
        id: wifiScan
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of cc.strip(this.text).split("\n")) {
                    // "  >   SSID with spaces      psk      -4100"
                    const m = line.match(/^\s{2}(>)?\s+(\S.*?)\s{2,}(psk|open|wep|8021x)\s+(-?\d+)\s*$/);
                    if (m)
                        out.push({
                            ssid: m[2].trim(),
                            security: m[3],
                            // iwd reports centidBm
                            rssi: parseInt(m[4]) / 100,
                            current: m[1] === ">"
                        });
                }
                cc.networks = out;
            }
        }
    }

    Process { id: wifiAction }

    function wifiRefresh() {
        wifiStation.running = false;
        wifiStation.running = true;
        wifiPower.running = false;
        wifiPower.running = true;
        wifiKnown.running = false;
        wifiKnown.running = true;
        wifiRescan();
    }

    // the device name only arrives with the first station probe, so the very
    // first scan has to wait for it rather than fire alongside it
    function wifiRescan() {
        if (wifiDevice === "")
            return;
        wifiScan.running = false;
        wifiScan.command = ["sh", "-c",
            "COLUMNS=200 iwctl station " + wifiDevice + " get-networks rssi-dbms"];
        wifiScan.running = true;
    }

    onWifiDeviceChanged: wifiRescan()

    property var hiddenName: null
    property var hiddenPass: null

    // enter on the name moves to the passphrase; enter there connects
    function hiddenSend(which) {
        if (which === "name" || hiddenPass.text === "") {
            if (hiddenName.text !== "")
                hiddenPass.forceActiveFocus();
            return;
        }
        if (hiddenName.text === "")
            return;
        wifiRun(["iwctl", "--passphrase", hiddenPass.text, "station", wifiDevice,
                 "connect-hidden", hiddenName.text]);
        hiddenName.text = "";
        hiddenPass.text = "";
        hiddenOpen = false;
    }

    // argv, never sh -c: an ssid is attacker chosen text
    function wifiRun(argv) {
        wifiAction.command = argv;
        wifiAction.running = false;
        wifiAction.running = true;
        wifiSettle.restart();
    }

    Timer {
        id: wifiSettle
        interval: 2500
        onTriggered: cc.wifiRefresh()
    }

    Timer {
        interval: 15000
        repeat: true
        running: cc.visible && cc.tab === "network"
        triggeredOnStart: true
        onTriggered: cc.wifiRefresh()
    }

    // powered state comes from the device list, which still names a radio that is off
    Process {
        id: wifiPower
        command: ["sh", "-c", "COLUMNS=200 iwctl device list"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of cc.strip(this.text).split("\n")) {
                    const m = line.match(/^\s+(\S+)\s+[0-9a-f:]{17}\s+(on|off)\s/i);
                    if (m) {
                        if (cc.wifiDevice === "")
                            cc.wifiDevice = m[1];
                        cc.wifiPowered = m[2] === "on";
                        break;
                    }
                }
            }
        }
    }

    property bool wifiPowered: true

    // ── Link ─────────────────────────────────────────────────────────────
    // the interface that carries the default route, wifi or not
    property string linkIface: ""
    property string linkIp: ""
    property string linkGateway: ""
    property real ping: -1
    property int loss: -1
    property real rxRate: 0
    property real txRate: 0
    property real rxTotal: 0
    property real txTotal: 0
    property var prevDev: null

    readonly property var currentNet: networks.find(x => x.current) ?? null
    readonly property string currentSsid: currentNet ? currentNet.ssid : ""
    // saved network waiting for its forget confirmation, "" when none
    property string forgettingSsid: ""

    function fmtBytes(b, unit) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1000 && i < u.length - 1) {
            b /= 1000;
            i++;
        }
        return (i === 0 ? b.toFixed(0) : b.toFixed(b < 10 ? 2 : 1)) + " " + u[i] + unit;
    }

    // one shell round: the route on its first line, then ping's two summary lines
    Process {
        id: linkProbe
        command: ["sh", "-c",
            "ip -4 -o route show default | head -1; echo;"
            + "ping -q -c 3 -i 0.2 -W 1 1.1.1.1 2>/dev/null | tail -2"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text;
                const r = t.match(/via (\S+) dev (\S+).*? src (\S+)/);
                cc.linkGateway = r ? r[1] : "";
                cc.linkIface = r ? r[2] : "";
                cc.linkIp = r ? r[3] : "";
                const l = t.match(/(\d+)% packet loss/);
                cc.loss = l ? parseInt(l[1]) : 100;
                const a = t.match(/rtt [^=]+= [\d.]+\/([\d.]+)/);
                cc.ping = a ? parseFloat(a[1]) : -1;
            }
        }
    }

    Timer {
        interval: 5000
        repeat: true
        running: cc.visible && cc.tab === "network"
        triggeredOnStart: true
        onTriggered: {
            linkProbe.running = false;
            linkProbe.running = true;
            wifiPower.running = false;
            wifiPower.running = true;
        }
    }

    FileView {
        id: devFile
        path: "/proc/net/dev"
        onLoaded: {
            const line = text().split("\n").find(x => x.trim().startsWith(cc.linkIface + ":"));
            if (!line || cc.linkIface === "")
                return;
            const f = line.split(":")[1].trim().split(/\s+/).map(Number);
            const now = Date.now();
            cc.rxTotal = f[0];
            cc.txTotal = f[8];
            if (cc.prevDev) {
                const dt = (now - cc.prevDev.t) / 1000;
                if (dt > 0) {
                    cc.rxRate = (f[0] - cc.prevDev.rx) / dt;
                    cc.txRate = (f[8] - cc.prevDev.tx) / dt;
                }
            }
            cc.prevDev = { t: now, rx: f[0], tx: f[8] };
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: cc.visible && cc.tab === "network"
        triggeredOnStart: true
        onTriggered: devFile.reload()
        // a fresh first sample on the next opening, not an average over the gap
        onRunningChanged: if (!running) cc.prevDev = null
    }

    readonly property var adapter: Bluetooth.defaultAdapter
    // device waiting for its forget confirmation, "" when none
    property string forgetting: ""

    // nf-md glyph for the bluez icon name, the plain bluetooth mark otherwise
    function btGlyph(icon, connected) {
        if (/headset|headphone/.test(icon))
            return "\u{f02cb}";
        if (/mouse/.test(icon))
            return "\u{f037d}";
        if (/keyboard/.test(icon))
            return "\u{f030c}";
        if (/gaming|joystick/.test(icon))
            return "\u{f0297}";
        if (/phone/.test(icon))
            return "\u{f011c}";
        if (/computer|laptop/.test(icon))
            return "\u{f0322}";
        if (/audio|speaker/.test(icon))
            return "\u{f04c3}";
        return connected ? "\u{f00b1}" : "\u{f00af}";
    }
    readonly property var devices: {
        const l = Bluetooth.devices.values;
        return l.slice().sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name));
    }
    readonly property var playback: Pipewire.nodes.values.filter(n => n.isStream && n.isSink)
    readonly property var capture: Pipewire.nodes.values.filter(n => n.isStream && !n.isSink)
    // media.class is only set on tracked nodes; the tracker below covers them all
    // the motherboard codec is wired to nothing here, only HDMI and the headset are
    function usable(n, cls) {
        return (n.properties["media.class"] ?? "") === cls && (n.name ?? "").indexOf("0000_00_1f.3") < 0;
    }

    // pipewire descriptions name the chip, not the plug
    function deviceName(n) {
        const d = n.description || n.nickname || n.name;
        if (/HDMI/.test(d))
            return "HDMI";
        return d.replace(/ (Analog|Digital) (Stereo|Mono)$/, "");
    }

    function streamName(n) {
        return n.properties["application.process.binary"] || n.properties["application.name"]
            || n.properties["media.name"] || n.description || n.name;
    }

    readonly property var sinks: Pipewire.nodes.values.filter(n => usable(n, "Audio/Sink"))
    readonly property var sources: Pipewire.nodes.values.filter(n => usable(n, "Audio/Source"))
    readonly property var streams: playback.concat(capture)

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: 440
    implicitHeight: Math.min(900, body.implicitHeight + 40)
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-control-center"
    // on demand, not exclusive: an exclusive layer makes hyprland swallow
    // every click outside it, so the click-away sheet would never see one
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    anchors {
        top: true
        right: true
    }

    margins {
        top: 57
        right: 20
    }

    function toggle(which) {
        const target = which ?? tab;
        if (visible && tab === target) {
            visible = false;
        } else {
            tab = target;
            sel = 0;
            navigating = false;
            asking = "";
            forgetting = "";
            forgettingSsid = "";
            hiddenOpen = false;
            visible = true;
            keys.forceActiveFocus();
        }
    }

    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    ClickAway {
        target: cc
        screen: cc.screen
    }

    IpcHandler {
        target: "controlcenter"

        function toggle(): void {
            cc.toggle();
        }

        function audio(): void {
            cc.toggle("audio");
        }

        function bluetooth(): void {
            cc.toggle("bluetooth");
        }

        function network(): void {
            cc.toggle("network");
        }
    }

    component Slider: MouseArea {
        id: slider

        property real value: 0
        property color accent: Theme.purple

        signal moved(real v)

        function set(x) {
            moved(Math.max(0, Math.min(1, x / width)));
        }

        height: 20
        onPressed: mouse => set(mouse.x)
        onPositionChanged: mouse => { if (pressed) set(mouse.x); }
        onWheel: wheel => moved(Math.max(0, Math.min(1, value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))

        Gauge {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            value: slider.value
            accent: slider.accent
        }
    }

    component Device: MouseArea {
        property var node: null
        property bool current: false
        property bool selected: false

        width: parent.width
        height: 26
        hoverEnabled: true

        Rectangle {
            anchors.fill: parent
            radius: 6
            color: parent.containsMouse || parent.selected ? Theme.surface : "transparent"
            border.width: parent.selected ? 1 : 0
            border.color: Theme.gray
        }

        Label {
            anchors.left: parent.left
            anchors.leftMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 12
            elide: Text.ElideRight
            text: (parent.current ? "\u25cf  " : "\u25cb  ")
                + (parent.node ? cc.deviceName(parent.node) : "")
            color: parent.current ? Theme.fg : Theme.gray
            font.pixelSize: 12
            font.bold: parent.current
        }
    }

    // one application stream: name with icon, mute button, level
    component Stream: Column {
        id: stream

        property var node: null
        property color accent: Theme.blue
        property string onGlyph: ""
        property string offGlyph: ""

        width: parent.width
        spacing: 4

        Row {
            width: parent.width
            spacing: 6

            IconImage {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                source: Quickshell.iconPath(
                    stream.node.properties["application.icon-name"]
                    || stream.node.properties["application.process.binary"] || "",
                    "audio-x-generic")
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: cc.streamName(stream.node)
                color: Theme.fg
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
                width: parent.width - 22
            }
        }

        Row {
            width: parent.width
            spacing: 10

            MouseArea {
                anchors.verticalCenter: parent.verticalCenter
                width: 20
                height: 20
                onClicked: stream.node.audio.muted = !stream.node.audio.muted

                Label {
                    anchors.centerIn: parent
                    text: stream.node.audio.muted ? stream.offGlyph : stream.onGlyph
                    color: stream.node.audio.muted ? Theme.red : stream.accent
                    font.pixelSize: 13
                    font.bold: true
                }
            }

            Slider {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 84
                accent: stream.accent
                value: stream.node.audio.volume
                onMoved: v => stream.node.audio.volume = v
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                text: Math.round(stream.node.audio.volume * 100) + "%"
                color: Theme.gray
                font.pixelSize: 12
                font.bold: true
            }
        }
    }

    component Section: Label {
        color: Theme.gray
        font.pixelSize: 11
        font.bold: true
    }

    component Pill: MouseArea {
        property string label: ""
        property color accent: Theme.yellow

        width: 80
        height: 26
        cursorShape: Qt.PointingHandCursor

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: Theme.surface
        }

        Label {
            anchors.centerIn: parent
            text: parent.label
            color: parent.accent
            font.pixelSize: 11
            font.bold: true
        }
    }

    // one cell of the link grid: name on the left, reading on the right
    component Stat: Item {
        property string label: ""
        property string value: ""

        height: 18

        Label {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: Theme.gray
            font.pixelSize: 12
        }

        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: parent.value
            color: Theme.fg
            font.family: Theme.monoFont
            font.pixelSize: 12
        }
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: cc.visible

        Keys.onEscapePressed: cc.visible = false
        Keys.onLeftPressed: cc.cycleTab(-1)
        Keys.onRightPressed: cc.cycleTab(1)
        Keys.onUpPressed: cc.moveSel(-1)
        Keys.onDownPressed: cc.moveSel(1)
        Keys.onReturnPressed: cc.activateRow()
        Keys.onEnterPressed: cc.activateRow()
        Keys.onSpacePressed: cc.toggleMute()
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)
                cc.nudgeVolume(0.05);
            else if (event.key === Qt.Key_Minus)
                cc.nudgeVolume(-0.05);
            else
                return;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.96)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Column {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 12

            Row {
                spacing: 8

                Repeater {
                    model: [
                        { id: "audio", label: "Audio" },
                        { id: "bluetooth", label: "Bluetooth" },
                        { id: "network", label: "Wi-Fi" }
                    ]

                    MouseArea {
                        required property var modelData

                        width: 130
                        height: 28
                        onClicked: cc.tab = modelData.id

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: cc.tab === modelData.id ? Theme.surface : "transparent"
                        }

                        Label {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: cc.tab === modelData.id ? Theme.fg : Theme.gray
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }
            }

            // ── Audio ────────────────────────────────────────────────────

            Column {
                width: parent.width
                spacing: 12
                visible: cc.tab === "audio"

                Section { text: "OUTPUT" }

                Row {
                    width: parent.width
                    spacing: 10

                    MouseArea {
                        readonly property var sink: Pipewire.defaultAudioSink
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        onClicked: if (sink && sink.audio) sink.audio.muted = !sink.audio.muted

                        Label {
                            anchors.centerIn: parent
                            text: parent.sink && parent.sink.audio && parent.sink.audio.muted ? "" : ""
                            color: parent.sink && parent.sink.audio && parent.sink.audio.muted ? Theme.red : Theme.purple
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }

                    Slider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 90
                        value: Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : 0
                        onMoved: v => { if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) Pipewire.defaultAudioSink.audio.volume = v; }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        text: Math.round((Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio ? Pipewire.defaultAudioSink.audio.volume : 0) * 100) + "%"
                        color: Theme.fg
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Repeater {
                    model: cc.sinks

                    Device {
                        required property var modelData
                        required property int index
                        node: modelData
                        current: Pipewire.defaultAudioSink === modelData
                        selected: cc.navigating && cc.tab === "audio" && cc.sel === index
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                Section { text: "MICROPHONE" }

                Row {
                    width: parent.width
                    spacing: 10

                    MouseArea {
                        readonly property var src: Pipewire.defaultAudioSource
                        anchors.verticalCenter: parent.verticalCenter
                        width: 26
                        height: 26
                        onClicked: if (src && src.audio) src.audio.muted = !src.audio.muted

                        Label {
                            anchors.centerIn: parent
                            text: parent.src && parent.src.audio && parent.src.audio.muted ? "\u{f036d}" : "\u{f036c}"
                            color: parent.src && parent.src.audio && parent.src.audio.muted ? Theme.red : Theme.orange
                            font.pixelSize: 16
                            font.bold: true
                        }
                    }

                    Slider {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 90
                        accent: Theme.orange
                        value: Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.volume : 0
                        onMoved: v => { if (Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio) Pipewire.defaultAudioSource.audio.volume = v; }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        text: Math.round((Pipewire.defaultAudioSource && Pipewire.defaultAudioSource.audio ? Pipewire.defaultAudioSource.audio.volume : 0) * 100) + "%"
                        color: Theme.fg
                        font.pixelSize: 12
                        font.bold: true
                    }
                }

                Repeater {
                    model: cc.sources

                    Device {
                        required property var modelData
                        required property int index
                        node: modelData
                        current: Pipewire.defaultAudioSource === modelData
                        selected: cc.navigating && cc.tab === "audio" && cc.sel === cc.sinks.length + index
                        onClicked: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }

                Section {
                    text: "PLAYBACK"
                    visible: cc.playback.length > 0
                }

                Label {
                    visible: cc.streams.length === 0
                    text: "No active audio streams"
                    color: Theme.gray
                    font.pixelSize: 12
                }

                Repeater {
                    model: cc.playback

                    Stream {
                        required property var modelData
                        node: modelData
                        accent: Theme.blue
                        onGlyph: ""
                        offGlyph: ""
                    }
                }

                Section {
                    text: "RECORDING"
                    visible: cc.capture.length > 0
                }

                Repeater {
                    model: cc.capture

                    Stream {
                        required property var modelData
                        node: modelData
                        accent: Theme.orange
                        onGlyph: "\u{f036c}"
                        offGlyph: "\u{f036d}"
                    }
                }
            }

            // ── Bluetooth ────────────────────────────────────────────────

            Column {
                width: parent.width
                spacing: 12
                visible: cc.tab === "bluetooth"

                Item {
                    width: parent.width
                    height: 26

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        text: "Bluetooth"
                        color: Theme.fg
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Pill {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 74
                        label: cc.adapter && cc.adapter.discovering ? "Stop" : "Scan"
                        enabled: cc.adapter !== null && cc.adapter.enabled
                        onClicked: cc.adapter.discovering = !cc.adapter.discovering
                    }
                }

                Section { text: "DEVICES" }

                Repeater {
                    model: cc.devices

                    MouseArea {
                        required property var modelData
                        required property int index

                        readonly property bool selected: cc.navigating && cc.tab === "bluetooth" && cc.sel === index

                        width: parent.width
                        height: 42
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        readonly property bool confirming: cc.forgetting === modelData.address

                        // right click asks, the red pill (or a second right click) forgets
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (!modelData.paired)
                                    return;
                                if (confirming) {
                                    modelData.forget();
                                    cc.forgetting = "";
                                } else {
                                    cc.forgetting = modelData.address;
                                }
                            } else if (confirming) {
                                cc.forgetting = "";
                            } else if (modelData.connected) {
                                modelData.disconnect();
                            } else {
                                modelData.paired ? modelData.connect() : modelData.pair();
                            }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: parent.containsMouse || parent.selected ? Theme.surface : "transparent"
                            border.width: parent.selected ? 1 : 0
                            border.color: Theme.gray
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            spacing: 10

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: cc.btGlyph(modelData.icon, modelData.connected)
                                color: modelData.connected ? Theme.aqua : Theme.gray
                                font.pixelSize: 16
                                font.bold: true
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Label {
                                    text: modelData.name
                                    color: Theme.fg
                                    font.pixelSize: 13
                                    font.bold: true
                                }

                                Label {
                                    text: {
                                        const bits = [];
                                        if (modelData.pairing)
                                            bits.push("Pairing");
                                        else if (modelData.connected)
                                            bits.push("Connected");
                                        else if (modelData.paired)
                                            bits.push("Paired");
                                        if (modelData.trusted)
                                            bits.push("Trusted");
                                        return bits.join(" · ");
                                    }
                                    visible: text !== ""
                                    color: Theme.gray
                                    font.pixelSize: 11
                                }
                            }
                        }

                        Pill {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            width: 70
                            visible: parent.confirming
                            label: "Forget"
                            accent: Theme.red
                            onClicked: {
                                modelData.forget();
                                cc.forgetting = "";
                            }
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            spacing: 4
                            visible: modelData.batteryAvailable && !parent.confirming

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                // nf-md battery-10 .. battery-90 are consecutive, battery (full) sits just before
                                text: {
                                    const tenth = Math.round(modelData.battery * 10);
                                    return String.fromCodePoint(tenth >= 10 ? 0xf0079 : tenth <= 0 ? 0xf008e : 0xf0079 + tenth);
                                }
                                color: modelData.battery <= 0.2 ? Theme.red : Theme.green
                                font.pixelSize: 15
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Math.round(modelData.battery * 100) + "%"
                                color: Theme.gray
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Label {
                    visible: cc.devices.length === 0
                    text: "No devices found"
                    color: Theme.gray
                    font.pixelSize: 12
                }
            }

            // ── Wi-Fi ────────────────────────────────────────────────────

            Column {
                width: parent.width
                spacing: 10
                visible: cc.tab === "network"

                Row {
                    width: parent.width
                    spacing: 12

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cc.linkIface === "" ? "󰖪" : (cc.linkIface.startsWith("wl") ? "󰤨" : "󰈀")
                        color: cc.linkIface === "" ? Theme.gray : Theme.blue
                        font.pixelSize: 28
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 96
                        spacing: 1

                        Label {
                            width: parent.width
                            elide: Text.ElideRight
                            text: {
                                if (cc.linkIface === "")
                                    return "Offline";
                                if (!cc.linkIface.startsWith("wl"))
                                    return "Ethernet";
                                return cc.currentSsid !== "" ? cc.currentSsid : cc.linkIface;
                            }
                            color: Theme.fg
                            font.pixelSize: 15
                            font.bold: true
                        }

                        Label {
                            width: parent.width
                            elide: Text.ElideRight
                            text: cc.wifiDevice === ""
                                ? "NO WI-FI ADAPTER"
                                : cc.wifiDevice.toUpperCase() + " · " + (cc.wifiPowered ? cc.wifiState.toUpperCase() : "OFF")
                                  + (cc.currentNet ? " · " + Math.round(cc.currentNet.rssi) + " dBm" : "")
                            color: Theme.gray
                            font.pixelSize: 11
                            font.letterSpacing: 1
                            font.bold: true
                        }
                    }

                    ToggleSwitch {
                        anchors.verticalCenter: parent.verticalCenter
                        on: cc.wifiPowered
                        enabled: cc.wifiDevice !== ""
                        onClicked: cc.wifiRun(["iwctl", "device", cc.wifiDevice, "set-property", "Powered", cc.wifiPowered ? "off" : "on"])
                    }
                }

                Grid {
                    width: parent.width
                    columns: 2
                    columnSpacing: 24
                    rowSpacing: 4

                    Stat { width: (parent.width - 24) / 2; label: "Ping"; value: cc.ping < 0 ? "—" : Math.round(cc.ping) + " ms" }
                    Stat { width: (parent.width - 24) / 2; label: "Packet loss"; value: cc.loss < 0 ? "—" : cc.loss + "%" }
                    Stat { width: (parent.width - 24) / 2; label: "Receiving"; value: cc.fmtBytes(cc.rxRate, "/s") }
                    Stat { width: (parent.width - 24) / 2; label: "Sending"; value: cc.fmtBytes(cc.txRate, "/s") }
                    Stat { width: (parent.width - 24) / 2; label: "Downloaded"; value: cc.fmtBytes(cc.rxTotal, "") }
                    Stat { width: (parent.width - 24) / 2; label: "Uploaded"; value: cc.fmtBytes(cc.txTotal, "") }
                    Stat { width: (parent.width - 24) / 2; label: "IP address"; value: cc.linkIp === "" ? "—" : cc.linkIp }
                    Stat { width: (parent.width - 24) / 2; label: "Gateway"; value: cc.linkGateway === "" ? "—" : cc.linkGateway }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.surface
                }

                Row {
                    width: parent.width
                    spacing: 8

                    Section {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 176
                        text: "NETWORKS"
                    }

                    Pill {
                        label: "Scan"
                        onClicked: cc.wifiRun(["iwctl", "station", cc.wifiDevice, "scan"])
                    }

                    Pill {
                        label: "Disconnect"
                        accent: Theme.red
                        onClicked: cc.wifiRun(["iwctl", "station", cc.wifiDevice, "disconnect"])
                    }
                }

                Repeater {
                    model: cc.networks.slice(0, 10)

                    MouseArea {
                        required property var modelData
                        required property int index

                        readonly property bool saved: cc.known[modelData.ssid] === true
                        readonly property bool selected: cc.navigating && cc.tab === "network" && cc.sel === index

                        readonly property bool asking: cc.asking === modelData.ssid
                        readonly property bool confirming: cc.forgettingSsid === modelData.ssid

                        width: parent.width
                        // the row grows to hold the passphrase field
                        height: asking ? 68 : 32
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // right click asks, the red pill (or a second right click) forgets
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                if (!saved)
                                    return;
                                if (confirming) {
                                    cc.wifiRun(["iwctl", "known-networks", modelData.ssid, "forget"]);
                                    cc.forgettingSsid = "";
                                } else {
                                    cc.forgettingSsid = modelData.ssid;
                                }
                                return;
                            }
                            if (confirming) {
                                cc.forgettingSsid = "";
                                return;
                            }
                            if (saved || modelData.security === "open")
                                cc.wifiRun(["iwctl", "station", cc.wifiDevice, "connect", modelData.ssid]);
                            else
                                cc.asking = asking ? "" : modelData.ssid;
                        }
                        onAskingChanged: if (asking) pass.forceActiveFocus()

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: parent.containsMouse || parent.selected ? Theme.surface : "transparent"
                            border.width: parent.selected ? 1 : 0
                            border.color: Theme.gray
                        }

                        Rectangle {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 6
                            height: 28
                            radius: 8
                            visible: parent.asking
                            color: Theme.bg
                            border.width: 1
                            border.color: Theme.surface

                            TextInput {
                                id: pass
                                anchors.fill: parent
                                anchors.margins: 7
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: TextInput.Password
                                passwordCharacter: "\u25cf"
                                color: Theme.fg
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                clip: true

                                Keys.onEscapePressed: cc.asking = ""
                                Keys.onReturnPressed: send()
                                Keys.onEnterPressed: send()

                                // iwctl takes the passphrase up front, so no tty prompt
                                function send() {
                                    if (text === "")
                                        return;
                                    cc.wifiRun(["iwctl", "--passphrase", text, "station", cc.wifiDevice,
                                                "connect", modelData.ssid]);
                                    text = "";
                                    cc.asking = "";
                                }

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pass.text === ""
                                    text: "Enter password"
                                    color: Theme.gray
                                    font.pixelSize: 12
                                }
                            }
                        }

                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 6
                            y: 16 - height / 2
                            // four bars, one per 15 dBm below -30; an array, not
                            // charAt, these glyphs are two utf-16 units each
                            text: ["\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"][
                                Math.max(0, Math.min(3, Math.floor((modelData.rssi + 90) / 15)))]
                            color: modelData.current ? Theme.green : Theme.gray
                            font.pixelSize: 15
                        }

                        Label {
                            anchors.left: parent.left
                            anchors.leftMargin: 30
                            y: 16 - height / 2
                            width: parent.width - 130
                            elide: Text.ElideRight
                            text: modelData.ssid
                            color: modelData.current ? Theme.fg : (parent.saved ? Theme.fg : Theme.gray)
                            font.pixelSize: 13
                            font.bold: modelData.current
                        }

                        Pill {
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            y: 16 - height / 2
                            width: 70
                            visible: parent.confirming
                            label: "Forget"
                            accent: Theme.red
                            onClicked: {
                                cc.wifiRun(["iwctl", "known-networks", modelData.ssid, "forget"]);
                                cc.forgettingSsid = "";
                            }
                        }

                        Label {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            y: 16 - height / 2
                            visible: !parent.confirming
                            text: modelData.current
                                ? "Connected"
                                : (parent.saved ? "Saved" : (modelData.security === "open" ? "" : "\uf023"))
                            color: modelData.current ? Theme.green : Theme.gray
                            font.pixelSize: 11
                        }
                    }
                }

                Label {
                    visible: cc.networks.length === 0
                    text: "No networks found"
                    color: Theme.gray
                    font.pixelSize: 12
                }

                // a network that does not broadcast: name, then passphrase
                MouseArea {
                    id: hiddenRow

                    width: parent.width
                    height: cc.hiddenOpen ? 100 : 32
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        cc.hiddenOpen = !cc.hiddenOpen;
                        if (cc.hiddenOpen)
                            hiddenName.forceActiveFocus();
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: parent.containsMouse ? Theme.surface : "transparent"
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        y: 16 - height / 2
                        text: "\u{f0928}"
                        color: Theme.gray
                        font.pixelSize: 15
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 30
                        y: 16 - height / 2
                        text: "Hidden network\u2026"
                        color: Theme.gray
                        font.pixelSize: 13
                    }

                    Repeater {
                        model: [
                            { id: "name", hint: "Network name", y: 36 },
                            { id: "pass", hint: "Passphrase", y: 68 }
                        ]

                        Rectangle {
                            required property var modelData

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 6
                            y: modelData.y
                            height: 28
                            radius: 8
                            visible: cc.hiddenOpen
                            color: Theme.bg
                            border.width: 1
                            border.color: Theme.surface

                            TextInput {
                                id: field

                                anchors.fill: parent
                                anchors.margins: 7
                                verticalAlignment: TextInput.AlignVCenter
                                echoMode: modelData.id === "pass" ? TextInput.Password : TextInput.Normal
                                passwordCharacter: "\u25cf"
                                color: Theme.fg
                                font.family: Theme.uiFont
                                font.pixelSize: 12
                                clip: true

                                Component.onCompleted: {
                                    if (modelData.id === "name")
                                        hiddenName = field;
                                    else
                                        hiddenPass = field;
                                }

                                Keys.onEscapePressed: cc.hiddenOpen = false
                                Keys.onReturnPressed: cc.hiddenSend(modelData.id)
                                Keys.onEnterPressed: cc.hiddenSend(modelData.id)

                                Label {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: field.text === ""
                                    text: modelData.hint
                                    color: Theme.gray
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
