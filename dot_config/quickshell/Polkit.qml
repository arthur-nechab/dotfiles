import Quickshell
import Quickshell.Services.Polkit
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    PolkitAgent {
        id: agent
    }

    PanelWindow {
        id: dialog

        readonly property var flow: agent.flow

        screen: Theme.mainScreen
        color: "transparent"
        visible: agent.isActive
        implicitWidth: 460
        implicitHeight: 220
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-polkit"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        onVisibleChanged: if (visible) pw.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.alpha(Theme.bg, 0.97)

            Behavior on color {
                ColorAnimation { duration: 300 }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 12

                Label {
                    text: "Authentication required"
                    color: Theme.fg
                    font.pixelSize: 16
                    font.bold: true
                }

                Label {
                    width: parent.width
                    text: dialog.flow ? dialog.flow.message : ""
                    color: Theme.gray
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                }

                // the polkit action behind the request, the only origin polkit exposes
                Label {
                    width: parent.width
                    visible: text !== ""
                    text: dialog.flow ? dialog.flow.actionId : ""
                    color: Theme.gray
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Rectangle {
                    width: parent.width
                    height: 40
                    radius: 10
                    color: Theme.surface

                    TextInput {
                        id: pw
                        anchors.fill: parent
                        anchors.margins: 12
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: dialog.flow && dialog.flow.responseVisible ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "●"
                        color: Theme.fg
                        font.family: Theme.uiFont
                        font.pixelSize: 15

                        Keys.onReturnPressed: dialog.send()
                        Keys.onEnterPressed: dialog.send()
                        Keys.onEscapePressed: dialog.cancel()
                    }
                }

                Label {
                    width: parent.width
                    visible: text !== ""
                    text: dialog.flow ? dialog.flow.supplementaryMessage : ""
                    color: dialog.flow && dialog.flow.supplementaryIsError ? Theme.red : Theme.gray
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }

                Row {
                    anchors.right: parent.right
                    spacing: 10

                    MouseArea {
                        width: 90
                        height: 30
                        onClicked: dialog.cancel()

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: Theme.surface
                        }

                        Label {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.gray
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }

                    MouseArea {
                        width: 110
                        height: 30
                        onClicked: dialog.send()

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: Theme.surface
                        }

                        Label {
                            anchors.centerIn: parent
                            text: "Authenticate"
                            color: Theme.yellow
                            font.pixelSize: 13
                            font.bold: true
                        }
                    }
                }
            }
        }

        function send() {
            if (!flow)
                return;
            flow.submit(pw.text);
            pw.text = "";
        }

        function cancel() {
            if (flow)
                flow.cancelAuthenticationRequest();
            pw.text = "";
        }
    }
}
