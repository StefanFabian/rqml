import QtQuick
import QtQuick.Controls

/**
 * A small circular indicator with a single letter or short text.
 * Used for status markers, source/target indicators, etc.
 */
Rectangle {
    id: root

    //! The font used for the indicator label (e.g. set font.family for icon fonts)
    property alias font: label.font

    //! The text to display inside the indicator (usually a single letter)
    property alias text: label.text

    //! The color of the text. Defaults to white or black based on the background color's lightness.
    property color textColor: root.color.hslLightness < 0.75 ? "#ffffff" : "#000000"

    //! The tooltip text to show on hover (disabled if empty)
    property string tooltipText: ""

    ToolTip.text: tooltipText
    ToolTip.visible: mouseArea.containsMouse && tooltipText !== ""
    height: 16
    radius: 8
    width: 16

    Label {
        id: label

        anchors.centerIn: parent
        color: root.textColor
        font.bold: true
        font.pixelSize: 10
        horizontalAlignment: Qt.AlignHCenter
    }
    MouseArea {
        id: mouseArea

        anchors.fill: parent
        enabled: tooltipText !== ""
        hoverEnabled: true
    }
}
