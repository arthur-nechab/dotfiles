import QtQuick

// Text in the shell font; colour and size stay with the caller
Text {
    color: Theme.fg
    font.family: Theme.uiFont

    // a theme change slides instead of cutting
    Behavior on color {
        ColorAnimation { duration: 300 }
    }
}
