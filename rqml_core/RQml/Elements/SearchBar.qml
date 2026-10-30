import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Fonts

/**
 * Reusable search bar with embedded search icon, clear button, and prev/next navigation.
 * The search text is debounced before being exposed via the `text` property.
 */
RowLayout {
    id: root

    //! Debounce interval in milliseconds
    property int debounceInterval: 200

    //! Placeholder text for the input field
    property string placeholderText: "Search..."

    //! Whether the search text field currently has active focus
    readonly property bool searchFocused: textField.activeFocus

    //! Whether to show prev/next navigation buttons
    property bool showNavigation: true

    //! Debounced, lowercased search text for consumers to filter against
    readonly property string text: internal.debouncedText

    signal nextRequested
    signal previousRequested

    function clear() {
        textField.text = "";
        commitSearchText();
    }
    function commitSearchText() {
        internal.debouncedText = textField.text.toLowerCase();
    }
    function focusSearch() {
        textField.forceActiveFocus();
    }

    spacing: 4

    QtObject {
        id: internal

        property string debouncedText: ""
    }
    TextField {
        id: textField

        Layout.fillWidth: true
        leftPadding: searchIcon.width + 12
        objectName: "searchBarTextField"
        placeholderText: root.placeholderText
        rightPadding: clearButton.visible ? clearButton.width + 8 : 8

        Keys.onEscapePressed: root.clear()
        Keys.onReturnPressed: event => {
            debounceTimer.stop();
            root.commitSearchText();
            if (event.modifiers & Qt.ShiftModifier)
                root.previousRequested();
            else
                root.nextRequested();
        }
        onTextChanged: debounceTimer.restart()

        Label {
            id: searchIcon

            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.top: parent.top
            font.family: IconFont.name
            font.pixelSize: 12
            opacity: 0.5
            text: IconFont.iconSearch
            verticalAlignment: Qt.AlignVCenter
        }
        Label {
            id: clearButton

            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            font.family: IconFont.name
            font.pixelSize: 10
            opacity: clearArea.containsMouse ? 1.0 : 0.5
            text: IconFont.iconClose
            visible: textField.text !== ""

            MouseArea {
                id: clearArea

                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                hoverEnabled: true

                onClicked: root.clear()
            }
        }
        Timer {
            id: debounceTimer

            interval: root.debounceInterval

            onTriggered: internal.debouncedText = textField.text.toLowerCase()
        }
    }
    IconButton {
        text: IconFont.iconChevronUp
        tooltipText: "Previous match (Shift+Enter)"
        visible: root.showNavigation

        onClicked: root.previousRequested()
    }
    IconButton {
        text: IconFont.iconChevronDown
        tooltipText: "Next match (Enter)"
        visible: root.showNavigation

        onClicked: root.nextRequested()
    }
}
