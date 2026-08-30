import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: picker

    property var scanned: []
    // filename -> theme, written by theme-from-wallpaper
    property var themes: ({})
    // grouped by theme, then by name, so the grid reads as palettes
    readonly property var files: scanned
        .map(p => ({ path: p, name: p.split("/").pop().replace(/\.[^.]+$/, ""),
                     theme: (themes[p.split("/").pop()] ?? {}).theme ?? "" }))
        .sort((a, b) => a.theme.localeCompare(b.theme) || a.name.localeCompare(b.name))


    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: 1468
    implicitHeight: 740
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-wallpaper-picker"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function toggle() {
        visible = !visible;
        if (visible) {
            index.reload();
            scan.running = false;
            scan.running = true;
            grid.forceActiveFocus();
        }
    }

    function apply(i) {
        const file = files[i];
        if (!file)
            return;
        chosen.setText(file.path + "\n");
        visible = false;
    }

    Process {
        id: scan
        command: ["find", Quickshell.env("HOME") + "/Pictures/Wallpapers", "-maxdepth", "1", "-type", "f", "(",
                  "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png", "-o", "-iname", "*.webp", ")"]
        stdout: StdioCollector {
            onStreamFinished: {
                picker.scanned = this.text.split("\n").filter(l => l !== "");
                const cur = chosen.text().trim();
                const at = picker.files.findIndex(f => f.path === cur);
                grid.currentIndex = at >= 0 ? at : 0;
            }
        }
    }

    FileView {
        id: index
        path: Quickshell.env("HOME") + "/.cache/wallpaper-themes.json"
        printErrors: false
        onLoaded: {
            try {
                picker.themes = JSON.parse(text());
            } catch (e) {
                picker.themes = {};
            }
        }
    }

    FileView {
        id: chosen
        path: Quickshell.env("HOME") + "/.cache/hypr/current-wallpaper"
        preload: true
        printErrors: false
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            picker.toggle();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.95)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        GridView {
            id: grid

            focus: true
            anchors.fill: parent
            anchors.margins: 14
            clip: true
            cellWidth: 288
            cellHeight: 178
            model: picker.files
            boundsBehavior: Flickable.StopAtBounds

            Keys.onEscapePressed: picker.visible = false
            Keys.onReturnPressed: picker.apply(grid.currentIndex)
            Keys.onEnterPressed: picker.apply(grid.currentIndex)

            delegate: MouseArea {
                required property var modelData

                required property int index

                width: 280
                height: 170
                hoverEnabled: true
                onPositionChanged: grid.currentIndex = index
                onClicked: picker.apply(index)

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Theme.surface
                    border.width: index === grid.currentIndex ? 2 : 0
                    border.color: Theme.yellow

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "file://" + modelData.path
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 560
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 3
                    height: 26
                    color: Qt.rgba(0, 0, 0, 0.6)

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name
                        color: "#ffffff"
                        font.pixelSize: 12
                        font.bold: true
                    }
                }
            }
        }
    }
}
