import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: menu

    signal lockRequested

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    // hug the row instead of reserving a fixed box around it
    implicitWidth: row.implicitWidth + 24
    implicitHeight: row.implicitHeight + 24
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-session"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // colour follows how far the action goes, not the icon: benign, then
    // disruptive, then destructive
    readonly property var actions: [
        { icon: "\u{f033e}", label: "Lock",      key: "l", color: Theme.blue,   cmd: "" },
        { icon: "\u{f0343}", label: "Log out",   key: "o", color: Theme.yellow, cmd: "loginctl terminate-session $XDG_SESSION_ID" },
        { icon: "\u{f0904}", label: "Suspend",   key: "s", color: Theme.purple, cmd: "systemctl suspend" },
        { icon: "\u{f0709}", label: "Reboot",    key: "r", color: Theme.orange, cmd: "systemctl reboot" },
        { icon: "\u{f0425}", label: "Shut down", key: "p", color: Theme.red,    cmd: "systemctl poweroff" }
    ]

    property int current: 0
    // index waiting for its second confirmation, -1 otherwise
    property int armed: -1

    function toggle() {
        visible = !visible;
        armed = -1;
        if (visible) {
            current = 0;
            keys.forceActiveFocus();
        }
    }

    onCurrentChanged: armed = -1

    function run(i) {
        const a = actions[i];
        if (!a)
            return;
        // reboot and shut down ask twice; the others are cheap to undo
        if (i >= 3 && armed !== i) {
            armed = i;
            return;
        }
        visible = false;
        armed = -1;
        if (a.cmd === "")
            lockRequested();
        else
            Quickshell.execDetached(["sh", "-c", a.cmd]);
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            menu.toggle();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.95)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Item {
            id: keys

            anchors.fill: parent
            focus: true

            Keys.onEscapePressed: menu.visible = false
            Keys.onLeftPressed: menu.current = (menu.current + menu.actions.length - 1) % menu.actions.length
            Keys.onRightPressed: menu.current = (menu.current + 1) % menu.actions.length
            Keys.onTabPressed: menu.current = (menu.current + 1) % menu.actions.length
            Keys.onReturnPressed: menu.run(menu.current)
            Keys.onEnterPressed: menu.run(menu.current)
            // l, o, s, r, p go straight to the action; the two red ones still ask twice
            Keys.onPressed: event => {
                const i = menu.actions.findIndex(a => a.key === event.text.toLowerCase());
                if (i < 0)
                    return;
                menu.current = i;
                menu.run(i);
                event.accepted = true;
            }
        }

        Row {
            id: row

            anchors.centerIn: parent
            spacing: 14

            Repeater {
                model: menu.actions

                MouseArea {
                    required property var modelData

                    required property int index

                    readonly property bool active: containsMouse || menu.current === index

                    width: 92
                    height: 108
                    hoverEnabled: true
                    onEntered: menu.current = index
                    onClicked: menu.run(index)

                    Rectangle {
                        anchors.fill: parent
                        radius: 14
                        color: parent.active ? Theme.surface : "transparent"
                        border.width: menu.current === parent.index ? 1 : 0
                        border.color: modelData.color
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 12

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.icon
                            color: modelData.color
                            font.pixelSize: 36
                        }

                        Label {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: menu.armed === parent.parent.index ? "Confirm" : modelData.label
                            color: menu.armed === parent.parent.index ? modelData.color : Theme.fg
                            font.pixelSize: 12
                            font.bold: true
                        }
                    }
                }
            }
        }
    }
}
