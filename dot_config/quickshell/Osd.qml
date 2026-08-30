import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick

PanelWindow {
    id: osd

    // volume and mute changes fire once as the bindings settle at startup
    property bool armed: false
    property string icon: ""
    property real value: 0
    property bool muted: false
    property string label: ""
    property color accent: Theme.purple
    // a text notice has no level to draw
    property bool bare: false

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: bare ? 80 + 14 + labelMetrics.width : 280
    implicitHeight: 70
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-osd"

    anchors {
        bottom: true
    }

    margins {
        bottom: 120
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource

    function show(ico, val, isMuted) {
        if (!armed)
            return;
        osd.bare = false;
        osd.icon = ico;
        osd.value = val;
        osd.muted = isMuted;
        osd.label = Math.round(val * 100) + "%";
        osd.accent = isMuted ? Theme.red : Theme.purple;
        osd.visible = true;
        hideTimer.restart();
    }

    // nightlight: the bar knows the temperature, the OSD only draws it
    // a state that flipped from the keyboard: icon and a few words, no bar
    function showText(ico, words, color) {
        if (!armed)
            return;
        osd.bare = true;
        osd.icon = ico;
        osd.label = words;
        osd.accent = color;
        osd.visible = true;
        hideTimer.restart();
    }

    function showTemp(temp, warm) {
        if (!armed)
            return;
        osd.bare = false;
        osd.icon = warm ? "\u{f0594}" : "\u{f0599}";
        osd.value = Math.max(0, Math.min(1, (temp - 1000) / 5500));
        osd.muted = false;
        osd.label = temp + "K";
        osd.accent = warm ? Theme.purple : Theme.yellow;
        osd.visible = true;
        hideTimer.restart();
    }

    Timer {
        interval: 600
        running: true
        onTriggered: osd.armed = true
    }

    TextMetrics {
        id: labelMetrics
        font.family: Theme.uiFont
        font.pixelSize: 14
        font.bold: true
        text: osd.label
    }

    Timer {
        id: hideTimer
        interval: 1500
        onTriggered: osd.visible = false
    }

    function showSink() {
        const a = osd.sink.audio;
        osd.show(a.muted ? "" : "", a.volume, a.muted);
    }

    Connections {
        target: osd.sink && osd.sink.audio ? osd.sink.audio : null

        function onVolumeChanged() { osd.showSink(); }
        function onMutedChanged() { osd.showSink(); }
    }

    Connections {
        target: osd.source && osd.source.audio ? osd.source.audio : null

        function onMutedChanged() {
            osd.show(osd.source.audio.muted ? "\u{f036d}" : "\u{f036c}",
                     osd.source.audio.volume, osd.source.audio.muted);
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.92)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Row {
            anchors.centerIn: parent
            spacing: 14

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: osd.icon
                color: osd.accent
                font.pixelSize: 22
                font.bold: true
            }

            Gauge {
                anchors.verticalCenter: parent.verticalCenter
                visible: !osd.bare
                width: 160
                value: osd.value
                accent: osd.accent
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: osd.bare ? implicitWidth : 52
                text: osd.label
                color: Theme.fg
                font.pixelSize: 14
                font.bold: true
            }
        }
    }
}
