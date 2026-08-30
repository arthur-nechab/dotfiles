import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick

PanelWindow {
    id: launcher

    // "apps" | "calc" | "emoji"
    property string mode: "apps"
    property var emojis: []
    property string calcResult: ""

    readonly property var results: {
        const q = search.query.trim().toLowerCase();

        if (mode === "calc")
            return calcResult === "" ? [] : [{ text: calcResult, sub: search.query }];

        if (mode === "emoji") {
            if (q === "")
                return emojis.slice(0, 200);
            const hit = [];
            for (const e of emojis) {
                if (e.name.includes(q) || e.keywords.includes(q)) {
                    hit.push(e);
                    if (hit.length === 200)
                        break;
                }
            }
            return hit;
        }

        const all = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        if (q === "")
            return all.slice().sort((a, b) => a.name.localeCompare(b.name)).slice(0, 50);
        const scored = [];
        for (const e of all) {
            const name = e.name.toLowerCase();
            let score = -1;
            if (name.startsWith(q))
                score = 0;
            else if (name.includes(q))
                score = 1;
            else if ((e.genericName ?? "").toLowerCase().includes(q))
                score = 2;
            else if ((e.keywords ?? []).some(k => k.toLowerCase().includes(q)))
                score = 3;
            else if ((e.comment ?? "").toLowerCase().includes(q))
                score = 4;
            if (score >= 0)
                scored.push({ entry: e, score: score });
        }
        scored.sort((a, b) => a.score - b.score || a.entry.name.localeCompare(b.entry.name));
        return scored.map(x => x.entry).slice(0, 50);
    }

    screen: Theme.mainScreen
    color: "transparent"
    visible: false
    implicitWidth: 600
    implicitHeight: 460
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-launcher"
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    function open(which) {
        mode = which ?? "apps";
        calcResult = "";
        visible = true;
        search.reset();
    }

    function close() {
        visible = false;
    }

    function toggle(which) {
        const target = which ?? "apps";
        if (visible && mode === target)
            close();
        else
            open(target);
    }

    function run() {
        const r = results[search.selected];
        if (!r)
            return;
        close();
        if (mode === "apps")
            r.execute();
        else
            Quickshell.clipboardText = mode === "calc" ? r.text : r.char;
    }

    FileView {
        path: Quickshell.shellDir + "/assets/emoji.tsv"
        preload: true
        printErrors: false
        onLoaded: {
            const out = [];
            for (const line of text().split("\n")) {
                if (line === "")
                    continue;
                const f = line.split("\t");
                out.push({ char: f[0], name: (f[1] ?? "").toLowerCase(), keywords: (f[2] ?? "").toLowerCase() });
            }
            launcher.emojis = out;
        }
    }

    Process {
        id: calc
        command: ["qalc", "-t", search.query]
        stdout: StdioCollector {
            onStreamFinished: launcher.calcResult = this.text.trim()
        }
    }

    Timer {
        id: calcDebounce
        interval: 150
        onTriggered: {
            if (search.query.trim() === "") {
                launcher.calcResult = "";
                return;
            }
            calc.running = false;
            calc.running = true;
        }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            launcher.toggle("apps");
        }

        function calc(): void {
            launcher.toggle("calc");
        }

        function emoji(): void {
            launcher.toggle("emoji");
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
            icon: launcher.mode === "calc" ? "\u{f00ec}" : (launcher.mode === "emoji" ? "\u{f01f5}" : "\u{f0349}")
            placeholder: launcher.mode === "calc"
                ? "Type an expression"
                : (launcher.mode === "emoji" ? "Search emoji" : "Search applications")
            model: launcher.results
            onQueryChanged: if (launcher.mode === "calc") calcDebounce.restart()
            onAccepted: launcher.run()
            onDismissed: launcher.close()

            row: Row {
                spacing: 12

                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    height: 28
                    visible: launcher.mode === "apps"
                    source: launcher.mode === "apps"
                        ? Quickshell.iconPath(entry?.icon ?? "", "application-x-executable")
                        : ""
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: launcher.mode === "emoji"
                    text: launcher.mode === "emoji" ? (entry?.char ?? "") : ""
                    font.pixelSize: 24
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Label {
                        text: (launcher.mode === "calc" ? entry?.text : entry?.name) ?? ""
                        font.pixelSize: launcher.mode === "calc" ? 20 : 14
                        font.bold: true
                    }

                    Label {
                        text: {
                            if (launcher.mode === "apps")
                                return entry?.genericName ?? "";
                            if (launcher.mode === "emoji")
                                return entry?.keywords ?? "";
                            return "Press Enter to copy";
                        }
                        visible: text !== "" && text !== entry?.name
                        color: Theme.gray
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        width: search.list.width - 80
                    }
                }
            }
        }
    }
}
