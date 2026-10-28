import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import "../interfaces"

/**
 * Lists lifecycle nodes with their states and triggers transitions from each row's menu.
 */
ColumnLayout {
    id: root

    //! ToastManager that shows failed transitions.
    property var toasts

    /**
     * Rediscovers the lifecycle nodes.
     */
    function refresh() {
        iface.refresh();
    }

    spacing: 4

    // Each refresh queries every node's state, so graph changes are combined generously.
    RefreshTrigger {
        active: root.visible
        interval: 5000

        onTriggered: root.refresh()
    }
    LifecycleInterface {
        id: iface
        onTransitionFailed: (node, label) => root.toasts.show(qsTr("Failed to %1 %2").arg(label).arg(node), "error")
    }
    QtObject {
        id: d

        readonly property bool anyMatch: {
            for (let i = 0; i < iface.nodes.count; ++i) {
                if (matches(iface.nodes.get(i).name))
                    return true;
            }
            return false;
        }

        function matches(name) {
            return name.toLowerCase().includes(searchBar.text);
        }
        function requestTransition(node, transition) {
            if (!transition.label.includes("shutdown")) {
                iface.triggerTransition(node, transition);
                return;
            }
            shutdownDialog.node = node;
            shutdownDialog.transition = transition;
            shutdownDialog.open();
        }
    }
    Dialog {
        id: shutdownDialog

        property string node
        property var transition

        anchors.centerIn: Overlay.overlay
        modal: true
        objectName: "nmShutdownDialog"
        standardButtons: Dialog.Yes | Dialog.No
        title: qsTr("Shut Down Node")
        width: Overlay.overlay ? Math.min(400, Overlay.overlay.width - 32) : 400

        onAccepted: iface.triggerTransition(shutdownDialog.node, shutdownDialog.transition)

        Label {
            text: qsTr("Shut down %1?").arg(shutdownDialog.node)
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 4

        SearchBar {
            id: searchBar
            Layout.fillWidth: true
            objectName: "nmLifecycleSearchBar"
            placeholderText: qsTr("Filter lifecycle nodes...")
            showNavigation: false
        }
        RefreshButton {
            Accessible.name: qsTr("Refresh states")
            objectName: "nmLifecycleRefreshButton"

            onClicked: {
                animate = true;
                iface.refreshStates();
                animate = false;
            }
        }
    }
    StackLayout {
        Layout.fillHeight: true
        Layout.fillWidth: true
        currentIndex: d.anyMatch ? 1 : 0

        Hint {
            horizontalAlignment: Text.AlignHCenter
            objectName: "nmLifecycleHint"
            text: iface.nodes.count === 0 ? qsTr("No lifecycle nodes found.") : qsTr("No lifecycle nodes match the filter.")
            verticalAlignment: Text.AlignVCenter
        }
        LoadingListView {
            id: nodeList
            model: iface.nodes
            objectName: "nmLifecycleList"

            delegate: Item {
                id: row

                readonly property bool matches: d.matches(row.model.name)
                required property var model

                height: matches ? rowLayout.implicitHeight : 0
                visible: matches
                width: nodeList.width

                ContextMenuArea {
                    id: contextMenu
                    objectName: "nmLifecycleContextMenu"

                    menu.onAboutToShow: iface.selectNode(row.model.name)

                    Instantiator {
                        model: iface.selectedNode === row.model.name ? iface.availableTransitions : []

                        delegate: MenuItem {
                            required property var modelData

                            enabled: !row.model.pending
                            text: modelData.label.charAt(0).toUpperCase() + modelData.label.slice(1)

                            onTriggered: d.requestTransition(row.model.name, modelData)
                        }

                        onObjectAdded: (index, object) => contextMenu.menu.insertItem(index, object)
                        onObjectRemoved: (index, object) => contextMenu.menu.removeItem(object)
                    }
                    MenuSeparator {
                    }
                    MenuItem {
                        text: qsTr("Copy Node Name")

                        onTriggered: RQml.copyTextToClipboard(row.model.name)
                    }
                }
                RowLayout {
                    id: rowLayout
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: parent.right
                    anchors.rightMargin: nodeList.ScrollBar.vertical.visible ? nodeList.ScrollBar.vertical.width : 4

                    StateIndicator {
                        Layout.preferredHeight: 16
                        Layout.preferredWidth: 16
                        state: row.model.state
                    }
                    TruncatedLabel {
                        Layout.fillWidth: true
                        elide: Text.ElideMiddle
                        text: row.model.name
                    }
                    Caption {
                        text: row.model.state
                    }
                    BusyIndicator {
                        Layout.preferredHeight: 16
                        Layout.preferredWidth: 16
                        objectName: "nmLifecycleBusyIndicator"
                        running: row.model.pending !== ""
                        visible: running
                    }
                    Button {
                        id: menuButton
                        Accessible.name: qsTr("Transitions of %1").arg(row.model.name)
                        Layout.preferredWidth: 40
                        objectName: "nmLifecycleMenuButton"
                        text: "..."

                        onClicked: contextMenu.menu.popup(menuButton, 0, menuButton.height)
                    }
                }
            }
        }
    }
}
