import Quickshell
import QtQuick

// removable volumes: a click mounts or unmounts, a right click browses
PopupWindow {
    id: usbPopup

    // the bar button the popup hangs from, and the bar's side and screen
    required property Item anchorItem
    property bool atTop: true
    property var clickScreen: null

    // the lsblk rows the bar keeps, and the signal that asks for a fresh read
    required property var devices

    signal refresh

    function run(cmd) {
        Quickshell.execDetached(["sh", "-c", cmd]);
    }


    anchor.item: usbPopup.anchorItem
    anchor.edges: usbPopup.atTop ? Edges.Bottom : Edges.Top
    anchor.gravity: usbPopup.atTop ? Edges.Bottom : Edges.Top
    anchor.margins.top: 7
    implicitWidth: 300
    implicitHeight: 36 + Math.max(1, usbColumn.implicitHeight)
    color: "transparent"
    visible: false

    // udisks answers before the mount point shows up in lsblk
    Timer {
        id: settle
        interval: 800
        onTriggered: usbPopup.refresh()
    }

    ClickAway {
        target: usbPopup
        screen: usbPopup.clickScreen
    }

    // the button hides itself once the last device is gone
    onVisibleChanged: if (visible && usbPopup.devices.length === 0) visible = false

    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        radius: 10
        color: Theme.bg

        Column {
            id: usbColumn

            anchors.centerIn: parent
            width: parent.width - 16
            spacing: 4

            Repeater {
                model: usbPopup.devices

                MouseArea {
                    id: dev

                    required property var modelData
                    readonly property bool mounted: (modelData.mountpoint ?? "") !== ""

                    width: usbColumn.width
                    height: 38
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    // right click browses a mounted volume instead of unmounting it
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            if (mounted)
                                Quickshell.execDetached(["xdg-open", modelData.mountpoint]);
                            return;
                        }
                        usbPopup.run("udisksctl " + (mounted ? "unmount" : "mount")
                                + " -b " + modelData.path
                                + " || notify-send -u critical 'Volume' '"
                                + modelData.path + "'");
                        settle.restart();
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: parent.containsMouse ? Theme.surface : "transparent"
                    }

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 8

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: dev.mounted ? "" : ""
                            color: dev.mounted ? Theme.green : Theme.gray
                            font.pixelSize: 16
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 32
                            spacing: 1

                            Label {
                                width: parent.width
                                text: (modelData.label ?? "") !== ""
                                    ? modelData.label
                                    : modelData.path
                                color: Theme.fg
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Label {
                                width: parent.width
                                text: modelData.size + " \u00b7 " + modelData.fstype
                                    + (dev.mounted
                                       ? " \u00b7 " + modelData.mountpoint
                                         + ((modelData.fsavail ?? "") !== "" ? " \u00b7 " + modelData.fsavail + " free" : "")
                                       : " \u00b7 not mounted")
                                color: Theme.gray
                                font.pixelSize: 11
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
