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

        property var request: null
        property string topic: ""
        property string type: ""
    }
    Utils {
        id: helpers
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/ActionCaller.qml";
        }

        anchors.fill: parent
    }
    TestCase {
        id: testCase

        property var lastCallbacks: null
        property var lastClient: null

        function init() {
            // The client binding must not depend on state that resetState() mutates.
            failOnWarning(/Binding loop detected/);
            Ros2.reset();
            contextObj.topic = "";
            contextObj.type = "";
            contextObj.request = null;
            lastCallbacks = null;
            lastClient = null;

            // Register a mock action
            Ros2.registerAction("/test_action", "tf2_msgs/action/LookupTransform", function (goal, callbacks, client) {
                    lastCallbacks = callbacks;
                    lastClient = client;
                    // Test drive the flow from the test case
                });
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                });

            // Wait for discovery
            tryVerify(function () {
                    var selector = find("actionTopicSelector");
                    return selector && (selector.model || []).indexOf("/test_action") !== -1;
                }, 5000);
        }
        function test_cancel_available_when_server_dies() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_dead_server");
            handle.setStatus(2); // Executing
            lastCallbacks.onGoalResponse(handle);
            tryCompare(sendButton, "text", "Cancel", 2000);

            // Server dies while executing: the goal stays active, but Cancel must
            // remain usable so it leads to the hold-to-drop escape hatch.
            lastClient.ready = false;
            verify(sendButton.enabled);
            mouseClick(sendButton);
            compare(Ros2._lastActionCancelled, true);
            var holdButton = find("actionHoldDropButton");
            tryVerify(function () {
                    return holdButton.visible && !sendButton.visible;
                }, 2000);
        }
        function test_discovery() {
            var topicSelector = find("actionTopicSelector");
            mouseClick(topicSelector);
            var fullName = "/test_action";
            for (var i = 0; i < fullName.length; ++i)
                keyClick(fullName[i]);
            keyClick(Qt.Key_Enter);
            tryVerify(function () {
                    return contextObj.topic === "/test_action";
                }, 5000);
            var typeSelector = find("actionTypeSelector");
            tryVerify(function () {
                    return typeSelector.text === "tf2_msgs/action/LookupTransform";
                }, 5000);
        }
        function test_feedback_selection() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_fb");
            handle.setStatus(1);
            lastCallbacks.onGoalResponse(handle);
            var fb0 = Ros2.createEmptyActionFeedback("tf2_msgs/action/LookupTransform");
            var fb1 = Ros2.createEmptyActionFeedback("tf2_msgs/action/LookupTransform");
            var fb2 = Ros2.createEmptyActionFeedback("tf2_msgs/action/LookupTransform");
            lastCallbacks.onFeedback(handle, fb0);
            lastCallbacks.onFeedback(handle, fb1);
            lastCallbacks.onFeedback(handle, fb2);
            var feedbackList = find("actionFeedbackList");
            tryVerify(function () {
                    return feedbackList.count === 3;
                }, 2000);
            // Auto-follow puts the selection at the latest message.
            tryCompare(feedbackList, "currentIndex", 2, 2000);
            var feedbackEditor = find("actionFeedbackEditor");
            verify(feedbackEditor);
            verify(feedbackEditor.readonly);

            // Clicking an older delegate must select it - exercising the
            // delegate's onClicked handler, not just the ListView API.
            feedbackList.positionViewAtIndex(0, ListView.Beginning);
            var delegate0 = feedbackList.itemAtIndex(0);
            verify(delegate0);
            mouseClick(delegate0);
            tryCompare(feedbackList, "currentIndex", 0, 2000);

            // The detail editor must be tracking the list's current item.
            tryVerify(function () {
                    return feedbackEditor.model && feedbackEditor.model.message != null;
                }, 2000);

            // Switching selection updates the currentItem reference - the
            // binding in the editor's model re-evaluates accordingly.
            var item0 = feedbackList.currentItem;
            feedbackList.currentIndex = 2;
            tryVerify(function () {
                    return feedbackList.currentItem && feedbackList.currentItem !== item0 && feedbackEditor.model && feedbackEditor.model.message != null;
                }, 2000);
        }
        function test_goal_cancellation() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_cancel");
            handle.setStatus(1); // Accepted/Executing → active
            lastCallbacks.onGoalResponse(handle);

            // Button flips to Cancel once a goal is active.
            tryCompare(sendButton, "text", "Cancel", 2000);
            compare(Ros2._lastActionCancelled, false);
            mouseClick(sendButton);
            tryVerify(function () {
                    return Ros2._lastActionCancelled === true;
                }, 2000);

            // Hold to drop shows right after the request even without any status
            // update, e.g. if the server died, and hides once a result arrives.
            var holdButton = find("actionHoldDropButton");
            tryVerify(function () {
                    return holdButton.visible && !sendButton.visible;
                }, 2000);
            lastCallbacks.onResult({
                    "status": 6,
                    "result": Ros2.createEmptyActionResult("tf2_msgs/action/LookupTransform")
                });
            tryVerify(function () {
                    return !holdButton.visible && sendButton.visible;
                }, 2000);
        }
        function test_goal_execution() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);

            // Wait for mock to receive goal
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);

            // 1. Accept goal
            var handle = Ros2.createGoalHandle("goal_123");
            handle.setStatus(1); // Executing
            lastCallbacks.onGoalResponse(handle);
            var statusLabel = find("actionStatusLabel");
            tryCompare(statusLabel, "text", "Processing goal.", 2000);
            compare(sendButton.text, "Cancel");

            // 2. Send feedback
            var feedback = Ros2.createEmptyActionFeedback("tf2_msgs/action/LookupTransform");
            lastCallbacks.onFeedback(handle, feedback);
            var feedbackList = find("actionFeedbackList");
            tryVerify(function () {
                    return feedbackList.count === 1;
                }, 2000);

            // 3. Send result
            handle.setStatus(4); // Succeeded
            var result = Ros2.createEmptyActionResult("tf2_msgs/action/LookupTransform");
            lastCallbacks.onResult({
                    "status": 4,
                    "result": result
                });
            var tabBar = find("actionTabBar");
            tryCompare(tabBar, "currentIndex", 2, 2000); // Result tab
            tryCompare(statusLabel, "text", "Ready", 2000);
        }
        function test_hold_to_drop_after_cancel() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_hang");
            handle.setStatus(2); // Executing → active
            lastCallbacks.onGoalResponse(handle);
            tryCompare(sendButton, "text", "Cancel", 2000);

            // Cancel is requested but the server hangs in the Canceling state.
            mouseClick(sendButton);
            compare(Ros2._lastActionCancelled, true);
            handle.setStatus(3); // Canceling

            // The (now useless) Cancel button hides and the hold-to-drop
            // escape hatch takes its place.
            var holdButton = find("actionHoldDropButton");
            verify(holdButton);
            tryVerify(function () {
                    return holdButton.visible && !sendButton.visible;
                }, 2000);

            // A tap must not drop anything - only a full hold does.
            holdButton.holdDuration = 120;
            mouseClick(holdButton);
            wait(holdButton.holdDuration * 2);
            verify(holdButton.visible);

            // Holding past holdDuration drops the goal locally and returns to
            // the request tab, ready to send again.
            mousePress(holdButton);
            tryVerify(function () {
                    return !holdButton.visible;
                }, 2000);
            mouseRelease(holdButton);
            var tabBar = find("actionTabBar");
            tryCompare(tabBar, "currentIndex", 0, 2000);
            tryCompare(sendButton, "text", "Send Goal", 2000);

            // A late result belonging to the dropped goal must be ignored: no
            // jump to the result tab.
            var result = Ros2.createEmptyActionResult("tf2_msgs/action/LookupTransform");
            lastCallbacks.onResult({
                    "status": 6,
                    "result": result
                });
            wait(100);
            compare(tabBar.currentIndex, 0);
        }
        function test_hold_to_drop_when_finished_without_result() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_no_result");
            handle.setStatus(2); // Executing
            lastCallbacks.onGoalResponse(handle);
            tryCompare(sendButton, "text", "Cancel", 2000);

            // Server reports a terminal status but the result never arrives.
            handle.setStatus(6); // Aborted
            var holdButton = find("actionHoldDropButton");
            tryVerify(function () {
                    return holdButton.visible && !sendButton.visible;
                }, 2000);
            compare(find("actionStatusLabel").text, "Processing goal.");
            lastCallbacks.onResult({
                    "status": 6,
                    "result": Ros2.createEmptyActionResult("tf2_msgs/action/LookupTransform")
                });
            tryVerify(function () {
                    return !holdButton.visible && sendButton.visible;
                }, 2000);
        }
        function test_late_acceptance_of_abandoned_goal_cancels_it() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var abandonedCallbacks = lastCallbacks;
            lastCallbacks = null;

            // Go back and send a new goal before the first one was accepted.
            tryCompare(sendButton, "text", "Back", 2000);
            mouseClick(sendButton);
            tryCompare(sendButton, "text", "Send Goal", 2000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);

            // The first goal is accepted late: it must be canceled and not take over the UI.
            compare(Ros2._lastActionCancelled, false);
            var abandonedHandle = Ros2.createGoalHandle("goal_abandoned");
            abandonedHandle.setStatus(2); // Executing
            abandonedCallbacks.onGoalResponse(abandonedHandle);
            compare(Ros2._lastActionCancelled, true);
            var statusLabel = find("actionStatusLabel");
            compare(statusLabel.text, "Ready");
        }
        function test_request_editing() {
            // Pre-populate context.request with a marker value; the editor
            // must adopt it on load (this is how persisted state survives a
            // reload).
            var preset = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = preset;
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                });
            var editor = find("actionRequestEditor");
            verify(editor);
            tryVerify(function () {
                    return editor.model && editor.model.message && editor.model.message["#messageType"] === "tf2_msgs/action/LookupTransform_Goal";
                }, 2000);
            // Editor is not readonly, so it can be used for composing the goal.
            verify(editor.readonly === false);

            // Changing the type must swap the editor's model to an empty goal
            // of the new type (i.e. composing starts fresh for the new type).
            contextObj.type = "";
            contextObj.request = null;
            var typeSelector = find("actionTypeSelector");
            verify(typeSelector);
            typeSelector.text = "tf2_msgs/action/LookupTransform";
            tryVerify(function () {
                    return editor.model && editor.model.message && editor.model.message["#messageType"] === "tf2_msgs/action/LookupTransform_Goal";
                }, 2000);
        }
        function test_selectors_locked_while_goal_active() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var topicSelector = find("actionTopicSelector");
            var typeSelector = find("actionTypeSelector");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_lock");
            handle.setStatus(2); // Executing
            lastCallbacks.onGoalResponse(handle);

            // Changing topic or type would orphan the running goal.
            tryVerify(function () {
                    return !topicSelector.enabled && !typeSelector.enabled;
                }, 2000);
            lastCallbacks.onResult({
                    "status": 4,
                    "result": Ros2.createEmptyActionResult("tf2_msgs/action/LookupTransform")
                });
            tryVerify(function () {
                    return topicSelector.enabled && typeSelector.enabled;
                }, 2000);
        }
        function test_server_reported_canceling() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");
            var sendButton = find("actionSendCancelButton");
            tryVerify(function () {
                    return sendButton.enabled;
                }, 5000);
            mouseClick(sendButton);
            tryVerify(function () {
                    return lastCallbacks !== null;
                }, 2000);
            var handle = Ros2.createGoalHandle("goal_ext_cancel");
            handle.setStatus(2); // Executing
            lastCallbacks.onGoalResponse(handle);
            var statusLabel = find("actionStatusLabel");
            tryCompare(statusLabel, "text", "Processing goal.", 2000);

            // Canceled from elsewhere: no local cancel request, only the status update.
            handle.setStatus(3); // Canceling
            tryCompare(statusLabel, "text", "Canceling...", 2000);
            compare(Ros2._lastActionCancelled, false);
            verify(find("actionHoldDropButton").visible);
            verify(!sendButton.visible);
        }
        function test_topic_refresh() {
            var selector = find("actionTopicSelector");
            verify(selector);
            verify((selector.model || []).indexOf("/test_action") !== -1);
            // Register an additional action after the plugin was loaded; the
            // model should be stale until the refresh button is pressed.
            Ros2.registerAction("/second_action", "tf2_msgs/action/LookupTransform", function (goal, callbacks) {});
            verify((selector.model || []).indexOf("/second_action") === -1);
            var btn = find("actionTopicRefreshButton");
            verify(btn);
            mouseClick(btn);
            tryVerify(function () {
                    return (selector.model || []).indexOf("/second_action") !== -1;
                }, 2000);
        }
        function test_type_refresh() {
            // Set topic via context + reload so typeSelect.refresh runs on
            // Component.onCompleted. (Setting context.topic post-load doesn't
            // propagate: the topicSelect.onTextChanged handler early-returns
            // when the new text already matches context.topic.)
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            pluginLoader.reload();
            tryVerify(function () {
                    return pluginLoader.status === Loader.Ready;
                });
            var typeSelector = find("actionTypeSelector");
            verify(typeSelector);
            tryVerify(function () {
                    return (typeSelector.model || []).indexOf("tf2_msgs/action/LookupTransform") !== -1;
                }, 2000);
            // Register a second type under the same action name; refresh
            // should pull it into the selector's model.
            Ros2.registerAction("/test_action", "action_tutorials_interfaces/action/Fibonacci", function (goal, callbacks) {});
            verify((typeSelector.model || []).indexOf("action_tutorials_interfaces/action/Fibonacci") === -1);
            var btn = find("actionTypeRefreshButton");
            verify(btn);
            mouseClick(btn);
            tryVerify(function () {
                    return (typeSelector.model || []).indexOf("action_tutorials_interfaces/action/Fibonacci") !== -1;
                }, 2000);
        }

        name: "ActionCallerTest"
        when: windowShown
    }
}
