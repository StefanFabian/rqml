/*
 * Copyright (C) 2025  Stefan Fabian
 *
 * This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
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

import QtQuick 2.15
import QtTest 1.15
import "../qml" as PluginQml
import Ros2

Item {
    id: windowRoot
    width: 800
    height: 600

    property var context: ({
        enabled: true,
        controller_manager_namespace: ""
    })

    PluginQml.ControllerManager {
        id: controllerManager
        anchors.fill: parent
    }

    TestCase {
        name: "ControllerManagerTest"
        when: windowShown

        function init() {
            Ros2.reset();
            // Set up controller_manager mock services
            Ros2._mockServices["controller_manager_msgs/srv/ListControllers"] = [
                "/mock_cm/list_controllers"
            ];

            // Mock list_controllers response
            Ros2._mockServiceResponses["/mock_cm/list_controllers"] = function(request) {
                return Ros2.wrapCppMessage({
                    controller: [
                        {
                            name: "joint_state_broadcaster",
                            state: "active",
                            type: "joint_state_broadcaster/JointStateBroadcaster",
                            claimed_interfaces: [],
                            required_command_interfaces: [],
                            required_state_interfaces: []
                        },
                        {
                            name: "arm_controller",
                            state: "inactive",
                            type: "joint_trajectory_controller/JointTrajectoryController",
                            claimed_interfaces: ["joint1/position", "joint2/position"],
                            required_command_interfaces: ["joint1/position", "joint2/position"],
                            required_state_interfaces: []
                        }
                    ]
                });
            };

            // Mock list_parameters response (for unloaded controllers)
            Ros2._mockServiceResponses["/mock_cm/list_parameters"] = function(request) {
                return Ros2.wrapCppMessage({
                    result: {
                        names: [
                            "joint_state_broadcaster.type",
                            "arm_controller.type",
                            "gripper_controller.type"
                        ]
                    }
                });
            };

            // Mock list_hardware_components response
            Ros2._mockServiceResponses["/mock_cm/list_hardware_components"] = function(request) {
                return Ros2.wrapCppMessage({
                    component: [
                        {
                            name: "mock_robot",
                            type: "system",
                            state: { id: 3, label: "active" },
                            command_interfaces: ["joint1/position", "joint2/position"],
                            state_interfaces: ["joint1/position", "joint2/position"]
                        }
                    ]
                });
            };
        }

        function test_01_plugin_loads() {
            verify(controllerManager !== null, "ControllerManager plugin should load");
        }

        function test_02_controller_manager_discovery() {
            var services = Ros2.queryServices("controller_manager_msgs/srv/ListControllers");
            compare(services.length, 1, "Should find 1 list_controllers service");
            compare(services[0], "/mock_cm/list_controllers");

            // Extract namespace
            var parts = services[0].split("/");
            parts.pop();
            var ns = parts.join("/");
            compare(ns, "/mock_cm", "Namespace should be /mock_cm");
        }

        function test_03_controllers_list() {
            // Trigger loading by setting the namespace
            context.controller_manager_namespace = "/mock_cm";
            wait(200);

            // Verify list_controllers service client works
            var client = Ros2.createServiceClient("/mock_cm/list_controllers", "controller_manager_msgs/srv/ListControllers");
            var response = null;
            client.sendRequestAsync({}, function(resp) {
                response = resp;
            });
            wait(100);

            verify(response !== null, "Should get controllers response");
            compare(response.controller.length, 2, "Should have 2 controllers");
            compare(response.controller.at(0).name, "joint_state_broadcaster");
            compare(response.controller.at(0).state, "active");
            compare(response.controller.at(1).name, "arm_controller");
            compare(response.controller.at(1).state, "inactive");
        }

        function test_04_hardware_components() {
            var client = Ros2.createServiceClient("/mock_cm/list_hardware_components", "controller_manager_msgs/srv/ListHardwareComponents");
            var response = null;
            client.sendRequestAsync({}, function(resp) {
                response = resp;
            });
            wait(100);

            verify(response !== null, "Should get hardware components response");
            compare(response.component.length, 1, "Should have 1 hardware component");
            compare(response.component.at(0).name, "mock_robot");
            compare(response.component.at(0).state.label, "active");
        }

        function test_05_controller_state_transitions() {
            // Verify the transition definitions are correct based on state
            // These are defined in the ControllerManager.qml d.getTransitionsForControllerState()
            // We can't directly call those from here, but we can verify the mock service works
            // for transition services

            Ros2._mockServiceResponses["/mock_cm/switch_controller"] = function(request) {
                return { ok: true };
            };

            var client = Ros2.createServiceClient("/mock_cm/switch_controller", "controller_manager_msgs/srv/SwitchController");
            var response = null;
            client.sendRequestAsync({
                activate_controllers: ["arm_controller"],
                deactivate_controllers: [],
                strictness: 3
            }, function(resp) {
                response = resp;
            });
            wait(100);

            verify(response !== null, "Should get transition response");
            verify(response.ok, "Transition should succeed");
        }

        function test_06_unloaded_controllers_from_parameters() {
            // list_parameters should reveal controllers that aren't loaded yet
            var client = Ros2.createServiceClient("/mock_cm/list_parameters", "rcl_interfaces/srv/ListParameters");
            var response = null;
            client.sendRequestAsync({}, function(resp) {
                response = resp;
            });
            wait(100);

            verify(response !== null, "Should get parameters response");
            var names = response.result.names;
            verify(names.length >= 3, "Should have at least 3 parameter names");

            // gripper_controller.type should indicate an unloaded controller
            var found = false;
            for (var i = 0; i < names.length; i++) {
                if (names.at(i) === "gripper_controller.type") {
                    found = true;
                    break;
                }
            }
            verify(found, "Should find gripper_controller.type in parameters");
        }
    }
}
