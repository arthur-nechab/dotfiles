import Quickshell
import QtQuick

// the frame every bar popup shares: it hangs just under a bar button
PopupWindow {
    // the bar button the popup hangs from, and the bar's screen
    required property Item anchorItem
    property var clickScreen: null

    anchor.item: anchorItem
    anchor.edges: Edges.Bottom
    anchor.gravity: Edges.Bottom
    anchor.margins.top: 7
    color: "transparent"
    visible: false
}
