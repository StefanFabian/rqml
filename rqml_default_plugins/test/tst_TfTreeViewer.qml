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

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 768
    width: 1024

    QtObject {
        id: contextObj

        property bool enabled: true
        property var graphTransformOpen: undefined
        property var listTransformOpen: undefined
        property string namespace: ""
        property string viewMode: "list"  // Use list view by default so delegates are realized
    }
    Utils {
        id: helpers

    }
    Loader {
        id: pluginLoader

        function reload() {
            source = "";
            source = "../qml/TfTreeViewer.qml";
        }

        anchors.fill: parent
    }
    Publisher {
        id: tfPublisher

        topic: "/tf"
        type: "tf2_msgs/msg/TFMessage"
    }
    Publisher {
        id: tfStaticPublisher

        topic: "/tf_static"
        type: "tf2_msgs/msg/TFMessage"
    }
    TestCase {

        // -----------------------------------------------------------------
        // Setup / Teardown
        // -----------------------------------------------------------------
        function init() {
            Ros2.reset();
            RQml.resetClipboard();
            // Register both /tf and /tf_static so subscriptions can find them
            Ros2.registerTopic("/tf", "tf2_msgs/msg/TFMessage");
            Ros2.registerTopic("/tf_static", "tf2_msgs/msg/TFMessage");
            contextObj.enabled = true;
            contextObj.namespace = "";
            contextObj.viewMode = "list";
            contextObj.graphTransformOpen = undefined;
            contextObj.listTransformOpen = undefined;
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000, "Loader should be ready");
            wait(50);
        }

        // -----------------------------------------------------------------
        // Helpers
        // -----------------------------------------------------------------
        function makeTransform(parentFrame, childFrame, tx, ty, tz) {
            var t = Ros2.createEmptyMessage("geometry_msgs/msg/TransformStamped");
            t.header.frame_id = parentFrame;
            t.header.stamp = Ros2.now();
            t.child_frame_id = childFrame;
            t.transform.translation.x = tx;
            t.transform.translation.y = ty;
            t.transform.translation.z = tz;
            t.transform.rotation.x = 0.0;
            t.transform.rotation.y = 0.0;
            t.transform.rotation.z = 0.0;
            t.transform.rotation.w = 1.0;
            return t;
        }
        function modelHasFrame(listView, frameId) {
            for (var i = 0; i < listView.model.count; ++i) {
                if (listView.model.get(i).frameId === frameId)
                    return true;
            }
            return false;
        }
        function publishTf(transformsList) {
            var msg = Ros2.createEmptyMessage("tf2_msgs/msg/TFMessage");
            msg.transforms = transformsList;
            return tfPublisher.publish(msg);
        }
        function publishTfStatic(transformsList) {
            var msg = Ros2.createEmptyMessage("tf2_msgs/msg/TFMessage");
            msg.transforms = transformsList;
            return tfStaticPublisher.publish(msg);
        }
        function seedGraphTree() {
            publishTfStatic([makeTransform("world", "base_link", 1.0, 2.0, 3.0)]);
            publishTf([makeTransform("base_link", "sensor", 0.1, 0.2, 0.3)]);
            wait(350);
        }
        function test_clear_button() {
            var listView = find("tfFrameListView");
            publishTf([makeTransform("world", "base_link", 0, 0, 0)]);
            publishTf([makeTransform("base_link", "lidar", 0, 0, 0)]);
            tryCompare(listView.model, "count", 3, 2000);
            var clearButton = find("tfClearButton");
            verify(clearButton !== null, "Clear button should exist");
            mouseClick(clearButton);
            tryCompare(listView.model, "count", 0, 2000, "Model should be empty after clear");
            var countLabel = find("tfFrameCountLabel");
            verify(countLabel.text.indexOf("Frames: 0") !== -1, "Frame count label should reset to 0");
            var emptyLabel = find("tfEmptyStateLabel");
            verify(emptyLabel.visible, "Empty state should be visible again");
            publishTf([makeTransform("world", "base_link", 0, 0, 0)]);
            publishTf([makeTransform("base_link", "lidar", 0, 0, 0)]);
            tryCompare(listView.model, "count", 3, 2000, "After publishing again, they should reappear.");
        }
        function test_collapse_expand() {
            var listView = find("tfFrameListView");

            // Build chain: world -> base_link -> sensor
            publishTf([makeTransform("world", "base_link", 0, 0, 0), makeTransform("base_link", "sensor", 0, 0, 1.0)]);
            tryCompare(listView.model, "count", 3, 2000, "Should display 3 frames");

            // Force delegate realization for base_link
            listView.positionViewAtIndex(0, ListView.Beginning);

            // Find base_link's index in the model
            var baseLinkIndex = -1;
            for (var i = 0; i < listView.model.count; ++i) {
                if (listView.model.get(i).frameId === "base_link") {
                    baseLinkIndex = i;
                    break;
                }
            }
            verify(baseLinkIndex !== -1, "base_link should be in model");
            var item = listView.model.get(baseLinkIndex);
            compare(item.hasChildren, true, "base_link should have children");
            compare(item.isCollapsed, false, "base_link should not be collapsed initially");

            // Realize the delegate and find its branch indicator MouseArea
            var delegate = null;
            tryVerify(function () {
                delegate = listView.itemAtIndex(baseLinkIndex);
                return delegate !== null;
            }, 2000, "Delegate for base_link should be realized");
            var branchArea = helpers.findChild(delegate, "tfBranchIndicatorArea");
            verify(branchArea !== null, "Branch indicator MouseArea should exist");
            mouseClick(branchArea);
            tryCompare(listView.model, "count", 2, 2000, "Sensor should be hidden after collapsing base_link");
            verify(!modelHasFrame(listView, "sensor"), "sensor should not appear when base_link is collapsed");
            verify(listView.model.get(baseLinkIndex).isCollapsed, "base_link should be marked as collapsed");

            // Expand again - ListView recycles delegates across rebuild,
            // so re-fetch the delegate and branch area fresh.
            wait(50);
            listView.positionViewAtIndex(baseLinkIndex, ListView.Beginning);
            var delegate2 = null;
            var branchArea2 = null;
            tryVerify(function () {
                delegate2 = listView.itemAtIndex(baseLinkIndex);
                if (delegate2 === null)
                    return false;
                branchArea2 = helpers.findChild(delegate2, "tfBranchIndicatorArea");
                return branchArea2 !== null;
            }, 2000, "Branch indicator should be realized again after collapse");
            mouseClick(branchArea2);
            tryCompare(listView.model, "count", 3, 2000, "Sensor should re-appear after expanding base_link");
            verify(modelHasFrame(listView, "sensor"), "sensor should be back in model");
        }
        function test_context_menu_copy() {
            var listView = find("tfFrameListView");
            publishTf([makeTransform("world", "base_link", 1.5, 2.5, 3.5)]);
            tryCompare(listView.model, "count", 2, 2000);

            // Find base_link index
            var baseLinkIndex = -1;
            for (var i = 0; i < listView.model.count; ++i) {
                if (listView.model.get(i).frameId === "base_link") {
                    baseLinkIndex = i;
                    break;
                }
            }
            verify(baseLinkIndex !== -1);
            listView.positionViewAtIndex(baseLinkIndex, ListView.Beginning);
            var delegate = null;
            tryVerify(function () {
                delegate = listView.itemAtIndex(baseLinkIndex);
                return delegate !== null;
            }, 2000, "Delegate for base_link should be realized");

            // Copy Frame ID
            RQml.resetClipboard();
            var copyFrameAction = helpers.findChild(delegate, "tfCopyFrameIdAction");
            verify(copyFrameAction, "Copy Frame ID action should be found");
            copyFrameAction.triggered();
            tryCompare(RQml, "clipboard", "base_link", 1000, "Clipboard should contain frame ID");

            // Copy Parent ID
            RQml.resetClipboard();
            var copyParentAction = helpers.findChild(delegate, "tfCopyParentIdAction");
            verify(copyParentAction, "Copy Parent ID action should be found");
            copyParentAction.triggered();
            tryCompare(RQml, "clipboard", "world", 1000, "Clipboard should contain parent ID");

            // Copy Transform - verify the action exists and writes something
            // containing translation and rotation info (exact format is internal).
            RQml.resetClipboard();
            var copyTransformAction = helpers.findChild(delegate, "tfCopyTransformAction");
            verify(copyTransformAction, "Copy Transform action should be found");
            copyTransformAction.triggered();
            tryVerify(function () {
                return RQml.clipboard.length > 0 && RQml.clipboard.indexOf("translation") !== -1 && RQml.clipboard.indexOf("rotation") !== -1;
            }, 1000, "Clipboard should contain translation and rotation");
        }
        function test_empty_state_message() {
            var emptyLabel = find("tfEmptyStateLabel");
            verify(emptyLabel !== null, "Empty state label should exist");
            verify(emptyLabel.visible, "Empty state should be visible with no data");
            verify(emptyLabel.text.indexOf("Waiting for TF data") !== -1, "Empty state should mention waiting for data");
        }
        function test_enable_disable() {
            var listView = find("tfFrameListView");
            var enableToggle = find("tfEnableToggle");
            verify(enableToggle !== null, "Enable toggle should exist");
            verify(enableToggle.checked, "Should be enabled initially");
            publishTf([makeTransform("world", "base_link", 0, 0, 0)]);
            tryCompare(listView.model, "count", 2, 2000);

            // Disable
            mouseClick(enableToggle);
            tryCompare(enableToggle, "checked", false, 1000, "Toggle should be off");
            compare(contextObj.enabled, false, "Context enabled should update");

            // Publish more frames - model should not update while polling is disabled
            publishTf([makeTransform("base_link", "ignored_child", 0, 0, 0)]);
            wait(400);
            compare(listView.model.count, 2, "No new frames shown when disabled");

            // Re-enable - buffer still received data, so ignored_child will appear
            mouseClick(enableToggle);
            tryCompare(enableToggle, "checked", true, 1000, "Toggle should be on");
            compare(contextObj.enabled, true, "Context enabled should update");
            publishTf([makeTransform("base_link", "new_child", 0, 0, 0)]);
            tryCompare(listView.model, "count", 4, 2000, "All frames visible after re-enabling");
        }
        function test_frame_count_label_shows_root_count() {
            var label = find("tfFrameCountLabel");
            verify(label !== null, "Frame count label should be found");
            publishTfStatic([makeTransform("world", "base_link", 0, 0, 0)]);
            publishTf([makeTransform("base_link", "sensor", 0, 0, 0)]);
            tryVerify(function () {
                return label.text.indexOf("Frames: 3") !== -1 && label.text.indexOf("Root frames: 1") !== -1;
            }, 2000, "Label should include both total and root frame counts");
        }
        function test_frame_display() {
            var listView = find("tfFrameListView");
            verify(listView !== null, "Frame list view should exist");
            publishTf([makeTransform("world", "base_link", 1.0, 2.0, 3.0)]);

            // Should add 2 frames: world (auto-created parent) and base_link
            tryCompare(listView.model, "count", 2, 2000, "List should contain world and base_link");
            verify(modelHasFrame(listView, "world"), "Model should contain 'world' frame");
            verify(modelHasFrame(listView, "base_link"), "Model should contain 'base_link' frame");
            var countLabel = find("tfFrameCountLabel");
            verify(countLabel !== null, "Frame count label should exist");
            verify(countLabel.text.indexOf("Frames: 2") !== -1, "Frame count label should show 2");
        }
        function test_graph_click_root_frame() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.fitToView();
            wait(50);
            var wCenter = gv._testNodeCenter("world");
            verify(wCenter !== null, "world node should be laid out");

            // Click world (root frame, no parent) -> source = world, target = ""
            mouseClick(gv, wCenter.x, wCenter.y, Qt.LeftButton);
            tryCompare(gv, "sourceFrame", "world", 1000, "Clicking root frame should set source to world");
            tryCompare(gv, "targetFrame", "", 1000, "Clicking root frame should set target to empty (no parent)");
        }
        function test_graph_click_sets_parent_and_target() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.fitToView();
            wait(50);
            var blCenter = gv._testNodeCenter("base_link");
            verify(blCenter !== null, "base_link node should be laid out");

            // Click base_link -> source = base_link, target = world (parent)
            mouseClick(gv, blCenter.x, blCenter.y, Qt.LeftButton);
            tryCompare(gv, "sourceFrame", "base_link", 1000, "Clicking base_link should set source to base_link");
            tryCompare(gv, "targetFrame", "world", 1000, "Clicking base_link should set target to its parent (world)");
            var panel = find("tfTransformPanel");
            verify(panel !== null, "Transform panel should be found");
            verify(panel.visible, "Transform panel should be visible");
        }
        function test_graph_ctrl_click_no_source_falls_back() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.fitToView();
            wait(50);

            // Ensure no selection
            plugin.sourceFrame = "";
            plugin.targetFrame = "";
            var blCenter = gv._testNodeCenter("base_link");
            verify(blCenter !== null);

            // Ctrl+click with no target -> falls back to normal click
            mouseClick(gv, blCenter.x, blCenter.y, Qt.LeftButton, Qt.ControlModifier);
            tryCompare(gv, "sourceFrame", "base_link", 1000, "Ctrl+click with no target should fall back to normal click (source = clicked frame)");
            tryCompare(gv, "targetFrame", "world", 1000, "Ctrl+click with no target should fall back to normal click (target = parent)");
        }
        function test_graph_ctrl_click_sets_target() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.fitToView();
            wait(50);
            var blCenter = gv._testNodeCenter("base_link");
            var sCenter = gv._testNodeCenter("sensor");
            verify(blCenter !== null, "base_link should be laid out");
            verify(sCenter !== null, "sensor should be laid out");

            // Normal click on base_link -> source = base_link, target = world (parent)
            mouseClick(gv, blCenter.x, blCenter.y, Qt.LeftButton);
            tryCompare(gv, "sourceFrame", "base_link", 1000);
            tryCompare(gv, "targetFrame", "world", 1000);

            // Ctrl+click on sensor -> source stays base_link, target = sensor
            mouseClick(gv, sCenter.x, sCenter.y, Qt.LeftButton, Qt.ControlModifier);
            tryCompare(gv, "sourceFrame", "base_link", 1000, "Ctrl+click should keep source unchanged");
            tryCompare(gv, "targetFrame", "sensor", 1000, "Ctrl+click should set target to sensor");
        }
        function test_graph_node_hover_shows_authority() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.fitToView();
            wait(200); // Wait for layout to settle
            var wCenter = gv._testNodeCenter("world");
            verify(wCenter !== null);
            var tooltip = find("tooltip");
            verify(tooltip !== null, "Tooltip should exist");

            // Move mouse away first and then to the node to ensure a position change event
            mouseMove(gv, 0, 0);
            wait(50);
            mouseMove(gv, wCenter.x, wCenter.y);
            wait(100);
            tryVerify(function () {
                return tooltip.visible;
            }, 3000, "Tooltip should become visible on hover");

            // Check if authority info is present in the tooltip
            tryVerify(function () {
                var content = tooltip.contentItem;
                if (!content)
                    return false;
                for (var i = 0; i < content.data.length; ++i) {
                    var item = content.data[i];
                    if (item && item.text && item.text.indexOf("Authority: world_authority") !== -1) {
                        return true;
                    }
                }
                return false;
            }, 3000, "Tooltip should show authority information");
        }
        function test_graph_search_overlay_clamps_width_in_narrow_layout() {
            var gv = useGraphMode();
            seedGraphTree();
            root.width = 400;
            wait(50);
            var toggle = find("tfGraphSearchToggle");
            verify(toggle !== null, "Graph search toggle should exist");
            mouseClick(toggle);
            var searchBar = find("tfGraphSearchBar");
            verify(searchBar !== null, "Expanded graph search bar should exist");
            tryVerify(function () {
                return searchBar.visible && searchBar.width > 0;
            }, 1000, "Graph search bar should remain usable in a narrow dock");
        }
        function test_list_click_sets_parent_and_target() {
            var listView = find("tfFrameListView");
            var transformDisplay = find("tfListTransformDisplay");
            verify(transformDisplay !== null, "List transform display should exist");
            seedGraphTree(); // world -> base_link -> sensor
            plugin.sourceFrame = "";
            plugin.targetFrame = "";

            // Find base_link index
            var blIdx = -1;
            for (var i = 0; i < listView.model.count; ++i) {
                if (listView.model.get(i).frameId === "base_link")
                    blIdx = i;
            }
            verify(blIdx !== -1);
            listView.positionViewAtIndex(blIdx, ListView.Beginning);
            var blItem = null;
            tryVerify(function () {
                blItem = listView.itemAtIndex(blIdx);
                return blItem !== null;
            }, 2000, "Delegate for base_link should be realized");

            // Click base_link -> source = base_link, target = world (parent)
            mouseClick(blItem);
            tryCompare(transformDisplay, "sourceFrame", "base_link", 1000, "Source should be base_link (clicked frame)");
            tryCompare(transformDisplay, "targetFrame", "world", 1000, "Target should be world (parent of base_link)");
        }
        function test_list_selection_syncs_with_graph() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.fitToView();

            // Switch to list mode
            var listButton = find("tfListModeButton");
            mouseClick(listButton);
            var listView = find("tfFrameListView");
            tryCompare(listView, "visible", true, 1000);

            // Find base_link in list
            var blIdx = -1;
            for (var i = 0; i < listView.model.count; ++i) {
                if (listView.model.get(i).frameId === "base_link")
                    blIdx = i;
            }
            verify(blIdx !== -1);

            // Click base_link in list -> source = base_link, target = world (parent)
            var blItem = null;
            tryVerify(function () {
                listView.positionViewAtIndex(blIdx, ListView.Beginning);
                blItem = listView.itemAtIndex(blIdx);
                return blItem !== null;
            }, 2000);
            mouseClick(blItem);
            tryCompare(plugin, "sourceFrame", "base_link", 1000, "Clicking list item should set sourceFrame to clicked frame");
            tryCompare(plugin, "targetFrame", "world", 1000, "Clicking list item should set targetFrame to parent");
            compare(gv.sourceFrame, "base_link", "Graph view should reflect source selection");
            compare(gv.targetFrame, "world", "Graph view should reflect target selection");

            // Verify source indicator on base_link
            // Re-fetch blItem since delegates may have been recycled
            tryVerify(function () {
                listView.positionViewAtIndex(blIdx, ListView.Beginning);
                blItem = listView.itemAtIndex(blIdx);
                return blItem !== null;
            }, 2000);
            var srcIndicator = helpers.findChild(blItem, "sourceIndicator");
            verify(srcIndicator !== null && srcIndicator.visible, "Source indicator should be visible on base_link");

            // Verify target indicator on world
            var worldIdx = -1;
            for (var i = 0; i < listView.model.count; ++i) {
                if (listView.model.get(i).frameId === "world")
                    worldIdx = i;
            }
            verify(worldIdx !== -1);
            var worldItem = null;
            tryVerify(function () {
                listView.positionViewAtIndex(worldIdx, ListView.Beginning);
                worldItem = listView.itemAtIndex(worldIdx);
                return worldItem !== null;
            }, 2000);
            var tgtIndicator = helpers.findChild(worldItem, "targetIndicator");
            verify(tgtIndicator !== null && tgtIndicator.visible, "Target indicator should be visible on world");
        }
        function test_namespace_discovery() {
            // Register additional TF topics in different namespaces
            Ros2.registerTopic("/robot1/tf", "tf2_msgs/msg/TFMessage");
            Ros2.registerTopic("/robot1/tf_static", "tf2_msgs/msg/TFMessage");
            Ros2.registerTopic("/robot2/tf", "tf2_msgs/msg/TFMessage");
            Ros2.registerTopic("/robot3/tf_static", "tf2_msgs/msg/TFMessage");

            // Reload so the plugin discovers them at construction time
            pluginLoader.reload();
            tryVerify(function () {
                return pluginLoader.status === Loader.Ready;
            }, 2000);
            var nsCombo = find("tfNamespaceComboBox");
            verify(nsCombo !== null, "Namespace ComboBox should exist");
            tryVerify(function () {
                var m = nsCombo.model || [];
                return Array.prototype.indexOf.call(m, "(global)") !== -1 && Array.prototype.indexOf.call(m, "/robot1") !== -1 && Array.prototype.indexOf.call(m, "/robot2") !== -1 && Array.prototype.indexOf.call(m, "/robot3") !== -1;
            }, 2000, "Namespace dropdown should list (global), /robot1, /robot2, /robot3");
        }

        // -----------------------------------------------------------------
        // Tests
        // -----------------------------------------------------------------
        function test_plugin_loads() {
            verify(plugin !== null, "TfTreeViewer plugin should load");
        }
        function test_refresh_button() {
            var nsCombo = find("tfNamespaceComboBox");
            verify(nsCombo !== null);

            // Initially only the global namespace is registered
            tryVerify(function () {
                var m = nsCombo.model || [];
                return Array.prototype.indexOf.call(m, "(global)") !== -1;
            }, 2000, "Global namespace should be present initially");
            var beforeModel = nsCombo.model || [];
            verify(Array.prototype.indexOf.call(beforeModel, "/robot_late") === -1, "/robot_late should not be present before refresh");

            // Register a new TF topic AFTER load
            Ros2.registerTopic("/robot_late/tf", "tf2_msgs/msg/TFMessage");
            var refreshButton = find("tfRefreshButton");
            verify(refreshButton !== null, "Refresh button should exist");
            mouseClick(refreshButton);
            tryVerify(function () {
                var m = nsCombo.model || [];
                return Array.prototype.indexOf.call(m, "/robot_late") !== -1;
            }, 2000, "Refresh should pick up newly-registered namespace");
        }
        function test_static_and_dynamic_frames() {
            var listView = find("tfFrameListView");
            publishTf([makeTransform("world", "base_link", 0, 0, 0)]);
            publishTfStatic([makeTransform("base_link", "lidar", 0.1, 0, 0.5)]);
            tryCompare(listView.model, "count", 3, 2000, "Should have world, base_link, and lidar");

            // Locate base_link and lidar entries to verify isStatic
            var baseLink = null, lidar = null;
            for (var i = 0; i < listView.model.count; ++i) {
                var item = listView.model.get(i);
                if (item.frameId === "base_link")
                    baseLink = item;
                else if (item.frameId === "lidar")
                    lidar = item;
            }
            verify(baseLink !== null, "base_link should be in model");
            verify(lidar !== null, "lidar should be in model");
            compare(baseLink.isStatic, false, "base_link should be dynamic");
            compare(lidar.isStatic, true, "lidar should be static");
        }
        function test_swap_button() {
            var gv = useGraphMode();
            seedGraphTree();
            plugin.sourceFrame = "world";
            plugin.targetFrame = "base_link";
            wait(50);
            var swapBtn = find("tfSwapButton");
            verify(swapBtn !== null, "Swap button should exist");
            verify(swapBtn.enabled, "Swap button should be enabled when both frames are set");
            mouseClick(swapBtn);
            tryCompare(plugin, "sourceFrame", "base_link", 1000, "After swap, source should be base_link");
            tryCompare(plugin, "targetFrame", "world", 1000, "After swap, target should be world");
        }
        function test_transform_panel_toggle_preserves_selection() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.sourceFrame = "world";
            gv.targetFrame = "base_link";
            var panel = find("tfTransformPanel");
            verify(panel !== null, "Transform panel should be found");
            verify(panel.expanded, "Panel should start expanded");
            var headerBtn = find("tfTransformDisplayHeader");
            verify(headerBtn !== null, "Header toggle button should be found");

            // Collapse the panel
            mouseClick(headerBtn);
            tryCompare(panel, "expanded", false, 1000, "Panel should collapse");
            compare(gv.sourceFrame, "world", "Source preserved after collapse");
            compare(gv.targetFrame, "base_link", "Target preserved after collapse");

            // Expand again
            mouseClick(headerBtn);
            tryCompare(panel, "expanded", true, 1000, "Panel should expand again");
        }
        function test_transform_popup_copy_json() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.sourceFrame = "world";
            gv.targetFrame = "base_link";
            var tft = gv._testTfTransform();
            verify(tft !== null, "TfTransform instance should be accessible");
            tft.translation = {
                "x": 1.25,
                "y": -2.5,
                "z": 0.5
            };
            tft.rotation = {
                "x": 0,
                "y": 0,
                "z": 0,
                "w": 1
            };
            tft.valid = true;
            wait(250);
            var copyBtn = find("tfTransformPopupCopyJson");
            verify(copyBtn !== null, "Copy JSON button should be found");
            RQml.resetClipboard();
            mouseClick(copyBtn);
            tryVerify(function () {
                return RQml.clipboard.length > 0;
            }, 1000, "Clipboard should receive JSON");
            var parsed = JSON.parse(RQml.clipboard);
            compare(parsed.source_frame, "world");
            compare(parsed.target_frame, "base_link");
            compare(parsed.translation.x, 1.25);
            compare(parsed.translation.y, -2.5);
            compare(parsed.translation.z, 0.5);
            compare(parsed.rotation.x, 0);
            compare(parsed.rotation.y, 0);
            compare(parsed.rotation.z, 0);
            compare(parsed.rotation.w, 1);
        }
        function test_transform_popup_copy_yaml() {
            var gv = useGraphMode();
            seedGraphTree();
            gv.sourceFrame = "world";
            gv.targetFrame = "base_link";
            var tft = gv._testTfTransform();
            tft.translation = {
                "x": 0,
                "y": 0,
                "z": 0
            };
            tft.rotation = {
                "x": 0,
                "y": 0,
                "z": 0,
                "w": 1
            };
            tft.valid = true;
            wait(250);
            var copyBtn = find("tfTransformPopupCopyYaml");
            verify(copyBtn !== null, "Copy YAML button should be found");
            RQml.resetClipboard();
            mouseClick(copyBtn);
            tryVerify(function () {
                return RQml.clipboard.length > 0;
            }, 1000);
            var yaml = RQml.clipboard;
            verify(yaml.indexOf("source_frame: world") !== -1, "YAML should contain source_frame");
            verify(yaml.indexOf("target_frame: base_link") !== -1, "YAML should contain target_frame");
            verify(yaml.indexOf("translation:") !== -1);
            verify(yaml.indexOf("rotation:") !== -1);
            verify(yaml.indexOf("  w: 1") !== -1, "YAML should contain nested quaternion w");
        }
        function test_view_mode_switching() {
            var stack = find("tfViewStack");
            verify(stack !== null, "View stack should exist");

            // Initially set to list in init()
            compare(stack.currentIndex, 1, "List view should be active initially");
            var graphButton = find("tfGraphModeButton");
            var listButton = find("tfListModeButton");
            verify(graphButton !== null, "Graph mode button should exist");
            verify(listButton !== null, "List mode button should exist");

            // Switch to graph
            mouseClick(graphButton);
            tryCompare(stack, "currentIndex", 0, 1000, "Stack should switch to graph view");
            compare(contextObj.viewMode, "graph", "Context viewMode should be 'graph'");

            // Switch back to list
            mouseClick(listButton);
            tryCompare(stack, "currentIndex", 1, 1000, "Stack should switch back to list");
            compare(contextObj.viewMode, "list", "Context viewMode should be 'list'");
        }

        // -----------------------------------------------------------------
        // Graph view: source/target selection + transform popup
        // -----------------------------------------------------------------
        function useGraphMode() {
            contextObj.viewMode = "graph";
            wait(50);
            var gv = find("tfGraphView");
            verify(gv !== null, "Graph view should be found");
            return gv;
        }

        name: "TfTreeViewerTest"
        when: windowShown
    }
}
