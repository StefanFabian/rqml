import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import "interfaces"

Rectangle {
    id: root

    property var kddockwidgets_min_size: Qt.size(480, 360)

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
        if (context.enabled === undefined)
            context.enabled = true;
        if (!context.controller_manager_namespace)
            context.controller_manager_namespace = "";
        if (!context.controller)
            context.controller = "";
        if (context.take_shortest_path === null)
            context.take_shortest_path = false;
        //Ros2.getLogger().setLoggerLevel(Ros2LoggerLevel.Debug)
        d.refresh();
    }

    QtObject {
        id: d

        property var controllerManagers: []
        property var trajectoryController: JointTrajectoryControllerInterface {
            controllerManager: context.controller_manager_namespace || ""
            controllerName: context.controller || ""
            takeShortestPath: context.take_shortest_path || false
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
                namespaceCombobox.currentIndex = Math.max(0, index);
                d.trajectoryController.refresh();
            }
        }
    }
    KeyActivationGuard {
        id: keyGuard
    }
    GridLayout {
        anchors.fill: parent
        anchors.margins: 4
        columns: 3

        Label {
            text: "Controller Manager Namespace"
        }
        Label {
            Layout.columnSpan: 2
            text: "Controller"
        }
        ComboBox {
            id: namespaceCombobox
            Layout.fillWidth: true
            model: d.controllerManagers
            objectName: "jtcNamespaceComboBox"

            onCurrentValueChanged: {
                if (!currentValue)
                    return;
                context.controller_manager_namespace = currentValue;
            }
        }
        ComboBox {
            id: controllerComboBox
            Layout.fillWidth: true
            currentIndex: {
                for (let i = 0; i < d.trajectoryController.controllers.count; i++) {
                    let c = d.trajectoryController.controllers.get(i);
                    if (c.name === context.controller)
                        return i;
                }
                return -1;
            }
            model: d.trajectoryController.controllers
            objectName: "jtcControllerComboBox"
            textRole: "name"

            onCurrentTextChanged: {
                if (!currentText)
                    return;
                context.controller = currentText;
            }
        }
        RefreshButton {
            objectName: "jtcRefreshButton"

            onClicked: {
                animate = true;
                d.trajectoryController.refresh();
                animate = false;
            }
        }
        Switch {
            id: shortestPathSwitch
            Layout.columnSpan: 3
            checked: context.take_shortest_path || false
            objectName: "jtcShortestPathSwitch"
            text: "Use shortest path duration for continuous joints"

            onCheckedChanged: context.take_shortest_path = checked
        }
        ListView {
            id: jointListView
            Layout.columnSpan: 3
            Layout.fillHeight: true
            Layout.fillWidth: true
            clip: true
            model: d.trajectoryController.joints
            objectName: "jtcJointListView"
            spacing: 4

            ScrollBar.vertical: ScrollBar {
                policy: jointListView.contentHeight > jointListView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }
            delegate: RowLayout {
                property var slider: positionSlider

                height: model.active ? 48 : 0
                spacing: 4
                visible: model.active || false
                width: parent.width - 16
                x: 8

                Label {
                    text: model.name
                }
                ChangeSlider {
                    id: positionSlider
                    Layout.fillWidth: true
                    currentValue: model.position
                    from: model.limits.lower
                    stepSize: 0.01
                    to: model.limits.upper
                    value: model.goal

                    onMoved: {
                        model.goal = Math.round(value * 100) / 100;
                    }
                }
                TextField {
                    id: positionField

                    readonly property string goalText: model.goal

                    implicitWidth: 60
                    objectName: "jtcGoalField_" + model.index
                    selectByMouse: true

                    validator: DoubleValidator {
                        bottom: model.limits.lower
                        top: model.limits.upper
                    }

                    // Not bound: typing updates the goal live, so only show external goal changes when not editing.
                    Component.onCompleted: text = goalText
                    onActiveFocusChanged: {
                        if (!activeFocus)
                            text = goalText;
                    }
                    onGoalTextChanged: {
                        if (!activeFocus)
                            text = goalText;
                    }
                    onTextEdited: {
                        let value = parseFloat(text);
                        if (isNaN(value) || value == null)
                            return;
                        value = Math.min(model.limits.upper, Math.max(value, model.limits.lower));
                        value = Math.round(value * 100) / 100;
                        if (Math.abs(value - model.goal) < 1e-9)
                            return;
                        model.goal = value;
                    }
                }
            }

            Keys.onPressed: event => {
                if (event.key !== Qt.Key_Return && event.key !== Qt.Key_Enter)
                    return;
                if (!sendButton.visible || !sendButton.enabled || d.trajectoryController.isGoalActive)
                    return;
                event.accepted = true;
                sendButton.clicked();
                sendButton.forceActiveFocus(Qt.ShortcutFocusReason);
            }
        }
        ColumnLayout {
            Layout.columnSpan: 3
            Layout.fillWidth: true
            visible: !!controllerComboBox.currentText && jointListView.count > 0 || false

            RowLayout {
                Layout.fillWidth: true

                Slider {
                    id: speedSlider

                    property real speed: value

                    Layout.fillWidth: true
                    from: 0.01
                    objectName: "jtcSpeedSlider"
                    to: 3
                    value: context.speed || 0.5

                    onMoved: context.speed = value
                }
                Label {
                    text: speedSlider.speed.toFixed(2) + " rad/s"
                }
            }
            RowLayout {
                Layout.fillWidth: true

                Button {
                    id: resetButton
                    Layout.fillWidth: true
                    Layout.margins: 8
                    objectName: "jtcResetButton"
                    text: "Reset"

                    onClicked: d.trajectoryController.resetGoals()
                }
                Button {
                    id: sendButton
                    Layout.fillWidth: true
                    Layout.margins: 8
                    enabled: d.trajectoryController.controllerReady
                    objectName: "jtcSendButton"
                    text: d.trajectoryController.isGoalActive ? "Cancel" : "Send"

                    Keys.onPressed: event => keyGuard.filter(event)
                    onClicked: {
                        keyGuard.arm();
                        if (d.trajectoryController.isGoalActive) {
                            d.trajectoryController.cancelGoals();
                        } else {
                            d.trajectoryController.sendGoals(speedSlider.speed);
                        }
                    }
                }
            }
        }
        Label {
            text: "Robot Description: " + (d.trajectoryController.hasRobotDescription ? "Loaded" : "Waiting...")
        }
    }
}
