pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property color bg:      palette.bg
    readonly property color surface: palette.surface
    readonly property color fg:      palette.fg
    // the palette gray, lightened toward fg until it reads at 4.5:1 on bg and surface, whatever the wallpaper gave
    readonly property color gray:    readable(palette.gray)
    readonly property color red:     palette.red
    readonly property color green:   palette.green
    readonly property color yellow:  palette.yellow
    readonly property color blue:    palette.blue
    readonly property color purple:  palette.purple
    readonly property color aqua:    palette.aqua
    readonly property color orange:  palette.orange
    readonly property real opacity:   palette.opacity
    // data-dense panels sit over text: opaque enough that nothing ghosts through
    readonly property real panelAlpha: 0.99

    function luminance(c) {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }

    function contrast(a, b) {
        const x = luminance(a), y = luminance(b);
        return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    }

    // palette values are strings: parse before reading r, g and b
    function readable(s) {
        const c = Qt.color(s), bgc = Qt.color(palette.bg), sf = Qt.color(palette.surface), top = Qt.color(palette.fg);
        for (let t = 0; t <= 1; t += 0.05) {
            const m = Qt.rgba(c.r + (top.r - c.r) * t, c.g + (top.g - c.g) * t, c.b + (top.b - c.b) * t, 1);
            if (contrast(m, bgc) >= 4.5 && contrast(m, sf) >= 4.5)
                return m;
        }
        return top;
    }

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
        // read before the first frame, so the bar never flashes the built-in palette
        blockLoading: true
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
