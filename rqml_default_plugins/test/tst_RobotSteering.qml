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
        topic: "/cmd_vel",
        stamped: false,
        rate: 10,
        enabled: false,
        linear: { min: -1.0, max: 1.0 },
        angular: { min: -1.0, max: 1.0 }
    })

    PluginQml.RobotSteering {
        id: robotSteering
        anchors.fill: parent
    }

    TestCase {
        name: "RobotSteeringTest"
        when: windowShown

        function init() {
            Ros2.reset();
            Ros2._mockTopics["geometry_msgs/msg/Twist"] = ["/cmd_vel", "/base/cmd_vel"];
            Ros2._mockTopics["geometry_msgs/msg/TwistStamped"] = ["/cmd_vel_stamped"];
            Ros2._mockTypeMap["/cmd_vel"] = ["geometry_msgs/msg/Twist"];
            Ros2._mockTypeMap["/cmd_vel_stamped"] = ["geometry_msgs/msg/TwistStamped"];
        }


        function test_01_plugin_loads() {
            verify(robotSteering !== null, "RobotSteering plugin should load");
        }

        function test_02_topic_query() {
            var twistTopics = Ros2.queryTopics("geometry_msgs/msg/Twist");
            compare(twistTopics.length, 2, "Should find 2 Twist topics");
            verify(twistTopics.indexOf("/cmd_vel") !== -1, "Should contain /cmd_vel");

            var stampedTopics = Ros2.queryTopics("geometry_msgs/msg/TwistStamped");
            compare(stampedTopics.length, 1, "Should find 1 TwistStamped topic");
        }

        function test_03_publisher_creation() {
            var publisher = Ros2.createPublisher("/cmd_vel", "geometry_msgs/msg/Twist", 1);
            verify(publisher !== null, "Publisher should be created");

            publisher.publish({
                linear: { x: 0.5, y: 0, z: 0 },
                angular: { x: 0, y: 0, z: 0.3 }
            });
            compare(Ros2.publishedMessages.length, 1, "Should have 1 published message");
            compare(Ros2.publishedMessages[0].topic, "/cmd_vel");
            compare(Ros2.publishedMessages[0].message.linear.x, 0.5);
            compare(Ros2.publishedMessages[0].message.angular.z, 0.3);
        }

        function test_04_stamped_message() {
            var publisher = Ros2.createPublisher("/cmd_vel_stamped", "geometry_msgs/msg/TwistStamped", 1);
            var stamp = Ros2.now();
            publisher.publish({
                header: { stamp: stamp },
                twist: {
                    linear: { x: 1.0, y: 0, z: 0 },
                    angular: { x: 0, y: 0, z: 0 }
                }
            });

            var msgs = Ros2.publishedMessages;
            var lastMsg = msgs[msgs.length - 1];
            verify(lastMsg.message.header !== undefined, "Stamped message should have header");
            verify(lastMsg.message.header.stamp !== undefined, "Header should have stamp");
            compare(lastMsg.message.twist.linear.x, 1.0, "Linear x should be 1.0");
        }

        function test_05_topic_validation() {
            verify(Ros2.isValidTopic("/cmd_vel"), "/cmd_vel should be valid");
            verify(Ros2.isValidTopic("/base/cmd_vel"), "/base/cmd_vel should be valid");
            verify(!Ros2.isValidTopic(""), "Empty string should be invalid");
            verify(!Ros2.isValidTopic("cmd_vel"), "No leading slash should be invalid");
            verify(!Ros2.isValidTopic("/"), "Slash only should be invalid");
        }

        function test_06_context_properties() {
            compare(context.topic, "/cmd_vel", "Default topic should be /cmd_vel");
            compare(context.stamped, false, "Default should be non-stamped");
            compare(context.rate, 10, "Default rate should be 10");
            compare(context.enabled, false, "Should start disabled");

            context.enabled = true;
            compare(context.enabled, true, "Should be enabled after toggle");
            context.enabled = false;
        }
    }
}
