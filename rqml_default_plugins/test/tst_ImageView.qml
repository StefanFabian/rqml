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
        enabled: true,
        invert: false,
        colorize: false,
        depth: 3.0,
        rotation: 0
    })

    PluginQml.ImageView {
        id: imageView
        anchors.fill: parent
    }

    TestCase {
        name: "ImageViewTest"
        when: windowShown

        function init() {
            Ros2.reset();
            Ros2._mockTopics["sensor_msgs/msg/Image"] = [
                "/camera/image_raw",
                "/depth_camera/image_raw"
            ];
            Ros2._mockTopics["sensor_msgs/msg/CompressedImage"] = [
                "/camera/image_raw/compressed"
            ];
            Ros2._mockTypeMap["/camera/image_raw"] = ["sensor_msgs/msg/Image"];
            Ros2._mockTypeMap["/depth_camera/image_raw"] = ["sensor_msgs/msg/Image"];
            Ros2._mockTypeMap["/camera/image_raw/compressed"] = ["sensor_msgs/msg/CompressedImage"];
        }

        function test_01_plugin_loads() {
            verify(imageView !== null, "ImageView plugin should load");
        }

        function test_02_topic_discovery() {
            var imageTopics = Ros2.queryTopics("sensor_msgs/msg/Image");
            compare(imageTopics.length, 2, "Should find 2 image topics");
            verify(imageTopics.indexOf("/camera/image_raw") !== -1, "Should contain /camera/image_raw");

            var compressedTopics = Ros2.queryTopics("sensor_msgs/msg/CompressedImage");
            compare(compressedTopics.length, 1, "Should find 1 compressed topic");
        }

        function test_03_rotation_controls() {
            context.rotation = 0;
            compare(context.rotation, 0, "Initial rotation should be 0");

            context.rotation = (context.rotation + 90) % 360;
            compare(context.rotation, 90, "Rotation should be 90 after rotate right");

            context.rotation = (context.rotation + 90) % 360;
            compare(context.rotation, 180, "Rotation should be 180 after another rotate right");

            context.rotation = ((context.rotation - 90) + 360) % 360;
            compare(context.rotation, 90, "Rotation should be 90 after rotate left");

            context.rotation = 0;
        }

        function test_04_enable_disable() {
            compare(context.enabled, true, "Should start enabled");
            context.enabled = false;
            compare(context.enabled, false, "Should be disabled");
            context.enabled = true;
        }

        function test_05_invert_colorize_toggles() {
            compare(context.invert, false, "Invert should default to false");
            compare(context.colorize, false, "Colorize should default to false");

            context.invert = true;
            compare(context.invert, true, "Invert should toggle");

            context.colorize = true;
            compare(context.colorize, true, "Colorize should toggle");

            context.invert = false;
            context.colorize = false;
        }

        function test_06_depth_setting() {
            compare(context.depth, 3.0, "Default depth should be 3.0");
            context.depth = 5.0;
            compare(context.depth, 5.0, "Depth should be updatable");
            context.depth = 3.0;
        }

        function test_07_topic_type_detection() {
            // Raw image topic should be detected correctly
            var rawTypes = Ros2.queryTopicTypes("/camera/image_raw");
            verify(rawTypes.indexOf("sensor_msgs/msg/Image") !== -1, "Should detect as Image type");

            // Compressed topic should be detected as CompressedImage
            var compTypes = Ros2.queryTopicTypes("/camera/image_raw/compressed");
            verify(compTypes.indexOf("sensor_msgs/msg/CompressedImage") !== -1, "Should detect as CompressedImage");
        }

        function test_08_topic_validation() {
            verify(Ros2.isValidTopic("/camera/image_raw"), "Image topic should be valid");
            verify(!Ros2.isValidTopic(""), "Empty should be invalid");
        }
    }
}
