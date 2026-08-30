import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Notifications
import QtQuick

Scope {
    id: root

    property var popups: []
    // arrival time by id; the server keeps no timestamp
    property var seen: ({})
    // pushed left when a right-anchored panel is open, so popups never overlap it
    property int shiftRight: 0
    // do not disturb: still tracked, just never shown as a popup
    property bool dnd: false

    // keyboard cursor over the grouped rows, shown only once the arrows moved
    property int sel: 0
    property bool navigating: false

    function toggle() {
        center.visible = !center.visible;
        if (center.visible) {
            sel = 0;
            navigating = false;
            centerKeys.forceActiveFocus();
        }
    }

    function clear() {
        for (const n of server.trackedNotifications.values.slice())
            n.dismiss();
        root.popups = [];
    }

    function drop(id) {
        root.popups = root.popups.filter(n => n.id !== id);
    }

    NotificationServer {
        id: server

        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyImagesSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        inlineReplySupported: true
        persistenceSupported: true

        onNotification: n => {
            n.tracked = true;
            const m = Object.assign({}, root.seen);
            m[n.id] = Date.now();
            root.seen = m;
            if (root.dnd)
                return;
            root.popups = [n].concat(root.popups.filter(p => p.id !== n.id)).slice(0, 5);
        }
    }

    // ── Popups ───────────────────────────────────────────────────────────

    PanelWindow {
        screen: Theme.mainScreen
        color: "transparent"
        // the history opens at the same corner, so popups yield to it
        visible: root.popups.length > 0 && !center.visible
        implicitWidth: 400
        implicitHeight: Math.max(1, stack.implicitHeight)
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notifications"

        anchors {
            top: true
            right: true
        }

        margins {
            top: 57
            right: 20 + root.shiftRight
        }

        Column {
            id: stack
            width: parent.width
            spacing: 8

            Repeater {
                model: root.popups

                Rectangle {
                    required property var modelData

                    width: stack.width
                    implicitHeight: Math.max(64, content.implicitHeight + 20)
                    radius: 12
                    color: Qt.alpha(Theme.bg, 0.95)

                    Behavior on color {
                        ColorAnimation { duration: 300 }
                    }
                    border.width: modelData.urgency === NotificationUrgency.Critical ? 2 : 0
                    border.color: Theme.red

                    Timer {
                        interval: modelData.urgency === NotificationUrgency.Critical
                            ? 15000
                            : (modelData.expireTimeout > 0 ? modelData.expireTimeout : 5000)
                        // reading time: the countdown restarts once the pointer leaves
                        running: !popArea.containsMouse
                        onTriggered: root.drop(modelData.id)
                    }

                    MouseArea {
                        id: popArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton) {
                                modelData.dismiss();
                                root.drop(modelData.id);
                                return;
                            }
                            if (modelData.actions.length > 0)
                                modelData.actions[0].invoke();
                            root.drop(modelData.id);
                        }
                    }

                    Row {
                        id: content
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 12

                        ClippingRectangle {
                            id: popArt

                            readonly property bool hasArt: modelData.image !== "" || modelData.appIcon !== ""

                            anchors.verticalCenter: parent.verticalCenter
                            width: 32
                            height: 32
                            radius: 8
                            color: hasArt ? "transparent" : Qt.alpha(Theme.gray, 0.15)

                            IconImage {
                                anchors.fill: parent
                                visible: popArt.hasArt
                                source: modelData.image !== "" ? modelData.image : Quickshell.iconPath(modelData.appIcon, "")
                            }

                            Label {
                                anchors.centerIn: parent
                                visible: !popArt.hasArt
                                text: "\u{f009a}"
                                color: Theme.gray
                                font.pixelSize: 16
                            }
                        }

                        Column {
                            width: parent.width - 56
                            spacing: 2

                            Label {
                                width: parent.width
                                text: modelData.summary
                                color: Theme.fg
                                font.pixelSize: 14
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Label {
                                width: parent.width
                                visible: text !== ""
                                text: modelData.body
                                color: Theme.gray
                                font.pixelSize: 12
                                textFormat: Text.MarkdownText
                                wrapMode: Text.Wrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                            }

                            Row {
                                spacing: 6
                                visible: modelData.actions.length > 0

                                Repeater {
                                    model: modelData.actions

                                    MouseArea {
                                        required property var modelData

                                        implicitWidth: actionLabel.implicitWidth + 18
                                        implicitHeight: 24
                                        onClicked: modelData.invoke()

                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 8
                                            color: Theme.surface
                                        }

                                        Label {
                                            id: actionLabel
                                            anchors.centerIn: parent
                                            text: modelData.text
                                            color: Theme.yellow
                                            font.pixelSize: 11
                                            font.bold: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── History ──────────────────────────────────────────────────────────

    // identical summaries from the same app fold into one row, newest on top
    readonly property var grouped: {
        const groups = [];
        const byKey = {};
        for (const n of server.trackedNotifications.values.slice().reverse()) {
            const key = n.appName + "\u0000" + n.summary;
            if (byKey[key]) {
                byKey[key].count += 1;
                byKey[key].all.push(n);
                continue;
            }
            byKey[key] = { n: n, count: 1, all: [n] };
            groups.push(byKey[key]);
        }
        return groups;
    }

    function age(id) {
        ageTick.tick;
        const t = root.seen[id];
        if (!t)
            return "";
        const m = Math.round((Date.now() - t) / 60000);
        if (m < 1)
            return "now";
        if (m < 60)
            return m + " min";
        return Math.round(m / 60) + " h";
    }

    Timer {
        id: ageTick
        property int tick: 0
        interval: 30000
        running: center.visible
        repeat: true
        onTriggered: tick += 1
    }

    PanelWindow {
        id: center

        screen: Theme.mainScreen
        color: "transparent"
        visible: false
        implicitWidth: 420
        // hug the list, up to a screen-friendly cap
        implicitHeight: Math.min(640, 72 + Math.max(24, list.contentHeight))
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell-notification-center"
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        anchors {
            top: true
            right: true
        }

        margins {
            top: 57
            right: 20
        }

        ClickAway {
            target: center
            screen: center.screen
        }

        Item {
            id: centerKeys

            anchors.fill: parent
            focus: center.visible

            function move(d) {
                if (root.grouped.length === 0)
                    return;
                root.navigating = true;
                root.sel = Math.max(0, Math.min(root.grouped.length - 1, root.sel + d));
                list.positionViewAtIndex(root.sel, ListView.Contain);
            }

            function current() {
                return root.grouped[root.sel] ?? null;
            }

            Keys.onEscapePressed: center.visible = false
            Keys.onUpPressed: move(-1)
            Keys.onDownPressed: move(1)
            Keys.onReturnPressed: {
                const g = current();
                if (!g)
                    return;
                if (g.n.actions.length > 0)
                    g.n.actions[0].invoke();
                for (const x of g.all)
                    x.dismiss();
            }
            Keys.onDeletePressed: {
                const g = current();
                if (g)
                    for (const x of g.all)
                        x.dismiss();
                root.sel = Math.min(root.sel, Math.max(0, root.grouped.length - 1));
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.alpha(Theme.bg, 0.95)

            Behavior on color {
                ColorAnimation { duration: 300 }
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Item {
                    width: parent.width
                    height: 24

                    Label {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications"
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Label {
                        anchors.left: parent.left
                        anchors.leftMargin: 122
                        anchors.verticalCenter: parent.verticalCenter
                        visible: server.trackedNotifications.values.length > 0
                        text: server.trackedNotifications.values.length
                        color: Theme.gray
                        font.pixelSize: 13
                        font.bold: true
                    }

                    MouseArea {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 28
                        height: 24
                        visible: server.trackedNotifications.values.length > 0
                        hoverEnabled: true
                        onClicked: root.clear()

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                            color: parent.containsMouse ? Theme.surface : "transparent"
                        }

                        Label {
                            anchors.centerIn: parent
                            text: "\u{f0a7a}"
                            color: parent.containsMouse ? Theme.red : Theme.gray
                            font.pixelSize: 16
                        }
                    }
                }

                Label {
                    visible: server.trackedNotifications.values.length === 0
                    text: "No notifications"
                    color: Theme.gray
                    font.pixelSize: 13
                }

                ListView {
                    id: list
                    width: parent.width
                    height: parent.height - 34
                    clip: true
                    spacing: 6
                    model: root.grouped
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: MouseArea {
                        id: row

                        required property var modelData
                        required property int index
                        readonly property bool selected: root.navigating && root.sel === index
                        readonly property var n: modelData.n
                        readonly property bool hasArt: n.image !== "" || n.appIcon !== ""

                        width: ListView.view.width
                        height: Math.max(56, histRow.implicitHeight + 16)
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // left runs the default action, right just drops the entry
                        onClicked: mouse => {
                            if (mouse.button === Qt.LeftButton && row.n.actions.length > 0)
                                row.n.actions[0].invoke();
                            for (const x of modelData.all)
                                x.dismiss();
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: row.containsMouse ? Qt.alpha(Theme.surface, 0.7) : Theme.surface
                            border.width: row.selected ? 1 : 0
                            border.color: Theme.gray
                        }

                        Row {
                            id: histRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 10

                            // an image thumbnail, the app icon, or a plain bell
                            ClippingRectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 36
                                height: 36
                                radius: 8
                                color: row.hasArt ? "transparent" : Qt.alpha(Theme.gray, 0.15)

                                IconImage {
                                    anchors.fill: parent
                                    visible: row.hasArt
                                    source: row.n.image !== ""
                                        ? row.n.image
                                        : Quickshell.iconPath(row.n.appIcon, "")
                                }

                                Label {
                                    anchors.centerIn: parent
                                    visible: !row.hasArt
                                    text: "\u{f009a}"
                                    color: Theme.gray
                                    font.pixelSize: 17
                                }
                            }

                            Column {
                                width: parent.width - 46
                                spacing: 2

                                Item {
                                    width: parent.width
                                    height: 16

                                    Label {
                                        anchors.left: parent.left
                                        anchors.right: meta.left
                                        anchors.rightMargin: 8
                                        text: row.n.summary
                                        font.pixelSize: 13
                                        font.bold: true
                                        elide: Text.ElideRight
                                    }

                                    Label {
                                        id: meta
                                        anchors.right: parent.right
                                        // the fold count goes first, it is the news
                                        leftPadding: 0
                                        // the shell's own scripts notify through notify-send: no app to name
                                        text: [modelData.count > 1 ? "\u00d7" + modelData.count : "",
                                               row.n.appName === "notify-send" ? "" : row.n.appName,
                                               root.age(row.n.id)].filter(x => x !== "").join(" \u00b7 ")
                                        color: Theme.gray
                                        font.pixelSize: 11
                                    }
                                }

                                Label {
                                    width: parent.width
                                    visible: text !== ""
                                    text: row.n.body
                                    color: Theme.gray
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 30
                                    radius: 8
                                    color: Theme.bg
                                    visible: row.n.hasInlineReply

                                    TextInput {
                                        id: reply
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        color: Theme.fg
                                        font.family: Theme.uiFont
                                        font.pixelSize: 12
                                        clip: true

                                        Keys.onReturnPressed: send()
                                        Keys.onEnterPressed: send()

                                        function send() {
                                            if (text === "")
                                                return;
                                            row.n.sendInlineReply(text);
                                            text = "";
                                            root.drop(row.n.id);
                                        }

                                        Label {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: reply.text === ""
                                            text: row.n.inlineReplyPlaceholder !== ""
                                                ? row.n.inlineReplyPlaceholder
                                                : "Reply"
                                            color: Theme.gray
                                            font: reply.font
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"

        function toggle(): void {
            root.toggle();
        }

        function dnd(): void {
            root.dnd = !root.dnd;
        }

        function clear(): void {
            root.clear();
        }
    }
}
