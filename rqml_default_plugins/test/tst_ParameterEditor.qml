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
import QtQuick.Controls
import QtTest
import Ros2

Item {
    id: root
    width: 1024; height: 768

    property var context: contextObj
    QtObject {
        id: contextObj
        property var quickAccess: []
        property bool showStarredOnly: false
        property string filterText: ""
    }

    Utils { id: helpers }

    Loader {
        id: pluginLoader
        anchors.fill: parent
        function reload() { source = ""; source = "../qml/ParameterEditor.qml"; }
    }

    property var plugin: pluginLoader.item

    function find(name) { return helpers.findChild(root, name); }

    TestCase {
        id: testCase
        name: "ParameterEditorTest"
        when: windowShown

        function init() {
            Ros2.reset();

            // Setup mock services for a test node
            var nodeName = "/test_node";

            Ros2.registerService(nodeName + "/list_parameters", "rcl_interfaces/srv/ListParameters", function(req) {
                var resp = Ros2.createEmptyServiceResponse("rcl_interfaces/srv/ListParameters");
                resp.result = { names: ["param1", "group.param2", "group.param3"] };
                return resp;
            });

            Ros2.registerService(nodeName + "/get_parameters", "rcl_interfaces/srv/GetParameters", function(req) {
                var resp = Ros2.createEmptyServiceResponse("rcl_interfaces/srv/GetParameters");
                resp.values = [
                    { type: 2, integer_value: 42 },   // param1
                    { type: 3, double_value: 3.14 },  // group.param2
                    { type: 4, string_value: "test" } // group.param3
                ];
                return resp;
            });

            Ros2.registerService(nodeName + "/describe_parameters", "rcl_interfaces/srv/DescribeParameters", function(req) {
                var resp = Ros2.createEmptyServiceResponse("rcl_interfaces/srv/DescribeParameters");
                resp.descriptors = [
                    { name: "param1", type: 2, description: "Int" },
                    { name: "group.param2", type: 3, description: "Double" },
                    { name: "group.param3", type: 4, description: "String" }
                ];
                return resp;
            });

            Ros2.registerService(nodeName + "/set_parameters", "rcl_interfaces/srv/SetParameters", function(req) {
                var resp = Ros2.createEmptyServiceResponse("rcl_interfaces/srv/SetParameters");
                resp.results = [{ successful: true, reason: "" }];
                return resp;
            });

            contextObj.quickAccess = [];
            contextObj.showStarredOnly = false;

            pluginLoader.reload();
            tryVerify(function() { return pluginLoader.status === Loader.Ready; }, 2000, "Loader should be ready");

            // Wait for discovery to complete
            tryVerify(function() { return find("mainTreeView").count >= 1; }, 5000, "Node discovery failed");
        }

        function test_discovery_and_expansion() {
            var treeView = find("mainTreeView");
            verify(treeView !== null);

            tryVerify(function() { return treeView.count >= 1; }, 5000);

            // Expand /test_node
            var nodeExpand = find("rowExpandButton_/test_node");
            verify(nodeExpand !== null);
            mouseClick(nodeExpand);

            // Expect: /test_node, param1, group
            tryVerify(function() { return treeView.count === 3; }, 5000, "Expansion failed. Count: " + treeView.count);

            // Expand group
            var groupExpand = null;
            tryVerify(function() {
                groupExpand = find("rowExpandButton_/test_node/group");
                return groupExpand !== null;
            }, 3000);
            mouseClick(groupExpand);

            tryVerify(function() { return treeView.count === 5; }, 5000, "Group expansion failed. Count: " + treeView.count);
        }

        function test_starring() {
            var treeView = find("mainTreeView");
            tryVerify(function() { return treeView.count >= 1; }, 5000);

            mouseClick(find("rowExpandButton_/test_node"));
            tryVerify(function() { return treeView.count === 3; }, 5000);

            var starButton = find("rowStarButton_/test_node/param1");
            verify(starButton !== null);

            mouseClick(starButton);
            tryVerify(function() { return contextObj.quickAccess.length === 1; }, 2000);
            compare(contextObj.quickAccess[0], "/test_node/param1");
        }

        function test_filtering() {
            var treeView = find("mainTreeView");
            tryVerify(function() { return treeView.count >= 1; }, 5000);

            // Using manual expansion instead of Load All (proven more stable in expansion test)
            mouseClick(find("rowExpandButton_/test_node"));
            tryVerify(function() { return treeView.count === 3; }, 5000);

            var groupExpand = find("rowExpandButton_/test_node/group");
            verify(groupExpand !== null);
            mouseClick(groupExpand);
            tryVerify(function() { return treeView.count === 5; }, 5000);

            var filterField = find("filterTextField");
            mouseClick(filterField);

            // Filtering for 'm2' matches 'group.param2'
            keyClick("m"); keyClick("2");

            // Expected: /test_node (parent), group (intermediate), group.param2 (match)
            tryVerify(function() { return treeView.count === 3; }, 5000, "Filtering for 'm2' failed. Count: " + treeView.count);

            // Clean up
            keyClick(Qt.Key_Backspace); keyClick(Qt.Key_Backspace);
            tryVerify(function() { return treeView.count === 5; }, 5000);
        }
    }
}
