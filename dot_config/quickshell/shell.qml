import Quickshell
import QtQuick

ShellRoot {
    Wallpaper {}

    Bar {
        id: bar

        dnd: notifications.dnd

        onNotificationsToggle: notifications.toggle()
        onDndToggle: notifications.dnd = !notifications.dnd
        onAudioToggle: controlCenter.toggle("audio")
        onBluetoothToggle: controlCenter.toggle("bluetooth")
        onNetworkToggle: controlCenter.toggle("network")
        onClipboardToggle: clipboard.toggle()
        onNightlightChanged: (temp, warm) => osd.showTemp(temp, warm)
        onMediaToggle: mediaPanel.toggle()
        onHomelabToggle: homelabPanel.toggle()
    }

    Osd {
        id: osd
    }

    // keyboard-driven states get the same notice as a volume change
    Connections {
        target: notifications
        function onDndChanged() {
            osd.showText(notifications.dnd ? "\u{f009b}" : "\u{f009a}",
                         notifications.dnd ? "Do Not Disturb on" : "Do Not Disturb off", Theme.gray);
        }
    }

    Connections {
        target: bar
        // only the end: a notice at the start would land in the video
        function onRecordingChanged() {
            if (!bar.recording)
                osd.showText("\u25cf", "Screen recording saved", Theme.red);
        }
    }

    SecondaryBar {
        dnd: notifications.dnd
    }
    Launcher {}
    Clipboard { id: clipboard }
    Screenshot {}
    Polkit {}
    WallpaperPicker {}
    MediaPanel { id: mediaPanel }
    HomelabPanel { id: homelabPanel }
    ControlCenter { id: controlCenter }

    Notifications {
        id: notifications

        shiftRight: controlCenter.visible ? controlCenter.width + 10 : 0
    }

    Lock {
        id: lock
    }

    SessionMenu {
        onLockRequested: lock.lock()
    }

    Idle {
        id: idle

        onLockRequested: lock.lock()
    }
}
