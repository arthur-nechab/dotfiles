import QtQuick

// a level bar: track in the surface colour, fill in the accent
Rectangle {
    property real value: 0
    property color accent: Theme.blue

    height: 6
    radius: height / 2
    color: Theme.surface

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, parent.value))
        height: parent.height
        radius: parent.radius
        color: parent.accent
    }
}
