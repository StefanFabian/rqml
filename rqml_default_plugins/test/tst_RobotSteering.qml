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
import QtTest
import Ros2

Item {
    id: root
    width: 1024; height: 768

    property var context: contextObj
    QtObject {
        id: contextObj
        property string topic: "/cmd_vel"
        property bool stamped: false
        property int rate: 10
        property bool enabled: false
        property var linear: ({ min: -1.0, max: 1.0 })
        property var angular: ({ min: -1.0, max: 1.0 })
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/RobotSteering.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    property var lastTwist: null
    property int twistCount: 0
    Subscription {
        id: twistSub
        topic: contextObj.topic
        messageType: "geometry_msgs/msg/Twist"
        onNewMessage: (msg) => {
            lastTwist = msg;
            twistCount++;
        }
    }

    property var lastTwistStamped: null
    property int twistStampedCount: 0
    Subscription {
        id: twistStampedSub
        topic: contextObj.topic
        messageType: "geometry_msgs/msg/TwistStamped"
        onNewMessage: (msg) => {
            lastTwistStamped = msg;
            twistStampedCount++;
        }
    }

    TestCase {
        id: testCase
        name: "RobotSteeringTest"
        when: windowShown

        function init() {
            Ros2.reset();
            // Re-register static subscriptions because reset() cleared them
            Ros2._registerSubscription(twistSub);
            Ros2._registerSubscription(twistStampedSub);

            Ros2.registerTopic("/cmd_vel", "geometry_msgs/msg/Twist");
            Ros2.registerTopic("/base/cmd_vel", "geometry_msgs/msg/Twist");
            Ros2.registerTopic("/cmd_vel_stamped", "geometry_msgs/msg/TwistStamped");

            contextObj.enabled = false;
            contextObj.stamped = false;
            contextObj.topic = "/cmd_vel";
            contextObj.rate = 10;
            contextObj.linear = { min: -1.0, max: 1.0 };
            contextObj.angular = { min: -1.0, max: 1.0 };

            twistCount = 0;
            twistStampedCount = 0;
            lastTwist = null;
            lastTwistStamped = null;

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; }, 2000, "Loader should be ready");
            // Wait for initial model population
            wait(50);
        }

        function test_plugin_loads() {
            verify(plugin !== null, "RobotSteering plugin should load");
        }

        function test_topic_selector() {
            var topicSelector = find("steeringTopicSelector");
            verify(topicSelector !== null, "Topic selector should be found");
            var model = topicSelector.model;
            verify(model.length >= 2,
                "Topic selector should have at least 2 velocity topics");

            topicSelector.text = "/base/cmd_vel";
            tryCompare(contextObj, "topic", "/base/cmd_vel", 3000, "Context topic should update");
        }

        function test_play_pause() {
            var playButton = find("steeringPlayButton");
            verify(playButton !== null, "Play button should be found");

            compare(contextObj.enabled, false, "Should start disabled");

            // Simulating authentic click
            mouseClick(playButton);
            tryCompare(contextObj, "enabled", true, 3000, "Context enabled property should be true");

            tryVerify(function() { return twistCount > 0; }, 5000, "Should receive published Twist messages");

            mouseClick(playButton);
            tryCompare(contextObj, "enabled", false, 3000, "Context enabled property should be false");
        }

        function test_stamped_checkbox() {
            var stampedCheckbox = find("steeringStampedCheckbox");
            verify(stampedCheckbox !== null, "Stamped checkbox should be found");

            var playButton = find("steeringPlayButton");
            mouseClick(playButton);

            mouseClick(stampedCheckbox);
            tryCompare(contextObj, "stamped", true, 3000, "Context stamped property should update");

            tryVerify(function() { return twistStampedCount > 0; }, 5000, "Should receive TwistStamped messages");

            mouseClick(stampedCheckbox);
            tryCompare(contextObj, "stamped", false, 3000, "Context stamped property should update back");
        }

        function test_stop_button() {
            var linearSlider = find("steeringLinearSlider");
            var angularSlider = find("steeringAngularSlider");
            var stopButton = find("steeringStopButton");
            verify(linearSlider !== null, "Linear slider should be found");
            verify(angularSlider !== null, "Angular slider should be found");
            verify(stopButton !== null, "Stop button should be found");


            var playButton = find("steeringPlayButton");

            mouseClick(playButton);
            linearSlider.value = 0.5;
            angularSlider.value = -0.5;

            mouseClick(stopButton);
            compare(linearSlider.value, 0, "Linear slider should be reset to zero");
            compare(angularSlider.value, 0, "Angular slider should be reset to zero");

            tryVerify(function() {
                if (!lastTwist) return false;
                return Math.abs(lastTwist.linear.x) < 0.01 && Math.abs(lastTwist.angular.z) < 0.01;
            }, 3000, "Should receive a zero velocity command");
        }

        function test_slider_drag_interaction() {
            var linearSlider = find("steeringLinearSlider");
            var playButton = find("steeringPlayButton");

            mouseClick(playButton);

            // Simulating honest slider interaction via mouse drag
            // SpeedSlider typically has a handle inside its Layout or is a Slider itself
            // If it follows standard Slider pattern, mouseClick at an offset moves it.
            mouseClick(linearSlider, linearSlider.width / 2, linearSlider.height * 0.2);

            tryVerify(function() {
                return Math.abs(linearSlider.value) > 0.1;
            }, 2000, "Slider value should change after mouse click at offset");

            tryVerify(function() {
                if (!lastTwist) return false;
                return Math.abs(lastTwist.linear.x - linearSlider.value) < 0.05;
            }, 3000, "Published message should reflect the slider's value after interaction");
        }

        function test_configurable_ranges() {
            // Preset non-default ranges in context and reload so the sliders
            // pick them up on construction. Values are chosen so that they
            // survive the 1-significant-digit rounding the embedded
            // DecimalInputField performs on display.
            contextObj.linear = { min: -2, max: 4 };
            contextObj.angular = { min: -3, max: 5 };
            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; }, 2000);

            var linearSlider = find("steeringLinearSlider");
            var angularSlider = find("steeringAngularSlider");
            verify(linearSlider !== null);
            verify(angularSlider !== null);

            // Context-provided ranges must be applied to each slider.
            compare(linearSlider.from, -2, "Linear min from context");
            compare(linearSlider.to, 4, "Linear max from context");
            compare(angularSlider.from, -3, "Angular min from context");
            compare(angularSlider.to, 5, "Angular max from context");

            // Values outside the configured range must be clamped.
            linearSlider.value = 100.0;
            compare(linearSlider.value, 4, "Linear value clamped to configured max");
            linearSlider.value = -100.0;
            compare(linearSlider.value, -2, "Linear value clamped to configured min");
            linearSlider.value = 0;

            angularSlider.value = 100.0;
            compare(angularSlider.value, 5, "Angular value clamped to configured max");
            angularSlider.value = -100.0;
            compare(angularSlider.value, -3, "Angular value clamped to configured min");
            angularSlider.value = 0;

            // Changing a slider's range persists back to the context so the
            // configured limits survive a reload.
            linearSlider.to = 6;
            tryVerify(function() { return contextObj.linear.max === 6; }, 2000,
                "context.linear.max should reflect slider.to");
            angularSlider.from = -4;
            tryVerify(function() { return contextObj.angular.min === -4; }, 2000,
                "context.angular.min should reflect slider.from");
        }

        function test_publication_rate() {
            var rateSpinBox = find("steeringRateSpinBox");
            verify(rateSpinBox !== null);

            var playButton = find("steeringPlayButton");
            mouseClick(playButton);

            // Direct set is fine for spinbox as it's a standard control "element tested itself"
            rateSpinBox.value = 20;
            tryCompare(contextObj, "rate", 20, 3000, "Context rate property should update");

            // 20 Hz target, sampled over 2s after a 500ms settle, ±25% tolerance.
            wait(500);
            var startCount = twistCount;
            wait(2000);
            var observed = twistCount - startCount;
            verify(observed >= 30 && observed <= 50,
                   "Expected ~40 messages over 2s at 20Hz (±25%), got " + observed);
        }
    }
}
