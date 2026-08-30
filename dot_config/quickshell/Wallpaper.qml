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

            property bool bOnTop: false

            Layer {
                id: layerA
                opacity: 1
                onStatusChanged: if (status === Image.Ready && !wall.bOnTop && layerB.opacity === 1) wall.swap()
            }

            Layer {
                id: layerB
                opacity: 0
                onStatusChanged: if (status === Image.Ready && wall.bOnTop && layerA.opacity === 1) wall.swap()
            }

            function swap() {
                layerA.opacity = bOnTop ? 0 : 1;
                layerB.opacity = bOnTop ? 1 : 0;
            }

            // the hidden layer takes the new file; the swap runs once it is decoded
            Connections {
                target: root
                function onPathChanged() {
                    const src = root.path === "" ? "" : "file://" + root.path;
                    if (layerA.source == "" && layerB.source == "") {
                        layerA.source = src;
                        return;
                    }
                    wall.bOnTop = layerA.opacity === 1;
                    (wall.bOnTop ? layerB : layerA).source = src;
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
