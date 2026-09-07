import Quickshell
import QtQuick

// the menu of one tray item; the bar sets handle and source then shows it
PopupWindow {
    id: trayMenu

    // the bar button the popup hangs from, and the bar's side and screen
    required property Item anchorItem
    property bool atTop: true
    property var clickScreen: null


    property var handle: null
    property Item source: null

    anchor.item: source
    anchor.edges: trayMenu.atTop ? Edges.Bottom : Edges.Top
    anchor.gravity: trayMenu.atTop ? Edges.Bottom : Edges.Top
    anchor.margins.top: 7
    implicitWidth: 230
    implicitHeight: menuColumn.implicitHeight + 32
    color: "transparent"
    visible: false
    grabFocus: true


    QsMenuOpener {
        id: menuOpener

        menu: trayMenu.handle
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        radius: 10
        color: Theme.bg

        Column {
            id: menuColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
            spacing: 1

            Repeater {
                model: menuOpener.children

                MouseArea {
                    required property var modelData

                    width: menuColumn.width
                    height: modelData.isSeparator ? 7 : 26
                    hoverEnabled: !modelData.isSeparator
                    enabled: modelData.enabled && !modelData.isSeparator
                    onClicked: {
                        modelData.triggered();
                        trayMenu.visible = false;
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        visible: !modelData.isSeparator
                        color: parent.containsMouse ? Theme.surface : "transparent"
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: modelData.isSeparator
                        height: 1
                        color: Theme.surface
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 16
                        elide: Text.ElideRight
                        visible: !modelData.isSeparator
                        text: modelData.text
                        color: modelData.enabled ? Theme.fg : Theme.gray
                        font.pixelSize: 13
                    }
                }
            }
        }
    }
}
