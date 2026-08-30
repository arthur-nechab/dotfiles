import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Mpris
import QtQuick

PanelWindow {
    id: panel

    property real pos: 0

    readonly property var player: {
        const l = Mpris.players.values;
        for (let i = 0; i < l.length; i++) if (l[i].isPlaying) return l[i];
        return l.length > 0 ? l[0] : null;
    }

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: 420
    implicitHeight: 170
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-media"

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

    // the player's window, by its desktop id when it has one
    function raise() {
        if (!player)
            return;
        const cls = player.desktopEntry !== "" ? player.desktopEntry : player.identity.toLowerCase();
        Quickshell.execDetached([Quickshell.env("HOME") + "/.config/scripts/launch-or-focus", cls, "true"]);
        visible = false;
    }

    function fmt(seconds) {
        if (!seconds || seconds < 0)
            return "0:00";
        const m = Math.floor(seconds / 60);
        const s = Math.floor(seconds % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Timer {
        interval: 1000
        running: panel.visible && panel.player !== null
        repeat: true
        triggeredOnStart: true
        onTriggered: panel.pos = panel.player.position
    }

    IpcHandler {
        target: "media"

        function toggle(): void {
            panel.toggle();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.96)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Row {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 14

            ClippingRectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 110
                height: 110
                radius: 10
                color: Theme.surface

                Image {
                    anchors.fill: parent
                    source: panel.player ? panel.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 124
                spacing: 6

                MouseArea {
                    width: parent.width
                    height: titleLabel.implicitHeight
                    hoverEnabled: true
                    cursorShape: panel.player ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: panel.raise()

                    Label {
                        id: titleLabel
                        width: parent.width
                        text: panel.player ? panel.player.trackTitle : "Nothing playing"
                        color: parent.containsMouse && panel.player ? Theme.yellow : Theme.fg
                        font.pixelSize: 15
                        font.bold: true
                        elide: Text.ElideRight
                    }
                }

                Label {
                    width: parent.width
                    visible: text !== ""
                    text: panel.player ? panel.player.trackArtist : ""
                    color: Theme.yellow
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    visible: text !== ""
                    text: panel.player ? panel.player.identity : ""
                    color: Theme.gray
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                MouseArea {
                    width: parent.width
                    height: 16
                    enabled: panel.player !== null && panel.player.canSeek
                    onPressed: mouse => panel.player.position = (mouse.x / width) * panel.player.length

                    Gauge {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 5
                        value: panel.player && panel.player.length > 0 ? panel.pos / panel.player.length : 0
                        accent: Theme.yellow
                    }
                }

                Item {
                    width: parent.width
                    height: 26

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Repeater {
                            model: [
                                { glyph: "\u{f04ae}", act: "previous" },
                                { glyph: "", act: "toggle" },
                                { glyph: "\u{f04ad}", act: "next" }
                            ]

                            MouseArea {
                                required property var modelData

                                width: 26
                                height: 26
                                enabled: panel.player !== null
                                onClicked: {
                                    const p = panel.player;
                                    if (modelData.act === "previous" && p.canGoPrevious)
                                        p.previous();
                                    else if (modelData.act === "next" && p.canGoNext)
                                        p.next();
                                    else if (modelData.act === "toggle" && p.canTogglePlaying)
                                        p.togglePlaying();
                                }

                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.act === "toggle"
                                        ? (panel.player && panel.player.isPlaying ? "\u{f03e4}" : "\u{f040a}")
                                        : modelData.glyph
                                    color: Theme.fg
                                    font.pixelSize: 18
                                    font.bold: true
                                }
                            }
                        }
                    }

                    Label {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.fmt(panel.pos) + " / " + panel.fmt(panel.player ? panel.player.length : 0)
                        color: Theme.gray
                        font.pixelSize: 11
                        font.bold: true
                    }
                }
            }
        }
    }
}
