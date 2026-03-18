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
        messages: undefined
    })

    PluginQml.MessagePublisher {
        id: messagePublisher
        anchors.fill: parent
    }

    TestCase {
        name: "MessagePublisherTest"
        when: windowShown

        function init() {
            Ros2.reset();
            Ros2._mockTopics[""] = ["/chatter", "/cmd_vel"];
            Ros2._mockTypeMap["/chatter"] = ["std_msgs/msg/String"];
            Ros2._mockTypeMap["/cmd_vel"] = ["geometry_msgs/msg/Twist"];

        }

        function test_01_plugin_loads() {
            verify(messagePublisher !== null, "MessagePublisher plugin should load");
        }

        function test_02_topic_query() {
            var topics = Ros2.queryTopics();
            compare(topics.length, 2, "Should find 2 topics");
            verify(topics.indexOf("/chatter") !== -1, "Should contain /chatter");
            verify(topics.indexOf("/cmd_vel") !== -1, "Should contain /cmd_vel");
        }

        function test_03_type_query() {
            var types = Ros2.getTopicTypes("/chatter");
            compare(types.length, 1, "Should find 1 type for /chatter");
            compare(types[0], "std_msgs/msg/String", "Type should be String");
        }

        function test_04_empty_message_creation() {
            var msg = Ros2.createEmptyMessage("std_msgs/msg/String");
            verify(msg !== null, "Empty message should be created");
            compare(msg["#messageType"], "std_msgs/msg/String");
            compare(msg.data, "", "Default string data should be empty");
        }

        function test_05_add_message_entry() {
            wait(50);
            // Ensure messages is initialized
            if (context.messages === undefined) context.messages = [];
            var initialLength = context.messages.length;

            messagePublisher.addMessageEntry("/chatter", "std_msgs/msg/String", 1);
            wait(50);

            compare(context.messages.length, initialLength + 1, "Should have one more message entry");
            var entry = context.messages[context.messages.length - 1];
            compare(entry.topic, "/chatter", "Entry topic should match");
            compare(entry.type, "std_msgs/msg/String", "Entry type should match");
            compare(entry.enabled, false, "Entry should start disabled");
            compare(entry.rate, 1, "Entry rate should be 1 Hz");
        }

        function test_06_remove_message_entry() {
            wait(50);
            if (context.messages === undefined) context.messages = [];
            messagePublisher.addMessageEntry("/chatter", "std_msgs/msg/String", 1);
            wait(50);
            var countBefore = context.messages.length;

            messagePublisher.removeEntry(countBefore - 1);
            wait(50);

            compare(context.messages.length, countBefore - 1, "Should have one less entry after removal");
        }

        function test_07_publisher_records_messages() {
            var publisher = Ros2.createPublisher("/chatter", "std_msgs/msg/String", 10);
            publisher.publish({ data: "hello" });
            publisher.publish({ data: "world" });

            compare(Ros2.publishedMessages.length, 2, "Should have recorded 2 published messages");
            compare(Ros2.publishedMessages[0].message.data, "hello");
            compare(Ros2.publishedMessages[1].message.data, "world");
        }

        function test_08_topic_validation() {
            verify(Ros2.isValidTopic("/chatter"), "/chatter should be valid");
            verify(!Ros2.isValidTopic("chatter"), "No leading slash should be invalid");
        }
    }
}
