import QtQuick

// a search field over a keyboard-driven list: the launcher and the clipboard
// share it, each brings its own row content
Item {
    id: root

    property string icon: ""
    property color iconColor: Theme.yellow
    property string placeholder: ""
    property var model: []
    property int selected: 0
    // (entry) => height, for rows that carry an image
    property var rowHeight: entry => 44
    // instantiated per row with `entry` and `index` in scope
    property Component row: null
    // space kept under the list, for a preview
    property int footer: 0

    readonly property alias query: input.text
    readonly property alias list: list

    signal accepted
    signal dismissed
    // keys the field does not handle; set event.accepted to consume
    signal keyPressed(var event)

    function reset() {
        input.text = "";
        selected = 0;
        input.forceActiveFocus();
    }

    function jump(index) {
        if (model.length === 0)
            return;
        selected = Math.max(0, Math.min(model.length - 1, index));
        list.positionViewAtIndex(selected, ListView.Contain);
    }

    function move(delta) {
        jump(selected + delta);
    }

    Column {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        Rectangle {
            width: parent.width
            height: 40
            radius: 10
            color: Theme.surface

            Row {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.icon
                    color: root.iconColor
                    font.pixelSize: 16
                    font.bold: true
                }

                TextInput {
                    id: input
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40
                    color: Theme.fg
                    font.family: Theme.uiFont
                    font.pixelSize: 15
                    font.bold: true
                    selectByMouse: true
                    selectionColor: root.iconColor
                    onTextChanged: root.selected = 0

                    Keys.onEscapePressed: root.dismissed()
                    Keys.onReturnPressed: root.accepted()
                    Keys.onEnterPressed: root.accepted()
                    Keys.onDownPressed: root.move(1)
                    Keys.onUpPressed: root.move(-1)
                    Keys.onPressed: event => {
                        // eight rows fit, so a page is eight
                        if (event.key === Qt.Key_PageDown)
                            root.move(8);
                        else if (event.key === Qt.Key_PageUp)
                            root.move(-8);
                        else if (event.key === Qt.Key_Home)
                            root.jump(0);
                        else if (event.key === Qt.Key_End)
                            root.jump(root.model.length - 1);
                        else {
                            root.keyPressed(event);
                            return;
                        }
                        event.accepted = true;
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === ""
                        text: root.placeholder
                        color: Theme.gray
                        font: input.font
                    }
                }
            }
        }

        ListView {
            id: list
            width: parent.width
            height: parent.height - 52 - root.footer
            clip: true
            model: root.model
            currentIndex: root.selected
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds

            delegate: MouseArea {
                id: rowArea

                required property int index
                required property var modelData

                width: list.width
                height: root.rowHeight(modelData)
                hoverEnabled: true
                // a real mouse move, not the list scrolling under a resting pointer
                onPositionChanged: root.selected = index
                onClicked: {
                    root.selected = index;
                    root.accepted();
                }

                Rectangle {
                    anchors.fill: parent
                    anchors.rightMargin: 4
                    radius: 8
                    color: rowArea.index === root.selected ? Theme.surface : "transparent"
                    border.width: rowArea.index === root.selected ? 1 : 0
                    border.color: Theme.gray

                    // an accent edge, readable whatever the theme contrast
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        visible: rowArea.index === root.selected
                        width: 3
                        height: parent.height - 14
                        radius: 2
                        color: Theme.yellow
                    }
                }

                Loader {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 14
                    // a row outlives its entry for a frame when the model changes
                    active: rowArea.modelData !== null && rowArea.modelData !== undefined
                    sourceComponent: root.row
                    property var entry: rowArea.modelData
                    property int index: rowArea.index
                }
            }
        }
    }
}
