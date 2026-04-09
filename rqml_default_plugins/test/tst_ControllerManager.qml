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
    width: 1024; height: 768

    property var context: contextObj
    QtObject {
        id: contextObj
        property bool enabled: true
        property string controller_manager_namespace: ""
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/ControllerManager.qml"; }
    }

    property var plugin: pluginLoader.item
    function find(name) { return helpers.findChild(root, name); }

    TestCase {
        id: testCase
        name: "ControllerManagerTest"
        when: windowShown

        function init() {
            Ros2.reset();
            contextObj.controller_manager_namespace = "";

            // Register services for multiple namespaces to test selection
            var handler = function(req) {
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

            Ros2.registerService("/mock_cm/list_parameters", "rcl_interfaces/srv/ListParameters", function(req) {
                var resp = Ros2.createEmptyServiceResponse("rcl_interfaces/srv/ListParameters");
                resp.result = Ros2.createEmptyMessage("rcl_interfaces/msg/ListParametersResult");
                resp.result.names = ["joint_state_broadcaster.type"];
                return resp;
            });

            Ros2.registerService("/mock_cm/list_hardware_components", "controller_manager_msgs/srv/ListHardwareComponents", function(req) {
                var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListHardwareComponents");
                var comp = Ros2.createEmptyMessage("controller_manager_msgs/msg/HardwareComponentState");
                comp.name = "mock_robot";
                comp.type = "system";
                comp.state = { id: 3, label: "active" };
                resp.component = [comp];
                return resp;
            });

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; });
        }

        function test_plugin_loads() {
            verify(plugin !== null, "ControllerManager plugin should load");
        }

        function test_controllers_list() {
            contextObj.controller_manager_namespace = "/mock_cm";

            var list = find("cmControllerList");
            verify(list !== null, "Controller list should be found");
            tryVerify(function() { return list.count >= 1; }, 5000, "Should find at least 1 controller");
            compare(list.model.get(0).name, "joint_state_broadcaster");
        }

        function test_hardware_components() {
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmHardwareList");
            verify(list !== null, "Hardware components list should be found");
            tryVerify(function() { return list.count === 1; }, 5000, "Should find 1 hardware component");
            compare(list.model.get(0).name, "mock_robot");
        }

        function test_refresh_button() {
            // Initial load uses the handler registered in init (one controller).
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function() { return list.count >= 1; }, 5000);
            compare(list.count, 1);

            // Re-register with a handler returning a different set. The plugin
            // must only pick up the change after an explicit refresh.
            Ros2.registerService("/mock_cm/list_controllers",
                "controller_manager_msgs/srv/ListControllers",
                function(req) {
                    var resp = Ros2.createEmptyServiceResponse(
                        "controller_manager_msgs/srv/ListControllers");
                    var c1 = Ros2.createEmptyMessage(
                        "controller_manager_msgs/msg/ControllerState");
                    c1.name = "joint_state_broadcaster";
                    c1.state = "active";
                    c1.type = "joint_state_broadcaster/JointStateBroadcaster";
                    var c2 = Ros2.createEmptyMessage(
                        "controller_manager_msgs/msg/ControllerState");
                    c2.name = "arm_controller";
                    c2.state = "inactive";
                    c2.type = "joint_trajectory_controller/JointTrajectoryController";
                    resp.controller = [c1, c2];
                    return resp;
                });

            var refreshBtn = find("cmRefreshButton");
            verify(refreshBtn);
            mouseClick(refreshBtn);
            tryVerify(function() { return list.count >= 2; }, 5000,
                "Refresh should pick up the updated controller list");

            // Both controllers must be present (order from the service).
            var names = [list.model.get(0).name, list.model.get(1).name];
            verify(names.indexOf("joint_state_broadcaster") !== -1);
            verify(names.indexOf("arm_controller") !== -1);
        }

        function test_controller_transitions() {
            // Record the requests hitting switch_controller so we can assert
            // on the exact payload sent.
            var switchRequests = [];
            Ros2.registerService("/mock_cm/switch_controller",
                "controller_manager_msgs/srv/SwitchController",
                function(req) {
                    switchRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse(
                        "controller_manager_msgs/srv/SwitchController");
                    resp.ok = true;
                    return resp;
                });

            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function() { return list.count >= 1; }, 5000);

            // Drive transitionController via the interface exposed as a test
            // hook - the context menu builds the same call.
            verify(plugin.controllerManagerInterface);
            plugin.controllerManagerInterface.transitionController(
                "joint_state_broadcaster", ["deactivate"]);

            tryVerify(function() { return switchRequests.length === 1; }, 2000,
                "Deactivate must send one switch_controller request");
            var req = switchRequests[0];
            compare(req.deactivate_controllers, ["joint_state_broadcaster"]);
            compare(req.activate_controllers, []);
            compare(req.strictness, 3);

            // Now activate - the client should be reused for the same service
            // name and a second request should be recorded.
            plugin.controllerManagerInterface.transitionController(
                "joint_state_broadcaster", ["activate"]);
            tryVerify(function() { return switchRequests.length === 2; }, 2000);
            compare(switchRequests[1].activate_controllers, ["joint_state_broadcaster"]);
            compare(switchRequests[1].deactivate_controllers, []);
        }

        function test_hardware_transitions() {
            var setStateRequests = [];
            Ros2.registerService("/mock_cm/set_hardware_component_state",
                "controller_manager_msgs/srv/SetHardwareComponentState",
                function(req) {
                    setStateRequests.push(req);
                    var resp = Ros2.createEmptyServiceResponse(
                        "controller_manager_msgs/srv/SetHardwareComponentState");
                    resp.ok = true;
                    resp.state = { id: 2, label: "inactive" };
                    return resp;
                });

            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmHardwareList");
            tryVerify(function() { return list.count === 1; }, 5000);

            plugin.controllerManagerInterface.transitionHardwareComponent(
                "mock_robot", { id: 2, label: "inactive" });

            tryVerify(function() { return setStateRequests.length === 1; }, 2000);
            compare(setStateRequests[0].name, "mock_robot");
            compare(setStateRequests[0].target_state.label, "inactive");
            compare(setStateRequests[0].target_state.id, 2);
        }

        function test_info_dialogs() {
            contextObj.controller_manager_namespace = "/mock_cm";
            var list = find("cmControllerList");
            tryVerify(function() { return list.count >= 1; }, 5000);

            // Controller info dialog opens with the given controller.
            var controllerDialog = find("cmControllerInfoDialog");
            verify(controllerDialog, "Controller info dialog found");
            verify(!controllerDialog.visible, "Dialog starts hidden");

            controllerDialog.openControllerInfo(list.model.get(0));
            tryVerify(function() { return controllerDialog.visible; }, 2000);
            compare(controllerDialog.controller.name, "joint_state_broadcaster");
            controllerDialog.close();
            tryVerify(function() { return !controllerDialog.visible; }, 2000);

            var hwList = find("cmHardwareList");
            tryVerify(function() { return hwList.count >= 1; }, 5000);
            var hwDialog = find("cmHardwareComponentInfoDialog");
            verify(hwDialog, "Hardware component info dialog found");
            verify(!hwDialog.visible);

            hwDialog.openHardwareComponentInfo(hwList.model.get(0));
            tryVerify(function() { return hwDialog.visible; }, 2000);
            hwDialog.close();
        }

        function test_namespace_selection() {
            var nsCombo = find("cmComboBox");
            verify(nsCombo !== null, "Namespace ComboBox should be found");

            // Wait for both namespaces to be discovered
            tryVerify(function() { return nsCombo.count >= 2; }, 5000);

            // Select "/another_mock"
            var targetIndex = -1;
            for (var i = 0; i < nsCombo.count; ++i) {
                if (nsCombo.textAt(i) === "/another_mock") { targetIndex = i; break; }
            }
            verify(targetIndex !== -1, "/another_mock should be in the list");

            nsCombo.currentIndex = targetIndex;
            tryCompare(contextObj, "controller_manager_namespace", "/another_mock", 2000);
        }
    }
}
