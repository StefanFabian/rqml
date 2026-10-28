import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import RQml.Elements
import RQml.Fonts
import "../interfaces"

/**
 * Lists the component containers and the components of the selected one, and loads or unloads components.
 */
ColumnLayout {
    id: root

    //! ToastManager that shows failed operations.
    property var toasts

    /**
     * Rediscovers the containers and re-lists the components of the selected one.
     */
    function refresh() {
        iface.refresh();
    }

    spacing: 4

    // Loaded and unloaded components change the ROS graph. Each refresh queries the selected container.
    RefreshTrigger {
        active: root.visible
        interval: 5000

        onTriggered: root.refresh()
    }
    ContainerInterface {
        id: iface
        onContainersChanged: {
            const persisted = context.selectedContainer;
            // Discovery is incremental, so the persisted container can appear after another one was picked.
            if (iface.containers.includes(persisted) && iface.selectedContainer !== persisted)
                iface.selectContainer(persisted);
            else if (!iface.containers.includes(iface.selectedContainer))
                iface.selectContainer(iface.containers[0] ?? "");
        }
        onOperationFailed: message => root.toasts.show(message, "error")
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.margins: 4

        ComboBox {
            Layout.fillWidth: true
            displayText: iface.selectedContainer || qsTr("No containers found")
            model: iface.containers
            objectName: "nmContainerComboBox"

            // Delayed so it applies after the ComboBox resets its index for a new model.
            Binding on currentIndex  {
                delayed: true
                value: iface.containers.indexOf(iface.selectedContainer)
            }

            onActivated: {
                iface.selectContainer(currentText);
                context.selectedContainer = currentText;
            }
        }
        IconTextButton {
            enabled: iface.selectedContainer !== "" && !iface.loadingComponent
            iconText: IconFont.iconAdd
            objectName: "nmLoadComponentButton"
            text: qsTr("Load...")

            onClicked: loadDialog.openFor(iface.selectedContainer)
        }
    }
    SearchBar {
        id: searchBar
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        objectName: "nmComponentSearchBar"
        placeholderText: qsTr("Filter components...")
        showNavigation: false
    }
    LoadingListView {
        id: componentList
        Layout.fillHeight: true
        Layout.fillWidth: true
        isLoading: iface.loading
        model: iface.components.filter(component => component.fullName.toLowerCase().includes(searchBar.text))
        objectName: "nmComponentList"

        delegate: ItemDelegate {
            required property var modelData
            readonly property bool unloading: iface.isUnloading(iface.selectedContainer, modelData)

            width: ListView.view.width

            contentItem: RowLayout {
                TruncatedLabel {
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                    text: modelData.fullName
                }
                Caption {
                    text: "#" + modelData.uniqueId
                }
                BusyIndicator {
                    Layout.preferredHeight: 24
                    Layout.preferredWidth: 24
                    running: visible
                    visible: unloading
                }
                Button {
                    objectName: "nmUnloadButton"
                    text: qsTr("Unload")
                    visible: !unloading

                    onClicked: {
                        unloadDialog.container = iface.selectedContainer;
                        unloadDialog.component = modelData;
                        unloadDialog.open();
                    }
                }
            }

            ContextMenuArea {
                MenuItem {
                    text: qsTr("Copy Node Name")

                    onTriggered: RQml.copyTextToClipboard(modelData.fullName)
                }
            }
        }

        Hint {
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            objectName: "nmComponentHint"
            text: iface.components.length === 0 ? qsTr("No components loaded.") : qsTr("No components match the filter.")
            verticalAlignment: Text.AlignVCenter
            visible: iface.selectedContainer !== "" && !iface.loading && componentList.count === 0
        }
    }
    Dialog {
        id: unloadDialog

        property var component: ({})
        property string container

        anchors.centerIn: Overlay.overlay
        modal: true
        objectName: "nmUnloadDialog"
        standardButtons: Dialog.Yes | Dialog.No
        title: qsTr("Unload Component")
        // The tab is created before it is in a window, so the overlay can be null.
        width: Overlay.overlay ? Math.min(400, Overlay.overlay.width - 32) : 400

        onAccepted: iface.unloadComponent(container, component)

        Label {
            text: qsTr("Unload %1 from %2?").arg(unloadDialog.component.fullName).arg(unloadDialog.container)
            width: parent.width
            wrapMode: Text.Wrap
        }
    }
    LoadComponentDialog {
        id: loadDialog
        objectName: "nmLoadComponentDialog"

        onLoadRequested: (container, params) => iface.loadComponent(container, params)
    }
}
