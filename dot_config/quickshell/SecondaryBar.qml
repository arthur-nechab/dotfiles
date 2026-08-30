import Quickshell
import Quickshell.Hyprland
import QtQuick

PanelWindow {
    id: bar

    property bool atTop: true
    // bound to Notifications.dnd in shell.qml
    property bool dnd: false

    // kept apart from the window's own screen, whose change would loop back into visible
    readonly property var other: Quickshell.screens.find(s => !s.model.includes(Theme.mainModel)) ?? null

    screen: other ?? Quickshell.screens[0]
    visible: other !== null
    color: "transparent"
    implicitHeight: 40

    anchors {
        left: true
        right: true
        top: bar.atTop
        bottom: !bar.atTop
    }

    margins {
        left: 8
        right: 8
        top: 4
        bottom: 4
    }

    // the workspace pinned to this monitor
    readonly property var ws: {
        Hyprland.focusedWorkspace;
        return Hyprland.workspaces.values.find(w => w.id === 5) ?? null;
    }

    component Pill: Rectangle {
        default property alias content: row.data

        implicitWidth: row.implicitWidth + 16
        implicitHeight: 30
        radius: 10
        color: Qt.alpha(Theme.bg, Theme.opacity)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
        }
    }

    Pill {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: "5"
            color: bar.ws && bar.ws.focused ? Theme.yellow : (bar.ws && bar.ws.active ? Theme.fg : Theme.gray)
            font.pixelSize: 14
            font.bold: true
        }
    }

    Pill {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(Theme.now, "HH:mm")
            font.pixelSize: 15
            font.bold: true
        }
    }

    Pill {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: bar.dnd

        Label {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f009b}"
            color: Theme.gray
            font.pixelSize: 15
        }
    }
}
