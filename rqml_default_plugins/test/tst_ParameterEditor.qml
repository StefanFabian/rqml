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
import "../qml/interfaces" as Interfaces
import Ros2

Item {
    id: windowRoot
    width: 800
    height: 600

    // Fake context for the plugin
    property var context: ({
        quickAccess: [],
        showStarredOnly: false
    })

    PluginQml.ParameterEditor {
        id: editor
        anchors.fill: parent
    }

    TestCase {
        name: "ParameterEditorTest"
        when: windowShown
        id: testCase

        function initTestCase() {
            // Give it some time if needed, but our mock is synchronous
        }

        function test_1_nodes_discovered() {
            verify(editor !== null)
            compare(editor.d.totalNodes, 1, "Should discover 1 node from mock")

            var elements = editor.d.treeElements
            verify(elements.length > 0, "Tree elements should not be empty")
            compare(elements[0].rowType, "node")
            compare(elements[0].nodeName, "/mock_node")
            // initially 0 params discovered
            // node title shouldn't have count yet
        }

        function test_1b_node_expand_via_toggle() {
            // Exercise expandCollapseToggle to verify it correctly accesses
            // acquiredNodes via the stateContext, not the outer context.
            wait(50);
            var view = findListView(editor);
            verify(view !== null, "ListView should exist");
            verify(view.contentItem !== null, "ListView contentItem should exist");

            // Find the node delegate
            var nodeDelegate = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.rowType === "node") {
                    nodeDelegate = del;
                    break;
                }
            }
            verify(nodeDelegate !== null, "Node delegate should be found");

            // Call expandCollapseToggle — this goes through the actual code path
            // that was buggy (context.acquiredNodes instead of stateCtx.acquiredNodes)
            nodeDelegate.expandCollapseToggle();
            wait(50);

            // After toggle, node should be expanded and acquired
            verify(editor.d.expandedState["/mock_node"] === true, "Node should be expanded after toggle");
            verify(editor.d.acquiredNodes.indexOf("/mock_node") !== -1, "Node should be acquired after toggle");
        }

        function test_2_node_expansion() {
            // test_1b already expanded the node and acquired it via expandCollapseToggle.
            // Here we ensure the group is also expanded, then rebuild to see full tree.
            var st = editor.d.expandedState;
            st["/mock_node"] = true;
            st["/mock_node/mock_group"] = true;
            editor.d.expandedState = st;

            // Node was already acquired by test_1b, just rebuild to reflect expanded groups
            editor.d.rebuildModel();
            wait(50)

            console.log("Expanded state is:", JSON.stringify(editor.d.expandedState))

            var elements = editor.d.treeElements
            verify(elements.length > 0)

            // Check that group "mock_group" was created because of path compression
            // We have mock_group.mock_param_1 and mock_group.mock_param_2
            var foundGroup = false
            var foundParam1 = false
            var foundParam2 = false

            console.log("Tree elements count:", elements.length)

            // Wait for delegates to instantiate
            wait(50);

            for (var i = 0; i < elements.length; i++) {
                var el = elements[i]
                console.log("Element", i, "type:", el.rowType, "fullPath:", el.fullPath, "displayName:", el.displayName)
                if (el.rowType === "group" && el.displayName === "mock_group (5)") {
                    foundGroup = true
                }
                if (el.rowType === "param" && el.paramName === "mock_group.mock_param_1") {
                    foundParam1 = true
                    compare(el.value, "hello mock", "String value should match mock")
                    compare(el.readOnly, false)
                }
                if (el.rowType === "param" && el.paramName === "mock_group.mock_param_2") {
                    foundParam2 = true
                    compare(el.value, 42, "Integer value should match mock")
                    compare(el.readOnly, true)
                    compare(el.integerRange.to, 100)
                }
            }

            verify(foundGroup, "Path compressed group should be found")
            verify(foundParam1, "Param 1 should be found")
            verify(foundParam2, "Param 2 should be found")
        }

        function test_2b_min_max_labels() {
            wait(50);
            var view = findListView(editor);
            verify(view !== null, "ListView should exist");

            // Look for the elements by objectName
            var labelsFound = {
                param_2_min: false,
                param_2_max: false,
                param_3_min: false,
                param_3_max: false,
                param_4_min: false,
                param_4_max: false,
                param_5_min: false,
                param_5_max: false
            };

            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.rowType === "param") {
                    var childName = del.modelData.paramName;
                    var minLbl = findObjectByName(del, "minLabel_" + childName);
                    var maxLbl = findObjectByName(del, "maxLabel_" + childName);

                    if (childName === "mock_group.mock_param_2") { // int, has range
                        if (minLbl) { labelsFound.param_2_min = true; compare(minLbl.text, "0", "Param 2 min should be 0"); verify(minLbl.visible, "Param 2 min should be visible"); }
                        if (maxLbl) { labelsFound.param_2_max = true; compare(maxLbl.text, "100", "Param 2 max should be 100"); verify(maxLbl.visible, "Param 2 max should be visible"); }
                    } else if (childName === "mock_group.mock_param_3") { // int, min only
                        if (minLbl) { labelsFound.param_3_min = true; compare(minLbl.text, "Min: 5", "Param 3 min should be 'Min: 5'"); verify(minLbl.visible, "Param 3 min should be visible"); }
                        if (maxLbl) { labelsFound.param_3_max = true; verify(!maxLbl.visible, "Param 3 max should NOT be visible"); }
                    } else if (childName === "mock_group.mock_param_4") { // int, max only
                        if (minLbl) { labelsFound.param_4_min = true; verify(!minLbl.visible, "Param 4 min should NOT be visible"); }
                        if (maxLbl) { labelsFound.param_4_max = true; compare(maxLbl.text, "Max: 100", "Param 4 max should be 'Max: 100'"); verify(maxLbl.visible, "Param 4 max should be visible"); }
                    } else if (childName === "mock_group.mock_param_5") { // double, has range
                        if (minLbl) { labelsFound.param_5_min = true; compare(minLbl.text, "0", "Param 5 min should be 0"); verify(minLbl.visible, "Param 5 min should be visible"); }
                        if (maxLbl) { labelsFound.param_5_max = true; compare(maxLbl.text, "10", "Param 5 max should be 10"); verify(maxLbl.visible, "Param 5 max should be visible"); }
                    }
                }
            }

            verify(labelsFound.param_2_min, "Param 2 minLabel not found");
            verify(labelsFound.param_2_max, "Param 2 maxLabel not found");
            verify(labelsFound.param_3_min, "Param 3 minLabel not found");
            verify(labelsFound.param_3_max, "Param 3 maxLabel not found");
            verify(labelsFound.param_4_min, "Param 4 minLabel not found");
            verify(labelsFound.param_4_max, "Param 4 maxLabel not found");
            verify(labelsFound.param_5_min, "Param 5 minLabel not found");
            verify(labelsFound.param_5_max, "Param 5 maxLabel not found");
        }

        function test_3_set_parameter() {
            // Test setting a parameter goes through
            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "new value", 4)
            // The service mock should trigger parametersChanged and update the inner value.
            // Wait, our mock actually doesn't update the cache of the ParameterService itself,
            // but the real ParameterService's setParameter method does:
            // if (node.parameters[paramName]) node.parameters[paramName].value = value;
            // root.parametersChanged(nodeName);

            // Since the real service is running, it should have updated the internal state.
            // We wait for the view to automatically react to the parameter updates via signals.
            wait(50)

            var foundParam1 = false
            var elements = editor.d.treeElements
            for (var i = 0; i < elements.length; i++) {
                var el = elements[i]
                if (el.rowType === "param" && el.paramName === "mock_group.mock_param_1") {
                    foundParam1 = true
                    compare(el.value, "new value", "Param value should have been updated")
                }
            }
            verify(foundParam1, "Param 1 should still be found")
        }

        function findListView(parentItem) {
            if (!parentItem) return null;
            if (parentItem.contentItem !== undefined && parentItem.contentY !== undefined) return parentItem;
            var children = parentItem.children || [];
            for (var i = 0; i < children.length; i++) {
                var found = findListView(children[i]);
                if (found) return found;
            }
            return null;
        }

        function findObjectByName(parentItem, objName) {
            if (!parentItem) return null;
            if (parentItem.objectName === objName) return parentItem;
            var children = parentItem.children || [];
            if (parentItem.contentItem) children = parentItem.contentItem.children;
            for (var i = 0; i < children.length; i++) {
                var found = findObjectByName(children[i], objName);
                if (found) return found;
            }
            return null;
        }

        function test_4_external_parameter_update() {
            // Simulate an external parameter change event on ROS 2 topic

            // Wait to ensure delegates exist
            wait(50);

            // Rebuild model is removed here because test 3 leaves the model fully populated
            // Wait so delegates are fully present
            wait(50);

            var view = findListView(editor);

            var stringEditorItem = null;
            if (view && view.contentItem) {
                for (var i = 0; i < view.contentItem.children.length; i++) {
                    var del = view.contentItem.children[i];
                    if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                        stringEditorItem = findObjectByName(del, "stringEditor_mock_group.mock_param_1");
                        break;
                    }
                }
            }

            verify(stringEditorItem !== null, "String editor delegate should be instantiated and found");

            var originalText = stringEditorItem.text;

            // Provide a mock ParameterEvent object matching rcl_interfaces/msg/ParameterEvent
            // We mock the C++ QList behavior where `[i]` does not work (returns undefined) but `.at(i)` does.
            var mockChangedParams = {
                length: 1,
                at: function(i) {
                    if (i === 0) return {
                        "name": "mock_group.mock_param_1",
                        "value": {
                            "type": 4,
                            "string_value": "external update"
                        }
                    };
                    return undefined;
                }
            };

            Interfaces.ParameterService._paramSub.message = {
                "node": "/mock_node",
                "changed_parameters": mockChangedParams
            };

            // The delegate's connection should have caught this and updated stringEditorItem.text
            wait(50); // wait for signal and bindings

            compare(stringEditorItem.text, "external update", "Delegate property 'text' should reactively update from external ParameterChanged event without full model rebuild destroying the item")
        }

        function test_5_save_and_load_parameters() {
            // Give delegates time to settle
            wait(50);

            // Save the group parameters to JSON
            var jsonPath = "test_params.json";
            editor.d.saveGroupParams("/mock_node", "/mock_node/mock_group", jsonPath);
            verify(RQml.fileExists(jsonPath), "JSON file should be created");

            var savedJsonStr = RQml.readFile(jsonPath);
            verify(savedJsonStr.indexOf("mock_param_1") !== -1, "JSON should contain mock_param_1");

            // Change a parameter internally to simulate user edit
            var data = Interfaces.ParameterService.getNodeData("/mock_node");
            var originalValue = data.parameters["mock_group.mock_param_1"].value;

            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "I AM CHANGED", 4);
            wait(50);
            compare(data.parameters["mock_group.mock_param_1"].value, "I AM CHANGED", "Parameter should be modified");

            // Now load the parameters back from the JSON
            editor.d.loadGroupParams("/mock_node", "/mock_node/mock_group", jsonPath);
            wait(50);

            compare(data.parameters["mock_group.mock_param_1"].value, originalValue, "Parameter should be restored from JSON");

            // Note: because we have mock Ros2.io for yaml as well, we should test it
            var yamlPath = "test_params.yaml";
            editor.d.saveGroupParams("/mock_node", "/mock_node/mock_group", yamlPath);

            // The Ros2.io mock writes it, we can then load it
            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "YAML CHANGE", 4);
            wait(50);
            compare(data.parameters["mock_group.mock_param_1"].value, "YAML CHANGE", "Parameter should be modified again");

            editor.d.loadGroupParams("/mock_node", "/mock_node/mock_group", yamlPath);
            wait(50);

            compare(data.parameters["mock_group.mock_param_1"].value, originalValue, "Parameter should be restored from YAML");
        }

        function test_6_save_dialog_flow() {
            wait(50);

            var saveDialog = editor.saveDialog;
            verify(saveDialog !== undefined, "Save dialog should exist");

            // Set properties like the delegate would
            saveDialog.activeNode = "/mock_node";
            saveDialog.activePath = "/mock_node/mock_group";
            saveDialog.selectedFile = "file://test_dialog.json";

            // Force onAccepted logic by calling the signal handler.
            // Since FileDialog is mocked or native, we can invoke it manually.
            saveDialog.accepted();

            var jsonPath = "test_dialog.json";
            verify(RQml.fileExists(jsonPath), "JSON file should be created via dialog flow");

            var savedJsonStr = RQml.readFile(jsonPath);
            verify(savedJsonStr.indexOf("mock_param_1") !== -1, "JSON should contain mock_param_1 when using Dialog");

            // Clean up files manually if needed
        }

        function test_7_save_dialog_flow_node() {
            wait(50);

            var saveDialog = editor.saveDialog;
            verify(saveDialog !== undefined, "Save dialog should exist");

            // Set properties like the delegate would for a NODE click
            saveDialog.activeNode = "/mock_node";
            saveDialog.activePath = "";
            saveDialog.selectedFile = "file://test_dialog_node.json";

            saveDialog.accepted();

            var jsonPath = "test_dialog_node.json";
            verify(RQml.fileExists(jsonPath), "JSON file should be created via dialog flow for node");

            var savedJsonStr = RQml.readFile(jsonPath);
            verify(savedJsonStr.indexOf("mock_group") !== -1, "JSON should contain mock_group when saving entire node");
            verify(savedJsonStr.indexOf("mock_param_1") !== -1, "JSON should contain mock_param_1 when saving entire node");
        }

        function test_8_starring_groups_and_members() {
            wait(50);
            context.showStarredOnly = false;
            editor.d.rebuildModel();
            wait(50);

            // Star group and member
            var qa = [];
            qa.push("/mock_node/mock_group");
            qa.push("/mock_node/mock_group.mock_param_1");
            context.quickAccess = qa;

            context.showStarredOnly = true;
            editor.d.rebuildModel();
            wait(50);

            var elements = editor.d.treeElements;
            var foundGroup = false;
            var foundParam1 = false;
            var foundParam2 = false;

            for (var i = 0; i < elements.length; i++) {
                var el = elements[i];
                if (el.rowType === "group" && el.fullPath === "/mock_node/mock_group") {
                    foundGroup = true;
                    verify(el.starred, "Group should be starred");
                }
                if (el.rowType === "param" && el.paramName === "mock_group.mock_param_1") {
                    foundParam1 = true;
                    verify(el.starred, "Param1 should be starred");
                }
                if (el.rowType === "param" && el.paramName === "mock_group.mock_param_2") {
                    foundParam2 = true;
                    verify(!el.starred, "Param2 should NOT be starred");
                }
            }

            verify(foundGroup, "Group should be visible when starred");
            verify(foundParam1, "Param 1 should be visible when starred");
            verify(foundParam2, "Param 2 should be visible because its group is starred");

            // Cleanup
            context.quickAccess = [];
            context.showStarredOnly = false;
            editor.d.rebuildModel();
            wait(50);
        }
        function test_9_reload_node() {
            var initialCount = editor.d.treeElements.length;

            var view = findListView(editor);
            var nodeDelegate = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.rowType === "node" && del.modelData.nodeName === "/mock_node") {
                    nodeDelegate = del;
                    break;
                }
            }

            verify(nodeDelegate !== null, "Could not find node delegate for /mock_node");

            var reloadBtn = findObjectByName(nodeDelegate, "reloadButton_/mock_node");
            verify(reloadBtn !== null, "Reload button should exist on the node delegate");

            Ros2.addMockParameter({
                name: "mock_group.mock_param_new",
                type: 4,
                string_value: "I am new",
                description: "Newly added param",
                read_only: false,
                floating_point_range: [],
                integer_range: []
            });

            mouseClick(reloadBtn);

            wait(200);

            var newCount = editor.d.treeElements.length;
            compare(newCount, initialCount + 1, "The tree elements count should have increased by 1");

            var foundNewParam = false;
            for (var j = 0; j < editor.d.treeElements.length; j++) {
                if (editor.d.treeElements[j].paramName === "mock_group.mock_param_new") {
                    foundNewParam = true;
                    break;
                }
            }
            verify(foundNewParam, "The newly added parameter should be found in the updated tree");
        }
    }
}
