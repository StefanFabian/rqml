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
import QtTest
import Ros2

Item {
    id: root
    width: 1024; height: 768

    property var context: contextObj
    QtObject {
        id: contextObj
        property var messages: []
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/MessagePublisher.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    property var lastMessage: null
    property int messageCount: 0
    Subscription {
        id: testSub
        topic: "/test_topic"
        messageType: "std_msgs/msg/String"
        onNewMessage: (msg) => {
            lastMessage = msg;
            messageCount++;
        }
    }

    TestCase {
        id: testCase
        name: "MessagePublisherTest"
        when: windowShown

        function init() {
            Ros2.reset();
            Ros2._registerSubscription(testSub);
            Ros2.registerTopic("/test_topic", "std_msgs/msg/String");

            contextObj.messages = [];
            messageCount = 0;
            lastMessage = null;

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; }, 2000, "Loader should be ready");
            wait(200);
        }

        function test_plugin_loads() {
            verify(plugin !== null, "MessagePublisher plugin should load");
        }

        function test_add_and_publish_flow() {
            var topicSelector = find("publisherTopicSelector");
            var typeSelector = find("publisherTypeSelector");
            var addButton = find("addMessageButton");
            var listView = find("messagesListView");

            verify(topicSelector !== null);
            verify(typeSelector !== null);
            verify(addButton !== null);
            verify(listView !== null);

            // 1. Add a message entry
            topicSelector.text = "/test_topic";
            typeSelector.text = "std_msgs/msg/String";

            mouseClick(addButton);
            tryCompare(listView, "count", 1, 2000, "Should have 1 message in list");

            // 2. Wait for delegate to be instantiated and find it
            var enabledCheckBox = null;
            tryVerify(function() {
                enabledCheckBox = find("enabledCheckBox_0");
                return enabledCheckBox !== null;
            }, 3000, "Enabled checkbox for row 0 should exist");

            compare(enabledCheckBox.checked, false, "Should be disabled initially");

            mouseClick(enabledCheckBox);
            tryCompare(enabledCheckBox, "checked", true, 2000, "Checkbox should be checked after click");

            // 3. Verify publication
            tryVerify(function() { return messageCount > 0; }, 5000, "Should receive published messages");
            verify(lastMessage !== null, "Received message should not be null");

            // 4. Disable and verify it stops
            mouseClick(enabledCheckBox);
            tryCompare(enabledCheckBox, "checked", false, 2000, "Checkbox should be unchecked after second click");

            var countAtDisable = messageCount;
            wait(500);
            compare(messageCount, countAtDisable, "Publication should have stopped");
        }

        function test_update_rate() {
            var addButton = find("addMessageButton");
            var listView = find("messagesListView");

            find("publisherTopicSelector").text = "/test_topic";
            find("publisherTypeSelector").text = "std_msgs/msg/String";
            mouseClick(addButton);

            tryCompare(listView, "count", 1, 2000);

            var enabledCheckBox = null;
            var rateSpinBox = null;
            tryVerify(function() {
                enabledCheckBox = find("enabledCheckBox_0");
                rateSpinBox = find("rateSpinBox_0");
                return enabledCheckBox !== null && rateSpinBox !== null;
            }, 3000, "Controls for row 0 should exist");

            mouseClick(enabledCheckBox);
            tryVerify(function() { return messageCount > 0; }, 3000);

            // Change rate and verify timing.
            // 20 Hz target, sampled over 2s after a 500ms settle, ±25% tolerance
            // (offscreen QPA + loaded CI can wobble timer cadence).
            rateSpinBox.value = 20;
            wait(500);
            var startCount = messageCount;
            wait(2000);
            var observed = messageCount - startCount;
            verify(observed >= 30 && observed <= 50,
                   "Expected ~40 messages over 2s at 20Hz (±25%), got " + observed);
        }

        function test_delete_message() {
            var addButton = find("addMessageButton");
            var listView = find("messagesListView");

            find("publisherTopicSelector").text = "/test_topic";
            find("publisherTypeSelector").text = "std_msgs/msg/String";
            mouseClick(addButton);
            tryCompare(listView, "count", 1, 2000);

            var deleteButton = null;
            tryVerify(function() {
                deleteButton = find("deleteButton_0");
                return deleteButton !== null;
            }, 3000, "Delete button for row 0 should exist");

            mouseClick(deleteButton);
            tryCompare(listView, "count", 0, 2000, "Message should be removed from list");
            compare(contextObj.messages.length, 0, "Context messages array should be empty");
        }
    }
}
