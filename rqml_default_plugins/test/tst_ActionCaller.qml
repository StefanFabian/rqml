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
        topic: "",
        type: "",
        request: null
    })

    PluginQml.ActionCaller {
        id: actionCaller
        anchors.fill: parent
    }

    TestCase {
        name: "ActionCallerTest"
        when: windowShown

        function init() {
            Ros2.reset();
            Ros2._mockActions = ["/test_action", "/another_action"];
            Ros2._mockTypeMap["/test_action"] = ["example_interfaces/action/Fibonacci"];
            Ros2._mockTypeMap["/another_action"] = ["nav2_msgs/action/NavigateToPose"];
        }

        function findChildByProperty(parentItem, propName, propValue) {
            if (!parentItem) return null;
            if (parentItem[propName] === propValue) return parentItem;
            var children = parentItem.children || [];
            if (parentItem.contentItem) children = parentItem.contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var found = findChildByProperty(children[i], propName, propValue);
                if (found) return found;
            }
            return null;
        }

        function test_01_plugin_loads() {
            verify(actionCaller !== null, "ActionCaller plugin should load");
        }

        function test_02_action_discovery() {
            var actions = Ros2.queryActions();
            compare(actions.length, 2, "Should discover 2 mock actions");
            verify(actions.indexOf("/test_action") !== -1, "Should contain /test_action");
        }

        function test_03_type_resolution() {
            var topicSelector = findChildByProperty(actionCaller, "placeholderText", "Action Topic");
            verify(topicSelector !== null, "Action FuzzySelector should be found");
            topicSelector.text = "/test_action";

            var typeSelector = findChildByProperty(actionCaller, "placeholderText", "Action Type");
            verify(typeSelector !== null, "Type FuzzySelector should be found");
            tryCompare(typeSelector, "text", "example_interfaces/action/Fibonacci", 1000,
                "Type should be automatically updated to Fibonacci");
            compare(windowRoot.context.type, "example_interfaces/action/Fibonacci", "context.type should be updated");

            // Change to another action
            topicSelector.text = "/another_action";
            tryCompare(typeSelector, "text", "nav2_msgs/action/NavigateToPose", 1000,
                "Type should be automatically updated to NavigateToPose");
            compare(windowRoot.context.type, "nav2_msgs/action/NavigateToPose", "context.type should be updated");

            // Clear topic
            topicSelector.text = "";
            tryCompare(typeSelector, "text", "nav2_msgs/action/NavigateToPose", 1000,
                "Type should NOT be cleared when topic is cleared");
            compare(windowRoot.context.type, "nav2_msgs/action/NavigateToPose", "context.type should remain");
        }

        function test_04_empty_goal_creation() {
            var goal = Ros2.createEmptyActionGoal("example_interfaces/action/Fibonacci");
            verify(goal !== null, "Goal should be created");
            compare(goal["#messageType"], "example_interfaces/action/Fibonacci_Goal");
            compare(goal.order, 0, "Default order should be 0");
        }

        function test_05_action_client_goal_flow() {
            Ros2._mockActionFlow = {
                goalHandle: { goalId: "test-goal-1", status: ActionGoalStatus.Accepted, isActive: true },
                feedbacks: [
                    { partial_sequence: [0, 1, 1] },
                    { partial_sequence: [0, 1, 1, 2] }
                ],
                result: {
                    code: ActionResultCode.SUCCEEDED,
                    result: { sequence: [0, 1, 1, 2, 3, 5] }
                }
            };

            var client = Ros2.createActionClient("/test_action", "example_interfaces/action/Fibonacci");
            verify(client !== null, "Action client should be created");
            verify(client.ready, "Action client should be ready");

            var goalReceived = false;
            var feedbackCount = 0;
            var resultReceived = false;
            var finalResult = null;

            client.sendGoalAsync({ order: 5 }, {
                onGoalResponse: function(goalHandle) {
                    goalReceived = true;
                    verify(goalHandle !== null, "Goal should be accepted");
                    compare(goalHandle.goalId, "test-goal-1");
                },
                onFeedback: function(goalHandle, feedback) {
                    feedbackCount++;
                    verify(feedback.partial_sequence !== undefined, "Feedback should have partial_sequence");
                },
                onResult: function(result) {
                    resultReceived = true;
                    finalResult = result;
                }
            });

            tryVerify(function() { return resultReceived; }, 1000,
                "Result should be received");
            verify(goalReceived, "Goal response should be received");
            compare(feedbackCount, 2, "Should receive 2 feedback messages");
            compare(finalResult.code, ActionResultCode.SUCCEEDED, "Result code should be SUCCEEDED");
        }

        function test_06_cancel_goals() {
            Ros2._lastActionCancelled = false;
            var client = Ros2.createActionClient("/test_action", "example_interfaces/action/Fibonacci");
            client.cancelAllGoals();
            verify(Ros2._lastActionCancelled, "cancelAllGoals should have been called");
        }

        function test_07_action_goal_status_enum() {
            compare(ActionGoalStatus.Unknown, 0);
            compare(ActionGoalStatus.Accepted, 1);
            compare(ActionGoalStatus.Executing, 2);
            compare(ActionGoalStatus.Canceling, 3);
            compare(ActionGoalStatus.Succeeded, 4);
            compare(ActionGoalStatus.Canceled, 5);
            compare(ActionGoalStatus.Aborted, 6);
        }

        function test_08_action_result_code_enum() {
            compare(ActionResultCode.UNKNOWN, 0);
            compare(ActionResultCode.SUCCEEDED, 1);
            compare(ActionResultCode.CANCELED, 2);
            compare(ActionResultCode.ABORTED, 3);
        }
    }
}
