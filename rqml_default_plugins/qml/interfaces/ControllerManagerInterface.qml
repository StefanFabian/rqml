import QtQuick
import QtQuick.Dialogs
import Ros2
import RQml.Utils

Object {
    id: root
    property string controllerManager
    property var controllers: ListModel {}
    property var hardwareComponents: ListModel {}
    readonly property bool loading: d.loadingControllers || d.loadingHardwareComponents

    onControllerManagerChanged: {
        var cmText = root.controllerManager;
        var valid = (cmText.length > 0);

        if (valid) {
            d.controllerServiceClient = Ros2.createServiceClient(cmText + "/list_controllers", "controller_manager_msgs/srv/ListControllers");
            d.parametersServiceClient = Ros2.createServiceClient(cmText + "/list_parameters", "rcl_interfaces/srv/ListParameters");
            d.componentsServiceClient = Ros2.createServiceClient(cmText + "/list_hardware_components", "controller_manager_msgs/srv/ListHardwareComponents");
            d.setComponentStateServiceClient = Ros2.createServiceClient(cmText + "/set_hardware_component_state", "controller_manager_msgs/srv/SetHardwareComponentState");
            activitySub.topic = cmText + "/activity";
            d.controllerTransitionServiceClients = {}; // Clear old clients
        } else {
            d.controllerServiceClient = null;
            d.parametersServiceClient = null;
            d.componentsServiceClient = null;
            d.setComponentStateServiceClient = null;
            activitySub.topic = "";
        }

        root.refresh();
    }

    function refresh() {
        if (!root.controllerManager || !d.controllerServiceClient) return;
        root.loadControllers();
        root.loadHardwareComponents();
    }

    function loadControllers() {
        if (!root.controllerManager)
            return;
        if (d.controllerServiceClient.pendingRequests > 0)
            return; // Already requesting
        d.loadingControllers = true;

        Ros2.debug("ControllerManager: Loading controllers from " + controllerManager);
        d.controllerServiceClient.sendRequestAsync({}, function (response) {
            if (!response) {
                Ros2.warn("ControllerManager: Failed to get controllers from " + controllerManager + ". Trying again.");
                root.loadControllers();
                return;
            }
            Ros2.debug("ControllerManager: Received " + response.controller.length + " controllers from " + controllerManager);
            root.controllers.clear();
            for (let i = 0; i < response.controller.length; ++i) {
                const controller = response.controller.at(i);
                if (controller.name == null || controller.state == null)
                    continue;
                root.controllers.append(MessageUtils.toListElement(controller));
            }

            addParameterControllers();
        });
    }

    function addParameterControllers() {
        if (!root.controllerManager)
            return;
        if (d.parametersServiceClient.pendingRequests > 0)
            return; // Already requesting
        Ros2.debug("ControllerManager: Loading unloaded controllers from parameters of " + controllerManager);
        d.parametersServiceClient.sendRequestAsync({}, function (response) {
            if (!response) {
                Ros2.warn("ControllerManager: Failed to get parameters from " + controllerManager + ". Trying again.");
                root.addParameterControllers();
                return;
            }
            for (let i = 0; i < response.result.names.length; ++i) {
                const name = response.result.names.at(i);
                if (!name.endsWith(".type"))
                    continue;
                const parts = name.split(".");
                if (parts.length > 2)
                    continue;
                const controllerName = parts[0];
                let found = false;
                for (let j = 0; j < root.controllers.count; ++j) {
                    const item = root.controllers.get(j);
                    if (item.name === controllerName) {
                        found = true;
                        break;
                    }
                }
                if (found)
                    continue;
                root.controllers.append({
                    name: controllerName,
                    state: "unloaded"
                });
            }
            d.loadingControllers = false;
            Ros2.debug("ControllerManager: Done loading controllers from " + controllerManager + ". Total controllers: " + root.controllers.count);
        });
    }

    function loadHardwareComponents() {
        if (!root.controllerManager)
            return;
        if (d.componentsServiceClient.pendingRequests > 0)
            return; // Already requesting
        d.loadingHardwareComponents = true;
        Ros2.debug("ControllerManager: Loading hardware components from " + controllerManager);
        d.componentsServiceClient.sendRequestAsync({}, function (response) {
            if (!response) {
                Ros2.warn("ControllerManager: Failed to get hardware components from " + controllerManager + ". Trying again.");
                root.loadHardwareComponents();
                return;
            }
            Ros2.debug("ControllerManager: Received " + response.component.length + " components from " + controllerManager);
            root.hardwareComponents.clear();
            for (let i = 0; i < response.component.length; ++i) {
                const component = response.component.at(i);
                root.hardwareComponents.append(MessageUtils.toJavaScriptObject(component));
            }
            d.loadingHardwareComponents = false;
        });
    }

    function transitionController(controllerName, actions) {
        if (!controllerName || !actions || actions.length === 0)
            return;
        if (!root.controllerManager)
            return;
        const action = actions[0];
        const serviceName = getTransitionServiceTopic(root.controllerManager, action);
        let client = d.controllerTransitionServiceClients[serviceName];
        if (client == null || client.name != serviceName) {
            client = Ros2.createServiceClient(serviceName, getTransitionServiceType(action));
            d.controllerTransitionServiceClients[serviceName] = client;
        }

        let request = {};
        if (action == "activate" || action == "deactivate") {
            request = {
                activate_controllers: action == "activate" ? [controllerName] : [],
                deactivate_controllers: action == "deactivate" ? [controllerName] : [],
                strictness: 3 // AUTO
            };
        } else {
            request.name = controllerName;
        }

        client.sendRequestAsync(request, function (response) {
            if (!response) {
                Ros2.warn("ControllerManager: Failed to call service " + serviceName + ". Trying again.");
                transitionController(controllerName, actions);
                return;
            }
            if (!response.ok) {
                errorDialog.title = "Controller Transition Error";
                errorDialog.text = "Failed to " + action + " controller " + controllerName + ".";
                if (response.message) {
                    errorDialog.informativeText = "Reason: " + response.message;
                }
                errorDialog.open();
                return;
            }
            actions.shift();
            transitionController(controllerName, actions);
        });
    }

    function transitionHardwareComponent(componentName, target_state) {
        if (!componentName || !target_state)
            return;
        if (!root.controllerManager)
            return;
        let request = {
            name: componentName,
            target_state: target_state
        };

        d.setComponentStateServiceClient.sendRequestAsync(request, function (response) {
            if (!response) {
                Ros2.warn("ControllerManager: Failed to call service " + serviceName + ". Trying again.");
                transitionHardwareComponent(componentName, target_state);
                return;
            }
            if (!response.ok) {
                errorDialog.title = "Hardware Component Transition Error";
                errorDialog.text = "Failed to transition hardware component " + componentName + " to " + target_state + ".";
                errorDialog.informativeText = "Component now in state: " + response.state.label + " (" + response.state.id + ")";
                errorDialog.open();
            }
            root.loadHardwareComponents();
        });
    }

    function getTransitionServiceTopic(ns, action) {
        if (action == "load")
            return ns + "/load_controller";
        if (action == "unload")
            return ns + "/unload_controller";
        if (action == "activate")
            return ns + "/switch_controller";
        if (action == "deactivate")
            return ns + "/switch_controller";
        if (action == "configure")
            return ns + "/configure_controller";
        Ros2.error("Unknown controller action: " + action);
        return "";
    }

    function getTransitionServiceType(action) {
        if (action == "load")
            return "controller_manager_msgs/srv/LoadController";
        if (action == "unload")
            return "controller_manager_msgs/srv/UnloadController";
        if (action == "activate")
            return "controller_manager_msgs/srv/SwitchController";
        if (action == "deactivate")
            return "controller_manager_msgs/srv/SwitchController";
        if (action == "configure")
            return "controller_manager_msgs/srv/ConfigureController";
        Ros2.error("Unknown controller action: " + action);
        return "";
    }

    MessageDialog {
        id: errorDialog
        buttons: MessageDialog.Ok
        modality: Qt.WindowModal
    }

    QtObject {
        id: d

        property bool loadingControllers: false
        property bool loadingHardwareComponents: false
        property var controllerServiceClient: null
        property var parametersServiceClient: null
        property var controllerTransitionServiceClients: ({})
        property var componentsServiceClient: null
        property var setComponentStateServiceClient: null
    }

    Subscription {
        id: activitySub
        topic: (root.controllerManager && root.controllerManager + "/activity") || ""
        messageType: "controller_manager_msgs/msg/ControllerManagerActivity"
        onNewMessage: msg => {
            for (let i = 0; i < root.controllers.count; ++i) {
                const item = root.controllers.get(i);
                let state = "unloaded";
                for (let j = 0; j < msg.controllers.length; ++j) {
                    const controller = msg.controllers.at(j);
                    if (controller.name !== item.name)
                        continue;
                    state = controller.state.label;
                    break;
                }
                if (item.state === state)
                    continue;
                item.state = state;
            }
            for (let i = 0; i < root.hardwareComponents.count; ++i) {
                const item = root.hardwareComponents.get(i);
                let state = "unknown";
                for (let j = 0; j < msg.hardware_components.length; ++j) {
                    const component = msg.hardware_components.at(j);
                    if (component.name !== item.name)
                        continue;
                    state = component.state.label;
                    break;
                }
                if (item.state === state)
                    continue;
                item.state = state;
            }
        }
    }
}
