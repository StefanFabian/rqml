import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import "elements"
import "interfaces"

Rectangle {
    id: root
    enum State {
        Unknown,
        Unconfigured,
        Inactive,
        Active,
        Finalized
    }

    // Test hook: exposes the ControllerManagerInterface so tests can drive
    // transitions without having to synthesize right-clicks on delegates.
    property alias controllerManagerInterface: d.controllerManager
    property var kddockwidgets_min_size: Qt.size(350, 500)

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
        if (context.enabled === undefined)
            context.enabled = true;
        if (context.switch_strictness === undefined)
            context.switch_strictness = ControllerManagerInterface.Strictness.Auto;
        if (context.activate_asap === undefined)
            context.activate_asap = false;
        if (context.switch_timeout === undefined)
            context.switch_timeout = 0;
        d.refresh();
    }

    GridLayout {
        anchors.fill: parent
        anchors.margins: 4
        columns: 4

        Label {
            text: "Controller Manager"
        }
        ComboBox {
            id: controllerManagerComboBox
            Layout.fillWidth: true
            model: d.controllerManagers
            objectName: "cmComboBox"

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
        IconButton {
            objectName: "cmSettingsButton"
            text: IconFont.iconSettings
            tooltipText: qsTr("Settings")

            onClicked: settingsDialog.open()
        }
        LoadingListView {
            id: controllerListView
            Layout.columnSpan: 4
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredHeight: 240
            headerPositioning: ListView.OverlayHeader
            isLoading: d.controllerManager.loading
            model: d.controllerManager.controllers
            objectName: "cmControllerList"
            spacing: 8

            delegate: MouseArea {
                property var controller: model

                acceptedButtons: Qt.LeftButton | Qt.RightButton
                height: 48 // With Qt 6.9 ContextMenu could be used, but not available before
                width: controllerListView.width

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

                Menu {
                    id: contextMenu
                    objectName: "cmControllerContextMenu"
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
                    MenuSeparator {
                    }
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
                        Layout.alignment: Qt.AlignVCenter
                        Layout.margins: 4
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
                        implicitHeight: parent.height - 8
                        implicitWidth: 40
                        text: "..."

                        onClicked: contextMenu.popup()
                    }
                }
            }
            header: ListHeader {
                text: "Controllers"
            }
        }
        LoadingListView {
            id: hardwareComponentsListView
            Layout.columnSpan: 4
            Layout.fillHeight: true
            Layout.fillWidth: true
            Layout.preferredHeight: 120
            Layout.topMargin: 8
            headerPositioning: ListView.OverlayHeader
            isLoading: d.controllerManager.loading
            model: d.controllerManager.hardwareComponents
            objectName: "cmHardwareList"
            spacing: 8

            delegate: MouseArea {
                property var hardwareComponent: model

                acceptedButtons: Qt.LeftButton | Qt.RightButton
                height: 48 // With Qt 6.9 ContextMenu could be used, but not available before
                width: hardwareComponentsListView.width

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

                Menu {
                    id: contextMenu
                    objectName: "cmHardwareContextMenu"
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
                    MenuSeparator {
                    }
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
                        Layout.alignment: Qt.AlignVCenter
                        Layout.margins: 4
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
                        implicitHeight: parent.height - 8
                        implicitWidth: 40
                        text: "..."

                        onClicked: contextMenu.popup()
                    }
                }
            }
            header: ListHeader {
                text: "Hardware Components"
                z: 2
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
    ControllerManagerSettingsDialog {
        id: settingsDialog
        objectName: "cmSettingsDialog"
        settings: context
    }
    ToastManager {
        id: toastManager
        objectName: "cmToastManager"
        z: 100
    }
    QtObject {
        id: d

        property var controllerManager: ControllerManagerInterface {
            activateAsap: context.activate_asap ?? false
            controllerManager: context.controller_manager_namespace || ""
            strictness: context.switch_strictness ?? ControllerManagerInterface.Strictness.Auto
            switchTimeout: context.switch_timeout ?? 0

            onControllerTransitionFailed: (name, action, message) => {
                toastManager.show(d.controllerFailureMessage(action, name, message), "error");
            }
            onControllerTransitionSucceeded: (name, action, message) => {
                // The message of a switch_controller call names the controllers
                // the controller manager (de)activated on its own, which is the
                // whole point of the AUTO and FORCE_AUTO strictness modes.
                toastManager.show(d.controllerSuccessMessage(action, name, message), "success");
            }
            onHardwareTransitionFailed: (name, targetLabel, currentLabel, currentId) => {
                toastManager.show(d.hardwareFailureMessage(name, targetLabel, currentLabel, currentId), "error");
            }
            onHardwareTransitionSucceeded: (name, targetLabel) => {
                toastManager.show(qsTr("%1 is now %2").arg(name).arg(targetLabel), "success");
            }
        }
        property var controllerManagers: []
        property var trajectoryClient: null

        // The transition messages are spelled out per action instead of being
        // composed from a verb and a sentence frame so that translators get a
        // complete sentence. %1 is the controller, %2 the message reported by
        // the controller manager.
        function controllerFailureMessage(action, name, message) {
            switch (action) {
            case "activate":
                return message ? qsTr("Failed to activate %1: %2").arg(name).arg(message) : qsTr("Failed to activate %1").arg(name);
            case "deactivate":
                return message ? qsTr("Failed to deactivate %1: %2").arg(name).arg(message) : qsTr("Failed to deactivate %1").arg(name);
            case "configure":
                return message ? qsTr("Failed to configure %1: %2").arg(name).arg(message) : qsTr("Failed to configure %1").arg(name);
            case "load":
                return message ? qsTr("Failed to load %1: %2").arg(name).arg(message) : qsTr("Failed to load %1").arg(name);
            case "unload":
                return message ? qsTr("Failed to unload %1: %2").arg(name).arg(message) : qsTr("Failed to unload %1").arg(name);
            }
            return message ? qsTr("Failed to transition %1: %2").arg(name).arg(message) : qsTr("Failed to transition %1").arg(name);
        }
        function controllerSuccessMessage(action, name, message) {
            switch (action) {
            case "activate":
                return message ? qsTr("Activated %1: %2").arg(name).arg(message) : qsTr("Activated %1").arg(name);
            case "deactivate":
                return message ? qsTr("Deactivated %1: %2").arg(name).arg(message) : qsTr("Deactivated %1").arg(name);
            case "configure":
                return message ? qsTr("Configured %1: %2").arg(name).arg(message) : qsTr("Configured %1").arg(name);
            case "load":
                return message ? qsTr("Loaded %1: %2").arg(name).arg(message) : qsTr("Loaded %1").arg(name);
            case "unload":
                return message ? qsTr("Unloaded %1: %2").arg(name).arg(message) : qsTr("Unloaded %1").arg(name);
            }
            return message ? qsTr("Transitioned %1: %2").arg(name).arg(message) : qsTr("Transitioned %1").arg(name);
        }
        function getTransitionsForControllerState(state) {
            const transitions = {
                "active": [{
                        "name": "Deactivate (inactive)",
                        "actions": ["deactivate"]
                    }, {
                        "name": "Deactivate and Unload (unloaded)",
                        "actions": ["deactivate", "unload"]
                    }],
                "inactive": [{
                        "name": "Activate (active)",
                        "actions": ["activate"]
                    }, {
                        "name": "Unload and Load (unconfigured)",
                        "actions": ["unload", "load"]
                    }, {
                        "name": "Unload (unloaded)",
                        "actions": ["unload"]
                    }],
                "unconfigured": [{
                        "name": "Configure and Activate (active)",
                        "actions": ["configure", "activate"]
                    }, {
                        "name": "Configure (inactive)",
                        "actions": ["configure"]
                    }, {
                        "name": "Unload (unloaded)",
                        "actions": ["unload"]
                    }],
                "unloaded": [{
                        "name": "Load (unconfigured)",
                        "actions": ["load"]
                    }]
            };
            return transitions[state] || [];
        }
        function getTransitionsForHardwareComponentState(state) {
            const transitions = {
                "active": [{
                        "name": "Deactivate (inactive)",
                        "target_state": {
                            "id": ControllerManager.State.Inactive,
                            "label": "inactive"
                        }
                    }, {
                        "name": "Deactivate and Cleanup (unconfigured)",
                        "target_state": {
                            "id": ControllerManager.State.Unconfigured,
                            "label": "unconfigured"
                        }
                    },],
                "inactive": [{
                        "name": "Activate (active)",
                        "target_state": {
                            "id": ControllerManager.State.Active,
                            "label": "active"
                        }
                    }, {
                        "name": "Cleanup (unconfigured)",
                        "target_state": {
                            "id": ControllerManager.State.Unconfigured,
                            "label": "unconfigured"
                        }
                    },],
                "unconfigured": [{
                        "name": "Configure and Activate (active)",
                        "target_state": {
                            "id": ControllerManager.State.Active,
                            "label": "active"
                        }
                    }, {
                        "name": "Configure (inactive)",
                        "target_state": {
                            "id": ControllerManager.State.Inactive,
                            "label": "inactive"
                        }
                    },]
            };
            return transitions[state] || [];
        }

        // A component that refuses a transition may not report a label, the
        // numeric lifecycle state id is always there.
        function hardwareFailureMessage(name, targetLabel, currentLabel, currentId) {
            return currentLabel ? qsTr("Failed to set %1 to %2, it is now %3 (%4)").arg(name).arg(targetLabel).arg(currentLabel).arg(currentId) : qsTr("Failed to set %1 to %2, it is now in state %3").arg(name).arg(targetLabel).arg(currentId);
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
    }
}
