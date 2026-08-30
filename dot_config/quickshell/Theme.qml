pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property color bg:      palette.bg
    readonly property color surface: palette.surface
    readonly property color fg:      palette.fg
    readonly property color gray:    palette.gray
    readonly property color red:     palette.red
    readonly property color green:   palette.green
    readonly property color yellow:  palette.yellow
    readonly property color blue:    palette.blue
    readonly property color purple:  palette.purple
    readonly property color aqua:    palette.aqua
    readonly property color orange:  palette.orange
    readonly property real opacity:   palette.opacity

    // monitor the panels live on; substring match, no serial in a public repo
    readonly property string mainModel: "M28U"
    readonly property var mainScreen: Quickshell.screens.find(s => s.model.includes(mainModel)) ?? Quickshell.screens[0]

    readonly property string uiFont: "Inter"

    // the one clock every bar and the lock screen read
    readonly property date now: clock.date

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }
    readonly property string monoFont: "BerkeleyMono Nerd Font"

    FileView {
        path: Quickshell.env("HOME") + "/.cache/quickshell-theme.json"
        watchChanges: true
        onFileChanged: reload()

        adapter: JsonAdapter {
            id: palette
            property string bg: "#1d2021"
            property string surface: "#3c3836"
            property string fg: "#ebdbb2"
            property string gray: "#928374"
            property string red: "#fb4934"
            property string green: "#b8bb26"
            property string yellow: "#fabd2f"
            property string blue: "#83a598"
            property string purple: "#d3869b"
            property string aqua: "#8ec07c"
            property string orange: "#fe8019"
            property real opacity: 0.8
        }
    }
}
