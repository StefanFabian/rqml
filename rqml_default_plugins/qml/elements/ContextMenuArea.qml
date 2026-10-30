import QtQuick
import QtQuick.Controls

/**
 * Fills its parent and opens a menu with the declared items on right-click.
 */
MouseArea {
    //! The opened Menu, e.g. to insert items created by an Instantiator.
    readonly property alias menu: menu
    default property alias menuItems: menu.contentData

    acceptedButtons: Qt.RightButton
    anchors.fill: parent

    onClicked: menu.popup()

    Menu {
        id: menu

    }
}
