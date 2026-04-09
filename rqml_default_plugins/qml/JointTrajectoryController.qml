import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import "interfaces"

Rectangle {
    id: root
    anchors.fill: parent
    property var kddockwidgets_min_size: Qt.size(480, 360)
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
            objectName: "jtcNamespaceComboBox"
            Layout.fillWidth: true
            model: d.controllerManagers

            onCurrentValueChanged: {
                if (!currentValue)
                    return;
                context.controller_manager_namespace = currentValue;
            }
        }

        ComboBox {
            id: controllerComboBox
            objectName: "jtcControllerComboBox"
            Layout.fillWidth: true
            model: d.trajectoryController.controllers
            textRole: "name"

            currentIndex: {
                for (let i = 0; i < d.trajectoryController.controllers.count; i++) {
                    let c = d.trajectoryController.controllers.get(i);
                    if (c.name === context.controller)
                        return i;
                }
                return -1;
            }

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
            objectName: "jtcShortestPathSwitch"
            Layout.columnSpan: 3
            text: "Use shortest path duration for continuous joints"
            checked: context.take_shortest_path || false
            onCheckedChanged: context.take_shortest_path = checked
        }

        ListView {
            id: jointListView
            objectName: "jtcJointListView"
            Layout.columnSpan: 3
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            clip: true
            model: d.trajectoryController.joints

            ScrollBar.vertical: ScrollBar {
                policy: jointListView.contentHeight > jointListView.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            }

            delegate: RowLayout {
                x: 8
                width: parent.width - 16
                height: model.active ? 48 : 0
                spacing: 4
                property var slider: positionSlider
                visible: model.active || false
                Label {
                    text: model.name
                }
                ChangeSlider {
                    id: positionSlider
                    Layout.fillWidth: true
                    stepSize: 0.01
                    from: model.limits.lower
                    to: model.limits.upper
                    value: model.goal
                    currentValue: model.position
                    onMoved: {
                        model.goal = Math.round(value * 100) / 100;
                    }
                }
                TextField {
                    id: positionField
                    implicitWidth: 60
                    selectByMouse: true
                    text: model.goal
                    validator: DoubleValidator {
                        bottom: model.limits.lower
                        top: model.limits.upper
                    }
                    onTextChanged: {
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
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.columnSpan: 3
            visible: !!controllerComboBox.currentText && jointListView.count > 0 || false

            RowLayout {
                Layout.fillWidth: true
                Slider {
                    id: speedSlider
                    objectName: "jtcSpeedSlider"
                    Layout.fillWidth: true
                    property real speed: value
                    from: 0.01
                    to: 3
                    value: context.speed || 0.5
                    onValueChanged: context.speed = value
                }
                Label {
                    text: speedSlider.speed.toFixed(2) + " rad/s"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Button {
                    id: resetButton
                    objectName: "jtcResetButton"
                    Layout.fillWidth: true
                    Layout.margins: 8
                    text: "Reset"
                    onClicked: d.trajectoryController.resetGoals()
                }

                Button {
                    id: sendButton
                    objectName: "jtcSendButton"
                    Layout.fillWidth: true
                    Layout.margins: 8
                    text: d.trajectoryController.isGoalActive ? "Cancel" : "Send"
                    enabled: d.trajectoryController.controllerReady
                    onClicked: {
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
