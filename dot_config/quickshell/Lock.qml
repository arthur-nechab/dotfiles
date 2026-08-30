import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    WlSessionLock {
        id: session

        locked: false

        surface: WlSessionLockSurface {
            id: surface

            color: "transparent"

            Image {
                anchors.fill: parent
                source: root.wallpaper === "" ? "" : "file://" + root.wallpaper
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: surface.width
                sourceSize.height: surface.height
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.55)
            }

            Column {
                anchors.centerIn: parent
                spacing: 24

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(Theme.now, "HH:mm")
                    color: "#ffffff"
                    font.pixelSize: 96
                    font.bold: true
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(Theme.now, "dddd d MMMM")
                    color: "#cccccc"
                    font.pixelSize: 20
                    font.bold: true
                }

                Rectangle {
                    id: box

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: 0
                    width: 340
                    height: 46
                    radius: 12
                    color: Qt.rgba(0, 0, 0, 0.5)

                    SequentialAnimation {
                        id: shake
                        loops: 3
                        NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 10; duration: 40 }
                        NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: -10; duration: 80 }
                        NumberAnimation { target: box; property: "anchors.horizontalCenterOffset"; to: 0; duration: 40 }
                    }

                    Connections {
                        target: root
                        function onCleared() { shake.restart(); }
                    }
                    border.width: 2
                    border.color: pam.messageIsError ? Theme.red : Qt.rgba(1, 1, 1, 0.25)

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        color: "#ffffff"
                        font.family: Theme.uiFont
                        font.pixelSize: 16
                        enabled: !pam.active || pam.responseRequired
                        focus: true

                        Component.onCompleted: forceActiveFocus()

                        // the compositor sends keys to the screen under the pointer; mirror the text everywhere
                        onTextChanged: root.typed = text

                        Keys.onReturnPressed: root.submit(text)
                        Keys.onEnterPressed: root.submit(text)
                        Keys.onPressed: event => { if (event.key === Qt.Key_CapsLock) root.capsLock = !root.capsLock; }

                        Connections {
                            target: root
                            function onTypedChanged() {
                                field.text = root.typed;
                            }
                            function onCleared() {
                                field.forceActiveFocus();
                            }
                        }
                    }
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: root.capsLock
                    text: "\u{f0631}  Caps Lock is on"
                    color: Theme.orange
                    font.pixelSize: 13
                    font.bold: true
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 340
                    horizontalAlignment: Text.AlignHCenter
                    text: root.status
                    color: pam.messageIsError ? Theme.red : "#cccccc"
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    signal cleared

    property string status: ""
    // seeded from hyprland at lock time, then followed key by key
    property bool capsLock: false

    property string wallpaper: ""

    FileView {
        path: Quickshell.env("HOME") + "/.cache/hypr/current-wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.wallpaper = text().trim()
    }

    PamContext {
        id: pam

        config: "hyprlock"
        configDirectory: "/etc/pam.d"

        onPamMessage: {
            root.status = message;
            if (responseRequired && pendingPassword !== "") {
                respond(pendingPassword);
                pendingPassword = "";
            }
        }

        onCompleted: result => {
            if (result === PamResult.Success) {
                root.status = "";
                session.locked = false;
            } else {
                root.status = "Incorrect password";
                root.typed = "";
                root.cleared();
            }
        }

        onError: err => {
            root.status = "Authentication error: " + err;
            root.typed = "";
            root.cleared();
        }
    }

    property string pendingPassword: ""
    property string typed: ""

    function submit(password) {
        if (password === "")
            return;
        root.status = "Verifying\u2026";
        pendingPassword = password;
        if (!pam.active)
            pam.start();
        else if (pam.responseRequired) {
            pam.respond(password);
            pendingPassword = "";
        }
    }

    function lock() {
        root.status = "";
        root.typed = "";
        capsProbe.running = false;
        capsProbe.running = true;
        session.locked = true;
    }

    Process {
        id: capsProbe
        command: ["sh", "-c", "hyprctl devices -j | jq -r '[.keyboards[] | select(.main) | .capsLock] | any'"]
        stdout: StdioCollector {
            onStreamFinished: root.capsLock = this.text.trim() === "true"
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }
    }
}
