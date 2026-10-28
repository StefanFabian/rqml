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

// Wiring of the Node Manager root: tab restore, refresh contract and cross-tab actions.
// The tabs themselves are covered by the tst_NodeManager<Tab>.qml files.
Item {
    id: root

    property var context: contextObj
    property var plugin: pluginLoader.item

    function find(name) {
        return helpers.findChild(root, name);
    }

    height: 600
    width: 800

    QtObject {
        id: contextObj

        property var currentTab
        property var graphHideCommon
        property var graphHideTf
        property var hideHiddenNodes
        property var selectedContainer
        property var selectedNodeFullName
        property var showDefaultInterfaces
    }
    Utils {
        id: helpers
    }
    Loader {
        id: pluginLoader
        function reload() {
            source = "";
            source = "../qml/NodeManager.qml";
        }

        anchors.fill: parent
    }
    Component {
        id: detachedPlugin
        Loader {
            source: "../qml/NodeManager.qml"
        }
    }
    TestCase {
        function addLifecycleNode(node) {
            Ros2.registerNode(node);
            Ros2.registerService(node + "/change_state", "lifecycle_msgs/srv/ChangeState", () => ({
                            "success": true
                        }));
            Ros2.registerService(node + "/get_state", "lifecycle_msgs/srv/GetState", () => ({
                            "current_state": {
                                "label": "unconfigured"
                            }
                        }));
        }
        function addNode(fullName, publishers, subscribers) {
            const endpoint = name => ({
                        "name": name,
                        "datatypes": ["std_msgs/msg/String"],
                        "qos": []
                    });
            Ros2.registerNode(fullName, {
                    "publishers": publishers.map(endpoint),
                    "subscriptions": subscribers.map(endpoint),
                    "serviceServers": [],
                    "serviceClients": [],
                    "actionServers": [],
                    "actionClients": []
                });
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            Ros2.reset();
            pluginLoader.visible = true;
            contextObj.currentTab = undefined;
            contextObj.graphHideCommon = undefined;
            contextObj.graphHideTf = undefined;
            contextObj.hideHiddenNodes = undefined;
            contextObj.selectedContainer = undefined;
            contextObj.selectedNodeFullName = undefined;
            contextObj.showDefaultInterfaces = undefined;
            addNode("/talker", ["/chatter"], []);
            addNode("/listener", [], ["/chatter"]);
            addNode("/_hidden", [], ["/chatter"]);
        }
        function load() {
            pluginLoader.reload();
            tryVerify(() => !!root.plugin, 2000);
        }
        function test_created_outside_a_window_without_warnings() {
            // Docking frameworks create the plugin item before it is in a window.
            const loader = createTemporaryObject(detachedPlugin, null);
            verify(loader.item);
            wait(50);
        }
        function test_graph_is_not_refreshed_periodically() {
            contextObj.currentTab = 3;
            load();
            const view = find("nmGraphView");
            tryCompare(view, "nodes", ["/listener", "/talker"], 2000);
            addNode("/late", [], ["/chatter"]);
            wait(2500);
            compare(view.nodes, ["/listener", "/talker"]);
        }
        function test_hidden_dock_is_not_refreshed_until_shown() {
            load();
            wait(10);
            compare(find("nmNodeList").count, 2);
            pluginLoader.visible = false;
            addNode("/late", [], []);
            wait(2500);
            compare(find("nmNodeList").count, 2, "no refresh while hidden");
            pluginLoader.visible = true;
            wait(50);
            compare(find("nmNodeList").count, 3, "refreshes as soon as it is shown");
        }
        function test_hidden_toggle_is_shared_between_tabs() {
            load();
            tryVerify(() => find("nmNodeList").count === 2, 1000);
            find("nmTabBar").currentIndex = 3;
            const checkBox = find("nmGraphHideHiddenCheckBox");
            tryVerify(() => checkBox.visible, 1000);
            mouseClick(checkBox);
            compare(contextObj.hideHiddenNodes, false);
            find("nmTabBar").currentIndex = 0;
            tryVerify(() => find("nmNodeList").count === 3, 1000);
            const nodesCheckBox = find("nmHideHiddenCheckBox");
            verify(!nodesCheckBox.checked);
            // Toggling back in the other tab must reach the graph, whose checkbox the user toggled before.
            mouseClick(nodesCheckBox);
            compare(contextObj.hideHiddenNodes, true);
            find("nmTabBar").currentIndex = 3;
            verify(checkBox.checked);
            find("nmGraphRefreshButton").clicked();
            tryCompare(find("nmGraphView"), "nodes", ["/listener", "/talker"], 2000);
        }
        function test_inspect_clears_a_filter_that_hides_the_node() {
            load();
            wait(10);
            const searchBar = find("nmNodeSearchBar");
            helpers.findChild(searchBar, "searchBarTextField").text = "lis";
            searchBar.commitSearchText();
            compare(find("nmNodeList").count, 1);
            find("nmGraphView").inspectNodeRequested("/talker");
            compare(searchBar.text, "");
            verify(find("nmNodeList").model.some(n => n.fullName === "/talker"));
        }
        function test_inspect_from_graph_shows_node_in_nodes_tab() {
            load();
            wait(10);
            find("nmTabBar").currentIndex = 3;
            const view = find("nmGraphView");
            tryCompare(view, "nodes", ["/listener", "/talker"], 2000);
            // A node started after the Nodes tab last refreshed must still be found.
            addNode("/late", ["/chatter"], []);
            view.inspectNodeRequested("/late");
            compare(find("nmTabBar").currentIndex, 0);
            compare(contextObj.selectedNodeFullName, "/late");
            const infoView = find("nmNodeInfoView");
            // Showing the tab refreshes it, so the info is there at once.
            verify(infoView.info !== null, "info shown without waiting for a refresh");
            compare(infoView.info.publishers[0].name, "/chatter");
        }
        function test_inspect_scrolls_the_node_into_view(data) {
            for (let i = 10; i < 70; ++i)
                addNode("/node_" + i, [], []);
            contextObj.currentTab = data.tab;
            load();
            wait(10);
            find("nmGraphView").inspectNodeRequested("/node_69");
            const list = find("nmNodeList");
            waitForItemPolished(list);
            const row = list.itemAtIndex(list.model.findIndex(n => n.fullName === "/node_69"));
            verify(row && row.y >= list.contentY && row.y + row.height <= list.contentY + list.height, "row in view, contentY " + list.contentY);
        }
        function test_inspect_scrolls_the_node_into_view_data() {
            return [{
                    "tag": "from the Nodes tab",
                    "tab": 0
                }, {
                    "tag": "from a restored Graph tab",
                    "tab": 3
                }];
        }
        function test_loads_and_refreshes_the_visible_tab() {
            load();
            compare(find("nmTabBar").currentIndex, 0);
            // tryVerify timeouts count 50 ms waits, not real time, so they cannot tell a deferred call from a timer.
            wait(10);
            compare(find("nmNodeList").count, 2);
            addNode("/late", [], []);
            tryVerify(() => find("nmNodeList").count === 3, 3000);
        }
        function test_node_list_follows_graph_changes_instead_of_polling() {
            load();
            wait(10);
            compare(find("nmNodeList").count, 2);
            // reset() does not emit graphChanged, so only polling could notice the vanished nodes.
            Ros2.reset();
            wait(2500);
            compare(find("nmNodeList").count, 2, "no periodic refresh");
            Ros2.graphChanged();
            tryVerify(() => find("nmNodeList").count === 0, 1000);
        }
        function test_restores_graph_tab_and_builds_it() {
            contextObj.currentTab = 3;
            load();
            compare(find("nmTabBar").currentIndex, 3);
            tryCompare(find("nmGraphView"), "nodes", ["/listener", "/talker"], 2000);
        }
        function test_switching_tab_refreshes_and_persists_it() {
            load();
            // Let the initial refresh of the Nodes tab happen first, it would otherwise refresh the new tab.
            wait(10);
            addLifecycleNode("/lc_talker");
            find("nmTabBar").currentIndex = 1;
            compare(contextObj.currentTab, 1);
            wait(10);
            compare(find("nmLifecycleList").count, 1);
        }

        name: "NodeManager"
        when: windowShown
    }
}
