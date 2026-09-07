import Quickshell.Io
import QtQuick

// a card that runs a shell command on click and reads its state back with a probe
MouseArea {
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
    // the owner panel's visibility: the probe only runs while it shows
    property bool polling: false
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
        running: toggle.polling && toggle.probe !== ""
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
