import QtQuick.Controls
import QtQuick.Layouts
import RQml.Fonts

Button {
    id: control

    property var iconFont: Qt.font({
        "family": IconFont.name,
        "pixelSize": 12
    })
    property string iconText: ""
    property string tooltipText

    ToolTip.delay: 500
    ToolTip.text: tooltipText
    ToolTip.visible: !!tooltipText && hovered
    implicitWidth: Math.max(implicitHeight, contentItem.implicitWidth + leftPadding + rightPadding)

    contentItem: RowLayout {
        spacing: 8

        Label {
            Layout.alignment: Qt.AlignVCenter
            color: control.palette.buttonText
            font: control.iconFont
            text: control.iconText
            visible: control.iconText !== ""
        }
        Label {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            color: control.palette.buttonText
            text: control.text
            visible: control.text !== ""
        }
    }
}
