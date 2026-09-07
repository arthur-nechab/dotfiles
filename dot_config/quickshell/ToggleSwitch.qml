import QtQuick

// an on/off switch: the knob slides to the accent side when on
MouseArea {
    property bool on: false
    property color accent: Theme.blue

    width: 44
    height: 22
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        radius: 11
        color: parent.on ? Qt.alpha(parent.accent, 0.35) : Theme.surface
    }

    Rectangle {
        x: parent.on ? parent.width - width - 3 : 3
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: 16
        radius: 8
        color: parent.on ? parent.accent : Theme.gray

        Behavior on x {
            NumberAnimation { duration: 150 }
        }
    }
}
