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

    QtObject {
        id: contextObj

        property string controller: ""
        property string controller_manager_namespace: ""
        property bool enabled: true
        property real speed: 0.5
        property bool take_shortest_path: false
    }
    Utils {
        id: helpers
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/JointTrajectoryController.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        id: testCase

        property var lastCallbacks: null
        property var lastGoal: null
        readonly property string mockUrdf: '<?xml version="1.0"?>' + '<robot name="test_robot">' + '  <joint name="joint1" type="revolute">' + '    <limit lower="-1.57" upper="1.57"/>' + '  </joint>' + '  <joint name="joint2" type="continuous">' + '  </joint>' + '</robot>'

        function init() {
            Ros2.reset();
            contextObj.controller_manager_namespace = "/mock_cm";
            contextObj.controller = "";
            lastGoal = null;
            lastCallbacks = null;

            // Register services, topics, and actions using the restored mock interface
            Ros2.registerService("/mock_cm/list_controllers", "controller_manager_msgs/srv/ListControllers", function (req) {
                    var resp = Ros2.createEmptyServiceResponse("controller_manager_msgs/srv/ListControllers");
                    var ctrl1 = Ros2.createEmptyMessage("controller_manager_msgs/msg/ControllerState");
                    ctrl1.name = "arm_controller";
                    ctrl1.state = "active";
                    ctrl1.type = "joint_trajectory_controller/JointTrajectoryController";
                    ctrl1.claimed_interfaces = ["joint1/position", "joint2/position"];
                    resp.controller = [ctrl1];
                    return resp;
                });
            Ros2.registerTopic("/mock_cm/joint_states", "sensor_msgs/msg/JointState");
            Ros2.registerTopic("/mock_cm/robot_description", "std_msgs/msg/String");
            Ros2.registerAction("/arm_controller/follow_joint_trajectory", "control_msgs/action/FollowJointTrajectory", function (goal, callbacks) {
                    lastGoal = JSON.parse(JSON.stringify(goal)); // Workaround for copy-on-access semantics
                    lastCallbacks = callbacks;
                });
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                });
        }
        function test_controls() {
            failOnWarning(/Binding loop/);
            // The speed slider only shows once a controller with joints is selected.
            test_joint_state_display();
            var ctrlCombo = find("jtcControllerComboBox");
            tryVerify(function () {
                    return ctrlCombo.count > 0;
                }, 5000);
            ctrlCombo.currentIndex = 0;
            var slider = find("jtcSpeedSlider");
            verify(slider !== null, "Speed slider should be found");
            tryVerify(function () {
                    return slider.visible && slider.width > 0;
                }, 5000);
            mouseClick(slider, slider.leftPadding + slider.availableWidth * 0.75, slider.height / 2);
            verify(slider.value > 2, "Clicking should move the slider, value: " + slider.value);
            compare(contextObj.speed, slider.value, "Context speed should sync with slider");
            var shortestSwitch = find("jtcShortestPathSwitch");
            verify(shortestSwitch !== null, "Shortest path switch should be found");
            mouseClick(shortestSwitch);
            verify(contextObj.take_shortest_path, "Context take_shortest_path should toggle");
        }
        function test_discovery() {
            var ctrlCombo = find("jtcControllerComboBox");
            verify(ctrlCombo !== null, "Controller ComboBox should be found");
            tryVerify(function () {
                    return ctrlCombo.count > 0;
                }, 5000, "Should find at least 1 controller");
            compare(ctrlCombo.model.get(0).name, "arm_controller");
        }
        function test_enter_sends_goal() {
            test_joint_state_display();
            var ctrlCombo = find("jtcControllerComboBox");
            tryVerify(function () {
                    return ctrlCombo.count > 0;
                }, 5000);
            ctrlCombo.currentIndex = 0;
            var sendBtn = find("jtcSendButton");
            tryVerify(function () {
                    return sendBtn.enabled;
                }, 5000, "Send button should be enabled");
            find("jtcJointListView").forceActiveFocus();
            keyClick(Qt.Key_Return);
            tryVerify(function () {
                    return lastGoal !== null;
                }, 5000, "Return should send the goal");
            verify(sendBtn.activeFocus, "Send/Cancel button should take focus after sending");
        }
        function test_goal_field_typing() {
            failOnWarning(/Binding loop/);
            test_joint_state_display();
            // Joint rows only show once a controller is selected.
            var ctrlCombo = find("jtcControllerComboBox");
            tryVerify(function () {
                    return ctrlCombo.count > 0;
                }, 5000);
            ctrlCombo.currentIndex = 0;
            var list = find("jtcJointListView");
            // ListView creates its delegates on the next polish, not when the model changes.
            var field = null;
            tryVerify(function () {
                    field = find("jtcGoalField_0");
                    return field !== null && field.visible;
                }, 5000, "Goal field should be shown");
            field.forceActiveFocus();
            field.selectAll();
            // The goal rounds to 0.13, which must not replace the text being typed.
            keyClick(Qt.Key_0);
            keyClick(Qt.Key_Period);
            keyClick(Qt.Key_1);
            keyClick(Qt.Key_2);
            keyClick(Qt.Key_5);
            compare(field.text, "0.125", "Typing should not be overwritten by the goal binding");
            compare(list.model.get(0).goal, 0.13);

            // Out-of-range input clamps to joint1's upper limit, shown once the field loses focus.
            field.selectAll();
            keyClick(Qt.Key_9);
            compare(list.model.get(0).goal, 1.57);
            find("jtcSendButton").forceActiveFocus();
            compare(field.text, "1.57");
            list.model.setProperty(0, "goal", 0.25);
            compare(field.text, "0.25", "External goal changes should show in the field");
        }
        function test_joint_state_display() {
            // 1. Inject URDF
            var urdfSub = Ros2.findSubscription("/mock_cm/robot_description");
            verify(urdfSub !== null, "URDF subscription should exist");
            urdfSub.injectMessage({
                    "data": mockUrdf
                });
            var list = find("jtcJointListView");
            verify(list !== null, "Joint list should be found");
            tryVerify(function () {
                    return list.count === 2;
                }, 5000, "Should find 2 joints from URDF");

            // 2. Inject JointState
            var jsSub = Ros2.findSubscription("/mock_cm/joint_states");
            verify(jsSub !== null, "JointState subscription should exist");
            jsSub.injectMessage({
                    "name": ["joint1", "joint2"],
                    "position": [0.5, 1.2]
                });
            tryVerify(function () {
                    var j1 = list.model.get(0);
                    var j2 = list.model.get(1);
                    return j1 && j2 && Math.abs(j1.position - 0.5) < 0.05 && Math.abs(j2.position - 1.2) < 0.05;
                }, 5000, "Joint positions should update from injected message");
        }
        function test_send_goal() {
            test_joint_state_display();

            // Select the controller via the real ComboBox so we exercise the
            // discovery → selection → context wiring instead of poking context.
            var ctrlCombo = find("jtcControllerComboBox");
            verify(ctrlCombo !== null, "Controller ComboBox should be found");
            tryVerify(function () {
                    return ctrlCombo.count > 0;
                }, 5000);
            ctrlCombo.currentIndex = 0;
            tryCompare(contextObj, "controller", "arm_controller", 2000, "Selecting in combo should propagate to context");
            var list = find("jtcJointListView");
            var j1 = list.model.get(0);
            j1.goal = 0.8;
            var sendBtn = find("jtcSendButton");
            verify(sendBtn !== null, "Send button should be found");
            tryVerify(function () {
                    return sendBtn.enabled;
                }, 5000, "Send button should be enabled");
            mouseClick(sendBtn);
            tryVerify(function () {
                    return lastGoal !== null;
                }, 5000, "Goal should be received by mock");

            // Standard array access [] for mock objects
            var names = lastGoal.trajectory.joint_names;
            var j1Index = -1;
            for (var i = 0; i < names.length; ++i) {
                if (names[i] === "joint1") {
                    j1Index = i;
                    break;
                }
            }
            if (j1Index !== -1) {
                var points = lastGoal.trajectory.points;
                var lastPoint = points[points.length - 1];
                compare(lastPoint.positions[j1Index], 0.8);
            }
        }

        name: "JointTrajectoryControllerTest"
        when: windowShown
    }
}
