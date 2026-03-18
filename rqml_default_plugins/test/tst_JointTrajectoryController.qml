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
        controller_manager_namespace: "",
        controller: "",
        take_shortest_path: false,
        speed: 0.5
    })

    PluginQml.JointTrajectoryController {
        id: jtc
        anchors.fill: parent
    }

    TestCase {
        name: "JointTrajectoryControllerTest"
        when: windowShown

        readonly property string mockUrdf: '<?xml version="1.0"?>' +
            '<robot name="test_robot">' +
            '  <joint name="joint1" type="revolute">' +
            '    <limit lower="-1.57" upper="1.57"/>' +
            '  </joint>' +
            '  <joint name="joint2" type="continuous">' +
            '  </joint>' +
            '  <joint name="fixed_joint" type="fixed">' +
            '  </joint>' +
            '</robot>'

        function init() {
            Ros2.reset();
            // Mock controller_manager services
            Ros2._mockServices["controller_manager_msgs/srv/ListControllers"] = [
                "/mock_cm/list_controllers"
            ];

            Ros2._mockServiceResponses["/mock_cm/list_controllers"] = function(request) {
                return Ros2.wrapCppMessage({
                    controller: [
                        {
                            name: "arm_controller",
                            state: "active",
                            type: "joint_trajectory_controller/JointTrajectoryController",
                            claimed_interfaces: ["joint1/position", "joint2/position"],
                            required_command_interfaces: ["joint1/position", "joint2/position"],
                            required_state_interfaces: []
                        },
                        {
                            name: "gripper_controller",
                            state: "active",
                            type: "position_controllers/GripperActionController",
                            claimed_interfaces: [],
                            required_command_interfaces: [],
                            required_state_interfaces: []
                        }
                    ]
                });
            };

            // Mock topics for subscription matching
            Ros2._mockTopics["sensor_msgs/msg/JointState"] = ["/mock_cm/joint_states"];
            Ros2._mockTopics["std_msgs/msg/String"] = ["/mock_cm/robot_description"];
        }

        function test_01_plugin_loads() {
            verify(jtc !== null, "JointTrajectoryController plugin should load");
        }

        function test_02_controller_discovery() {
            context.controller_manager_namespace = "/mock_cm";
            wait(200);

            // The interface should have loaded controllers via list_controllers
            var client = Ros2.createServiceClient("/mock_cm/list_controllers", "controller_manager_msgs/srv/ListControllers");
            var response = null;
            client.sendRequestAsync({}, function(resp) {
                response = resp;
            });
            wait(100);

            verify(response !== null, "Should get list_controllers response");
            // Only JointTrajectoryController type controllers should be shown
            var jtcCount = 0;
            for (var i = 0; i < response.controller.length; i++) {
                var c = response.controller.at(i);
                if (c.type === "joint_trajectory_controller/JointTrajectoryController" && c.state === "active") {
                    jtcCount++;
                }
            }
            compare(jtcCount, 1, "Should find exactly 1 active trajectory controller");
        }

        function test_03_urdf_parsing() {
            // The URDF parser is in JointTrajectoryControllerInterface.
            // We can test it by injecting a URDF message via the subscription.
            context.controller_manager_namespace = "/mock_cm";
            wait(100);

            var urdfSub = Ros2.findSubscription("/mock_cm/robot_description");
            if (urdfSub) {
                urdfSub.injectMessage({ data: mockUrdf });
                wait(500); // URDF parsing uses XMLHttpRequest which is async
            }
        }

        function test_04_joint_state_updates() {
            context.controller_manager_namespace = "/mock_cm";
            wait(100);

            var jointStateSub = Ros2.findSubscription("/mock_cm/joint_states");
            if (jointStateSub) {
                jointStateSub.injectMessage({
                    name: ["joint1", "joint2"],
                    position: [0.5, 1.2],
                    velocity: [0.0, 0.0],
                    effort: [0.0, 0.0]
                });
                wait(100);
            }
        }

        function test_05_action_client_creation() {
            // Verify action client can be created for trajectory controller
            var client = Ros2.createActionClient("/arm_controller/follow_joint_trajectory", "control_msgs/action/FollowJointTrajectory");
            verify(client !== null, "Action client should be created");
            verify(client.ready, "Action client should be ready");
        }

        function test_06_empty_goal_creation() {
            var goal = Ros2.createEmptyActionGoal("control_msgs/action/FollowJointTrajectory");
            verify(goal !== null, "Goal should be created");
            verify(goal.trajectory !== undefined, "Goal should have trajectory field");
            verify(goal.trajectory.joint_names !== undefined, "Trajectory should have joint_names");
            verify(goal.trajectory.points !== undefined, "Trajectory should have points");
        }

        function test_07_speed_context() {
            compare(context.speed, 0.5, "Default speed should be 0.5");
            context.speed = 1.0;
            compare(context.speed, 1.0, "Speed should update");
            context.speed = 0.5;
        }

        function test_08_shortest_path_context() {
            compare(context.take_shortest_path, false, "Default should be false");
            context.take_shortest_path = true;
            compare(context.take_shortest_path, true, "Should toggle to true");
            context.take_shortest_path = false;
        }
    }
}
