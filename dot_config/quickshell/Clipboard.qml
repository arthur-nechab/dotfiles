import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

PanelWindow {
    id: board

    property var entries: []
    // clipse entries as stored on disk, the source of every edit
    property var raw: []
    property bool pinnedOnly: false

    readonly property var results: {
        const q = search.query.trim().toLowerCase();
        let l = pinnedOnly ? entries.filter(e => e.pinned) : entries;
        if (q !== "")
            l = l.filter(e => e.value.toLowerCase().includes(q));
        return l.slice(0, 100);
    }

    readonly property var current: results[search.selected] ?? null

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: 620
    implicitHeight: 580
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function open() {
        pinnedOnly = false;
        history.reload();
        visible = true;
        search.reset();
    }

    function close() {
        visible = false;
    }

    function toggle() {
        visible ? close() : open();
    }

    function run() {
        const r = current;
        if (!r)
            return;
        close();
        if (r.image) {
            paste.command = ["sh", "-c", "wl-copy --type image/png < " + JSON.stringify(r.path)];
            paste.running = true;
        } else {
            Quickshell.clipboardText = r.value;
        }
    }

    Process { id: paste }

    // clipse keeps its history in a json file; edits go straight into it
    function same(e, r) {
        return (e.recorded ?? "").slice(0, 16) === r.recorded && (e.value ?? "") === r.value;
    }

    function rewrite(change) {
        const r = current;
        if (!r)
            return;
        const list = change(raw, r);
        history.setText(JSON.stringify({ clipboardHistory: list }, null, 2));
        // setText lands on disk later; feed the list now instead of rereading a stale file
        load(list);
        search.jump(search.selected);
    }

    function remove() {
        rewrite((list, r) => list.filter(e => !same(e, r)));
    }

    function togglePin() {
        rewrite((list, r) => list.map(e => same(e, r) ? Object.assign({}, e, { pinned: !r.pinned }) : e));
    }

    FileView {
        id: history
        path: Quickshell.env("HOME") + "/.config/clipse/clipboard_history.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let list = [];
            try {
                list = JSON.parse(text()).clipboardHistory ?? [];
            } catch (e) {
            }
            load(list);
        }
    }

    function load(list) {
        raw = list;
        const out = [];
        for (const e of list) {
            // clipse writes the string "null", not a json null, for text entries
            const img = e.filePath !== undefined && e.filePath !== "null";
            out.push({
                value: e.value ?? "",
                image: img,
                path: img ? e.filePath : "",
                pinned: e.pinned === true,
                recorded: (e.recorded ?? "").slice(0, 16)
            });
        }
        // pins first, clipse already stores the rest newest first
        board.entries = out.filter(e => e.pinned).concat(out.filter(e => !e.pinned));
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            board.toggle();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: Qt.alpha(Theme.bg, 0.95)

        Behavior on color {
            ColorAnimation { duration: 300 }
        }

        SearchList {
            id: search

            anchors.fill: parent
            icon: board.pinnedOnly ? "\u{f0403}" : "\u{f0192}"
            iconColor: board.pinnedOnly ? Theme.yellow : Theme.green
            placeholder: board.pinnedOnly ? "Search pinned items" : "Search clipboard  ·  Tab pinned, Ctrl+P pin, Del remove"
            model: board.results
            rowHeight: e => e.image ? 68 : 44
            footer: 112
            onAccepted: board.run()
            onDismissed: board.close()
            onKeyPressed: event => {
                if (event.key === Qt.Key_Tab)
                    board.pinnedOnly = !board.pinnedOnly;
                else if (event.key === Qt.Key_Delete)
                    board.remove();
                else if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier))
                    board.togglePin();
                else
                    return;
                event.accepted = true;
            }

            row: Row {
                spacing: 12

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: entry.image
                    source: entry.image ? "file://" + entry.path : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    width: visible ? 76 : 0
                    height: 56
                    sourceSize.height: 112
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !entry.image
                    text: entry.pinned ? "\u{f0403}" : "\u{f0219}"
                    color: entry.pinned ? Theme.yellow : Theme.gray
                    font.pixelSize: 15
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (entry.image ? 100 : 40)
                    spacing: 1

                    Label {
                        width: parent.width
                        // newlines would let one entry eat the whole row
                        text: entry.value.replace(/\s+/g, " ").trim()
                        font.pixelSize: 14
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    Label {
                        width: parent.width
                        text: entry.recorded
                        color: Theme.gray
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // the selected entry in full, where one line was not enough
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 14
            height: 100
            radius: 10
            color: Theme.surface

            Behavior on color {
                ColorAnimation { duration: 300 }
            }

            Label {
                anchors.fill: parent
                anchors.margins: 10
                visible: board.current !== null && !board.current.image
                text: board.current && !board.current.image ? board.current.value : ""
                font.pixelSize: 12
                wrapMode: Text.Wrap
                maximumLineCount: 5
                elide: Text.ElideRight
            }

            Image {
                anchors.fill: parent
                anchors.margins: 6
                visible: board.current !== null && board.current.image
                source: board.current && board.current.image ? "file://" + board.current.path : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.height: 200
            }
        }
    }
}
