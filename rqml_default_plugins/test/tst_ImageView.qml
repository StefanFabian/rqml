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
        property string topic: "/camera/image_raw"
        property string transport: "raw"
        property bool enabled: true
        property bool invert: false
        property bool colorize: false
        property real depth: 3.0
        property int rotation: 0
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/ImageView.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    TestCase {
        id: testCase
        name: "ImageViewTest"
        when: windowShown

        function init() {
            Ros2.reset();
            // Discovery setup for image topics
            Ros2.registerTopic("/camera/image_raw", "sensor_msgs/msg/Image");

            contextObj.topic = "/camera/image_raw";
            contextObj.transport = "raw";
            contextObj.enabled = true;
            contextObj.invert = false;
            contextObj.colorize = false;
            contextObj.depth = 3.0;
            contextObj.rotation = 0;

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; }, 2000, "Loader should be ready");
            wait(200);
        }

        function test_plugin_loads() {
            verify(plugin !== null, "ImageView plugin should load");
        }

        function test_discovery() {
            var topicSelector = find("imageTopicSelector");
            verify(topicSelector !== null);

            topicSelector.text = "/camera/image_raw";
            tryCompare(contextObj, "topic", "/camera/image_raw", 3000, "Context topic should update");
        }

        function test_play_pause() {
            var playButton = find("imagePlayButton");
            verify(playButton !== null, "Play button found");

            compare(contextObj.enabled, true, "Should start enabled");

            // Simulating authentic click to pause
            mouseClick(playButton);
            tryCompare(contextObj, "enabled", false, 3000, "Context enabled property should be false after click");

            // Simulating authentic click to play
            mouseClick(playButton);
            tryCompare(contextObj, "enabled", true, 3000, "Context enabled property should be true after second click");
        }

        function test_invert_toggle() {
            var invertCheckbox = null;
            tryVerify(function() {
                invertCheckbox = find("imageInvertCheckbox");
                return invertCheckbox !== null;
            }, 3000, "Invert checkbox should be found");

            // Initially false
            compare(invertCheckbox.checked, false);

            // Simulating authentic click
            mouseClick(invertCheckbox);
            tryCompare(invertCheckbox, "checked", true, 2000, "Invert checkbox should be checked");
            compare(contextObj.invert, true, "Context invert property should be true");
        }

        function test_rotation_cycling() {
            var rotateLeft = find("imageRotateLeftButton");
            verify(rotateLeft !== null, "Rotate left button found");

            var rotationLabel = find("imageRotationLabel");
            verify(rotationLabel !== null, "Rotation label found");

            // Initial rotation 0
            compare(contextObj.rotation, 0);
            compare(rotationLabel.text, "0°");

            // Cycle through (Rotate Left: 0 -> 270)
            mouseClick(rotateLeft);
            tryCompare(contextObj, "rotation", 270, 2000);
            compare(rotationLabel.text, "270°");

            mouseClick(rotateLeft);
            tryCompare(contextObj, "rotation", 180, 2000);
            compare(rotationLabel.text, "180°");
        }
    }
}
