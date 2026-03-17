import QtQuick.Controls
import RQml.Fonts

RoundButton {
    implicitWidth: 48
    implicitHeight: 48
    property string tooltipText
    font.family: IconFont.name
    font.pixelSize: 20
    radius: 4

    ToolTip.visible: !!tooltipText && hovered
    ToolTip.text: tooltipText
    ToolTip.delay: 500
}
