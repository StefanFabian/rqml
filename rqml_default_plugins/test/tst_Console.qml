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
    width: 800; height: 600

    property var context: contextObj
    QtObject {
        id: contextObj
        property bool enabled: true
        property string topic: "/rosout"
        property bool autoScroll: true
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/Console.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    Publisher {
        id: testLogPublisher
        topic: "/rosout"
        type: "rcl_interfaces/msg/Log"
    }

    TestCase {
        name: "ConsoleTest"
        when: windowShown

        function createLogMessage(level, name, msg) {
            var logMsg = Ros2.createEmptyMessage("rcl_interfaces/msg/Log");
            logMsg.level = level;
            logMsg.name = name;
            logMsg.msg = msg;
            logMsg.file = "test.cpp";
            logMsg.function = "testFn";
            logMsg.line = 42;
            logMsg.stamp = Ros2.now();
            return logMsg;
        }

        function publishLog(level, nodeName, message) {
            return testLogPublisher.publish(createLogMessage(level, nodeName, message));
        }

        function init() {
            Ros2.reset();
            RQml.resetClipboard();
            // Re-register the topic explicitly since reset() clears the mock state
            Ros2.registerTopic("/rosout", "rcl_interfaces/msg/Log");

            contextObj.enabled = true;
            contextObj.autoScroll = true;
            contextObj.topic = "/rosout";
            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; }, 2000, "Loader should be ready");
            // Wait for initial model population
            wait(50);
        }

        function test_plugin_loads() {
            verify(plugin !== null, "Console plugin should load");
        }

        function test_log_display() {
            var listView = find("consoleListView");
            verify(listView !== null, "Console ListView should exist");

            publishLog(20, "/test_node", "Hello from test");
            publishLog(30, "/test_node", "Warning message");
            tryCompare(listView.model, "count", 2, 1000, "ListModel should contain two log entries");
        }

        function test_log_level_filtering() {
            var listView = find("consoleListView");
            verify(listView !== null, "Console ListView should exist");

            publishLog(10, "/node1", "Debug msg");
            publishLog(20, "/node1", "Info msg");
            publishLog(30, "/node1", "Warning msg");
            publishLog(40, "/node1", "Error msg");
            publishLog(50, "/node1", "Fatal msg");
            tryCompare(listView.model, "count", 5, 1000, "All 5 log levels should be shown");

            // Open filter popup
            var filterButton = find("consoleFilterButton");
            verify(filterButton !== null, "Filter button found");
            mouseClick(filterButton);

            var filterPopup = find("consoleFilterPopup");
            tryVerify(function() { return filterPopup.visible; }, 2000, "Filter popup should be visible");

            var debugToggle = find("filterLevelToggle_10");
            verify(debugToggle !== null, "Debug filter toggle found");

            // Toggle off Debug
            mouseClick(debugToggle);
            tryCompare(listView.model, "count", 4, 1000, "Debug message should be filtered out");

            // Toggle back on
            mouseClick(debugToggle);
            tryCompare(listView.model, "count", 5, 1000, "All messages should be visible again");
        }

        function test_enable_disable() {
            var listView = find("consoleListView");
            verify(listView !== null, "Console ListView should exist");

            publishLog(20, "/node1", "Enabled msg");
            tryCompare(listView.model, "count", 1, 1000);

            var enableToggle = find("consoleEnableToggle");
            verify(enableToggle !== null, "Enable toggle found");
            verify(enableToggle.checked, "Should be enabled initially");

            // Disable
            mouseClick(enableToggle);
            tryCompare(enableToggle, "checked", false, 1000, "Toggle should be unchecked");
            compare(contextObj.enabled, false, "Context enabled property should update");

            publishLog(20, "/node1", "Should be ignored");
            wait(200);
            compare(listView.model.count, 1, "No message added when disabled");

            // Enable
            mouseClick(enableToggle);
            tryCompare(enableToggle, "checked", true, 2000, "Toggle should be checked");
            compare(contextObj.enabled, true, "Context enabled property should update");

            publishLog(20, "/node1", "Re-enabled msg");
            tryCompare(listView.model, "count", 2, 2000, "Message added after re-enabling");
        }

        function test_auto_scroll() {
            var autoScrollCheckbox = find("consoleAutoScrollCheckbox");
            verify(autoScrollCheckbox !== null, "Auto-scroll checkbox found");
            verify(autoScrollCheckbox.checked, "Should be checked initially");

            // Toggle off
            mouseClick(autoScrollCheckbox);
            tryCompare(autoScrollCheckbox, "checked", false, 2000, "Checkbox should be unchecked");
            compare(contextObj.autoScroll, false, "Context autoScroll should be false");

            // Toggle on
            mouseClick(autoScrollCheckbox);
            tryCompare(autoScrollCheckbox, "checked", true, 2000, "Checkbox should be checked");
            compare(contextObj.autoScroll, true, "Context autoScroll should be true");
        }

        function test_clear_button() {
            var listView = find("consoleListView");
            publishLog(20, "/node1", "Msg 1");
            publishLog(30, "/node1", "Msg 2");
            tryCompare(listView.model, "count", 2, 2000);

            var clearButton = find("consoleClearButton");
            verify(clearButton !== null, "Clear button found");

            mouseClick(clearButton);
            tryCompare(listView.model, "count", 0, 2000, "Model should be empty after clear");
        }

        function test_text_filter() {
            var listView = find("consoleListView");
            publishLog(20, "/node1", "Hello world");
            publishLog(20, "/node2", "Goodbye world");
            publishLog(20, "/node3", "Hello again");
            tryCompare(listView.model, "count", 3, 2000);

            var filterField = find("consoleFilterTextField");
            verify(filterField !== null, "Filter field found");

            // Focus and type "Hello"
            mouseClick(filterField);
            keyClick("H"); keyClick("e"); keyClick("l"); keyClick("l"); keyClick("o");
            // Debounce is 300ms, it should still be 3 messages
            wait(150)
            compare(listView.model.count, 3, "Should still show 3 messages after 150ms");
            // But after some more time, it should filter to 2 messages
            tryCompare(listView.model, "count", 2, 500, "Filter should apply matching 'Hello'");

            // Backspace to clear
            for (var i = 0; i < 5; i++) {
                keyClick(Qt.Key_Backspace);
            }
            tryCompare(listView.model, "count", 3, 1000, "Should show all messages after clearing filter");
        }

        function test_context_menu() {
            var listView = find("consoleListView");
            publishLog(20, "/my_node", "The quick brown fox");
            tryCompare(listView.model, "count", 1, 2000);

            // Force a delegate to be realized
            listView.positionViewAtIndex(0, ListView.Beginning);
            var delegate = null;
            tryVerify(function() {
                delegate = listView.itemAtIndex(0);
                return delegate !== null;
            }, 2000, "Delegate at index 0 should be realized");

            // Copy Message
            RQml.resetClipboard();
            var copyMessage = helpers.findChild(delegate, "consoleCopyMessageAction");
            verify(copyMessage, "Copy Message action found");
            copyMessage.triggered();
            tryCompare(RQml, "clipboard", "The quick brown fox", 1000);

            // Copy Node Name
            RQml.resetClipboard();
            var copyNode = helpers.findChild(delegate, "consoleCopyNodeNameAction");
            verify(copyNode, "Copy Node Name action found");
            copyNode.triggered();
            tryCompare(RQml, "clipboard", "/my_node", 1000);

            // Copy Location
            RQml.resetClipboard();
            var copyLocation = helpers.findChild(delegate, "consoleCopyLocationAction");
            verify(copyLocation, "Copy Location action found");
            copyLocation.triggered();
            tryCompare(RQml, "clipboard", "test.cpp:42 (testFn)", 1000);
        }

        function test_settings_dialog() {
            // Register an alternative log topic the mock can discover.
            Ros2.registerTopic("/other_logs", "rcl_interfaces/msg/Log");

            var settingsButton = find("consoleSettingsButton");
            verify(settingsButton, "Settings button found");
            mouseClick(settingsButton);

            var dialog = find("consoleSettingsDialog");
            verify(dialog, "Settings dialog found");
            tryVerify(function() { return dialog.visible; }, 2000, "Settings dialog should open");

            var topicSelect = find("consoleSettingsTopicSelect");
            verify(topicSelect, "Topic ComboBox found");
            // The discovered topic should be listed immediately (discovery runs in Component.onCompleted).
            tryVerify(function() {
                var m = topicSelect.model || [];
                return m.indexOf && m.indexOf("/rosout") !== -1;
            }, 2000, "Rosout topic should be in initial model");

            // Changing the edit text updates the plugin context.
            topicSelect.editText = "/other_logs";
            tryCompare(contextObj, "topic", "/other_logs", 2000,
                "Context topic should reflect the new selection");

            // Invalid topic should NOT overwrite a valid context.topic.
            topicSelect.editText = "not_a_topic";
            wait(50);
            compare(contextObj.topic, "/other_logs",
                "Invalid topic should be ignored");

            // Register a new log topic AFTER the dialog opened and verify the
            // refresh button picks it up - only the refresh should update the
            // model, not automatic discovery.
            Ros2.registerTopic("/late_logs", "rcl_interfaces/msg/Log");
            var beforeRefresh = (topicSelect.model || []);
            verify(Array.prototype.indexOf.call(beforeRefresh, "/late_logs") === -1,
                "Model should be stale before refresh");

            var refreshButton = find("consoleSettingsRefreshButton");
            verify(refreshButton, "Refresh button found");
            mouseClick(refreshButton);
            tryVerify(function() {
                var m = topicSelect.model || [];
                return Array.prototype.indexOf.call(m, "/late_logs") !== -1;
            }, 2000, "Refresh should include the newly-registered topic");
        }
    }
}
