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
                if (el.rowType === "group" && el.displayName === "mock_group (2)") {
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
    }
}
