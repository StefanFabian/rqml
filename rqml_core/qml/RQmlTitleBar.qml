import QtQuick
import QtQuick.Controls
import RQml.Elements
import RQml.Fonts
import "qrc:/kddockwidgets/qtquick/views/qml" as KDDW

// Title bar that follows the application theme and highlights when its plugin is the selected
// (focused) one, so the user can see which plugin Ctrl+W would close.
KDDW.TitleBarBase {
    id: root

    readonly property bool highlighted: {
        // Floating window title bars report window activation without notifying, so re-read on change.
        Window.active;
        return titleBarCpp && titleBarCpp.isFocused;
    }

    // TitleBarBase is a plain Rectangle without a palette, so use the theme palette of the title label.
    readonly property var themePalette: titleLabel.palette

    color: highlighted ? Qt.tint(themePalette.window, Qt.rgba(themePalette.highlight.r, themePalette.highlight.g, themePalette.highlight.b, 0.35)) : themePalette.window

    Label {
        id: titleLabel

        elide: Text.ElideRight
        text: root.title

        anchors {
            left: parent.left
            leftMargin: 5
            right: buttons.left
            verticalCenter: parent.verticalCenter
        }
    }
    Row {
        id: buttons

        spacing: 2

        anchors {
            right: parent.right
            rightMargin: 2
            verticalCenter: parent.verticalCenter
        }
        TitleBarButton {
            text: IconFont.iconWindowMinimize
            tooltipText: qsTr("Minimize")
            visible: root.minimizeButtonVisible

            onClicked: root.minimizeButtonClicked()
        }
        TitleBarButton {
            text: IconFont.iconFloat
            tooltipText: qsTr("Float")
            visible: root.floatButtonVisible

            onClicked: root.floatButtonClicked()
        }
        TitleBarButton {
            text: root.maximizeUsesRestoreIcon ? IconFont.iconWindowRestore : IconFont.iconWindowMaximize
            tooltipText: root.maximizeUsesRestoreIcon ? qsTr("Restore") : qsTr("Maximize")
            visible: root.maximizeButtonVisible

            onClicked: root.maximizeButtonClicked()
        }
        TitleBarButton {
            enabled: root.closeButtonEnabled
            text: IconFont.iconClose
            tooltipText: qsTr("Close")

            onClicked: root.closeButtonClicked()
        }
    }
    Rectangle {
        color: root.themePalette.highlight
        height: 2
        visible: root.highlighted

        anchors {
            bottom: parent.bottom
            left: parent.left
            right: parent.right
        }
    }

    component TitleBarButton: IconButton {
        bottomInset: 0
        flat: true
        focusPolicy: Qt.NoFocus
        font.pixelSize: 12
        implicitHeight: 24
        leftInset: 0
        padding: 0
        rightInset: 0
        topInset: 0
    }
}
