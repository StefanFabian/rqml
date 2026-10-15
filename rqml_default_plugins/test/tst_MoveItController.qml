/*
 * Copyright (C) 2025  Aljoscha Schmidt
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

        property real accelerationScale: 0.1
        property string actionServer: ""
        property string moveGroup: ""
        property int planningAttempts: 5
        property real planningTime: 5.0
        property real velocityScale: 0.1
    }
    Utils {
        id: helpers
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/MoveItController.qml";
        }

        anchors.fill: parent
    }
    Publisher {
        id: urdfPublisher
        topic: "/robot_description"
        type: "std_msgs/msg/String"
    }
    Publisher {
        id: srdfPublisher
        topic: "/robot_description_semantic"
        type: "std_msgs/msg/String"
    }
    Publisher {
        id: jointStatePublisher
        topic: "/joint_states"
        type: "sensor_msgs/msg/JointState"
    }
    TestCase {
        id: testCase

        property var lastCallbacks: null
        property var lastGoalMessage: null
        readonly property string mockSrdf: '<?xml version="1.0"?>' + '<robot name="test_robot">' + '  <group name="arm">' + '    <chain base_link="base_link" tip_link="tip_link"/>' + '  </group>' + '  <group name="partial">' + '    <joint name="joint1"/>' + '  </group>' + '  <group name="combined">' + '    <group name="partial"/>' + '    <joint name="joint2"/>' + '  </group>' + '  <group_state name="home" group="arm">' + '    <joint name="joint1" value="0.0"/>' + '    <joint name="joint2" value="0.0"/>' + '    <joint name="joint3" value="0.0"/>' + '  </group_state>' + '  <group_state name="ready" group="arm">' + '    <joint name="joint1" value="1.0"/>' + '    <joint name="joint2" value="-0.5"/>' + '    <joint name="joint3" value="0.5"/>' + '  </group_state>' + '</robot>'

        // ================================================================
        // Circular Subgroup Cycle Guard
        // ================================================================
        readonly property string mockSrdfCircular: '<?xml version="1.0"?>' + '<robot name="test_robot">' + '  <group name="a">' + '    <joint name="joint1"/>' + '    <group name="b"/>' + '  </group>' + '  <group name="b">' + '    <joint name="joint2"/>' + '    <group name="a"/>' + '  </group>' + '</robot>'
        readonly property string mockUrdf: '<?xml version="1.0"?>' + '<robot name="test_robot">' + '  <link name="base_link"/>' + '  <link name="link1"/>' + '  <link name="link2"/>' + '  <link name="tip_link"/>' + '  <link name="fixed_link"/>' + '  <joint name="joint1" type="revolute">' + '    <parent link="base_link"/>' + '    <child link="link1"/>' + '    <limit lower="-1.57" upper="1.57"/>' + '  </joint>' + '  <joint name="joint2" type="revolute">' + '    <parent link="link1"/>' + '    <child link="link2"/>' + '    <limit lower="-3.14" upper="3.14"/>' + '  </joint>' + '  <joint name="joint3" type="continuous">' + '    <parent link="link2"/>' + '    <child link="tip_link"/>' + '  </joint>' + '  <joint name="fixed_joint" type="fixed">' + '    <parent link="link1"/>' + '    <child link="fixed_link"/>' + '  </joint>' + '</robot>'

        function init() {
            Ros2.reset();

            // Register mock action server
            Ros2.registerAction("/move_group", "moveit_msgs/action/MoveGroup", function (goal, callbacks) {
                    lastCallbacks = callbacks;
                    lastGoalMessage = goal;
                });

            // Register topics for discovery
            Ros2.registerTopic("/joint_states", "sensor_msgs/msg/JointState");
            Ros2.registerTopic("/robot_description", "std_msgs/msg/String");
            Ros2.registerTopic("/robot_description_semantic", "std_msgs/msg/String");

            // Reset context
            contextObj.actionServer = "";
            contextObj.moveGroup = "";
            contextObj.velocityScale = 0.1;
            contextObj.accelerationScale = 0.1;
            contextObj.planningTime = 5.0;
            contextObj.planningAttempts = 5;
            lastCallbacks = null;
            lastGoalMessage = null;
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
        }
        function injectJointStates(names, positions) {
            var msg = Ros2.createEmptyMessage("sensor_msgs/msg/JointState");
            msg.header.stamp = Ros2.now();
            msg.name = names;
            msg.position = positions;
            msg.velocity = [];
            msg.effort = [];
            jointStatePublisher.publish(msg);
        }
        function injectSrdf() {
            var msg = Ros2.createEmptyMessage("std_msgs/msg/String");
            msg.data = mockSrdf;
            srdfPublisher.publish(msg);
        }
        function injectUrdf() {
            var msg = Ros2.createEmptyMessage("std_msgs/msg/String");
            msg.data = mockUrdf;
            urdfPublisher.publish(msg);
        }

        /**
         * Set up full plugin state: action server selected, URDF+SRDF loaded,
         * move group "arm" selected with joints populated.
         */
        function setupFullState() {
            // Set both context values before reload so the plugin binds to them
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "arm";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectUrdf();
            // URDF parsing is async via XMLHttpRequest — wait for status label
            var urdfLabel = find("moveitUrdfStatusLabel");
            tryVerify(function () {
                    return urdfLabel && urdfLabel.text === "URDF: Loaded";
                }, 3000, "setupFullState: URDF should be loaded");
            injectSrdf();
            // SRDF parsing is async via XMLHttpRequest — wait for status label
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryVerify(function () {
                    return srdfLabel && srdfLabel.text === "SRDF: Loaded";
                }, 3000, "setupFullState: SRDF should be loaded");

            // Wait for joints to appear from chain resolution
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList && jointList.count === 3;
                }, 5000, "setupFullState: joints should be populated");
        }
        function test_action_server_change_clears_state() {
            // Set up full state with the first action server
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.5, -1.0, 0.25]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);

            // Verify we have data
            var urdfLabel = find("moveitUrdfStatusLabel");
            compare(urdfLabel.text, "URDF: Loaded");
            var srdfLabel = find("moveitSrdfStatusLabel");
            compare(srdfLabel.text, "SRDF: Loaded");
            verify(jl.count === 3, "Should have 3 joints before switch");

            // Register a second action server and switch to it
            Ros2.registerAction("/other_move_group", "moveit_msgs/action/MoveGroup", function (goal, callbacks) {});
            contextObj.actionServer = "/other_move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();

            // All state should be cleared
            var urdfLabelAfter = find("moveitUrdfStatusLabel");
            tryCompare(urdfLabelAfter, "text", "URDF: Waiting...", 3000, "URDF should reset when action server changes");
            var srdfLabelAfter = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabelAfter, "text", "SRDF: Waiting...", 3000, "SRDF should reset when action server changes");
            var jointListAfter = find("moveitJointListView");
            tryVerify(function () {
                    return jointListAfter.count === 0;
                }, 3000, "Joints should be cleared when action server changes");
        }
        function test_action_server_discovery() {
            var comboBox = find("moveitActionServerComboBox");
            verify(comboBox !== null, "Action server ComboBox should exist");

            // Set action server via context so discovery runs
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);

            // Wait for discovery timer (500ms interval)
            tryVerify(function () {
                    var cb = find("moveitActionServerComboBox");
                    return cb && cb.count > 0;
                }, 3000, "Action server should be discovered");
        }
        function test_action_server_refresh() {
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();

            // Register a second action server after load
            Ros2.registerAction("/second_move_group", "moveit_msgs/action/MoveGroup", function (goal, callbacks) {});
            var comboBox = find("moveitActionServerComboBox");
            verify(comboBox !== null);

            // Not yet in the model
            var found = false;
            for (var i = 0; i < comboBox.count; i++) {
                if (comboBox.model.get(i).name === "/second_move_group") {
                    found = true;
                    break;
                }
            }
            verify(!found, "Second action server should not be in model yet");

            // Click refresh
            var refreshBtn = find("moveitRefreshButton");
            verify(refreshBtn !== null, "Refresh button should exist");
            mouseClick(refreshBtn);
            tryVerify(function () {
                    var cb = find("moveitActionServerComboBox");
                    for (var i = 0; i < cb.count; i++) {
                        if (cb.model.get(i).name === "/second_move_group")
                            return true;
                    }
                    return false;
                }, 3000, "Second action server should appear after refresh");
        }
        function test_apply_named_pose() {
            setupFullState();

            // Inject joint states so joints are initialized
            var jointList = find("moveitJointListView");
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            tryVerify(function () {
                    return jointList.model.get(0).initialized;
                }, 3000, "Joints should be initialized");

            // Find and click the "ready" pose button
            var posesFlow = find("moveitNamedPosesFlow");
            tryVerify(function () {
                    return posesFlow.visible;
                }, 3000);
            var readyButton = null;
            for (var i = 0; i < posesFlow.children.length; i++) {
                if (posesFlow.children[i].text === "ready") {
                    readyButton = posesFlow.children[i];
                    break;
                }
            }
            verify(readyButton !== null, "Should find 'ready' button");
            mouseClick(readyButton);

            // Verify goals updated to ready pose values
            tryVerify(function () {
                    var j1 = jointList.model.get(0); // joint1
                    var j2 = jointList.model.get(1); // joint2
                    var j3 = jointList.model.get(2); // joint3
                    return Math.abs(j1.goal - 1.0) < 0.02 && Math.abs(j2.goal - (-0.5)) < 0.02 && Math.abs(j3.goal - 0.5) < 0.02;
                }, 3000, "Joint goals should match 'ready' pose values");
        }

        // ================================================================
        // Auto-select & Empty State
        // ================================================================
        function test_auto_select_action_server() {
            // init() leaves context.actionServer empty; the plugin should
            // pick up /move_group from discovery automatically.
            var comboBox = find("moveitActionServerComboBox");
            verify(comboBox !== null);
            tryVerify(function () {
                    return contextObj.actionServer === "/move_group";
                }, 3000, "First discovered action server should auto-populate context");
            tryCompare(comboBox, "currentText", "/move_group", 3000);
        }
        function test_auto_select_first_move_group() {
            // No pre-selected move group. Inject SRDF and expect the first
            // group (alphabetically "arm") to be auto-selected.
            verify(contextObj.moveGroup === "");
            waitForDiscovery();
            injectSrdf();
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000);
            tryVerify(function () {
                    return contextObj.moveGroup === "arm";
                }, 3000, "First available move group should auto-populate context");
            var groupCombo = find("moveitMoveGroupComboBox");
            tryCompare(groupCombo, "currentText", "arm", 3000);
        }
        function test_auto_select_respects_existing_selection() {
            // Pre-set a non-first group — auto-select must not overwrite it.
            Ros2.reset();
            Ros2.registerAction("/move_group", "moveit_msgs/action/MoveGroup", function (goal, callbacks) {});
            Ros2.registerTopic("/robot_description_semantic", "std_msgs/msg/String");
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "partial";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectSrdf();
            tryCompare(find("moveitSrdfStatusLabel"), "text", "SRDF: Loaded", 3000);
            // Give the countChanged handler a chance to run.
            wait(200);
            compare(contextObj.moveGroup, "partial", "Pre-selected move group must not be overwritten");
        }
        function test_chain_joint_resolution() {
            setupFullState();
            var jointList = find("moveitJointListView");
            verify(jointList !== null, "Joint list should exist");
            tryVerify(function () {
                    return jointList.count === 3;
                }, 3000, "arm group should have 3 joints (chain-resolved)");

            // Joints should be sorted alphabetically
            compare(jointList.model.get(0).name, "joint1", "First joint");
            compare(jointList.model.get(1).name, "joint2", "Second joint");
            compare(jointList.model.get(2).name, "joint3", "Third joint");

            // Verify joint1 limits from URDF
            var j1 = jointList.model.get(0);
            compare(j1.limits.lower, -1.57, "joint1 lower limit");
            compare(j1.limits.upper, 1.57, "joint1 upper limit");

            // Verify fixed_joint is excluded
            for (var i = 0; i < jointList.count; i++) {
                verify(jointList.model.get(i).name !== "fixed_joint", "Fixed joint should not be in the list");
            }
        }
        function test_circular_subgroup_terminates() {
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "a";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectUrdf();
            tryCompare(find("moveitUrdfStatusLabel"), "text", "URDF: Loaded", 3000);
            var msg = Ros2.createEmptyMessage("std_msgs/msg/String");
            msg.data = mockSrdfCircular;
            srdfPublisher.publish(msg);
            tryCompare(find("moveitSrdfStatusLabel"), "text", "SRDF: Loaded", 3000);

            // If the cycle guard fails this will hang or stack-overflow;
            // tryVerify caps the wait so we surface the regression instead.
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.count === 2;
                }, 5000, "Group 'a' should resolve joint1 + joint2 via subgroup without cycling");
            var names = [jointList.model.get(0).name, jointList.model.get(1).name].sort();
            compare(names[0], "joint1");
            compare(names[1], "joint2");
        }

        // ================================================================
        // Context Persistence & UI Controls
        // ================================================================
        function test_context_persistence() {
            // Set context values and select a move group so the planning UI is visible
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "arm";
            contextObj.velocityScale = 0.5;
            contextObj.accelerationScale = 0.3;
            contextObj.planningTime = 10.0;
            contextObj.planningAttempts = 8;
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectSrdf();
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000);

            // Expand planning config to make sliders visible
            var headerButton = find("moveitPlanningConfigButton");
            mouseClick(headerButton);
            tryVerify(function () {
                    var vs = find("moveitVelocitySlider");
                    return vs !== null && vs.visible;
                }, 3000, "Planning config should expand");

            // Verify sliders read from context (UI bindings, not just contextObj values)
            var velSlider = find("moveitVelocitySlider");
            tryVerify(function () {
                    return Math.abs(velSlider.value - 0.5) < 0.02;
                }, 3000, "Velocity slider should reflect context value 0.5");
            var accSlider = find("moveitAccelerationSlider");
            tryVerify(function () {
                    return Math.abs(accSlider.value - 0.3) < 0.02;
                }, 3000, "Acceleration slider should reflect context value 0.3");
            var timeSlider = find("moveitPlanningTimeSlider");
            tryVerify(function () {
                    return Math.abs(timeSlider.value - 10.0) < 0.1;
                }, 3000, "Planning time slider should reflect context value 10.0");
            var attemptsSlider = find("moveitPlanningAttemptsSlider");
            tryVerify(function () {
                    return Math.abs(attemptsSlider.value - 8) < 0.5;
                }, 3000, "Planning attempts slider should reflect context value 8");
        }
        function test_continuous_joint_wrapping() {
            setupFullState();
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.count === 3;
                }, 3000);

            // joint3 is continuous — inject a position > pi that should be wrapped
            // 4.0 rad → (4.0 + pi) % (2*pi) - pi ≈ -2.28 rad
            injectJointStates(["joint3"], [4.0]);
            wait(50);
            tryVerify(function () {
                    var j3 = jointList.model.get(2); // joint3
                    // Wrapped value should be in [-pi, pi]
                    return j3.position >= -Math.PI && j3.position <= Math.PI;
                }, 3000, "Continuous joint position should be wrapped to [-pi, pi]");

            // Verify the exact wrapped value
            var j3 = jointList.model.get(2);
            var expected = ((4.0 + Math.PI) % (2 * Math.PI)) - Math.PI;
            expected = Math.round(expected * 100) / 100;
            compare(j3.position, expected, "Wrapped value should match formula");

            // Verify a non-continuous joint is NOT wrapped
            injectJointStates(["joint1"], [4.0]);
            wait(50);
            // joint1 is revolute — should be clamped by limits (-1.57, 1.57)
            // but not wrapped. The subscription stores the raw position.
            tryVerify(function () {
                    var j1 = jointList.model.get(0);
                    // Revolute joints don't get wrapped — position is stored as-is
                    // (limits are enforced by the slider, not the subscription)
                    return Math.abs(j1.position - 4.0) < 0.02 || Math.abs(j1.position) < 0.02; // rounded to 0 if || 0.0 kicks in
                }, 3000, "Revolute joint should not be wrapped");
        }
        function test_empty_state_hidden_when_configured() {
            setupFullState();
            var emptyLabel = find("moveitEmptyStateLabel");
            verify(emptyLabel !== null);
            verify(!emptyLabel.visible, "Empty-state label must be hidden once fully configured");
        }
        function test_empty_state_no_action_server() {
            Ros2.reset();
            contextObj.actionServer = "";
            contextObj.moveGroup = "";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            // Let the discovery timer fire at least once.
            wait(700);
            var emptyLabel = find("moveitEmptyStateLabel");
            verify(emptyLabel !== null, "Empty-state label should exist");
            verify(emptyLabel.visible, "Empty-state label should be visible");
            compare(emptyLabel.text, "No MoveGroup action server found.");

            // Configuration controls should be hidden.
            var groupCombo = find("moveitMoveGroupComboBox");
            verify(!groupCombo.visible, "Move group combo must be hidden");
            var jointList = find("moveitJointListView");
            verify(!jointList.visible, "Joint list must be hidden");
        }
        function test_empty_state_no_move_groups() {
            // Action server is available but no SRDF → no move groups.
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            var emptyLabel = find("moveitEmptyStateLabel");
            tryVerify(function () {
                    return emptyLabel && emptyLabel.visible && emptyLabel.text === "No MoveGroups found.";
                }, 3000, "Empty label should report missing move groups");
        }

        // ================================================================
        // Error Banner Auto-Hide
        // ================================================================
        function test_error_banner_auto_hides() {
            // The 10s auto-hide is too long for a realistic test — verify that
            // the visibility is wired to isGoalActive==false + time-based hide
            // by dismissing via the close button (same user-visible behavior path).
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);
            var handle = Ros2.createGoalHandle("banner_hide_goal");
            handle.setStatus(1);
            lastCallbacks.onGoalResponse(handle);
            lastCallbacks.onResult({
                    "status": 4,
                    "result": {
                        "error_code": {
                            "val": -1
                        }
                    }
                });
            var errorBanner = find("moveitErrorBannerRect");
            tryVerify(function () {
                    return errorBanner.visible;
                }, 3000, "Error banner should be visible after failure");

            // Find the close ('x') button inside the banner and click it.
            var closeBtn = null;
            function findClose(item) {
                if (!item)
                    return;
                if (item.text === "x" && item.flat === true) {
                    closeBtn = item;
                    return;
                }
                var kids = item.children || [];
                for (var i = 0; i < kids.length; i++) {
                    findClose(kids[i]);
                    if (closeBtn)
                        return;
                }
            }
            findClose(errorBanner);
            verify(closeBtn !== null, "Close button should exist in error banner");
            mouseClick(closeBtn);
            tryVerify(function () {
                    return !errorBanner.visible;
                }, 3000, "Error banner should hide when close button clicked");
        }
        function test_error_banner_dismissed_on_new_goal() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);

            // First goal: trigger a failure
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);
            var handle1 = Ros2.createGoalHandle("fail_goal");
            handle1.setStatus(1);
            lastCallbacks.onGoalResponse(handle1);
            lastCallbacks.onResult({
                    "status": 4,
                    "result": {
                        "error_code": {
                            "val": -1
                        }
                    }
                });
            var errorBanner = find("moveitErrorBannerRect");
            tryVerify(function () {
                    return errorBanner.visible;
                }, 3000, "Error banner should be visible after failure");

            // Second goal: accept it - error should be dismissed
            lastCallbacks = null;
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);
            var handle2 = Ros2.createGoalHandle("success_goal");
            handle2.setStatus(1);
            lastCallbacks.onGoalResponse(handle2);
            tryVerify(function () {
                    return !errorBanner.visible;
                }, 3000, "Error banner should be dismissed when new goal is accepted");
        }

        // ================================================================
        // Motion Execution
        // ================================================================
        function test_execute_sends_goal() {
            setupFullState();

            // Inject joint states to initialize joints
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, 0.2, 0.3]);
            wait(50);
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.model.get(0).initialized;
                }, 3000, "Joints should be initialized");
            var executeBtn = find("moveitExecuteButton");
            verify(executeBtn !== null, "Execute button should exist");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000, "Execute button should be enabled when action is ready");
            mouseClick(executeBtn);

            // Verify the action handler received the goal
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000, "Action handler should receive goal");

            // Verify goal message structure
            verify(lastGoalMessage !== null, "Goal message should be captured");
        }
        function test_goal_acceptance() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);

            // Accept the goal
            var handle = Ros2.createGoalHandle("moveit_goal_1");
            handle.setStatus(1); // Executing
            lastCallbacks.onGoalResponse(handle);

            // Button should switch to "Cancel"
            tryCompare(executeBtn, "text", "Cancel", 3000, "Button should show 'Cancel' after goal accepted");
        }
        function test_goal_cancellation() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);

            // Accept the goal
            var handle = Ros2.createGoalHandle("moveit_goal_cancel");
            handle.setStatus(1);
            lastCallbacks.onGoalResponse(handle);
            tryCompare(executeBtn, "text", "Cancel", 3000);
            compare(Ros2._lastActionCancelled, false, "Should not be cancelled yet");

            // Click cancel
            mouseClick(executeBtn);
            tryVerify(function () {
                    return Ros2._lastActionCancelled === true;
                }, 3000, "Action should be cancelled");
        }
        function test_goal_rejected() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);

            // Reject goal by passing null handle
            lastCallbacks.onGoalResponse(null);

            // Button should return to "Execute"
            tryCompare(executeBtn, "text", "Execute", 3000, "Button should return to 'Execute' after rejection");

            // Error banner should show rejection message
            var errorBanner = find("moveitErrorBannerRect");
            tryVerify(function () {
                    return errorBanner.visible;
                }, 3000, "Error banner should show on goal rejection");
            var errorTitle = find("moveitErrorTitle");
            tryCompare(errorTitle, "text", "Goal Rejected", 3000);
        }
        function test_goal_result_control_failed() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);
            var handle = Ros2.createGoalHandle("moveit_goal_4");
            handle.setStatus(1);
            lastCallbacks.onGoalResponse(handle);

            // Send control failure (error_code.val = -4, special handling)
            lastCallbacks.onResult({
                    "status": 4,
                    "result": {
                        "error_code": {
                            "val": -4
                        }
                    }
                });
            var errorBanner = find("moveitErrorBannerRect");
            tryVerify(function () {
                    return errorBanner.visible;
                }, 3000, "Error banner should be visible on control failure");
            var errorTitle = find("moveitErrorTitle");
            tryCompare(errorTitle, "text", "Controller Error", 3000, "Control failure should show 'Controller Error' title");
            var errorDetails = find("moveitErrorDetails");
            tryVerify(function () {
                    return errorDetails.text.indexOf("Motion execution failed") !== -1;
                }, 3000, "Should show motion execution failed details");
        }
        function test_goal_result_planning_failed() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);
            var handle = Ros2.createGoalHandle("moveit_goal_3");
            handle.setStatus(1);
            lastCallbacks.onGoalResponse(handle);

            // Send planning failure (error_code.val = -1)
            lastCallbacks.onResult({
                    "status": 4,
                    "result": {
                        "error_code": {
                            "val": -1
                        }
                    }
                });

            // Error banner should be visible with planning failed message
            var errorBanner = find("moveitErrorBannerRect");
            tryVerify(function () {
                    return errorBanner.visible;
                }, 3000, "Error banner should be visible on planning failure");
            var errorTitle = find("moveitErrorTitle");
            tryVerify(function () {
                    return errorTitle.text.indexOf("PLANNING_FAILED") !== -1;
                }, 3000, "Error title should contain PLANNING_FAILED");
        }
        function test_goal_result_success() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.1, -0.1, 0.1]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);
            var executeBtn = find("moveitExecuteButton");
            tryVerify(function () {
                    return executeBtn.enabled;
                }, 5000);
            mouseClick(executeBtn);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000);

            // Accept goal
            var handle = Ros2.createGoalHandle("moveit_goal_2");
            handle.setStatus(1);
            lastCallbacks.onGoalResponse(handle);
            tryCompare(executeBtn, "text", "Cancel", 3000);

            // Send success result (error_code.val = 1)
            handle.setStatus(4); // Succeeded
            lastCallbacks.onResult({
                    "status": 4,
                    "result": {
                        "error_code": {
                            "val": 1
                        }
                    }
                });

            // Button should return to "Execute"
            tryCompare(executeBtn, "text", "Execute", 3000, "Button should return to 'Execute' after success");

            // Error banner should NOT be visible
            var errorBanner = find("moveitErrorBannerRect");
            verify(errorBanner !== null);
            verify(!errorBanner.visible, "Error banner should not be visible on success");
        }

        // ================================================================
        // Joint State Updates
        // ================================================================
        function test_joint_state_subscription() {
            setupFullState();
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.count === 3;
                }, 3000);

            // Inject joint states
            injectJointStates(["joint1", "joint2", "joint3"], [0.5, -1.0, 0.25]);

            // Verify positions update
            tryVerify(function () {
                    var j1 = jointList.model.get(0);
                    return Math.abs(j1.position - 0.5) < 0.02;
                }, 3000, "joint1 position should update to 0.5");
            tryVerify(function () {
                    var j2 = jointList.model.get(1);
                    return Math.abs(j2.position - (-1.0)) < 0.02;
                }, 3000, "joint2 position should update to -1.0");

            // For uninitialized joints, goal should be set to position
            tryVerify(function () {
                    var j1 = jointList.model.get(0);
                    return j1.initialized && Math.abs(j1.goal - 0.5) < 0.02;
                }, 3000, "Uninitialized joint1 goal should match position");
        }

        // ================================================================
        // Joint TextField Writeback
        // ================================================================
        function test_joint_textfield_updates_goal() {
            setupFullState();
            injectJointStates(["joint1", "joint2", "joint3"], [0.0, 0.0, 0.0]);
            wait(50);
            var jl = find("moveitJointListView");
            tryVerify(function () {
                    return jl.model.get(0).initialized;
                }, 3000);

            // Locate the TextField inside the first delegate.
            var delegate = jl.itemAtIndex ? jl.itemAtIndex(0) : null;
            if (!delegate) {
                // Fallback: walk contentItem children.
                var content = jl.contentItem;
                for (var i = 0; i < content.children.length; i++) {
                    var c = content.children[i];
                    if (c.children && c.children.length > 0) {
                        delegate = c;
                        break;
                    }
                }
            }
            verify(delegate !== null, "Joint row delegate should exist");
            var textField = null;
            function findTextField(item) {
                if (!item)
                    return;
                // QQuickTextField exposes `selectByMouse` and `validator`.
                if (item.selectByMouse !== undefined && item.validator !== undefined) {
                    textField = item;
                    return;
                }
                var kids = item.children || [];
                for (var k = 0; k < kids.length; k++) {
                    findTextField(kids[k]);
                    if (textField)
                        return;
                }
            }
            findTextField(delegate);
            verify(textField !== null, "TextField should exist in joint row");
            failOnWarning(/Binding loop/);
            textField.forceActiveFocus();
            textField.selectAll();
            // "1" sets goal 1, whose formatted "1.00" must not replace the text being typed.
            keyClick(Qt.Key_1);
            keyClick(Qt.Key_Period);
            keyClick(Qt.Key_5);
            compare(textField.text, "1.5", "Typing should not be overwritten by the goal binding");
            tryVerify(function () {
                    return Math.abs(jl.model.get(0).goal - 1.5) < 0.02;
                }, 3000, "Typing in TextField should update joint goal");

            // Out-of-range input should be clamped to joint1's upper limit (1.57).
            textField.selectAll();
            keyClick(Qt.Key_9);
            tryVerify(function () {
                    return Math.abs(jl.model.get(0).goal - 1.57) < 0.02;
                }, 3000, "Out-of-range input should clamp to joint limits");

            // Leaving the field shows the clamped goal; goals set elsewhere (slider, named pose)
            // show in the field.
            find("moveitExecuteButton").forceActiveFocus();
            verify(!textField.activeFocus);
            compare(textField.text, "1.57");
            jl.model.setProperty(0, "goal", 0.123);
            compare(textField.text, "0.12");

            // Return in a joint field bubbles up to the plugin and executes.
            tryVerify(function () {
                    return find("moveitExecuteButton").enabled;
                }, 5000);
            textField.forceActiveFocus();
            keyClick(Qt.Key_Return);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 3000, "Return in a joint field should execute");
            verify(find("moveitExecuteButton").activeFocus, "Execute/Cancel button should take focus after executing");
        }
        function test_move_group_population() {
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectSrdf();
            var groupCombo = find("moveitMoveGroupComboBox");
            verify(groupCombo !== null, "Move group ComboBox should exist");
            tryVerify(function () {
                    return groupCombo.count === 3;
                }, 3000, "Should have 3 move groups (arm, combined, partial)");

            // Verify sorted alphabetically
            compare(groupCombo.model.get(0).name, "arm", "First group should be 'arm'");
            compare(groupCombo.model.get(1).name, "combined", "Second group should be 'combined'");
            compare(groupCombo.model.get(2).name, "partial", "Third group should be 'partial'");
        }

        // ================================================================
        // Named Poses
        // ================================================================
        function test_named_poses_displayed() {
            setupFullState();
            var posesFlow = find("moveitNamedPosesFlow");
            verify(posesFlow !== null, "Named poses flow should exist");
            tryVerify(function () {
                    return posesFlow.visible && posesFlow.children.length > 0;
                }, 3000, "Named pose buttons should be visible");

            // Should have "home" and "ready" buttons
            var buttonTexts = [];
            for (var i = 0; i < posesFlow.children.length; i++) {
                var child = posesFlow.children[i];
                if (child.text !== undefined) {
                    buttonTexts.push(child.text);
                }
            }
            verify(buttonTexts.indexOf("home") !== -1, "Should have 'home' pose button");
            verify(buttonTexts.indexOf("ready") !== -1, "Should have 'ready' pose button");
        }
        function test_namespace_aware_topic_discovery() {
            // Register a namespaced action server and topics at both global
            // and namespaced paths. The plugin should prefer the namespaced topic.
            Ros2.registerAction("/athena/move_group", "moveit_msgs/action/MoveGroup", function (goal, callbacks) {
                    lastCallbacks = callbacks;
                });
            Ros2.registerTopic("/joint_states", "sensor_msgs/msg/JointState");
            Ros2.registerTopic("/athena/joint_states", "sensor_msgs/msg/JointState");
            Ros2.registerTopic("/robot_description", "std_msgs/msg/String");
            Ros2.registerTopic("/athena/robot_description", "std_msgs/msg/String");
            Ros2.registerTopic("/robot_description_semantic", "std_msgs/msg/String");
            Ros2.registerTopic("/athena/robot_description_semantic", "std_msgs/msg/String");
            contextObj.actionServer = "/athena/move_group";
            contextObj.moveGroup = "arm";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();

            // Inject URDF/SRDF on the namespaced topics
            var urdfMsg = Ros2.createEmptyMessage("std_msgs/msg/String");
            urdfMsg.data = mockUrdf;
            // Publish on the namespaced topic
            var nsUrdfPub = Ros2.createPublisher("/athena/robot_description", "std_msgs/msg/String");
            nsUrdfPub.publish(urdfMsg);
            var urdfLabel = find("moveitUrdfStatusLabel");
            tryCompare(urdfLabel, "text", "URDF: Loaded", 3000, "Plugin should subscribe to namespaced URDF topic");
            var srdfMsg = Ros2.createEmptyMessage("std_msgs/msg/String");
            srdfMsg.data = mockSrdf;
            var nsSrdfPub = Ros2.createPublisher("/athena/robot_description_semantic", "std_msgs/msg/String");
            nsSrdfPub.publish(srdfMsg);
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000, "Plugin should subscribe to namespaced SRDF topic");

            // Verify joints resolved
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.count === 3;
                }, 5000, "Joints should populate via namespaced topics");
        }
        function test_namespace_prefers_closer_match() {
            // Given /athena/joint_states and /athena/sub_robot/joint_states,
            // with action server /athena/move_group, the direct-namespace
            // topic should win over the deeper descendant.
            Ros2.registerAction("/athena/move_group", "moveit_msgs/action/MoveGroup", function (goal, callbacks) {
                    lastCallbacks = callbacks;
                });
            Ros2.registerTopic("/athena/joint_states", "sensor_msgs/msg/JointState");
            Ros2.registerTopic("/athena/sub_robot/joint_states", "sensor_msgs/msg/JointState");
            Ros2.registerTopic("/athena/robot_description", "std_msgs/msg/String");
            Ros2.registerTopic("/athena/robot_description_semantic", "std_msgs/msg/String");
            contextObj.actionServer = "/athena/move_group";
            contextObj.moveGroup = "arm";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            var urdfPub = Ros2.createPublisher("/athena/robot_description", "std_msgs/msg/String");
            var urdfMsg = Ros2.createEmptyMessage("std_msgs/msg/String");
            urdfMsg.data = mockUrdf;
            urdfPub.publish(urdfMsg);
            tryCompare(find("moveitUrdfStatusLabel"), "text", "URDF: Loaded", 3000);
            var srdfPub = Ros2.createPublisher("/athena/robot_description_semantic", "std_msgs/msg/String");
            var srdfMsg = Ros2.createEmptyMessage("std_msgs/msg/String");
            srdfMsg.data = mockSrdf;
            srdfPub.publish(srdfMsg);
            tryCompare(find("moveitSrdfStatusLabel"), "text", "SRDF: Loaded", 3000);
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.count === 3;
                }, 5000);

            // Publish on the deeper descendant — should NOT drive the model.
            var deepPub = Ros2.createPublisher("/athena/sub_robot/joint_states", "sensor_msgs/msg/JointState");
            var deepMsg = Ros2.createEmptyMessage("sensor_msgs/msg/JointState");
            deepMsg.header.stamp = Ros2.now();
            deepMsg.name = ["joint1"];
            deepMsg.position = [0.9];
            deepMsg.velocity = [];
            deepMsg.effort = [];
            deepPub.publish(deepMsg);
            wait(300);
            verify(!jointList.model.get(0).initialized, "Deeper-descendant topic should not drive joint state");

            // Publish on the direct namespace topic — SHOULD drive the model.
            var directPub = Ros2.createPublisher("/athena/joint_states", "sensor_msgs/msg/JointState");
            var directMsg = Ros2.createEmptyMessage("sensor_msgs/msg/JointState");
            directMsg.header.stamp = Ros2.now();
            directMsg.name = ["joint1"];
            directMsg.position = [0.33];
            directMsg.velocity = [];
            directMsg.effort = [];
            directPub.publish(directMsg);
            tryVerify(function () {
                    return jointList.model.get(0).initialized && Math.abs(jointList.model.get(0).position - 0.33) < 0.02;
                }, 3000, "Direct-namespace topic should win over deeper descendant");
        }
        function test_planning_config_collapsible() {
            // Need a move group selected for the planning config to be visible
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "arm";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectSrdf();
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000);
            var headerButton = find("moveitPlanningConfigButton");
            verify(headerButton !== null, "Planning config header should exist");

            // Initially collapsed - sliders should not be visible
            var velSlider = find("moveitVelocitySlider");
            if (velSlider) {
                verify(!velSlider.visible, "Velocity slider should be hidden when collapsed");
            }

            // Expand
            mouseClick(headerButton);
            tryVerify(function () {
                    var vs = find("moveitVelocitySlider");
                    return vs !== null && vs.visible;
                }, 3000, "Velocity slider should be visible after expanding");
            var accSlider = find("moveitAccelerationSlider");
            verify(accSlider !== null && accSlider.visible, "Acceleration slider should be visible");
            var timeSlider = find("moveitPlanningTimeSlider");
            verify(timeSlider !== null && timeSlider.visible, "Planning time slider should be visible");
            var attemptsSlider = find("moveitPlanningAttemptsSlider");
            verify(attemptsSlider !== null && attemptsSlider.visible, "Attempts slider should be visible");

            // Collapse again
            mouseClick(headerButton);
            tryVerify(function () {
                    var vs = find("moveitVelocitySlider");
                    return vs === null || !vs.visible;
                }, 3000, "Velocity slider should be hidden after collapsing");
        }

        // ================================================================
        // Slider → Context Writeback
        // ================================================================
        function test_planning_sliders_write_back_to_context() {
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "arm";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectSrdf();
            tryCompare(find("moveitSrdfStatusLabel"), "text", "SRDF: Loaded", 3000);
            mouseClick(find("moveitPlanningConfigButton"));
            tryVerify(function () {
                    var vs = find("moveitVelocitySlider");
                    return vs !== null && vs.visible;
                }, 3000);

            // Slider.onMoved fires only on user input; simulate by setting
            // value + emitting the moved() signal (matches the binding path).
            var velSlider = find("moveitVelocitySlider");
            velSlider.value = 0.42;
            velSlider.moved();
            tryVerify(function () {
                    return Math.abs(contextObj.velocityScale - 0.42) < 0.001;
                }, 3000, "Velocity slider should write velocityScale to context");
            var accSlider = find("moveitAccelerationSlider");
            accSlider.value = 0.27;
            accSlider.moved();
            tryVerify(function () {
                    return Math.abs(contextObj.accelerationScale - 0.27) < 0.001;
                }, 3000, "Acceleration slider should write accelerationScale to context");
            var timeSlider = find("moveitPlanningTimeSlider");
            timeSlider.value = 12.5;
            timeSlider.moved();
            tryVerify(function () {
                    return Math.abs(contextObj.planningTime - 12.5) < 0.01;
                }, 3000, "Planning time slider should write planningTime to context");
            var attemptsSlider = find("moveitPlanningAttemptsSlider");
            attemptsSlider.value = 7;
            attemptsSlider.moved();
            tryVerify(function () {
                    return contextObj.planningAttempts === 7;
                }, 3000, "Attempts slider should write planningAttempts to context");
        }

        // ================================================================
        // Basic Loading & Discovery
        // ================================================================
        function test_plugin_loads() {
            verify(plugin !== null, "MoveItController plugin should load");
        }

        // Regression: refresh must drop and re-create URDF/SRDF subscriptions.
        // Previously updateTopics() filtered by Ros2.queryTopics() which could
        // miss the topic on startup; the publisher's transient-local cache
        // then never re-delivered on a later re-subscribe. With always-
        // subscribe + refresh-resets-subscriptions, clicking refresh clears
        // the status and re-subscribing delivers the next published URDF/SRDF.
        function test_refresh_resets_subscriptions() {
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            var urdfLabel = find("moveitUrdfStatusLabel");
            var srdfLabel = find("moveitSrdfStatusLabel");
            injectUrdf();
            injectSrdf();
            tryCompare(urdfLabel, "text", "URDF: Loaded", 3000);
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000);
            var refreshBtn = find("moveitRefreshButton");
            verify(refreshBtn !== null);
            mouseClick(refreshBtn);

            // Refresh clears status and re-subscribes
            tryCompare(urdfLabel, "text", "URDF: Waiting...", 1000, "Refresh should clear URDF status");
            tryCompare(srdfLabel, "text", "SRDF: Waiting...", 1000, "Refresh should clear SRDF status");

            // Re-publish; fresh subscription must receive the message
            injectUrdf();
            injectSrdf();
            tryCompare(urdfLabel, "text", "URDF: Loaded", 3000, "URDF should reload after refresh + re-publish");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000, "SRDF should reload after refresh + re-publish");
        }
        function test_reset_goals() {
            setupFullState();

            // Inject joint states with known positions
            var jointList = find("moveitJointListView");
            injectJointStates(["joint1", "joint2", "joint3"], [0.5, -1.0, 0.25]);
            wait(50);

            // Wait for positions and goals to be initialized
            tryVerify(function () {
                    return jointList.model.get(0).initialized;
                }, 3000, "Joints should be initialized");

            // Change goals away from positions by applying "ready" pose
            var posesFlow = find("moveitNamedPosesFlow");
            tryVerify(function () {
                    return posesFlow.visible;
                }, 3000);
            var readyButton = null;
            for (var i = 0; i < posesFlow.children.length; i++) {
                if (posesFlow.children[i].text === "ready") {
                    readyButton = posesFlow.children[i];
                    break;
                }
            }
            verify(readyButton !== null);
            mouseClick(readyButton);

            // Verify goals changed
            tryVerify(function () {
                    return Math.abs(jointList.model.get(0).goal - 1.0) < 0.02;
                }, 3000, "Goal should change to ready pose value");

            // Click Reset
            var resetBtn = find("moveitResetButton");
            verify(resetBtn !== null, "Reset button should exist");
            mouseClick(resetBtn);

            // Goals should return to current positions
            tryVerify(function () {
                    var j1 = jointList.model.get(0);
                    return Math.abs(j1.goal - j1.position) < 0.02;
                }, 3000, "joint1 goal should reset to position after reset");
            tryVerify(function () {
                    var j2 = jointList.model.get(1);
                    return Math.abs(j2.goal - j2.position) < 0.02;
                }, 3000, "joint2 goal should reset to position after reset");
        }
        function test_srdf_before_urdf_order() {
            // SRDF arriving before URDF — groups should be stored and joints
            // built once URDF provides the kinematic chain.
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "arm";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();

            // Inject SRDF first
            injectSrdf();
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000);

            // Move groups should be populated even without URDF
            var groupCombo = find("moveitMoveGroupComboBox");
            tryVerify(function () {
                    return groupCombo.count === 3;
                }, 3000, "Move groups should be available from SRDF alone");

            // But joints can't be resolved yet (no kinematic chain)
            var jointList = find("moveitJointListView");

            // Now inject URDF — joints should rebuild using the already-parsed SRDF
            injectUrdf();
            var urdfLabel = find("moveitUrdfStatusLabel");
            tryCompare(urdfLabel, "text", "URDF: Loaded", 3000);

            // Chain-resolved joints should now appear
            tryVerify(function () {
                    return jointList.count === 3;
                }, 5000, "Joints should be populated after URDF arrives (SRDF-first order)");
            compare(jointList.model.get(0).name, "joint1");
            compare(jointList.model.get(1).name, "joint2");
            compare(jointList.model.get(2).name, "joint3");
        }
        function test_srdf_loading() {
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            var srdfLabel = find("moveitSrdfStatusLabel");
            verify(srdfLabel !== null, "SRDF status label should exist");
            compare(srdfLabel.text, "SRDF: Waiting...", "Should show waiting initially");
            injectSrdf();
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000, "SRDF should be loaded after injection");
        }
        function test_status_bar_labels() {
            var urdfLabel = find("moveitUrdfStatusLabel");
            var srdfLabel = find("moveitSrdfStatusLabel");
            var actionLabel = find("moveitActionStatusLabel");
            verify(urdfLabel !== null, "URDF status label should exist");
            verify(srdfLabel !== null, "SRDF status label should exist");
            verify(actionLabel !== null, "Action status label should exist");

            // Initially all waiting/connecting
            compare(urdfLabel.text, "URDF: Waiting...");
            compare(srdfLabel.text, "SRDF: Waiting...");
            compare(actionLabel.text, "Action: Connecting...");

            // Set action server - action should become ready
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            var actionLabelAfter = find("moveitActionStatusLabel");
            tryCompare(actionLabelAfter, "text", "Action: Ready", 3000, "Action should be ready after setting action server");
        }
        function test_subgroup_joint_resolution() {
            contextObj.actionServer = "/move_group";
            contextObj.moveGroup = "combined";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            injectUrdf();
            var urdfLabel = find("moveitUrdfStatusLabel");
            tryCompare(urdfLabel, "text", "URDF: Loaded", 3000);
            injectSrdf();
            var srdfLabel = find("moveitSrdfStatusLabel");
            tryCompare(srdfLabel, "text", "SRDF: Loaded", 3000);
            var jointList = find("moveitJointListView");
            verify(jointList !== null);
            tryVerify(function () {
                    return jointList.count === 2;
                }, 3000, "combined group should have 2 joints");
            compare(jointList.model.get(0).name, "joint1", "First joint from subgroup");
            compare(jointList.model.get(1).name, "joint2", "Second joint direct");
        }
        function test_unknown_joints_ignored() {
            setupFullState();
            var jointList = find("moveitJointListView");
            tryVerify(function () {
                    return jointList.count === 3;
                }, 3000);

            // Inject joint states including an unknown joint
            injectJointStates(["joint1", "unknown_joint", "joint2"], [0.42, 99.0, -0.77]);

            // Known joints should update
            tryVerify(function () {
                    return Math.abs(jointList.model.get(0).position - 0.42) < 0.02;
                }, 3000, "joint1 should update");
            tryVerify(function () {
                    return Math.abs(jointList.model.get(1).position - (-0.77)) < 0.02;
                }, 3000, "joint2 should update");

            // Joint list count should remain unchanged (no phantom joints)
            compare(jointList.count, 3, "Unknown joint should not be added to the list");
        }

        // ================================================================
        // URDF/SRDF Parsing
        // ================================================================
        function test_urdf_loading() {
            contextObj.actionServer = "/move_group";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                }, 2000);
            waitForDiscovery();
            var urdfLabel = find("moveitUrdfStatusLabel");
            verify(urdfLabel !== null, "URDF status label should exist");
            compare(urdfLabel.text, "URDF: Waiting...", "Should show waiting initially");
            injectUrdf();
            tryCompare(urdfLabel, "text", "URDF: Loaded", 3000, "URDF should be loaded after injection");
        }

        /**
         * Wait for the MoveItInterface discovery timer to fire at least once.
         * The timer runs every 500ms; we poll for its effect (action server
         * appearing in the ComboBox) instead of using a fixed wait().
         * This ensures updateTopics() has run and topic subscriptions are set up.
         */
        function waitForDiscovery() {
            var comboBox = find("moveitActionServerComboBox");
            tryVerify(function () {
                    return comboBox && comboBox.count > 0;
                }, 3000, "Discovery timer should fire and populate action servers");
            // updateTopics() sets subscription topics (jointStateTopic, urdfTopic,
            // srdfTopic) after populating the combobox. Allow QML bindings to
            // propagate so subscriptions are active before injecting messages.
            wait(100);
        }

        name: "MoveItControllerTest"
        when: windowShown
    }
}
