/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
import QtQuick
import QtQuick.Controls
import QtTest
import Ros2

Item {
    id: root

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 768
    width: 1024

    // Mimics the real plugin context: keys the plugin has not initialized yet
    // are undefined, so the default initialization is exercised as well.
    QtObject {
        id: contextObj

        property var activate_asap: undefined
        property string controller_manager_namespace: ""
        property bool enabled: true
        property var switch_strictness: undefined
        property var switch_timeout: undefined
    }
    Utils {
        id: helpers
    }
    SignalSpy {
        id: transitionSpy
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/ControllerManager.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        id: testCase

        // Constants of lifecycle_msgs/msg/State.
        readonly property int stateActive: 3
        readonly property int stateInactive: 2
        readonly property int stateUnconfigured: 1
        // Constants of controller_manager_msgs/srv/SwitchController.
        readonly property int strictnessAuto: 3
        readonly property int strictnessBestEffort: 1
        readonly property int strictnessForceAuto: 4
        readonly property int strictnessStrict: 2

        // Returns the index of the entry with the given strictness value or -1.
        function indexOfStrictness(comboBox, value) {
            for (var i = 0; i < comboBox.count; ++i) {
                if (comboBox.valueAt(i) === value)
                    return i;
            }
            return -1;
        }
        function init() {
            Ros2.reset();
            transitionSpy.target = null;
            transitionSpy.clear();
            contextObj.controller_manager_namespace = "";
            contextObj.switch_strictness = undefined;
            contextObj.activate_asap = undefined;
            contextObj.switch_timeout = undefined;

            // Register services for multiple namespaces to test selection
            var handler = function (req) {
                var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListControllers");
                var ctrl1 = Ros2.createEmptyMessage("controller_manager_msgs/msg/ControllerState");
                ctrl1.name = "joint_state_broadcaster";
                ctrl1.state = "active";
                ctrl1.type = "joint_state_broadcaster/JointStateBroadcaster";
                resp.controller = [ctrl1];
                return resp;
            };
            Ros2.registerService("/mock_cm/list_controllers", "controller_manager_msgs/srv/ListControllers", handler);
            Ros2.registerService("/another_mock/list_controllers", "controller_manager_msgs/srv/ListControllers", handler);
            Ros2.registerService("/mock_cm/list_parameters", "rcl_interfaces/srv/ListParameters", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("rcl_interfaces/srv/ListParameters");
                    resp.result = Ros2.createEmptyMessage("rcl_interfaces/msg/ListParametersResult");
                    resp.result.names = ["joint_state_broadcaster.type"];
                    return resp;
                });
            Ros2.registerService("/mock_cm/list_hardware_components", "controller_manager_msgs/srv/ListHardwareComponents", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListHardwareComponents");
                    var comp = Ros2.createEmptyMessage("controller_manager_msgs/msg/HardwareComponentState");
                    comp.name = "mock_robot";
                    comp.type = "system";
                    comp.state = {
                        "id": 3,
                        "label": "active"
                    };
                    resp.component = [comp];
                    return resp;
                });
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                });
        }
        // Returns the menu item with the given text or null. Separators and
        // other item types without a text are skipped.
        function menuItemWithText(menu, text) {
            for (var i = 0; i < menu.count; ++i) {
                var item = menu.itemAt(i);
                if (item && item.text === text)
                    return item;
            }
            return null;
        }
        function openSettingsDialog() {
            var settingsButton = find("cmSettingsButton");
            verify(settingsButton, "Settings button should be found");
            mouseClick(settingsButton);
            var dialog = find("cmSettingsDialog");
            verify(dialog, "Settings dialog should be found");
            tryVerify(function () {
                    return dialog.visible;
                }, 2000, "Settings dialog should open");
            return dialog;
        }
        // Answers switch_controller with the given outcome and message.
        function registerSwitchController(ok, message) {
            Ros2.registerService("/mock_cm/switch_controller", "controller_manager_msgs/srv/SwitchController", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SwitchController");
                    resp.ok = ok;
                    resp.message = message;
                    return resp;
                });
        }
        function test_context_defaults() {
            // The plugin has to persist its defaults into the context so that
            // they end up in the saved configuration.
            tryCompare(contextObj, "switch_strictness", strictnessAuto, 2000, "switch_strictness should be initialized to AUTO");
            tryCompare(contextObj, "activate_asap", false, 2000, "activate_asap should be initialized to false");
            tryCompare(contextObj, "switch_timeout", 0, 2000, "switch_timeout should be initialized to zero");
            verify(contextObj.activate_asap !== undefined, "activate_asap must be defined, not just falsy");
            verify(contextObj.switch_timeout !== undefined, "switch_timeout must be defined, not just falsy");
        }
        function test_controller_menu_entry_can_be_used_repeatedly() {
            // transitionController consumes the action list it is handed. If
            // that list is the one inside the menu model, the entry works only
            // once.
            var switchRequests = [];
            Ros2.registerService("/mock_cm/switch_controller", "controller_manager_msgs/srv/SwitchController", function (req) {
                    switchRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SwitchController");
                    resp.ok = true;
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);
            list.positionViewAtIndex(0, ListView.Beginning);
            var menu = null;
            tryVerify(function () {
                    var delegateItem = list.itemAtIndex(0);
                    menu = delegateItem ? helpers.findChild(delegateItem, "cmControllerContextMenu") : null;
                    return menu !== null && menuItemWithText(menu, "Deactivate (inactive)") !== null;
                }, 5000, "Controller context menu should be available");
            menuItemWithText(menu, "Deactivate (inactive)").triggered();
            tryVerify(function () {
                    return switchRequests.length === 1;
                }, 2000, "First use of the menu entry must send a request");
            menuItemWithText(menu, "Deactivate (inactive)").triggered();
            tryVerify(function () {
                    return switchRequests.length === 2;
                }, 2000, "The menu entry must still work the second time");
            compare(switchRequests[1].deactivate_controllers, ["joint_state_broadcaster"]);
        }
        function test_controller_transition_chain_reports_once() {
            // "Deactivate and Unload" runs two services. Only the last one may
            // report, but the message of switch_controller must survive since
            // unload_controller does not return one.
            registerSwitchController(true, "Deactivated dependent controllers");
            Ros2.registerService("/mock_cm/unload_controller", "controller_manager_msgs/srv/UnloadController", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/UnloadController");
                    resp.ok = true;
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);
            transitionSpy.target = plugin.controllerManagerInterface;
            transitionSpy.signalName = "controllerTransitionSucceeded";
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["deactivate", "unload"]);
            transitionSpy.wait(2000);
            wait(100); // Give a second, wrong report the chance to arrive.
            compare(transitionSpy.count, 1, "A chain must report exactly once");
            compare(transitionSpy.signalArguments[0][1], "unload", "The last action of the chain is reported");
            compare(transitionSpy.signalArguments[0][2], "Deactivated dependent controllers", "The message of the earlier switch must not be lost");
        }
        function test_controller_transition_reports_failure() {
            registerSwitchController(false, "Could not activate, interface already claimed");
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);
            var toasts = find("cmToastManager");
            verify(toasts, "Toast manager should be found");
            compare(toasts.count, 0, "No toast before the transition");
            transitionSpy.target = plugin.controllerManagerInterface;
            transitionSpy.signalName = "controllerTransitionFailed";
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["activate"]);
            transitionSpy.wait(2000);
            compare(transitionSpy.count, 1, "Exactly one failure should be reported");
            compare(transitionSpy.signalArguments[0][0], "joint_state_broadcaster");
            compare(transitionSpy.signalArguments[0][1], "activate");
            compare(transitionSpy.signalArguments[0][2], "Could not activate, interface already claimed", "The reason of the controller manager must be passed on");
            tryCompare(toasts, "count", 1, 2000, "The failure has to be surfaced to the user");
            compare(toastLevelAt(toasts, 0), "error", "A failed transition has to be shown as an error");
            compare(toastMessageAt(toasts, 0), "Failed to activate joint_state_broadcaster: Could not activate, interface already claimed", "The toast has to name the action, the controller and the reason");
        }
        function test_controller_transition_reports_success_with_message() {
            // A switch_controller message names the controllers the controller
            // manager switched on its own, which is what makes FORCE_AUTO
            // comprehensible.
            registerSwitchController(true, "Deactivated arm_controller to free position interfaces");
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);
            var toasts = find("cmToastManager");
            verify(toasts, "Toast manager should be found");
            transitionSpy.target = plugin.controllerManagerInterface;
            transitionSpy.signalName = "controllerTransitionSucceeded";
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["activate"]);
            transitionSpy.wait(2000);
            compare(transitionSpy.count, 1);
            compare(transitionSpy.signalArguments[0][0], "joint_state_broadcaster");
            compare(transitionSpy.signalArguments[0][1], "activate");
            compare(transitionSpy.signalArguments[0][2], "Deactivated arm_controller to free position interfaces", "The message of the controller manager must be passed on");
            tryCompare(toasts, "count", 1, 2000, "The success has to be surfaced to the user");
            compare(toastLevelAt(toasts, 0), "success", "A successful transition has to be shown as a success, not as a plain info");
            compare(toastMessageAt(toasts, 0), "Activated joint_state_broadcaster: Deactivated arm_controller to free position interfaces", "The toast has to report the action in past tense and keep the message");
        }
        function test_controller_transitions() {
            // Record the requests hitting switch_controller so we can assert
            // on the exact payload sent.
            var switchRequests = [];
            Ros2.registerService("/mock_cm/switch_controller", "controller_manager_msgs/srv/SwitchController", function (req) {
                    switchRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SwitchController");
                    resp.ok = true;
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);

            // Drive transitionController via the interface exposed as a test
            // hook - the context menu builds the same call.
            verify(plugin.controllerManagerInterface);
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["deactivate"]);
            tryVerify(function () {
                    return switchRequests.length === 1;
                }, 2000, "Deactivate must send one switch_controller request");
            var req = switchRequests[0];
            compare(req.deactivate_controllers, ["joint_state_broadcaster"]);
            compare(req.activate_controllers, []);
            // Defaults applied by the plugin when the context is still empty.
            compare(req.strictness, strictnessAuto);
            compare(req.activate_asap, false);
            compare(req.timeout.sec, 0);
            compare(req.timeout.nanosec, 0);

            // Now activate - the client should be reused for the same service
            // name and a second request should be recorded.
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["activate"]);
            tryVerify(function () {
                    return switchRequests.length === 2;
                }, 2000);
            compare(switchRequests[1].activate_controllers, ["joint_state_broadcaster"]);
            compare(switchRequests[1].deactivate_controllers, []);
        }
        function test_controllers_list() {
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            verify(list !== null, "Controller list should be found");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000, "Should find at least 1 controller");
            compare(list.model.get(0).name, "joint_state_broadcaster");
        }
        function test_hardware_components() {
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmHardwareList");
            verify(list !== null, "Hardware components list should be found");
            tryVerify(function () {
                    return list.count === 1;
                }, 5000, "Should find 1 hardware component");
            compare(list.model.get(0).name, "mock_robot");
        }
        function test_hardware_transition_activate_from_context_menu() {
            var request = triggerHardwareMenuEntry(stateInactive, "inactive", "Activate (active)");
            compare(request.name, "mock_robot");
            compare(request.target_state.label, "active");
            compare(request.target_state.id, stateActive, "Target state id must be lifecycle_msgs PRIMARY_STATE_ACTIVE");
        }
        function test_hardware_transition_deactivate_from_context_menu() {
            var request = triggerHardwareMenuEntry(stateActive, "active", "Deactivate (inactive)");
            compare(request.name, "mock_robot");
            compare(request.target_state.label, "inactive");
            compare(request.target_state.id, stateInactive, "Target state id must be lifecycle_msgs PRIMARY_STATE_INACTIVE");
        }
        function test_hardware_transition_reports_failure() {
            // The component refuses and stays active.
            Ros2.registerService("/mock_cm/set_hardware_component_state", "controller_manager_msgs/srv/SetHardwareComponentState", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SetHardwareComponentState");
                    resp.ok = false;
                    resp.state = {
                        "id": stateActive,
                        "label": "active"
                    };
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmHardwareList");
            tryVerify(function () {
                    return list.count === 1;
                }, 5000);
            var toasts = find("cmToastManager");
            verify(toasts, "Toast manager should be found");
            transitionSpy.target = plugin.controllerManagerInterface;
            transitionSpy.signalName = "hardwareTransitionFailed";
            plugin.controllerManagerInterface.transitionHardwareComponent("mock_robot", {
                    "id": stateInactive,
                    "label": "inactive"
                });
            transitionSpy.wait(2000);
            compare(transitionSpy.count, 1);
            compare(transitionSpy.signalArguments[0][0], "mock_robot");
            compare(transitionSpy.signalArguments[0][1], "inactive", "The requested state is reported");
            compare(transitionSpy.signalArguments[0][2], "active", "The state the component actually is in is reported");
            compare(transitionSpy.signalArguments[0][3], stateActive, "The id of that state is reported as well, it is the only part a component always fills in");
            tryCompare(toasts, "count", 1, 2000, "The failure has to be surfaced to the user");
            compare(toastLevelAt(toasts, 0), "error", "A failed hardware transition has to be shown as an error");
            compare(toastMessageAt(toasts, 0), "Failed to set mock_robot to inactive, it is now active (" + stateActive + ")", "The toast has to name the requested and the actual state");
        }
        function test_hardware_transition_reports_success() {
            var toasts = find("cmToastManager");
            verify(toasts, "Toast manager should be found");
            transitionSpy.target = plugin.controllerManagerInterface;
            transitionSpy.signalName = "hardwareTransitionSucceeded";
            var request = triggerHardwareMenuEntry(stateActive, "active", "Deactivate (inactive)");
            compare(request.name, "mock_robot");
            transitionSpy.wait(2000);
            compare(transitionSpy.count, 1);
            compare(transitionSpy.signalArguments[0][0], "mock_robot");
            compare(transitionSpy.signalArguments[0][1], "inactive", "The reached state is reported");
            tryCompare(toasts, "count", 1, 2000, "The hardware transition has to be surfaced to the user");
            compare(toastLevelAt(toasts, 0), "success", "A successful hardware transition has to be shown as a success");
            compare(toastMessageAt(toasts, 0), "mock_robot is now inactive", "The toast has to name the component and the state it reached");
        }
        function test_hardware_transitions() {
            var setStateRequests = [];
            Ros2.registerService("/mock_cm/set_hardware_component_state", "controller_manager_msgs/srv/SetHardwareComponentState", function (req) {
                    setStateRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SetHardwareComponentState");
                    resp.ok = true;
                    resp.state = {
                        "id": 2,
                        "label": "inactive"
                    };
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmHardwareList");
            tryVerify(function () {
                    return list.count === 1;
                }, 5000);
            plugin.controllerManagerInterface.transitionHardwareComponent("mock_robot", {
                    "id": stateInactive,
                    "label": "inactive"
                });
            tryVerify(function () {
                    return setStateRequests.length === 1;
                }, 2000);
            compare(setStateRequests[0].name, "mock_robot");
            compare(setStateRequests[0].target_state.label, "inactive");
            compare(setStateRequests[0].target_state.id, stateInactive);
        }
        function test_info_dialogs() {
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);

            // Controller info dialog opens with the given controller.
            var controllerDialog = find("cmControllerInfoDialog");
            verify(controllerDialog, "Controller info dialog found");
            verify(!controllerDialog.visible, "Dialog starts hidden");
            controllerDialog.openControllerInfo(list.model.get(0));
            tryVerify(function () {
                    return controllerDialog.visible;
                }, 2000);
            compare(controllerDialog.controller.name, "joint_state_broadcaster");
            controllerDialog.close();
            tryVerify(function () {
                    return !controllerDialog.visible;
                }, 2000);
            var hwList = find("cmHardwareList");
            tryVerify(function () {
                    return hwList.count >= 1;
                }, 5000);
            var hwDialog = find("cmHardwareComponentInfoDialog");
            verify(hwDialog, "Hardware component info dialog found");
            verify(!hwDialog.visible);
            hwDialog.openHardwareComponentInfo(hwList.model.get(0));
            tryVerify(function () {
                    return hwDialog.visible;
                }, 2000);
            hwDialog.close();
        }
        function test_namespace_selection() {
            var nsCombo = find("cmComboBox");
            verify(nsCombo !== null, "Namespace ComboBox should be found");

            // Wait for both namespaces to be discovered
            tryVerify(function () {
                    return nsCombo.count >= 2;
                }, 5000);

            // Select "/another_mock"
            var targetIndex = -1;
            for (var i = 0; i < nsCombo.count; ++i) {
                if (nsCombo.textAt(i) === "/another_mock") {
                    targetIndex = i;
                    break;
                }
            }
            verify(targetIndex !== -1, "/another_mock should be in the list");
            nsCombo.currentIndex = targetIndex;
            tryCompare(contextObj, "controller_manager_namespace", "/another_mock", 2000);
        }
        function test_plugin_loads() {
            verify(plugin !== null, "ControllerManager plugin should load");
        }
        function test_refresh_button() {
            // Initial load uses the handler registered in init (one controller).
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);
            compare(list.count, 1);

            // Re-register with a handler returning a different set. The plugin
            // must only pick up the change after an explicit refresh.
            Ros2.registerService("/mock_cm/list_controllers", "controller_manager_msgs/srv/ListControllers", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListControllers");
                    var c1 = Ros2.createEmptyMessage("controller_manager_msgs/msg/ControllerState");
                    c1.name = "joint_state_broadcaster";
                    c1.state = "active";
                    c1.type = "joint_state_broadcaster/JointStateBroadcaster";
                    var c2 = Ros2.createEmptyMessage("controller_manager_msgs/msg/ControllerState");
                    c2.name = "arm_controller";
                    c2.state = "inactive";
                    c2.type = "joint_trajectory_controller/JointTrajectoryController";
                    resp.controller = [c1, c2];
                    return resp;
                });
            var refreshBtn = find("cmRefreshButton");
            verify(refreshBtn);
            mouseClick(refreshBtn);
            tryVerify(function () {
                    return list.count >= 2;
                }, 5000, "Refresh should pick up the updated controller list");

            // Both controllers must be present (order from the service).
            var names = [list.model.get(0).name, list.model.get(1).name];
            verify(names.indexOf("joint_state_broadcaster") !== -1);
            verify(names.indexOf("arm_controller") !== -1);
        }
        function test_settings_applied_to_switch_request() {
            var switchRequests = [];
            Ros2.registerService("/mock_cm/switch_controller", "controller_manager_msgs/srv/SwitchController", function (req) {
                    switchRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SwitchController");
                    resp.ok = true;
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);

            // Change the settings the way a user would, then check that the
            // switch_controller request actually carries them.
            var dialog = openSettingsDialog();
            var strictnessComboBox = find("cmSettingsStrictnessComboBox");
            strictnessComboBox.currentIndex = indexOfStrictness(strictnessComboBox, strictnessForceAuto);
            mouseClick(find("cmSettingsActivateAsapCheckBox"));
            find("cmSettingsTimeoutSpinBox").value = 2.5;
            dialog.close();
            tryVerify(function () {
                    return !dialog.visible;
                }, 2000);
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["activate"]);
            tryVerify(function () {
                    return switchRequests.length === 1;
                }, 2000);
            var req = switchRequests[0];
            compare(req.strictness, strictnessForceAuto, "Selected strictness should reach the service");
            compare(req.activate_asap, true, "Activate ASAP should reach the service");
            compare(req.timeout.sec, 2, "Timeout seconds should reach the service");
            compare(req.timeout.nanosec, 500000000, "Timeout nanoseconds should reach the service");

            // Settings only apply to switch_controller, not to the other
            // lifecycle services.
            var configureRequests = [];
            Ros2.registerService("/mock_cm/configure_controller", "controller_manager_msgs/srv/ConfigureController", function (req2) {
                    configureRequests.push(req2);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ConfigureController");
                    resp.ok = true;
                    return resp;
                });
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["configure"]);
            tryVerify(function () {
                    return configureRequests.length === 1;
                }, 2000);
            compare(configureRequests[0].name, "joint_state_broadcaster");
            compare(configureRequests[0].strictness, undefined, "ConfigureController has no strictness field");
        }
        function test_settings_dialog() {
            var dialog = openSettingsDialog();
            var strictnessComboBox = find("cmSettingsStrictnessComboBox");
            verify(strictnessComboBox, "Strictness ComboBox should be found");

            // All strictness modes of the service definition must be offered.
            compare(strictnessComboBox.count, 4, "Four strictness modes should be offered");
            verify(indexOfStrictness(strictnessComboBox, strictnessBestEffort) !== -1, "BEST_EFFORT should be offered");
            verify(indexOfStrictness(strictnessComboBox, strictnessStrict) !== -1, "STRICT should be offered");
            verify(indexOfStrictness(strictnessComboBox, strictnessAuto) !== -1, "AUTO should be offered");
            verify(indexOfStrictness(strictnessComboBox, strictnessForceAuto) !== -1, "FORCE_AUTO should be offered");

            // Precondition, the initialization itself is covered by
            // test_context_defaults.
            compare(contextObj.switch_strictness, strictnessAuto);
            compare(strictnessComboBox.currentValue, strictnessAuto, "Dialog should show the persisted strictness");
            var description = find("cmSettingsStrictnessDescription");
            verify(description, "Strictness description should be found");
            var autoDescription = description.text;
            verify(autoDescription.length > 0, "Strictness description should not be empty");

            // Selecting another mode persists it and updates the description.
            strictnessComboBox.currentIndex = indexOfStrictness(strictnessComboBox, strictnessForceAuto);
            tryCompare(contextObj, "switch_strictness", strictnessForceAuto, 2000, "Selected strictness should be persisted");
            tryVerify(function () {
                    return description.text !== autoDescription;
                }, 2000, "Description should follow the selected strictness");
            var activateAsapCheckBox = find("cmSettingsActivateAsapCheckBox");
            verify(activateAsapCheckBox, "Activate ASAP CheckBox should be found");
            verify(!activateAsapCheckBox.checked, "Activate ASAP should be off by default");
            mouseClick(activateAsapCheckBox);
            tryCompare(contextObj, "activate_asap", true, 2000, "Activate ASAP should be persisted");
            var timeoutSpinBox = find("cmSettingsTimeoutSpinBox");
            verify(timeoutSpinBox, "Timeout SpinBox should be found");
            compare(timeoutSpinBox.value, 0, "Timeout should default to zero");
            timeoutSpinBox.value = 2.5;
            tryCompare(contextObj, "switch_timeout", 2.5, 2000, "Timeout should be persisted");
            // The displayed SpinBox has to follow as well, otherwise the write
            // back handler would have shadowed the one of DecimalSpinBox.
            var innerSpinBox = timeoutSpinBox.children[0];
            verify(innerSpinBox, "DecimalSpinBox should contain a SpinBox");
            tryCompare(innerSpinBox, "value", timeoutSpinBox.decimalToInt(2.5), 2000, "SpinBox should display the assigned value");

            // Reopening the dialog re-syncs the controls with the context, even
            // though user interaction has broken the initial bindings.
            dialog.close();
            tryVerify(function () {
                    return !dialog.visible;
                }, 2000);
            contextObj.switch_strictness = strictnessStrict;
            contextObj.activate_asap = false;
            contextObj.switch_timeout = 1.5;
            openSettingsDialog();
            compare(strictnessComboBox.currentValue, strictnessStrict, "Reopening should show the persisted strictness");
            compare(activateAsapCheckBox.checked, false, "Reopening should show the persisted activate_asap");
            compare(timeoutSpinBox.value, 1.5, "Reopening should show the persisted timeout");
        }
        function test_switch_request_matches_service_definition() {
            // The mock service client passes the request map through unchanged,
            // so a plain payload assertion would only test the plugin against
            // itself. Validate the field names against the request built from
            // the real .srv definition instead.
            var switchRequests = [];
            Ros2.registerService("/mock_cm/switch_controller", "controller_manager_msgs/srv/SwitchController", function (req) {
                    switchRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SwitchController");
                    resp.ok = true;
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function () {
                    return list.count >= 1;
                }, 5000);
            plugin.controllerManagerInterface.transitionController("joint_state_broadcaster", ["activate"]);
            tryVerify(function () {
                    return switchRequests.length === 1;
                }, 2000);
            var template = Ros2.createEmptyServiceRequest("controller_manager_msgs/srv/SwitchController");
            verify(template, "Empty request should be created from the real service definition");
            var sent = switchRequests[0];

            // Assert the payload is actually populated first - the loops below
            // pass vacuously on an empty request.
            var expectedKeys = ["activate_controllers", "deactivate_controllers", "strictness", "activate_asap", "timeout"];
            for (var e = 0; e < expectedKeys.length; ++e) {
                verify(sent[expectedKeys[e]] !== undefined, "Request must contain '" + expectedKeys[e] + "'");
            }
            verify(sent.timeout.sec !== undefined && sent.timeout.nanosec !== undefined, "Request must contain a populated timeout");

            // Every field that is sent has to exist in the real .srv.
            for (var key in sent) {
                verify(template[key] !== undefined, "Field '" + key + "' must exist in SwitchController.srv");
            }
            for (var durationKey in sent.timeout) {
                verify(template.timeout[durationKey] !== undefined, "Field 'timeout." + durationKey + "' must exist in SwitchController.srv");
            }
        }
        // Level of the toast at the given index. An unknown level is rendered
        // like an info toast, so it has to be asserted explicitly.
        function toastLevelAt(toastManager, index) {
            var toast = toastManager.getToast(index);
            return toast ? toast.level : "";
        }
        // Message of the toast at the given index.
        function toastMessageAt(toastManager, index) {
            var toast = toastManager.getToast(index);
            return toast ? toast.message : "";
        }
        // Reports mock_robot in the given lifecycle state, triggers the context
        // menu entry with the given text and returns the resulting
        // set_hardware_component_state request.
        // test_hardware_transitions drives the interface with an explicit target
        // state, this goes through the menu so that
        // getTransitionsForHardwareComponentState is covered as well. The plugin
        // reloads the list after a transition, which recreates the delegate and
        // its menu, so only one transition can be triggered per plugin instance.
        function triggerHardwareMenuEntry(currentStateId, currentStateLabel, entry) {
            Ros2.registerService("/mock_cm/list_hardware_components", "controller_manager_msgs/srv/ListHardwareComponents", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListHardwareComponents");
                    var comp = Ros2.createEmptyMessage("controller_manager_msgs/msg/HardwareComponentState");
                    comp.name = "mock_robot";
                    comp.type = "system";
                    comp.state = {
                        "id": currentStateId,
                        "label": currentStateLabel
                    };
                    resp.component = [comp];
                    return resp;
                });
            var setStateRequests = [];
            Ros2.registerService("/mock_cm/set_hardware_component_state", "controller_manager_msgs/srv/SetHardwareComponentState", function (req) {
                    setStateRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/SetHardwareComponentState");
                    resp.ok = true;
                    // A successful transition reports the state that was reached.
                    resp.state = req.target_state;
                    return resp;
                });
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmHardwareList");
            tryVerify(function () {
                    return list.count === 1;
                }, 5000);
            tryCompare(list.model.get(0).state, "label", currentStateLabel, 5000, "Component should be in the state under test");
            list.positionViewAtIndex(0, ListView.Beginning);
            var menu = null;
            tryVerify(function () {
                    var delegateItem = list.itemAtIndex(0);
                    menu = delegateItem ? helpers.findChild(delegateItem, "cmHardwareContextMenu") : null;
                    return menu !== null && menuItemWithText(menu, entry) !== null;
                }, 5000, "Context menu with '" + entry + "' should be available");
            menuItemWithText(menu, entry).triggered();
            tryVerify(function () {
                    return setStateRequests.length === 1;
                }, 2000, "Menu item must send one set_hardware_component_state request");
            return setStateRequests[0];
        }

        name: "ControllerManagerTest"
        when: windowShown
    }
}
