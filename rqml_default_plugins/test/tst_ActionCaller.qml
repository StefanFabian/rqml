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
    width: 1024; height: 768

    property var context: contextObj
    QtObject {
        id: contextObj
        property string topic: ""
        property string type: ""
        property var request: null
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/ActionCaller.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    TestCase {
        id: testCase
        name: "ActionCallerTest"
        when: windowShown

        property var lastCallbacks: null

        function init() {
            Ros2.reset();
            contextObj.topic = "";
            contextObj.type = "";
            contextObj.request = null;
            lastCallbacks = null;

            // Register a mock action
            Ros2.registerAction("/test_action", "tf2_msgs/action/LookupTransform", function(goal, callbacks) {
                lastCallbacks = callbacks;
                // Test drive the flow from the test case
            });

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; });

            // Wait for discovery
            tryVerify(function() {
                var selector = find("actionTopicSelector");
                return selector && (selector.model || []).indexOf("/test_action") !== -1;
            }, 5000);
        }

        function test_discovery() {
            var topicSelector = find("actionTopicSelector");
            mouseClick(topicSelector);
            var fullName = "/test_action";
            for (var i = 0; i < fullName.length; ++i) keyClick(fullName[i]);
            keyClick(Qt.Key_Enter);

            tryVerify(function() { return contextObj.topic === "/test_action"; }, 5000);

            var typeSelector = find("actionTypeSelector");
            tryVerify(function() {
                return typeSelector.text === "tf2_msgs/action/LookupTransform";
            }, 5000);
        }

        function test_goal_execution() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal("tf2_msgs/action/LookupTransform");

            var sendButton = find("actionSendCancelButton");
            tryVerify(function() { return sendButton.enabled; }, 5000);

            mouseClick(sendButton);

            // Wait for mock to receive goal
            tryVerify(function() { return lastCallbacks !== null; }, 2000);

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
            tryVerify(function() { return feedbackList.count === 1; }, 2000);

            // 3. Send result
            handle.setStatus(4); // Succeeded
            var result = Ros2.createEmptyActionResult("tf2_msgs/action/LookupTransform");
            lastCallbacks.onResult({ status: 4, result: result });

            var tabBar = find("actionTabBar");
            tryCompare(tabBar, "currentIndex", 2, 2000); // Result tab
            tryCompare(statusLabel, "text", "Ready", 2000);
        }

        function test_topic_refresh() {
            var selector = find("actionTopicSelector");
            verify(selector);
            verify((selector.model || []).indexOf("/test_action") !== -1);
            // Register an additional action after the plugin was loaded; the
            // model should be stale until the refresh button is pressed.
            Ros2.registerAction("/second_action", "tf2_msgs/action/LookupTransform",
                function(goal, callbacks) {});
            verify((selector.model || []).indexOf("/second_action") === -1);

            var btn = find("actionTopicRefreshButton");
            verify(btn);
            mouseClick(btn);
            tryVerify(function() {
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
            tryVerify(function() { return pluginLoader.status === Loader.Ready; });

            var typeSelector = find("actionTypeSelector");
            verify(typeSelector);
            tryVerify(function() {
                return (typeSelector.model || []).indexOf("tf2_msgs/action/LookupTransform") !== -1;
            }, 2000);
            // Register a second type under the same action name; refresh
            // should pull it into the selector's model.
            Ros2.registerAction("/test_action", "action_tutorials_interfaces/action/Fibonacci",
                function(goal, callbacks) {});
            verify((typeSelector.model || []).indexOf(
                "action_tutorials_interfaces/action/Fibonacci") === -1);

            var btn = find("actionTypeRefreshButton");
            verify(btn);
            mouseClick(btn);
            tryVerify(function() {
                return (typeSelector.model || []).indexOf(
                    "action_tutorials_interfaces/action/Fibonacci") !== -1;
            }, 2000);
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
            tryVerify(function() { return pluginLoader.status === Loader.Ready; });

            var editor = find("actionRequestEditor");
            verify(editor);
            tryVerify(function() {
                return editor.model && editor.model.message
                    && editor.model.message["#messageType"]
                        === "tf2_msgs/action/LookupTransform_Goal";
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
            tryVerify(function() {
                return editor.model && editor.model.message
                    && editor.model.message["#messageType"]
                        === "tf2_msgs/action/LookupTransform_Goal";
            }, 2000);
        }

        function test_feedback_selection() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal(
                "tf2_msgs/action/LookupTransform");

            var sendButton = find("actionSendCancelButton");
            tryVerify(function() { return sendButton.enabled; }, 5000);
            mouseClick(sendButton);
            tryVerify(function() { return lastCallbacks !== null; }, 2000);

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
            tryVerify(function() { return feedbackList.count === 3; }, 2000);
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
            tryVerify(function() {
                return feedbackEditor.model
                    && feedbackEditor.model.message != null;
            }, 2000);

            // Switching selection updates the currentItem reference - the
            // binding in the editor's model re-evaluates accordingly.
            var item0 = feedbackList.currentItem;
            feedbackList.currentIndex = 2;
            tryVerify(function() {
                return feedbackList.currentItem
                    && feedbackList.currentItem !== item0
                    && feedbackEditor.model
                    && feedbackEditor.model.message != null;
            }, 2000);
        }

        function test_goal_cancellation() {
            contextObj.topic = "/test_action";
            contextObj.type = "tf2_msgs/action/LookupTransform";
            contextObj.request = Ros2.createEmptyActionGoal(
                "tf2_msgs/action/LookupTransform");

            var sendButton = find("actionSendCancelButton");
            tryVerify(function() { return sendButton.enabled; }, 5000);
            mouseClick(sendButton);
            tryVerify(function() { return lastCallbacks !== null; }, 2000);

            var handle = Ros2.createGoalHandle("goal_cancel");
            handle.setStatus(1); // Accepted/Executing → active
            lastCallbacks.onGoalResponse(handle);

            // Button flips to Cancel once a goal is active.
            tryCompare(sendButton, "text", "Cancel", 2000);
            compare(Ros2._lastActionCancelled, false);

            mouseClick(sendButton);
            tryVerify(function() { return Ros2._lastActionCancelled === true; }, 2000);
        }
    }
}
