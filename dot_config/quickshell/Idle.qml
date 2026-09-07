import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    signal lockRequested

    // a player without its own inhibitor (music, a background tab) still holds the screen
    readonly property bool playing: Mpris.players.values.some(p => p.isPlaying)

    IdleMonitor {
        timeout: 1800
        enabled: !root.playing
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) root.lockRequested()
    }

    IdleMonitor {
        timeout: 2100
        enabled: !root.playing
        respectInhibitors: true
        onIsIdleChanged: Hyprland.dispatch(isIdle ? "dpms off" : "dpms on")
    }
}
