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

        // Clean up temp files created by save/load tests.
        // RQml doesn't expose removeFile, so overwrite with empty content.
        function cleanupTestCase() {
            var tempFiles = [
                "/tmp/test_params.json",
                "/tmp/test_params.yaml",
                "test_dialog.json",
                "test_dialog_node.json"
            ];
            for (var i = 0; i < tempFiles.length; i++) {
                if (RQml.fileExists(tempFiles[i])) {
                    RQml.writeFile(tempFiles[i], "");
                }
            }
        }

        function test_01_nodes_discovered() {
            verify(editor !== null)
            wait(50)
            var view = findObjectByName(editor, "mainTreeView")
            verify(view !== null, "ListView should exist")

            var elements = view.model
            verify(elements.length > 0, "Tree elements should not be empty")
            compare(elements[0].rowType, "node")
            compare(elements[0].nodeName, "/mock_node")
        }

        function test_02_node_expand_via_toggle() {
            // Verifies that expandCollapseToggle correctly accesses acquiredNodes
            // via the internal stateContext rather than the outer plugin context.
            wait(50);
            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");
            verify(view.contentItem !== null, "ListView contentItem should exist");

            var nodeDelegate = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.rowType === "node") {
                    nodeDelegate = del;
                    break;
                }
            }
            verify(nodeDelegate !== null, "Node delegate should be found");

            var prevCount = view.count;
            nodeDelegate.expandCollapseToggle();
            wait(50);

            verify(view.count > prevCount, "Node should be expanded and show children after toggle");
            var elements = view.model;
            verify(elements[0].expanded === true, "Node should be marked as expanded");
        }

        function test_03_node_expansion() {
            var view = findObjectByName(editor, "mainTreeView");
            var groupDelegate = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.rowType === "group" && del.modelData.fullPath === "/mock_node/mock_group") {
                    groupDelegate = del;
                    break;
                }
            }
            verify(groupDelegate !== null, "Group delegate should be found");

            var prevCount = view.count;
            groupDelegate.expandCollapseToggle();
            wait(50);

            verify(view.count > prevCount, "Group should be expanded and show children");

            var elements = view.model;
            verify(elements.length > 0)

            // Verify path compression created a single "mock_group" node for all params under that prefix
            var foundGroup = false
            var foundParam1 = false
            var foundParam2 = false

            wait(50);

            for (var i = 0; i < elements.length; i++) {
                var el = elements[i]
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

        function test_04_min_max_labels() {
            wait(50);
            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");

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

        function test_05_set_parameter() {
            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "new value", 4, function() {})

            var view = findObjectByName(editor, "mainTreeView");
            var stringEditor = null;

            tryVerify(function() {
                if (!view || !view.contentItem) return false;
                for (var i = 0; i < view.contentItem.children.length; i++) {
                    var del = view.contentItem.children[i];
                    if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                        stringEditor = findObjectByName(del, "stringEditor_mock_group.mock_param_1");
                        if (stringEditor && stringEditor.text === "new value") {
                            return true;
                        }
                    }
                }
                return false;
            }, 1000, "Param value should have been updated in the UI");

            verify(stringEditor !== null, "Param 1 string editor should be found");
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

        function test_06_set_parameter_failure_resets_value() {
            wait(50);

            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");

            // Find the string editor for mock_param_1
            var stringEditor = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                    stringEditor = findObjectByName(del, "stringEditor_mock_group.mock_param_1");
                    break;
                }
            }
            verify(stringEditor !== null, "String editor should be found");

            var goodValue = stringEditor.text;

            Ros2.nextSetParameterResult = { successful: false, reason: "value rejected by node" };

            stringEditor.text = "invalid value";
            stringEditor.editingFinished();
            wait(100);

            compare(stringEditor.text, goodValue,
                "Editor must revert to last known good value after a failed setParameter");

            // Verify the service still holds the original value
            var data = Interfaces.ParameterService.getNodeData("/mock_node");
            compare(data.parameters["mock_group.mock_param_1"].value, goodValue,
                "Service value must remain unchanged after failed set");
        }

        function test_07_external_parameter_update() {
            wait(50);

            var view = findObjectByName(editor, "mainTreeView");

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

            // rcl_interfaces C++ QList types don't support index operator from QML; use .at(i) instead.
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

            wait(50);

            compare(stringEditorItem.text, "external update",
                "Delegate text should update reactively from external ParameterChanged event without a full model rebuild")
        }

        function test_08_save_and_load_parameters() {
            var jsonPath = "/tmp/test_params.json";
            var yamlPath = "/tmp/test_params.yaml";

            // Instead of dealing with the native file dialog behavior in tests,
            // invoke the tested internal functions to verify logic rather than testing the QML FileDialog itself.
            editor.d.saveGroupParams("/mock_node", "/mock_node/mock_group", jsonPath);

            tryVerify(function() { return RQml.fileExists(jsonPath); }, 1000, "JSON file should be created");

            var savedJsonStr = RQml.readFile(jsonPath);
            verify(savedJsonStr.indexOf("mock_param_1") !== -1, "JSON should contain mock_param_1");

            var data = Interfaces.ParameterService.getNodeData("/mock_node");
            var originalValue = data.parameters["mock_group.mock_param_1"].value;

            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "I AM CHANGED", 4, function() {});

            tryVerify(function() {
                var d = Interfaces.ParameterService.getNodeData("/mock_node");
                return d.parameters["mock_group.mock_param_1"].value === "I AM CHANGED";
            }, 1000, "Parameter should be modified");

            editor.d.loadGroupParams("/mock_node", "/mock_node/mock_group", jsonPath);

            tryVerify(function() {
                var d = Interfaces.ParameterService.getNodeData("/mock_node");
                return d.parameters["mock_group.mock_param_1"].value === originalValue;
            }, 1000, "Parameter should be restored from JSON");

            editor.d.saveGroupParams("/mock_node", "/mock_node/mock_group", yamlPath);

            tryVerify(function() {
                var content = Ros2.io.readYaml(yamlPath);
                return content && content["mock_param_1"] !== undefined;
            }, 1000, "YAML file should be created");

            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "YAML CHANGE", 4, function() {});

            tryVerify(function() {
                var d = Interfaces.ParameterService.getNodeData("/mock_node");
                return d.parameters["mock_group.mock_param_1"].value === "YAML CHANGE";
            }, 1000, "Parameter should be modified again");

            editor.d.loadGroupParams("/mock_node", "/mock_node/mock_group", yamlPath);

            tryVerify(function() {
                var d = Interfaces.ParameterService.getNodeData("/mock_node");
                return d.parameters["mock_group.mock_param_1"].value === originalValue;
            }, 1000, "Parameter should be restored from YAML");
        }

        function test_09_save_dialog_flow() {
            wait(50);

            var saveDialog = editor.saveDialog;
            verify(saveDialog !== undefined, "Save dialog should exist");

            saveDialog.activeNode = "/mock_node";
            saveDialog.activePath = "/mock_node/mock_group";
            saveDialog.selectedFile = "file://test_dialog.json";
            saveDialog.accepted();

            var jsonPath = "test_dialog.json";
            verify(RQml.fileExists(jsonPath), "JSON file should be created via dialog flow");

            var savedJsonStr = RQml.readFile(jsonPath);
            verify(savedJsonStr.indexOf("mock_param_1") !== -1, "JSON should contain mock_param_1 when using Dialog");
        }

        function test_10_save_dialog_flow_node() {
            wait(50);

            var saveDialog = editor.saveDialog;
            verify(saveDialog !== undefined, "Save dialog should exist");

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

        function test_11_starring_groups_and_members() {
            var starBtn = findObjectByName(editor, "starToggleButton");
            verify(starBtn !== null, "Star button should be found");

            if (starBtn.checked) {
                mouseClick(starBtn);
                wait(50);
            }

            var qa = [];
            qa.push("/mock_node/mock_group");
            qa.push("/mock_node/mock_group.mock_param_1");
            context.quickAccess = qa;

            mouseClick(starBtn);

            var view = findObjectByName(editor, "mainTreeView");
            var foundGroup = false;
            var foundParam1 = false;
            var foundParam2 = false;

            tryVerify(function() {
                var elements = view.model;
                if (!elements) return false;

                var g = false;
                var p1 = false;
                var p2 = false;

                for (var i = 0; i < elements.length; i++) {
                    var el = elements[i];
                    if (el.rowType === "group" && el.fullPath === "/mock_node/mock_group") {
                        if (el.starred) g = true;
                    }
                    if (el.rowType === "param" && el.paramName === "mock_group.mock_param_1") {
                        if (el.starred) p1 = true;
                    }
                    if (el.rowType === "param" && el.paramName === "mock_group.mock_param_2") {
                        if (!el.starred) p2 = true;
                    }
                }

                foundGroup = g;
                foundParam1 = p1;
                foundParam2 = p2;

                return g && p1 && p2;
            }, 1000, "Models should update starring correctly");

            verify(foundGroup, "Group should be visible when starred");
            verify(foundParam1, "Param 1 should be visible when starred");
            verify(foundParam2, "Param 2 should be visible because its group is starred");

            context.quickAccess = [];
            mouseClick(starBtn);
            wait(50);
        }
        function test_12_scroll_preserves_updated_values() {
            // Add enough parameters to force ListView scrolling/delegate recycling.
            for (var i = 1; i <= 20; i++) {
                Ros2.addMockParameter({
                    name: "zz_scroll_param_" + i,
                    type: 4,
                    string_value: "original_" + i,
                    description: "Scroll test param " + i,
                    read_only: false,
                    floating_point_range: [],
                    integer_range: []
                });
            }

            // Reload the node to pick up the new parameters
            Interfaces.ParameterService.refresh("/mock_node");
            wait(300);

            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");
            verify(view.contentHeight > view.height, "Content should be scrollable");

            // Change mock_param_1's value (it's near the top, currently visible)
            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "scroll_test_value", 4, function() {});
            wait(100);

            var stringEditor = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                    stringEditor = findObjectByName(del, "stringEditor_mock_group.mock_param_1");
                    break;
                }
            }
            verify(stringEditor !== null, "String editor should be found before scrolling");
            compare(stringEditor.text, "scroll_test_value", "Value should be updated before scroll");

            // Scroll to the bottom to destroy top delegates
            view.contentY = view.contentHeight - view.height;
            wait(200);

            var topDelegateStillExists = false;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var d = view.contentItem.children[i];
                if (d && d.modelData && d.modelData.paramName === "mock_group.mock_param_1") {
                    topDelegateStillExists = true;
                    break;
                }
            }
            // If delegate is still alive, scrolling didn't recycle — skip the rest
            // (this can happen if cacheBuffer is large)
            if (topDelegateStillExists) {
                skip("Delegate was not recycled (cacheBuffer too large) — scroll-back check is inconclusive");
                view.contentY = 0;
                wait(100);
                return;
            }

            // Scroll back to the top — delegate is recreated from model data
            view.contentY = 0;
            wait(200);

            var recreatedEditor = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                    recreatedEditor = findObjectByName(del, "stringEditor_mock_group.mock_param_1");
                    break;
                }
            }
            verify(recreatedEditor !== null, "String editor should be found after scrolling back");
            compare(recreatedEditor.text, "scroll_test_value",
                "Recreated delegate must show updated value after scroll recycling, not stale original");
        }

        function test_13_reload_node() {
            // Ensure we're scrolled to the top (test_12 may have left scroll at bottom)
            var view = findObjectByName(editor, "mainTreeView");
            view.contentY = 0;
            wait(100);

            var initialCount = view.count;

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

            var newCount = view.count;
            compare(newCount, initialCount + 1, "The tree elements count should have increased by 1");

            var foundNewParam = false;
            var elements = view.model;
            for (var j = 0; j < elements.length; j++) {
                if (elements[j].paramName === "mock_group.mock_param_new") {
                    foundNewParam = true;
                    break;
                }
            }
            verify(foundNewParam, "The newly added parameter should be found in the updated tree");
        }

        function test_14_busy_indicator_visibility() {
            wait(50);
            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");

            var rowDelegate = null;
            var busyInd = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                    rowDelegate = del;
                    busyInd = findObjectByName(del, "busyIndicator_mock_group.mock_param_1");
                    break;
                }
            }
            verify(rowDelegate !== null, "Row delegate for mock_param_1 should be found");
            verify(busyInd !== null, "BusyIndicator should be found");

            // Check initial state
            compare(rowDelegate.isSetting, false, "isSetting should be false initially");
            verify(!busyInd.visible, "BusyIndicator should not be visible initially");

            Interfaces.ParameterService.setParameter("/mock_node", "mock_group.mock_param_1", "busy test", 4, function() {});

            // Immediately after calling (before the async response), it should be true
            compare(rowDelegate.isSetting, true, "isSetting should be true immediately after setParameter");
            verify(busyInd.visible, "BusyIndicator should be visible immediately after setParameter");

            // Wait for it to finish
            wait(100);
            compare(rowDelegate.isSetting, false, "isSetting should be false after setParameter finishes");
            verify(!busyInd.visible, "BusyIndicator should not be visible after setParameter finishes");
        }

        function test_15_numerical_editor_failure_resets_text() {
            wait(50);
            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");

            // 1. Test IntegerInputField (mock_param_3)
            var intField = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_3") {
                    intField = findObjectByName(del, "intField_mock_group.mock_param_3");
                    break;
                }
            }
            verify(intField !== null, "intField should be found");
            var originalIntText = intField.text;

            Ros2.nextSetParameterResult = { successful: false, reason: "int rejected" };
            intField.text = "999";
            intField.editingFinished();
            wait(100);
            compare(intField.text, originalIntText, "Integer text should reset on failure");

            // 2. Test DecimalInputField (mock_param_5)
            var doubleField = null;
            for (var j = 0; j < view.contentItem.children.length; j++) {
                var del2 = view.contentItem.children[j];
                if (del2 && del2.modelData && del2.modelData.paramName === "mock_group.mock_param_5") {
                    doubleField = findObjectByName(del2, "doubleField_mock_group.mock_param_5");
                    break;
                }
            }
            verify(doubleField !== null, "doubleField should be found");
            var originalDoubleText = doubleField.text;

            Ros2.nextSetParameterResult = { successful: false, reason: "double rejected" };
            doubleField.text = "9.99";
            doubleField.editingFinished();
            wait(100);
            compare(doubleField.text, originalDoubleText, "Double text should reset on failure");
        }
        function test_16_avoid_redundant_set_parameter() {
            wait(50);
            var view = findObjectByName(editor, "mainTreeView");
            verify(view !== null, "ListView should exist");

            // 1. Test String Editor
            var stringEditor = null;
            for (var i = 0; i < view.contentItem.children.length; i++) {
                var del = view.contentItem.children[i];
                if (del && del.modelData && del.modelData.paramName === "mock_group.mock_param_1") {
                    stringEditor = findObjectByName(del, "stringEditor_mock_group.mock_param_1");
                    break;
                }
            }
            verify(stringEditor !== null, "String editor should be found");

            Ros2.nextSetParameterResult = { successful: true };
            stringEditor.editingFinished();
            wait(50);
            verify(Ros2.nextSetParameterResult !== null, "setParameter should NOT have been called for string if value unchanged");

            // 2. Test Integer Input Field
            var intField = null;
            for (var j = 0; j < view.contentItem.children.length; j++) {
                var delInt = view.contentItem.children[j];
                if (delInt && delInt.modelData && delInt.modelData.paramName === "mock_group.mock_param_3") {
                    intField = findObjectByName(delInt, "intField_mock_group.mock_param_3");
                    break;
                }
            }
            verify(intField !== null, "intField should be found");

            Ros2.nextSetParameterResult = { successful: true };
            intField.editingFinished();
            wait(50);
            verify(Ros2.nextSetParameterResult !== null, "setParameter should NOT have been called for int if value unchanged");

            // 3. Test Decimal Input Field
            var doubleField = null;
            for (var k = 0; k < view.contentItem.children.length; k++) {
                var delDouble = view.contentItem.children[k];
                if (delDouble && delDouble.modelData && delDouble.modelData.paramName === "mock_group.mock_param_5") {
                    doubleField = findObjectByName(delDouble, "doubleField_mock_group.mock_param_5");
                    break;
                }
            }
            verify(doubleField !== null, "doubleField should be found");

            Ros2.nextSetParameterResult = { successful: true };
            doubleField.editingFinished();
            wait(50);
            verify(Ros2.nextSetParameterResult !== null, "setParameter should NOT have been called for double if value unchanged");
        }
    }
}
