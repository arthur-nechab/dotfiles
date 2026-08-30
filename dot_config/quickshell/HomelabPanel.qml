import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: panel

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: 460
    // follow the content instead of reserving 900px of empty card
    implicitHeight: Math.min(900, Math.max(160, body.implicitHeight + 32))
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-homelab"

    ClickAway {
        target: panel
        screen: panel.screen
    }

    anchors {
        top: true
        left: true
    }

    margins {
        top: 57
        left: 10
    }

    function toggle() {
        visible = !visible;
    }

    // opening refreshes everything at once, then the timers take over
    onVisibleChanged: {
        Homelab.panelOpen = visible;
        if (visible)
            Homelab.refreshAll();
    }

    IpcHandler {
        target: "homelab"

        function toggle(): void {
            panel.toggle();
        }
    }

    component Toggle: MouseArea {
        id: toggle

        property string glyph: ""
        property string label: ""
        property string probe: ""
        property string match: ""
        property string onCmd: ""
        property string offCmd: ""
        property string onMsg: ""
        property string offMsg: ""
        property color accent: Theme.aqua
        property int pollInterval: 5000
        property bool active: false
        property bool busy: false
        property string pending: ""

        width: 84
        height: 54
        hoverEnabled: true
        onClicked: {
            // the notification waits for the command: announcing on click would
            // claim a result the process has not produced yet
            toggle.pending = toggle.active ? toggle.offMsg : toggle.onMsg;
            toggle.busy = true;
            action.command = ["sh", "-c", toggle.active ? toggle.offCmd : toggle.onCmd];
            action.running = false;
            action.running = true;
        }

        function announce(what: string): void {
            notify.command = ["notify-send", "-a", "homelab", "-i",
                              "utilities-system-monitor", toggle.label, what];
            notify.running = false;
            notify.running = true;
        }

        Process {
            id: notify
        }

        Process {
            id: action

            stderr: StdioCollector {}

            onExited: (code, status) => {
                toggle.busy = false;
                if (code === 0) {
                    toggle.announce(toggle.pending);
                } else {
                    const err = action.stderr.text.trim().split("\n").pop();
                    toggle.announce(err !== "" ? err : "Failed (exit " + code + ")");
                }
                check.restart();
            }
        }

        Process {
            id: status
            command: ["sh", "-c", toggle.probe]
            stdout: StdioCollector {
                onStreamFinished: toggle.active = this.text.indexOf(toggle.match) >= 0
            }
        }

        Timer {
            id: check
            interval: 400
            onTriggered: {
                status.running = false;
                status.running = true;
            }
        }

        Timer {
            interval: toggle.pollInterval
            running: panel.visible && toggle.probe !== ""
            repeat: true
            triggeredOnStart: true
            onTriggered: {
                status.running = false;
                status.running = true;
            }
        }

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 10
            color: toggle.containsMouse ? Theme.surface : "transparent"
            border.width: toggle.active ? 2 : 1
            border.color: toggle.active ? toggle.accent : Theme.surface
        }

        Column {
            anchors.centerIn: parent
            spacing: 4

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: toggle.glyph
                color: toggle.active ? toggle.accent : Theme.gray
                opacity: toggle.busy ? 0.4 : 1
                font.pixelSize: 20
                font.bold: true
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: toggle.label
                color: toggle.active ? Theme.fg : Theme.gray
                font.pixelSize: 11
                font.bold: true
            }
        }
    }

    component Meter: Item {
        property string label: ""
        property int percent: 0
        property color accent: Theme.blue

        width: 100
        height: 26

        Label {
            anchors.left: parent.left
            anchors.top: parent.top
            text: parent.label
            color: Theme.gray
            font.pixelSize: 11
            font.bold: true
        }

        Label {
            anchors.right: parent.right
            anchors.top: parent.top
            text: parent.percent + "%"
            color: Theme.fg
            font.pixelSize: 11
            font.bold: true
        }

        Gauge {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 8
            value: parent.percent / 100
            accent: parent.percent > 85 ? Theme.red : parent.accent
        }
    }

    component Section: Column {
        property string title: ""

        width: parent.width
        spacing: 6

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.surface
        }

        Label {
            text: parent.title
            color: Theme.gray
            font.pixelSize: 12
            font.letterSpacing: 1
            font.bold: true
        }
    }

    component Line: MouseArea {
        property string label: ""
        property string value: ""
        property color tint: Theme.fg
        // page a click opens, "" for a plain row
        property string url: ""

        width: parent.width
        height: 22
        enabled: url !== ""
        hoverEnabled: url !== ""
        cursorShape: url !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: Homelab.open(url)

        Rectangle {
            anchors.fill: parent
            anchors.margins: -4
            radius: 6
            color: parent.containsMouse ? Theme.surface : "transparent"
        }

        Label {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.45
            elide: Text.ElideRight
            text: parent.label
            color: Theme.fg
            font.pixelSize: 13
        }

        Label {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.52
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: parent.value
            color: parent.tint
            font.pixelSize: 13
            font.bold: true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.96)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Label {
            anchors.centerIn: parent
            width: parent.width - 60
            visible: !Homelab.anyConfigured
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Not configured\nAdd services to ~/.config/quickshell/local.json"
            color: Theme.gray
            font.pixelSize: 13
        }

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            visible: Homelab.anyConfigured
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: body
                width: parent.width
                spacing: 18

                Item {
                    width: parent.width
                    height: 54

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Toggle {
                            id: netbirdToggle

                            glyph: "\u{f0582}"
                            label: "NetBird"
                            probe: "netbird status | grep -q 'Management: Connected' && echo ON"
                            match: "ON"
                            onCmd: "netbird up"
                            offCmd: "netbird down"
                            onMsg: "VPN connected"
                            offMsg: "VPN disconnected"
                        }

                        Toggle {
                            glyph: "\u{f06a9}"
                            accent: Theme.yellow
                            label: "Ollama"
                            probe: "systemctl is-active --quiet ollama && echo ON"
                            match: "ON"
                            onCmd: "systemctl start ollama"
                            offCmd: "systemctl stop ollama"
                            onMsg: "Model server started"
                            offMsg: "Model server stopped"
                        }

                        Toggle {
                            glyph: "\u{f08ae}"
                            accent: Theme.purple
                            label: "VRAM"
                            probe: "curl -sf -m 2 http://localhost:11434/api/ps | jq -e '.models | length > 0' >/dev/null && echo ON"
                            match: "ON"
                            onCmd: "true"
                            offCmd: "curl -sf -m 2 http://localhost:11434/api/ps | jq -r '.models[].name' | xargs -r -n1 ollama stop"
                            onMsg: "No model loaded"
                            offMsg: "GPU memory freed"
                        }
                    }

                }

                Section {
                    title: "ALERTS"
                    visible: Homelab.firing > 0

                    Repeater {
                        model: Homelab.alerts.slice(0, 8)

                        MouseArea {
                            required property var modelData

                            readonly property color tint: modelData.severity === "critical"
                                ? Theme.red : Theme.orange

                            width: parent.width
                            height: 24
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Homelab.open(Homelab.alertsUrl)

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 6
                                color: parent.containsMouse ? Theme.surface : "transparent"
                            }

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: parent.tint
                            }

                            Label {
                                anchors.left: parent.left
                                anchors.leftMargin: 16
                                anchors.right: badge.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                elide: Text.ElideRight
                                text: modelData.name
                                color: Theme.fg
                                font.pixelSize: 13
                            }

                            Rectangle {
                                id: badge

                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(22, count.implicitWidth + 12)
                                height: 18
                                radius: 9
                                color: Qt.alpha(parent.tint, 0.16)

                                Label {
                                    id: count

                                    anchors.centerIn: parent
                                    text: modelData.count > 1
                                        ? String(modelData.count) : "!"
                                    color: badge.parent.tint
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }
                    }

                    Label {
                        visible: Homelab.alerts.length > 8
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: (Homelab.alerts.length - 8) + " more\u2026"
                        color: Theme.gray
                        font.pixelSize: 12
                    }
                }

                Section {
                    title: "GATUS"
                    visible: Homelab.hasGatus
                    spacing: 6

                    // no endpoint up and none down means the probe never answered,
                    // which is not the same thing as everything being fine
                    readonly property bool reachable: Homelab.gatusUp + Homelab.gatusDown > 0

                    Line {
                        visible: !parent.reachable
                        label: "endpoints"
                        value: "Unreachable"
                        tint: Theme.red
                    }

                    // same card as pi-hole: three summary figures read better
                    // centred than as label/value rows
                    Rectangle {
                        visible: parent.reachable
                        width: parent.width
                        height: 62
                        radius: 10
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.surface

                        Row {
                            anchors.fill: parent
                            anchors.margins: 12

                            Repeater {
                                model: [
                                    { v: String(Homelab.gatusUp), l: "UP", c: Theme.green },
                                    { v: String(Homelab.gatusDown), l: "DOWN",
                                      c: Homelab.gatusDown > 0 ? Theme.red : Theme.gray },
                                    { v: Homelab.gatusUptime < 0
                                          ? "-" : Homelab.gatusUptime.toFixed(1) + "%",
                                      l: "UPTIME", c: Theme.fg }
                                ]

                                Column {
                                    required property var modelData

                                    width: parent.width / 3
                                    spacing: 2

                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.v
                                        color: modelData.c
                                        font.pixelSize: 18
                                        font.bold: true
                                    }

                                    Label {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.l
                                        color: Theme.gray
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                        font.bold: true
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: Homelab.gatusList.filter(e => !e.ok)

                        Line {
                            required property var modelData
                            label: modelData.name
                            value: "Offline"
                            tint: Theme.red
                            url: Homelab.gatusUrl
                        }
                    }
                }

                Section {
                    title: "DNS"
                    visible: Homelab.hasDns
                    spacing: 8

                    Label {
                        visible: Homelab.blockedPercent < 0
                        text: "Unreachable"
                        color: Theme.gray
                        font.pixelSize: 12
                        font.bold: true
                    }

                    Row {
                        visible: Homelab.blockedPercent >= 0
                        width: parent.width

                        Column {
                            width: parent.width / 2
                            spacing: 1

                            Label {
                                text: Homelab.blockedPercent.toFixed(1) + "%"
                                color: Theme.purple
                                font.pixelSize: 20
                                font.bold: true
                            }

                            Label {
                                text: "blocked"
                                color: Theme.gray
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }

                        Column {
                            width: parent.width / 2
                            spacing: 1

                            Label {
                                anchors.right: parent.right
                                text: Homelab.queriesToday.toLocaleString(Qt.locale("fr_FR"), "f", 0)
                                color: Theme.fg
                                font.pixelSize: 20
                                font.bold: true
                            }

                            Label {
                                anchors.right: parent.right
                                text: "queries today"
                                color: Theme.gray
                                font.pixelSize: 11
                                font.bold: true
                            }
                        }
                    }

                    // one bar per hour, blocked share on top of it
                    Row {
                        id: hourly

                        visible: Homelab.blockedPercent >= 0 && Homelab.dnsHourly.length > 0
                        width: parent.width
                        height: 36
                        spacing: 2

                        readonly property int peak: Math.max(1, ...Homelab.dnsHourly.map(h => h.total))
                        readonly property real slot: (width - spacing * (Homelab.dnsHourly.length - 1)) / Math.max(1, Homelab.dnsHourly.length)

                        Repeater {
                            model: Homelab.dnsHourly

                            Item {
                                required property var modelData

                                width: hourly.slot
                                height: hourly.height

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: Math.max(2, parent.height * parent.modelData.total / hourly.peak)
                                    radius: 2
                                    color: Theme.surface
                                }

                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: parent.height * parent.modelData.blocked / hourly.peak
                                    radius: 2
                                    color: Theme.purple
                                }
                            }
                        }
                    }

                    Rectangle {
                        visible: Homelab.blockedPercent >= 0
                        width: parent.width
                        height: 10
                        radius: 4
                        color: Theme.surface

                        readonly property int total: Math.max(1, Homelab.queriesToday)

                        Row {
                            anchors.fill: parent
                            spacing: 0

                            Rectangle {
                                width: parent.width * Homelab.blockedToday / parent.parent.total
                                height: parent.height
                                color: Theme.purple
                            }

                            Rectangle {
                                width: parent.width * Homelab.cachedToday / parent.parent.total
                                height: parent.height
                                color: Theme.aqua
                            }

                            Rectangle {
                                width: parent.width * Homelab.recursiveToday / parent.parent.total
                                height: parent.height
                                color: Theme.blue
                            }

                            Rectangle {
                                width: parent.width * Homelab.authoritativeToday / parent.parent.total
                                height: parent.height
                                color: Theme.green
                            }
                        }
                    }

                    Row {
                        visible: Homelab.blockedPercent >= 0
                        width: parent.width
                        spacing: 12

                        Repeater {
                            model: [
                                { c: Theme.purple, l: "blocked",   v: Homelab.blockedToday },
                                { c: Theme.aqua,   l: "cached",    v: Homelab.cachedToday },
                                { c: Theme.blue,   l: "recursive", v: Homelab.recursiveToday },
                                { c: Theme.green,  l: "local",     v: Homelab.authoritativeToday }
                            ]

                            Row {
                                required property var modelData
                                spacing: 5

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: modelData.c
                                }

                                Label {
                                    text: modelData.v + " " + modelData.l
                                    color: Theme.gray
                                    font.pixelSize: 11
                                    font.bold: true
                                }
                            }
                        }
                    }

                }

                Section {
                    title: "HOSTS"
                    visible: Homelab.hasProxmox
                    spacing: 8

                    // the vps only answers through the mesh, so its row follows
                    // the netbird toggle rather than the prometheus config
                    Repeater {
                        model: Homelab.nodes.concat(Homelab.hasOvh && netbirdToggle.active ? [{
                            name: "ovh",
                            online: Homelab.ovhReachable,
                            cpu: Math.round(Homelab.ovhCpu),
                            memPercent: Math.round(Homelab.ovhRam),
                            diskPercent: Math.round(Homelab.ovhDisk)
                        }] : [])

                        Column {
                            required property var modelData

                            width: parent.width
                            spacing: 4

                            Row {
                                spacing: 8

                                Label {
                                    text: modelData.name
                                    color: Theme.fg
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Label {
                                    anchors.bottom: parent.bottom
                                    anchors.bottomMargin: 1
                                    visible: !modelData.online
                                    text: "Offline"
                                    color: Theme.red
                                    font.pixelSize: 11
                                }
                            }

                            Row {
                                visible: modelData.online
                                width: parent.width
                                spacing: 8

                                Meter {
                                    width: (parent.width - 16) / 3
                                    label: "CPU"
                                    percent: modelData.cpu
                                }

                                Meter {
                                    width: (parent.width - 16) / 3
                                    label: "RAM"
                                    percent: modelData.memPercent
                                }

                                Meter {
                                    width: (parent.width - 16) / 3
                                    label: "DISK"
                                    percent: modelData.diskPercent
                                }
                            }
                        }
                    }
                }

                Section {
                    title: "SCRUTINY"
                    visible: Homelab.hasScrutiny && Homelab.failedDisks.length > 0

                    Repeater {
                        model: Homelab.failedDisks

                        Line {
                            required property var modelData
                            label: modelData.host + " \u00b7 " + modelData.name
                            value: "SMART failed"
                            tint: Theme.red
                        }
                    }
                }

            }
        }

        MouseArea {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            width: freshness.implicitWidth + 26
            height: 32
            hoverEnabled: true
            onClicked: Homelab.refreshAll()

            Rectangle {
                anchors.fill: parent
                radius: 9
                color: parent.containsMouse ? Theme.surface : "transparent"
            }

            Label {
                id: freshness

                anchors.centerIn: parent
                // the icon alone; it turns orange once the data is stale
                readonly property int age: {
                    clockTick.tick;
                    return Homelab.lastUpdate === 0 ? 0
                        : Math.round((Date.now() - Homelab.lastUpdate) / 1000);
                }

                text: "\u{f0450}"
                color: age > 120 ? Theme.orange : Theme.gray
                font.pixelSize: 14
                font.bold: true
            }
        }

        Timer {
            id: clockTick

            property int tick: 0

            interval: 1000
            running: panel.visible
            repeat: true
            onTriggered: tick += 1
        }
    }
}
