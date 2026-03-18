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
        enabled: true,
        topic: "/rosout",
        autoScroll: true
    })

    PluginQml.Console {
        id: console_
        anchors.fill: parent
    }

    TestCase {
        name: "ConsoleTest"
        when: windowShown

        // Find the internal QtObject 'd' by searching `data` for its unique properties
        function findInternalD() {
            for (var i = 0; i < console_.data.length; i++) {
                var obj = console_.data[i];
                if (obj && obj.logCount !== undefined && obj.allLogs !== undefined)
                    return obj;
            }
            return null;
        }

        // Find the ListView by walking the visual child tree
        function findListView(parentItem) {
            if (!parentItem) return null;
            if (parentItem.count !== undefined && parentItem.contentItem !== undefined
                    && parentItem.model !== undefined && parentItem.reuseItems !== undefined)
                return parentItem;
            var children = parentItem.children || [];
            for (var i = 0; i < children.length; i++) {
                var found = findListView(children[i]);
                if (found) return found;
            }
            return null;
        }

        function makeMockLogMessage(level, name, msg, file, line, func) {
            return {
                level: level,
                name: name,
                msg: msg,
                file: file || "test.cpp",
                line: line || 42,
                "function": func || "testFunc",
                stamp: {
                    toJSDate: function() { return new Date(2025, 0, 1, 12, 0, 0, 0); }
                }
            };
        }

        function init() {
            windowRoot.context.enabled = true;
            windowRoot.context.autoScroll = true;
            windowRoot.context.topic = "/rosout";
            var d = findInternalD();
            if (d) d.clear();
        }

        function test_01_plugin_loads() {
            verify(console_ !== null, "Console plugin should load");
        }

        function test_02_log_display() {
            var sub = Ros2.findSubscription("/rosout");
            verify(sub !== null, "Subscription for /rosout should exist");

            var listView = findListView(console_);
            verify(listView !== null, "ListView should exist");
            var model = listView.model;
            compare(model.count, 0, "Model should start empty after init");

            sub.injectMessage(makeMockLogMessage(20, "/test_node", "Hello from test"));
            wait(50);
            compare(model.count, 1, "ListModel should contain one log entry after injection");

            sub.injectMessage(makeMockLogMessage(30, "/test_node", "Warning message"));
            wait(50);
            compare(model.count, 2, "ListModel should contain two log entries");
        }

        function test_03_log_level_filtering() {
            var sub = Ros2.findSubscription("/rosout");
            verify(sub !== null, "Subscription should exist");

            var d = findInternalD();
            verify(d !== null, "Internal state object should exist");

            var listView = findListView(console_);
            var model = listView.model;

            // All 5 levels are active by default
            sub.injectMessage(makeMockLogMessage(10, "/node1", "Debug msg"));
            sub.injectMessage(makeMockLogMessage(20, "/node1", "Info msg"));
            sub.injectMessage(makeMockLogMessage(30, "/node1", "Warning msg"));
            sub.injectMessage(makeMockLogMessage(40, "/node1", "Error msg"));
            sub.injectMessage(makeMockLogMessage(50, "/node1", "Fatal msg"));
            wait(50);
            compare(model.count, 5, "All 5 log levels should be shown when no filter is active");
            compare(d.logCount, 5, "Total log count should be 5");

            // Remove debug level (10) from filter and re-apply
            var idx = d.filter.levels.indexOf(10);
            if (idx !== -1) d.filter.levels.splice(idx, 1);
            d.applyFilter();

            compare(model.count, 4, "Debug message should be filtered out");
            compare(d.logCount, 5, "Total log count should remain 5");
        }

        function test_04_enable_disable() {
            var sub = Ros2.findSubscription("/rosout");
            verify(sub !== null, "Subscription should exist");

            var listView = findListView(console_);
            var model = listView.model;

            // Inject while enabled — should appear
            sub.injectMessage(makeMockLogMessage(20, "/node1", "Enabled msg"));
            wait(50);
            compare(model.count, 1, "Message should be added when enabled");

            // Disable capture
            windowRoot.context.enabled = false;
            wait(50);

            sub.injectMessage(makeMockLogMessage(20, "/node1", "Should be ignored"));
            wait(50);
            compare(model.count, 1, "Message should NOT be added when disabled");

            // Re-enable and verify new messages work
            windowRoot.context.enabled = true;
            sub.injectMessage(makeMockLogMessage(20, "/node1", "Re-enabled msg"));
            wait(50);
            compare(model.count, 2, "Message should be added after re-enabling");
        }

        function test_05_auto_scroll_toggle() {
            compare(windowRoot.context.autoScroll, true, "Auto-scroll should default to true");

            windowRoot.context.autoScroll = false;
            compare(windowRoot.context.autoScroll, false, "Auto-scroll should be togglable to false");

            windowRoot.context.autoScroll = true;
            compare(windowRoot.context.autoScroll, true, "Auto-scroll should be togglable back to true");
        }
    }
}
