import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import "elements"
import "interfaces"

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(350, 500)
    color: palette.base
    // Test hook: exposes the ControllerManagerInterface so tests can drive
    // transitions without having to synthesize right-clicks on delegates.
    property alias controllerManagerInterface: d.controllerManager

    Component.onCompleted: {
        if (context.enabled === undefined)
            context.enabled = true;
        d.refresh();
    }

    enum State {
        Unknown = 0,
        Unconfigured = 1,
        Inactive = 2,
        Active = 3,
        Finalized = 4
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: 4
        columns: 3

        Label {
            text: "Controller Manager"
        }

        ComboBox {
            id: controllerManagerComboBox
            objectName: "cmComboBox"
            Layout.fillWidth: true
            model: d.controllerManagers

            onCurrentValueChanged: {
                if (!currentValue || currentValue === context.controller_manager_namespace)
                    return;
                context.controller_manager_namespace = currentValue;
            }
        }

        RefreshButton {
            objectName: "cmRefreshButton"
            onClicked: {
                animate = true;
                d.refresh();
                animate = false;
            }
        }

        LoadingListView {
            id: controllerListView
            objectName: "cmControllerList"
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.preferredHeight: 240
            Layout.fillHeight: true
            isLoading: d.controllerManager.loading
            model: d.controllerManager.controllers
            spacing: 8
            header: ListHeader {
                text: "Controllers"
            }
            headerPositioning: ListView.OverlayHeader

            delegate: MouseArea { // With Qt 6.9 ContextMenu could be used, but not available before
                width: controllerListView.width
                height: 48
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        contextMenu.popup();
                    }
                }
                onPressAndHold: mouse => {
                    if (mouse.source === Qt.MouseEventNotSynthesized) {
                        contextMenu.popup();
                    }
                }
                property var controller: model

                Menu {
                    id: contextMenu
                    width: {
                        let result = 0;
                        let padding = 0;
                        for (let i = 0; i < count; ++i) {
                            let item = itemAt(i);
                            result = Math.max(item.contentItem.implicitWidth, result);
                            padding = Math.max(item.padding, padding);
                        }
                        return result + padding * 2;
                    }
                    Instantiator {
                        model: d.getTransitionsForControllerState(controller.state)

                        delegate: MenuItem {
                            text: modelData.name
                            onTriggered: {
                                d.controllerManager.transitionController(controller.name, modelData.actions);
                            }
                        }
                        onObjectAdded: (index, object) => contextMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => contextMenu.removeItem(object)
                    }
                    MenuSeparator {}
                    Action {
                        text: qsTr("Show Info")
                        onTriggered: {
                            controllerInfoDialog.openControllerInfo(controller);
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: controllerListView.ScrollBar.vertical.visible ? controllerListView.ScrollBar.vertical.width : 0

                    StateIndicator {
                        Layout.margins: 4
                        Layout.alignment: Qt.AlignVCenter
                        state: model.state
                    }

                    Label {
                        Layout.fillWidth: true
                        text: model.name
                    }

                    Label {
                        Layout.margins: 8
                        text: model.state
                    }

                    Button {
                        Layout.margins: 4
                        implicitWidth: 40
                        implicitHeight: parent.height - 8
                        text: "..."
                        onClicked: contextMenu.popup()
                    }
                }
            }
        }

        LoadingListView {
            id: hardwareComponentsListView
            objectName: "cmHardwareList"
            Layout.columnSpan: 3
            Layout.preferredHeight: 120
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 8
            isLoading: d.controllerManager.loading
            model: d.controllerManager.hardwareComponents
            spacing: 8
            header: ListHeader {
                text: "Hardware Components"
                z: 2
            }
            headerPositioning: ListView.OverlayHeader

            delegate: MouseArea { // With Qt 6.9 ContextMenu could be used, but not available before
                width: hardwareComponentsListView.width
                height: 48
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        contextMenu.popup();
                    }
                }
                onPressAndHold: mouse => {
                    if (mouse.source === Qt.MouseEventNotSynthesized) {
                        contextMenu.popup();
                    }
                }
                property var hardwareComponent: model

                Menu {
                    id: contextMenu
                    width: {
                        let result = 0;
                        let padding = 0;
                        for (let i = 0; i < count; ++i) {
                            let item = itemAt(i);
                            result = Math.max(item.contentItem.implicitWidth, result);
                            padding = Math.max(item.padding, padding);
                        }
                        return result + padding * 2;
                    }
                    Instantiator {
                        model: d.getTransitionsForHardwareComponentState(hardwareComponent.state.label)

                        delegate: MenuItem {
                            text: modelData.name
                            onTriggered: {
                                d.controllerManager.transitionHardwareComponent(hardwareComponent.name, modelData.target_state);
                            }
                        }
                        onObjectAdded: (index, object) => contextMenu.insertItem(index, object)
                        onObjectRemoved: (index, object) => contextMenu.removeItem(object)
                    }
                    MenuSeparator {}
                    Action {
                        text: qsTr("Show Info")
                        onTriggered: {
                            hardwareComponentInfoDialog.openHardwareComponentInfo(hardwareComponent);
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.rightMargin: hardwareComponentsListView.ScrollBar.vertical.visible ? hardwareComponentsListView.ScrollBar.vertical.width : 0

                    StateIndicator {
                        Layout.margins: 4
                        Layout.alignment: Qt.AlignVCenter
                        state: model.state.label
                    }
                    Label {
                        Layout.fillWidth: true
                        text: model.name
                    }

                    Label {
                        Layout.margins: 8
                        text: model.state.label
                    }

                    Button {
                        Layout.margins: 4
                        implicitWidth: 40
                        implicitHeight: parent.height - 8
                        text: "..."
                        onClicked: contextMenu.popup()
                    }
                }
            }
        }
    }

    ControllerInfoDialog {
        id: controllerInfoDialog
        objectName: "cmControllerInfoDialog"
    }


    HardwareComponentInfoDialog {
        id: hardwareComponentInfoDialog
        objectName: "cmHardwareComponentInfoDialog"
    }

    QtObject {
        id: d
        property var controllerManagers: []
        property var trajectoryClient: null
        property var controllerManager: ControllerManagerInterface {
            controllerManager: context.controller_manager_namespace || ""
        }

        function refresh() {
            const prevControllerManager = context.controller_manager_namespace;

            const services = Ros2.queryServices("controller_manager_msgs/srv/ListControllers");
            let controllerManagers = prevControllerManager ? [prevControllerManager] : [];
            for (let i = 0; i < services.length; i++) {
                const parts = services[i].split("/");
                parts.pop(); // remove service name
                const ns = parts.join("/");
                if (controllerManagers.indexOf(ns) === -1) {
                    controllerManagers.push(ns);
                }
            }
            // Remove empty entries
            controllerManagers = controllerManagers.filter(function (e) {
                return e;
            });
            controllerManagers.sort();
            d.controllerManagers = [];
            d.controllerManagers = controllerManagers;

            if (prevControllerManager) {
                const index = d.controllerManagers.indexOf(prevControllerManager);
                controllerManagerComboBox.currentIndex = Math.max(0, index);
                d.controllerManager.refresh();
            }
        }

        function getTransitionsForControllerState(state) {
            const transitions = {
                "active": [
                    {
                        name: "Deactivate (inactive)",
                        actions: ["deactivate"]
                    },
                    {
                        name: "Deactivate and Unload (unloaded)",
                        actions: ["deactivate", "unload"]
                    }
                ],
                "inactive": [
                    {
                        name: "Activate (active)",
                        actions: ["activate"]
                    },
                    {
                        name: "Unload and Load (unconfigured)",
                        actions: ["unload", "load"]
                    },
                    {
                        name: "Unload (unloaded)",
                        actions: ["unload"]
                    }
                ],
                "unconfigured": [
                    {
                        name: "Configure and Activate (active)",
                        actions: ["configure", "activate"]
                    },
                    {
                        name: "Configure (inactive)",
                        actions: ["configure"]
                    },
                    {
                        name: "Unload (unloaded)",
                        actions: ["unload"]
                    }
                ],
                "unloaded": [
                    {
                        name: "Load (unconfigured)",
                        actions: ["load"]
                    }
                ]
            };
            return transitions[state] || [];
        }

        function getTransitionsForHardwareComponentState(state) {
            const transitions = {
                "active": [
                    {
                        name: "Deactivate (inactive)",
                        target_state: {
                            id: State.Inactive,
                            label: "inactive"
                        }
                    },
                    {
                        name: "Deactivate and Cleanup (unconfigured)",
                        target_state: {
                            id: State.Unconfigured,
                            label: "unconfigured"
                        }
                    },
                ],
                "inactive": [
                    {
                        name: "Activate (active)",
                        target_state: {
                            id: State.Active,
                            label: "active"
                        }
                    },
                    {
                        name: "Cleanup (unconfigured)",
                        target_state: {
                            id: State.Unconfigured,
                            label: "unconfigured"
                        }
                    },
                ],
                "unconfigured": [
                    {
                        name: "Configure and Activate (active)",
                        target_state: {
                            id: State.Active,
                            label: "active"
                        }
                    },
                    {
                        name: "Configure (inactive)",
                        target_state: {
                            id: State.Inactive,
                            label: "inactive"
                        }
                    },
                ]
            };
            return transitions[state] || [];
        }
    }
}
