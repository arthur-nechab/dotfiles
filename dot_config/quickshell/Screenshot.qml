import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property bool active: false
    property bool dragging: false
    // "shot" saves an image, "ocr" copies the text it reads
    property string mode: "shot"
    readonly property color accent: mode === "ocr" ? Theme.aqua : Theme.orange
    // kept in compositor coordinates: grim -g wants the global layout, not a screen
    property real x0: 0
    property real y0: 0
    property real x1: 0
    property real y1: 0

    readonly property int selX: Math.round(Math.min(x0, x1))
    readonly property int selY: Math.round(Math.min(y0, y1))
    readonly property int selW: Math.round(Math.abs(x1 - x0))
    readonly property int selH: Math.round(Math.abs(y1 - y0))

    // pointer in compositor coordinates, for the window under it
    property real px: -1
    property real py: -1

    // windows of the workspace shown on each monitor, smallest first so a
    // click lands on the dialog rather than the window behind it
    readonly property var windows: {
        Hyprland.toplevels.values;
        const shown = {};
        for (const m of Hyprland.monitors.values)
            shown[m.id] = m.activeWorkspace ? m.activeWorkspace.id : -1;
        return Hyprland.toplevels.values
            .map(t => t.lastIpcObject)
            .filter(w => w && w.mapped && !w.hidden && shown[w.monitor] === w.workspace.id)
            .sort((a, b) => a.size[0] * a.size[1] - b.size[0] * b.size[1]);
    }

    readonly property var hovered: windows.find(w =>
        px >= w.at[0] && px < w.at[0] + w.size[0] && py >= w.at[1] && py < w.at[1] + w.size[1]) ?? null

    // one still per output, shown under the overlay so the screen holds still
    property int frozenAt: 0
    readonly property string freezeDir: Quickshell.env("XDG_RUNTIME_DIR") + "/quickshell-freeze"

    function start(mode) {
        root.mode = mode;
        Hyprland.refreshToplevels();
        dragging = false;
        freeze.command = ["sh", "-c", "mkdir -p " + JSON.stringify(freezeDir) + " && "
            + Quickshell.screens.map(s => "grim -t ppm -o " + JSON.stringify(s.name) + " "
                + JSON.stringify(freezeDir + "/" + s.name + ".ppm") + " &").join(" ") + " wait"];
        freeze.running = true;
    }

    Process {
        id: freeze
        onExited: {
            root.frozenAt = Date.now();
            root.active = true;
        }
    }

    function cancel() {
        active = false;
        dragging = false;
    }

    // a plain click takes the window under the pointer, a drag takes the region
    function grab() {
        active = false;
        dragging = false;
        if (selW < 5 || selH < 5) {
            if (hovered)
                shoot(hovered.at[0] + "," + hovered.at[1] + " " + hovered.size[0] + "x" + hovered.size[1]);
            return;
        }
        shoot(selX + "," + selY + " " + selW + "x" + selH);
    }

    // file and clipboard both, like hyprshot did; grim -g takes a geometry, -o an output
    function shoot(geometry, output) {
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd-HHmmss");
        const file = Quickshell.env("HOME") + "/Pictures/Screenshots/" + stamp + ".png";
        const src = output ? "-o " + JSON.stringify(output) : "-g " + JSON.stringify(geometry);
        capture.command = root.mode === "ocr"
            ? [Quickshell.env("HOME") + "/.config/scripts/ocr", geometry]
            : ["sh", "-c",
                "mkdir -p ~/Pictures/Screenshots && grim " + src + " " + JSON.stringify(file)
                + " && wl-copy --type image/png < " + JSON.stringify(file)
                + " && notify-send -i " + JSON.stringify(file) + " 'Screenshot saved' " + JSON.stringify(stamp + ".png")];
        // the overlay is a layer surface and grim captures composited output,
        // so it has to be gone from the screen before the shot fires
        settle.restart();
    }

    Timer {
        id: settle
        interval: 60
        onTriggered: capture.running = true
    }

    Process { id: capture }

    IpcHandler {
        target: "screenshot"

        function region(): void {
            root.start("shot");
        }

        function ocr(): void {
            root.start("ocr");
        }

        function window(): void {
            root.mode = "shot";
            const w = Hyprland.activeToplevel ? Hyprland.activeToplevel.lastIpcObject : null;
            if (w)
                root.shoot(w.at[0] + "," + w.at[1] + " " + w.size[0] + "x" + w.size[1]);
        }

        function output(): void {
            root.mode = "shot";
            if (Hyprland.focusedMonitor)
                root.shoot("", Hyprland.focusedMonitor.name);
        }

        // the overlay takes an exclusive keyboard grab, so it needs a way out
        // that does not depend on the overlay itself still answering keys
        function cancel(): void {
            root.cancel();
        }
    }

    Variants {
        model: root.active ? Quickshell.screens : []

        PanelWindow {
            id: overlay

            required property var modelData

            screen: modelData
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell-screenshot"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            readonly property real lx: root.selX - modelData.x
            readonly property real ly: root.selY - modelData.y

            Image {
                anchors.fill: parent
                // the query string defeats the image cache between two shots
                source: "file://" + root.freezeDir + "/" + modelData.name + ".ppm?" + root.frozenAt
                cache: false
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                focus: true

                Keys.onEscapePressed: root.cancel()

                onPressed: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        root.cancel();
                        return;
                    }
                    root.px = root.x0 = root.x1 = overlay.modelData.x + mouse.x;
                    root.py = root.y0 = root.y1 = overlay.modelData.y + mouse.y;
                    root.dragging = true;
                }
                onPositionChanged: mouse => {
                    root.px = overlay.modelData.x + mouse.x;
                    root.py = overlay.modelData.y + mouse.y;
                    if (!root.dragging)
                        return;
                    root.x1 = root.px;
                    root.y1 = root.py;
                }
                onReleased: mouse => {
                    if (mouse.button === Qt.LeftButton && root.dragging)
                        root.grab();
                }
            }

            // four panes around the selection instead of one dim layer over it,
            // so the region reads at its true brightness while you drag
            component Dim: Rectangle {
                color: "#000000"
                opacity: 0.45
            }

            Dim {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: root.dragging ? Math.max(0, overlay.ly) : parent.height
            }

            Dim {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: root.dragging
                height: Math.max(0, parent.height - overlay.ly - root.selH)
            }

            Dim {
                anchors.left: parent.left
                visible: root.dragging
                y: overlay.ly
                height: root.selH
                width: Math.max(0, overlay.lx)
            }

            Dim {
                anchors.right: parent.right
                visible: root.dragging
                y: overlay.ly
                height: root.selH
                width: Math.max(0, parent.width - overlay.lx - root.selW)
            }

            Rectangle {
                visible: root.dragging
                x: overlay.lx
                y: overlay.ly
                width: root.selW
                height: root.selH
                color: "transparent"
                border.width: 1
                border.color: root.accent
            }

            // the window a click would take
            Rectangle {
                visible: !root.dragging && root.hovered !== null
                x: root.hovered ? root.hovered.at[0] - overlay.modelData.x : 0
                y: root.hovered ? root.hovered.at[1] - overlay.modelData.y : 0
                width: root.hovered ? root.hovered.size[0] : 0
                height: root.hovered ? root.hovered.size[1] : 0
                radius: 10
                color: Qt.alpha(root.accent, 0.08)
                border.width: 2
                border.color: root.accent
            }

            Rectangle {
                visible: root.dragging && root.selW > 0
                x: overlay.lx
                y: overlay.ly - 24 >= 0 ? overlay.ly - 24 : overlay.ly + root.selH + 4
                width: size.implicitWidth + 12
                height: 20
                radius: 6
                color: Theme.bg

                Label {
                    id: size
                    anchors.centerIn: parent
                    text: root.selW + " × " + root.selH
                    color: root.accent
                    font.pixelSize: 12
                    font.bold: true
                }
            }

        }
    }
}
