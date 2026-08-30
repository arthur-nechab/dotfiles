import Quickshell
import Quickshell.Wayland
import QtQuick

// transparent sheet under a panel: the first click anywhere else closes it
PanelWindow {
    id: away

    required property var target

    visible: target.visible
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    // same layer as the panels; it maps first, so it stacks under them
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-clickaway"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    MouseArea {
        anchors.fill: parent
        onPressed: away.target.visible = false
    }
}
