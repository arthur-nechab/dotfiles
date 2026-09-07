import Quickshell
import QtQuick
import QtQuick.Controls

// the month under the clock; the bar owns the ipc that drives it
PopupWindow {
    id: calendar

    // the bar button the popup hangs from, and the bar's side and screen
    required property Item anchorItem
    property bool atTop: true
    property var clickScreen: null

    anchor.item: calendar.anchorItem
    anchor.edges: calendar.atTop ? Edges.Bottom : Edges.Top
    anchor.gravity: calendar.atTop ? Edges.Bottom : Edges.Top
    anchor.margins.top: 7
    implicitWidth: 260
    implicitHeight: calContent.implicitHeight + 45
    color: "transparent"
    visible: false

    // one month step, drawn like the bar's buttons
    component Arrow: MouseArea {
        property string glyph: ""

        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 24
        hoverEnabled: true

        Rectangle {
            anchors.fill: parent
            radius: 8
            color: parent.containsMouse ? Theme.surface : "transparent"
        }

        Label {
            anchors.centerIn: parent
            text: parent.glyph
            color: Theme.gray
            font.pixelSize: 15
            font.bold: true
        }
    }

    ClickAway {
        target: calendar
        screen: calendar.clickScreen
    }

    property string selected: Qt.formatDate(Theme.now, "yyyy-MM-dd")
    // the month on display; the arrows move it, opening comes back to today
    property int shownMonth: Theme.now.getMonth()
    property int shownYear: Theme.now.getFullYear()

    function shift(d) {
        const t = new Date(shownYear, shownMonth + d, 1);
        shownMonth = t.getMonth();
        shownYear = t.getFullYear();
    }

    onVisibleChanged: {
        if (!visible)
            return;
        selected = Qt.formatDate(Theme.now, "yyyy-MM-dd");
        shownMonth = Theme.now.getMonth();
        shownYear = Theme.now.getFullYear();
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 10
        radius: 10
        color: Theme.bg

        Column {
            id: calContent

            anchors.centerIn: parent
            spacing: 4

            Item {
                width: 224
                height: 24

                Arrow {
                    anchors.left: parent.left
                    glyph: "\u{f0141}"
                    onClicked: calendar.shift(-1)
                }

                Label {
                    anchors.centerIn: parent
                    text: Qt.formatDate(new Date(calendar.shownYear, calendar.shownMonth, 1), "MMMM yyyy")
                    color: Theme.yellow
                    font.pixelSize: 14
                    font.bold: true
                }

                Arrow {
                    anchors.right: parent.right
                    glyph: "\u{f0142}"
                    onClicked: calendar.shift(1)
                }
            }

            DayOfWeekRow {
                width: 224
                locale: Qt.locale()
                delegate: Label {
                    text: model.shortName
                    color: Theme.gray
                    font.pixelSize: 12
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            MonthGrid {

                width: 224
                height: 170
                month: calendar.shownMonth
                year: calendar.shownYear
                locale: Qt.locale()
                onClicked: date => calendar.selected = Qt.formatDate(date, "yyyy-MM-dd")

                delegate: Item {
                    required property var model

                    readonly property string day: Qt.formatDate(model.date, "yyyy-MM-dd")

                    Rectangle {
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        radius: 6
                        visible: parent.day === calendar.selected
                        color: Theme.surface
                    }

                    Label {
                        anchors.centerIn: parent
                        text: model.day
                        color: model.today ? Theme.red : (model.month === calendar.shownMonth ? Theme.fg : Theme.gray)
                        opacity: model.month === calendar.shownMonth ? 1 : 0.4
                        font.pixelSize: 14
                        font.bold: true
                    }

                }
            }
        }
    }
}
