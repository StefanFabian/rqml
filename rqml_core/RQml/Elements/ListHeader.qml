import QtQuick
import QtQuick.Controls

Item {
    id: control

    property alias text: headerLabel.text
    property color textColor: palette.highlightedText ?? "#ffffff"

    height: 40
    width: parent.width
    z: 2

    Rectangle {
        anchors.bottomMargin: 8
        anchors.fill: parent
        color: palette.highlight ?? "#424242"

        Label {
            id: headerLabel

            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            color: control.textColor
            font.bold: true
        }
    }
}
