import Quickshell
import QtQuick

// the home assistant sensors under the weather reading
PopupWindow {
    id: weatherPopup

    // the bar button the popup hangs from, and the bar's side and screen
    required property Item anchorItem
    property bool atTop: true
    property var clickScreen: null


    anchor.item: weatherPopup.anchorItem
    anchor.edges: weatherPopup.atTop ? Edges.Bottom : Edges.Top
    anchor.gravity: weatherPopup.atTop ? Edges.Bottom : Edges.Top
    anchor.margins.top: 7
    implicitWidth: 240
    implicitHeight: 38 + column.implicitHeight
    color: "transparent"
    visible: false

    ClickAway {
        target: weatherPopup
        screen: weatherPopup.clickScreen
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
