import QtQuick
import Ros2
import RQml.Utils

Object {
    id: root

    // Mirrors the constants of controller_manager_msgs/srv/SwitchController.
    enum Strictness {
        BestEffort = 1,
        Strict,
        Auto,
        ForceAuto
    }

    // Activate controllers as soon as their hardware dependencies are ready
    // instead of waiting for all interfaces.
    property bool activateAsap: false
    property string controllerManager
    property var controllers: ListModel {
    }
    property var hardwareComponents: ListModel {
    }
    readonly property bool loading: d.loadingControllers || d.loadingHardwareComponents
    // Strictness used for activate/deactivate, see the Strictness enum.
    property int strictness: ControllerManagerInterface.Strictness.Auto
    // Timeout in seconds before pending controllers are aborted. Zero makes the
    // controller manager fall back to its default of 1 s.
    property real switchTimeout: 0

    // Outcome of a transition
    signal controllerTransitionFailed(string name, string action, string message)
    signal controllerTransitionSucceeded(string name, string action, string message)
    signal hardwareTransitionFailed(string name, string targetLabel, string currentLabel, int currentId)
    signal hardwareTransitionSucceeded(string name, string targetLabel)

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
                            "name": controllerName,
                            "state": "unloaded"
                        });
                }
                d.loadingControllers = false;
                Ros2.debug("ControllerManager: Done loading controllers from " + controllerManager + ". Total controllers: " + root.controllers.count);
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
    function refresh() {
        if (!root.controllerManager || !d.controllerServiceClient)
            return;
        root.loadControllers();
        root.loadHardwareComponents();
    }
    // Runs the given actions in order, reporting the outcome of the last one.
    function transitionController(controllerName, actions) {
        if (!controllerName || !actions || actions.length === 0)
            return;
        if (!root.controllerManager)
            return;
        // Work on a copy. The caller may hand in an array it still needs, e.g.
        // the action list of a context menu entry, which would be consumed
        // otherwise and leave the entry usable only once.
        d.runControllerActions(controllerName, actions.slice(), []);
    }
    function transitionHardwareComponent(componentName, target_state) {
        if (!componentName || !target_state)
            return;
        if (!root.controllerManager)
            return;
        let request = {
            "name": componentName,
            "target_state": target_state
        };
        d.setComponentStateServiceClient.sendRequestAsync(request, function (response) {
                if (!response) {
                    Ros2.warn("ControllerManager: Failed to call service " + root.controllerManager + "/set_hardware_component_state. Trying again.");
                    transitionHardwareComponent(componentName, target_state);
                    return;
                }
                if (response.ok) {
                    root.hardwareTransitionSucceeded(componentName, target_state.label);
                } else {
                    root.hardwareTransitionFailed(componentName, target_state.label, response.state.label, response.state.id);
                }
                root.loadHardwareComponents();
            });
    }

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

    QtObject {
        id: d

        property var componentsServiceClient: null
        property var controllerServiceClient: null
        property var controllerTransitionServiceClients: ({})
        property bool loadingControllers: false
        property bool loadingHardwareComponents: false
        property var parametersServiceClient: null
        property var setComponentStateServiceClient: null

        // Runs the remaining actions in order. Only the last one reports
        // success, the collected messages of all of them are passed on because
        // only switch_controller returns one at all.
        function runControllerActions(controllerName, remainingActions, collectedMessages) {
            const action = remainingActions[0];
            const serviceName = root.getTransitionServiceTopic(root.controllerManager, action);
            let client = d.controllerTransitionServiceClients[serviceName];
            if (client == null || client.name != serviceName) {
                client = Ros2.createServiceClient(serviceName, root.getTransitionServiceType(action));
                d.controllerTransitionServiceClients[serviceName] = client;
            }
            let request = {};
            if (action == "activate" || action == "deactivate") {
                request = {
                    "activate_controllers": action == "activate" ? [controllerName] : [],
                    "deactivate_controllers": action == "deactivate" ? [controllerName] : [],
                    "strictness": root.strictness,
                    "activate_asap": root.activateAsap,
                    "timeout": d.secondsToDuration(root.switchTimeout)
                };
            } else {
                request.name = controllerName;
            }
            client.sendRequestAsync(request, function (response) {
                    if (!response) {
                        Ros2.warn("ControllerManager: Failed to call service " + serviceName + ". Trying again.");
                        d.runControllerActions(controllerName, remainingActions, collectedMessages);
                        return;
                    }
                    if (!response.ok) {
                        root.controllerTransitionFailed(controllerName, action, response.message || "");
                        return;
                    }
                    if (response.message)
                        collectedMessages.push(response.message);
                    remainingActions.shift();
                    if (remainingActions.length === 0) {
                        root.controllerTransitionSucceeded(controllerName, action, collectedMessages.join("; "));
                        return;
                    }
                    d.runControllerActions(controllerName, remainingActions, collectedMessages);
                });
        }
        function secondsToDuration(seconds) {
            const clamped = Math.max(0, seconds);
            let sec = Math.floor(clamped);
            let nanosec = Math.round((clamped - sec) * 1e9);
            // Rounding may push the fraction to a full second.
            if (nanosec >= 1e9) {
                sec += 1;
                nanosec -= 1e9;
            }
            return {
                "sec": sec,
                "nanosec": nanosec
            };
        }
    }
    Subscription {
        id: activitySub
        messageType: "controller_manager_msgs/msg/ControllerManagerActivity"
        topic: (root.controllerManager && root.controllerManager + "/activity") || ""

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
