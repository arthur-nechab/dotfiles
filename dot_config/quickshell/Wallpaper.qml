import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    property string path: ""

    FileView {
        id: current
        path: Quickshell.env("HOME") + "/.cache/hypr/current-wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.path = text().trim()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: wall

            required property var modelData

            screen: modelData
            color: "#000000"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell-wallpaper"

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // two layers: the next image loads underneath, then fades over the
            // current one, so a change never shows as a cut
            component Layer: Image {
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                // decode at screen size: qt refuses any image over 256 MB once
                // expanded to rgba, and a 75 megapixel jpeg clears that alone
                sourceSize.width: modelData.width
                sourceSize.height: modelData.height

                Behavior on opacity {
                    NumberAnimation { duration: 400; easing.type: Easing.InOutQuad }
                }
            }

            // which layer is on screen; the other one takes the next file
            property bool showA: true

            Layer {
                id: layerA
                opacity: wall.showA ? 1 : 0
                onStatusChanged: if (status === Image.Ready && !wall.showA) wall.showA = true
            }

            Layer {
                id: layerB
                opacity: wall.showA ? 0 : 1
                onStatusChanged: if (status === Image.Ready && wall.showA) wall.showA = false
            }

            // the hidden layer takes the new file and comes up once it is decoded;
            // a second change before that lands in the same hidden layer
            Connections {
                target: root
                function onPathChanged() {
                    const src = root.path === "" ? "" : "file://" + root.path;
                    if (layerA.source == "" && layerB.source == "") {
                        layerA.source = src;
                        return;
                    }
                    const hidden = wall.showA ? layerB : layerA;
                    // going back to the previous file: it is still decoded there, no status change comes
                    if (hidden.source == src) {
                        wall.showA = !wall.showA;
                        return;
                    }
                    hidden.source = src;
                }
            }
        }
    }

    // ── Palette picked from the wallpaper ────────────────────────────────

    // the script classifies the image and copies themes/<name>.json into the
    // cache file Theme watches, then restyles every app it knows
    Process {
        id: theming
        command: [Quickshell.env("HOME") + "/.config/scripts/theme-from-wallpaper"]
    }

    onPathChanged: if (root.path !== "") theming.running = true

    IpcHandler {
        target: "theme"

        function refresh(): void {
            Quickshell.execDetached([Quickshell.env("HOME") + "/.config/scripts/theme-from-wallpaper", "--force"]);
        }
    }
}
