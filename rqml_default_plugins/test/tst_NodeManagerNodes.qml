/*
 * Copyright (C) 2026  Stefan Fabian
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
import QtQuick.Controls.Material
import QtTest
import Ros2
import RQml.Elements
import "../qml/elements"

Item {
    id: root

    property var context: contextObj

    // A service or action client entry of NodeInfoView.info with its server nodes.
    function client(name, servers) {
        return {
            "name": name,
            "datatypes": ["std_srvs/srv/Empty"],
            "peers": servers.map(node => ({
                        "node": node
                    }))
        };
    }

    // Returns the visible descendants of @p item (including itself) for which @p predicate holds.
    function findAll(item, predicate) {
        let found = item.visible && predicate(item) ? [item] : [];
        for (let i = 0; i < item.children.length; ++i)
            found = found.concat(findAll(item.children[i], predicate));
        return found;
    }
    function findText(item, text) {
        return findAll(item, o => o.text === text)[0] ?? null;
    }
    function headers(item) {
        return findAll(item, o => o instanceof ListHeader).map(o => o.text);
    }
    function nodeInfo(fields) {
        return Object.assign({
            "publishers": [],
            "subscriptions": [],
            "serviceServers": [],
            "serviceClients": [],
            "actionServers": [],
            "actionClients": []
        }, fields);
    }
    function qos(reliability, durability, history, depth) {
        return {
            "reliability": reliability,
            "durability": durability,
            "history": history,
            "depth": depth
        };
    }
    function topic(name, endpointQos, peers) {
        return {
            "name": name,
            "datatypes": ["std_msgs/msg/String"],
            "qos": endpointQos ?? [qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)],
            "peers": peers
        };
    }

    height: 600
    width: 800

    QtObject {
        id: contextObj

        property var hideHiddenNodes
        property var selectedNodeFullName
        property var showDefaultInterfaces
    }
    Component {
        id: pillsComponent

        QosPills {
            width: 300
        }
    }
    Component {
        id: windowComponent

        Window {
        }
    }
    Component {
        id: infoViewComponent

        NodeInfoView {
            height: 200
            width: 400
        }
    }
    Component {
        id: tabComponent

        NodesTab {
            anchors.fill: parent
        }
    }
    TestCase {
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
        }
        // Returns the pill rows of @p pills as lists of {text, color}.
        function rows(pills) {
            return findAll(pills, o => o.flow !== undefined).map(row => findAll(row, o => o.radius !== undefined).map(pill => ({
                            "text": pill.children[0].text,
                            "color": pill.color
                        })));
        }
        function test_duplicate_endpoints_collapsed() {
            const a = qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10);
            const b = qos(ReliabilityPolicy.BestAvailable, DurabilityPolicy.BestAvailable, HistoryPolicy.SystemDefault, 0);
            const pills = createTemporaryObject(pillsComponent, root, {
                "qos": [a, b, qos(a.reliability, a.durability, a.history, a.depth), b]
            });
            compare(rows(pills).map(row => row.map(p => p.text)), [["Reliable", "Volatile", "Keep last 10"], ["Best available", "Best available", "System default"]]);
        }
        function test_empty_list_renders_nothing() {
            const pills = createTemporaryObject(pillsComponent, root, {
                "qos": []
            });
            compare(rows(pills).length, 0);
            compare(pills.implicitHeight, 0);
        }
        function test_two_profiles() {
            const pills = createTemporaryObject(pillsComponent, root, {
                "qos": [qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10), qos(ReliabilityPolicy.BestEffort, DurabilityPolicy.TransientLocal, HistoryPolicy.KeepAll, 1000)]
            });
            const result = rows(pills);
            compare(result.map(row => row.map(p => p.text)), [["Reliable", "Volatile", "Keep last 10"], ["Best effort", "Transient local", "Keep all"]]);
            const expectedColors = [[Material.Green, Material.Grey, Material.Cyan], [Material.Orange, Material.Blue, Material.Purple]];
            for (let r = 0; r < 2; ++r) {
                for (let p = 0; p < 3; ++p)
                    verify(Qt.colorEqual(result[r][p].color, Material.color(expectedColors[r][p])), result[r][p].text + " has color " + result[r][p].color);
            }
        }
        function test_unknown_history_omitted() {
            // Fast DDS reports graph endpoints with unknown history and depth 0.
            const pills = createTemporaryObject(pillsComponent, root, {
                "qos": [qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Unknown, HistoryPolicy.Unknown, 0)]
            });
            compare(rows(pills).map(row => row.map(p => p.text)), [["Reliable", "Unknown"]]);
        }
        function test_wraps_at_narrow_width() {
            const pills = createTemporaryObject(pillsComponent, root, {
                "qos": [qos(ReliabilityPolicy.Reliable, DurabilityPolicy.TransientLocal, HistoryPolicy.KeepLast, 10)]
            });
            const items = findAll(pills, o => o.radius !== undefined);
            tryVerify(() => items.every(p => p.y === items[0].y), 1000, "Pills should share a line when they fit");
            pills.width = 100;
            tryVerify(() => items[2].y > items[0].y, 1000, "Pills should wrap onto a new line");
            verify(items.every(p => p.x + p.width <= pills.width), "Pills should stay inside the width");
        }

        name: "QosPills"
        when: windowShown
    }
    TestCase {
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            RQml.resetClipboard();
        }
        function test_copy_name_and_type() {
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "publishers": [topic("/chatter")]
                })
            });
            const menu = findAll(view, o => o.menu !== undefined)[0].menu;
            menu.itemAt(0).triggered();
            compare(RQml.clipboard, "/chatter");
            menu.itemAt(1).triggered();
            compare(RQml.clipboard, "std_msgs/msg/String");
        }
        function test_default_interface_filter() {
            const service = name => ({
                        "name": name,
                        "datatypes": ["rcl_interfaces/srv/GetParameters"]
                    });
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "publishers": [topic("/rosout", undefined, []), topic("/chatter", undefined, [])],
                    "subscriptions": [topic("/parameter_events", undefined, [])],
                    "serviceServers": [service("/talker/get_parameters"), service("/talker/set_parameters_atomically"), service("/talker/reset")],
                    "serviceClients": [service("/talker/describe_parameters")]
                })
            });
            compare(headers(view), ["Publishers (1)", "Service Servers (1)"]);
            verify(findText(view, "/chatter"));
            verify(findText(view, "/talker/reset"));
            view.showDefaultInterfaces = true;
            compare(headers(view), ["Publishers (2)", "Subscribers (1)", "Service Servers (3)", "Service Clients (1)"]);
        }
        function test_multiple_servers_error_only_on_clients() {
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "serviceServers": [
                        {
                            "name": "/reset",
                            "datatypes": ["std_srvs/srv/Empty"]
                        }
                    ],
                    "publishers": [topic("/chatter", null, [
                            {
                                "node": "/a",
                                "qos": qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                            },
                            {
                                "node": "/b",
                                "qos": qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                            }
                        ])]
                })
            });
            compare(findAll(view, o => o.objectName === "nmMultipleServersError").length, 0);
            compare(findAll(view, o => o.objectName === "nmUnconnectedMarker").length, 0);
        }
        function test_null_info_shows_empty_text() {
            const view = createTemporaryObject(infoViewComponent, root, {
                "emptyText": "Nothing here."
            });
            verify(findText(view, "Nothing here."), "Hint should show the empty text");
            compare(headers(view), []);
            view.info = nodeInfo({
                "publishers": [topic("/chatter")]
            });
            verify(!findText(view, "Nothing here."), "Hint should hide once there is info");
        }
        function test_peer_counts_and_unconnected_highlight() {
            const peer = node => ({
                        "node": node,
                        "qos": qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                    });
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "publishers": [topic("/connected", null, [peer("/a"), peer("/b"), peer("/b")]), topic("/lonely", null, [])],
                    "subscriptions": [topic("/input", null, [peer("/a")])],
                    "serviceServers": [
                        {
                            "name": "/reset",
                            "datatypes": ["std_srvs/srv/Empty"]
                        }
                    ],
                    "serviceClients": [client("/served", ["/server"]), client("/missing", [])],
                    "actionClients": [client("/move", ["/mover", "/mover_copy"])]
                })
            });
            compare(findAll(view, o => o.objectName === "nmPeersButton").map(o => o.text), ["3 subscribers", "1 publisher", "1 server", "2 servers"]);
            compare(findAll(view, o => o.objectName === "nmNoPeersLabel").map(o => o.text), ["No subscribers", "No server"]);
            const markers = findAll(view, o => o.objectName === "nmUnconnectedMarker");
            compare(markers.map(o => Qt.colorEqual(o.color, Material.color(Material.Red))), [false, false, true], "Only the topic and client without peers and the client with two servers should be marked");
            const errors = findAll(view, o => o.objectName === "nmMultipleServersError");
            compare(errors.length, 1, "Only the client with two servers should get the error");
            compare(errors[0].ToolTip.text, "2 servers: each of them executes every request, the client uses the first response.");
        }
        function test_peer_popup_lists_nodes() {
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "publishers": [topic("/chatter", null, [
                            {
                                "node": "/z",
                                "qos": qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                            },
                            {
                                "node": "/a",
                                "qos": qos(ReliabilityPolicy.BestEffort, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                            },
                            {
                                "node": "/a",
                                "qos": qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                            }
                        ])]
                })
            });
            const popup = findChild(view, "nmPeerPopup");
            mouseClick(findAll(view, o => o.objectName === "nmPeersButton")[0]);
            tryVerify(() => popup.opened);
            verify(findText(popup.contentItem, "Subscribers of /chatter"), "Popup should name the topic");
            const list = findAll(popup.contentItem, o => o instanceof ListView)[0];
            tryVerify(() => list.itemAtIndex(1) !== null);
            compare([list.itemAtIndex(0).children[0].text, list.itemAtIndex(1).children[0].text], ["/a", "/z"]);
            compare(findAll(list.itemAtIndex(0), o => o.text === "Best effort").length, 1, "Peers of one node should keep their QoS");
            compare(findAll(list.itemAtIndex(0), o => o.flow !== undefined).length, 2, "Each distinct QoS of a node should get a row");
            popup.close();
        }
        function test_peer_popup_opens_after_moving_window() {
            // Dock widgets create their guest in a temporary window and move it into the dock's window.
            const tempWindow = createTemporaryObject(windowComponent, root);
            const view = createTemporaryObject(infoViewComponent, null, {
                "info": nodeInfo({
                    "publishers": [topic("/chatter", null, [
                            {
                                "node": "/a",
                                "qos": qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10)
                            }
                        ])]
                })
            });
            view.parent = tempWindow.contentItem;
            view.parent = root;
            tempWindow.destroy();
            wait(0);
            const popup = findChild(view, "nmPeerPopup");
            mouseClick(findAll(view, o => o.objectName === "nmPeersButton")[0]);
            tryVerify(() => popup.opened);
            popup.close();
        }
        function test_scrolls_when_taller_than_view() {
            const publishers = [];
            for (let i = 0; i < 30; ++i)
                publishers.push(topic("/topic_" + i));
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "publishers": publishers
                })
            });
            verify(view.contentHeight > view.height, "Content should be taller than the view");
            mouseWheel(view, view.width / 2, view.height / 2, 0, -360);
            tryVerify(() => view.contentItem.contentY > 0, 2000, "Wheel should scroll the content");
        }
        function test_sections_and_counts() {
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "publishers": [topic("/a"), topic("/b")],
                    "subscriptions": [topic("/c")],
                    "actionServers": [
                        {
                            "name": "/fibonacci",
                            "datatypes": ["example_interfaces/action/Fibonacci"]
                        }
                    ]
                })
            });
            compare(headers(view), ["Publishers (2)", "Subscribers (1)", "Action Servers (1)"]);
            verify(findText(view, "example_interfaces/action/Fibonacci"), "Entries should show their types");
            compare(findAll(view, o => o.text === "Reliable").length, 3, "Topics should show their QoS");
        }
        function test_server_popup_lists_nodes() {
            const view = createTemporaryObject(infoViewComponent, root, {
                "info": nodeInfo({
                    "serviceClients": [client("/add", ["/z_server", "/a_server"])]
                })
            });
            const popup = findChild(view, "nmPeerPopup");
            mouseClick(findAll(view, o => o.objectName === "nmPeersButton")[0]);
            tryVerify(() => popup.opened);
            verify(findText(popup.contentItem, "Servers of /add"), "Popup should name the service");
            const list = findAll(popup.contentItem, o => o instanceof ListView)[0];
            tryVerify(() => list.itemAtIndex(1) !== null);
            compare([list.itemAtIndex(0).children[0].text, list.itemAtIndex(1).children[0].text], ["/a_server", "/z_server"]);
            compare(findAll(list.itemAtIndex(0), o => o.flow !== undefined).length, 0, "Servers have no QoS");
            popup.close();
        }

        name: "NodeInfoView"
        when: windowShown
    }
    TestCase {
        function createTab() {
            const tab = createTemporaryObject(tabComponent, root);
            tab.refresh();
            return tab;
        }
        function find(tab, name) {
            return findAll(tab, o => o.objectName === name)[0] ?? null;
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            Ros2.reset();
            RQml.resetClipboard();
            contextObj.hideHiddenNodes = undefined;
            contextObj.selectedNodeFullName = undefined;
            contextObj.showDefaultInterfaces = undefined;
        }
        // The node list once all its rows exist, null while it is hidden.
        function nodeList(tab) {
            const list = find(tab, "nmNodeList");
            if (list)
                tryVerify(() => list.itemAtIndex(list.count - 1) !== null);
            return list;
        }
        function rowNames(tab) {
            const list = nodeList(tab);
            const names = [];
            for (let i = 0; i < (list?.count ?? 0); ++i)
                names.push(list.itemAtIndex(i).text);
            return names;
        }
        function test_case_insensitive_filter() {
            Ros2.registerNode("/Talker");
            Ros2.registerNode("/listener");
            const tab = createTab();
            typeFilter(tab, "TALK");
            compare(rowNames(tab), ["/Talker"]);
            typeFilter(tab, "x");
            tryVerify(() => find(tab, "nmNodeListHint")?.text === "No nodes match the filter.", 1000);
        }
        function test_copy_node_name() {
            Ros2.registerNode("/talker");
            const tab = createTab();
            const row = nodeList(tab).itemAtIndex(0);
            findAll(row, o => o.menu !== undefined)[0].menu.itemAt(0).triggered();
            compare(RQml.clipboard, "/talker");
        }
        function test_empty_hint() {
            const tab = createTab();
            compare(find(tab, "nmNodeListHint").text, "No nodes found. Is ROS running?");
        }
        function test_hidden_toggle_and_external_change() {
            Ros2.registerNode("/_daemon");
            Ros2.registerNode("/talker");
            const tab = createTab();
            const checkBox = find(tab, "nmHideHiddenCheckBox");
            verify(checkBox.checked, "Hidden nodes should be hidden by default");
            compare(rowNames(tab), ["/talker"]);
            mouseClick(checkBox);
            compare(contextObj.hideHiddenNodes, false);
            compare(rowNames(tab), ["/_daemon", "/talker"]);
            // The Graph tab shares the flag.
            contextObj.hideHiddenNodes = true;
            compare(rowNames(tab), ["/talker"]);
            verify(checkBox.checked, "Check box should follow the shared flag");
        }
        function test_keyboard_selection() {
            Ros2.registerNode("/a");
            Ros2.registerNode("/b");
            Ros2.registerNode("/c");
            const tab = createTab();
            find(tab, "nmNodeSearchBar").focusSearch();
            keyClick(Qt.Key_Up);
            compare(contextObj.selectedNodeFullName, undefined, "Up without a selection should do nothing");
            keyClick(Qt.Key_Down);
            compare(contextObj.selectedNodeFullName, "/a");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            compare(contextObj.selectedNodeFullName, "/c", "Down should stop at the last row");
            keyClick(Qt.Key_Up);
            compare(contextObj.selectedNodeFullName, "/b");
            keyClick(Qt.Key_Return);
            compare(contextObj.selectedNodeFullName, "/b", "Return should keep a visible selection");
            typeFilter(tab, "c");
            keyClick(Qt.Key_Return);
            compare(contextObj.selectedNodeFullName, "/c", "Return should select the first visible row");
        }
        function test_keyboard_selection_applies_typed_filter() {
            Ros2.registerNode("/alpha");
            Ros2.registerNode("/camera");
            const tab = createTab();
            find(tab, "nmNodeSearchBar").focusSearch();
            keyClick("c");
            keyClick(Qt.Key_Down);
            compare(contextObj.selectedNodeFullName, "/camera", "Down right after typing should step through the typed filter's rows");
        }
        function test_keyboard_selection_scrolls_into_view() {
            for (let i = 10; i < 70; ++i)
                Ros2.registerNode("/node_" + i);
            const tab = createTab();
            contextObj.selectedNodeFullName = "/node_68";
            find(tab, "nmNodeSearchBar").focusSearch();
            keyClick(Qt.Key_Down);
            compare(contextObj.selectedNodeFullName, "/node_69");
            const list = find(tab, "nmNodeList");
            tryVerify(() => {
                const item = list.itemAtIndex(59);
                return item && item.y >= list.contentY && item.y + item.height <= list.contentY + list.height;
            }, 1000, "Selected row should scroll into view");
        }
        function test_peers_and_qos_from_graph() {
            const reliable = qos(ReliabilityPolicy.Reliable, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10);
            const bestEffort = qos(ReliabilityPolicy.BestEffort, DurabilityPolicy.Volatile, HistoryPolicy.KeepLast, 10);
            const named = names => names.map(name => topic(name, []));
            Ros2.registerNode("/talker", nodeInfo({
                "publishers": [topic("/chatter", [bestEffort])]
            }));
            Ros2.registerNode("/ns/listener", nodeInfo({
                "subscriptions": [topic("/chatter", [reliable, reliable])],
                "serviceClients": named(["/reset"]),
                "actionClients": named(["/move"])
            }));
            Ros2.registerNode("/server_a", nodeInfo({
                "serviceServers": named(["/reset"])
            }));
            Ros2.registerNode("/server_b", nodeInfo({
                "serviceServers": named(["/reset"]),
                "actionServers": named(["/move"])
            }));
            const tab = createTab();
            const infoView = find(tab, "nmNodeInfoView");
            const buttons = () => findAll(infoView, o => o.objectName === "nmPeersButton").map(o => o.text);
            tab.showNode("/talker");
            compare(buttons(), ["2 subscribers"], "Each endpoint on the other side should count");
            compare(findAll(infoView, o => o.text === "Best effort").length, 1, "Only the node's own endpoint QoS should show");
            tab.showNode("/ns/listener");
            compare(buttons(), ["1 publisher", "2 servers", "1 server"]);
            compare(findAll(infoView, o => o.text === "Reliable").length, 1, "Equal QoS of the node's endpoints should collapse");
            const popup = findChild(infoView, "nmPeerPopup");
            // Clicked directly as the rows are still being laid out after the selection change.
            findAll(infoView, o => o.objectName === "nmPeersButton")[0].clicked();
            tryVerify(() => popup.opened);
            const list = findAll(popup.contentItem, o => o instanceof ListView)[0];
            tryVerify(() => list.itemAtIndex(0) !== null);
            compare(list.itemAtIndex(0).children[0].text, "/talker");
            popup.close();
        }
        function test_refresh_keeps_scroll_position() {
            for (let i = 10; i < 70; ++i)
                Ros2.registerNode("/node_" + i);
            const tab = createTab();
            const list = find(tab, "nmNodeList");
            // Scroll like a user does; positionViewAtEnd() moves originY on newer Qt versions.
            list.contentY = list.contentHeight - list.height;
            const contentY = list.contentY;
            verify(contentY > 0, "List should be scrolled down");
            Ros2.registerNode("/node_00");
            tab.refresh();
            waitForItemPolished(list);
            compare(list.contentY, contentY, "A joining node should keep the scroll position");
            list.flick(0, 3000);
            tab.refresh();
            verify(list.flicking, "An unchanged refresh should not stop a flick");
        }
        function test_selection_shows_info() {
            Ros2.registerNode("/listener");
            Ros2.registerNode("/talker", nodeInfo({
                "publishers": [topic("/chatter")]
            }));
            const tab = createTab();
            const row = nodeList(tab).itemAtIndex(1);
            mouseClick(row);
            compare(contextObj.selectedNodeFullName, "/talker");
            verify(row.highlighted, "Selected row should be highlighted");
            verify(findAll(tab, o => o instanceof Title && o.text === "/talker").length === 1, "Title should name the node");
            const infoView = find(tab, "nmNodeInfoView");
            compare(headers(infoView), ["Publishers (1)"]);
            verify(findText(infoView, "/chatter"));
        }
        function test_sorted_list() {
            Ros2.registerNode("/zeta");
            Ros2.registerNode("/alpha");
            Ros2.registerNode("/ns/beta");
            Ros2.registerNode("/zeta"); // ROS 2 allows duplicate node names.
            const tab = createTab();
            compare(rowNames(tab), ["/alpha", "/ns/beta", "/zeta"]);
        }
        function test_unchanged_refresh_keeps_delegates() {
            // Fresh info objects on every refresh, as in production. Ros2.QoS() gadgets never compare equal.
            const registerTalker = endpointQos => {
                Ros2.reset();
                Ros2.registerNode("/talker", nodeInfo({
                    "publishers": [topic("/chatter", endpointQos)]
                }));
            };
            registerTalker([Ros2.QoS()]);
            const tab = createTab();
            tab.showNode("/talker");
            const infoView = find(tab, "nmNodeInfoView");
            const entry = findText(infoView, "/chatter");
            const row = nodeList(tab).itemAtIndex(0);
            verify(entry && row);
            registerTalker([Ros2.QoS()]);
            tab.refresh();
            verify(findText(infoView, "/chatter") === entry, "Unchanged info should keep its delegates");
            verify(nodeList(tab).itemAtIndex(0) === row, "Unchanged node list should keep its delegates");
            registerTalker([qos(ReliabilityPolicy.Reliable, DurabilityPolicy.TransientLocal, HistoryPolicy.KeepLast, 10)]);
            tab.refresh();
            verify(findText(infoView, "Transient local"), "Changed QoS should update the info");
        }
        function test_unconnected_warning() {
            const named = names => names.map(name => topic(name));
            Ros2.registerNode("/a", nodeInfo({
                "subscriptions": named(["/missing"]),
                "serviceClients": named(["/gone/get_parameters"])
            }));
            Ros2.registerNode("/b", nodeInfo({
                "publishers": named(["/data"]),
                "serviceServers": named(["/reset"])
            }));
            Ros2.registerNode("/c", nodeInfo({
                "subscriptions": named(["/data", "/other_missing"]),
                "serviceClients": named(["/reset", "/unserved"]),
                "actionClients": named(["/move"])
            }));
            const tab = createTab();
            const list = nodeList(tab);
            const warning = i => findAll(list.itemAtIndex(i), o => o.objectName === "nmUnconnectedWarning")[0];
            compare(warning(0).ToolTip.text, "1 subscription or client has no publisher or server");
            verify(!warning(1));
            compare(warning(2).ToolTip.text, "3 subscriptions or clients have no publisher or server");
            Ros2.registerNode("/d", nodeInfo({
                "publishers": named(["/missing"])
            }));
            tab.refresh();
            verify(!warning(0), "A new publisher should clear the warning");
        }
        function test_vanished_node_shows_hint() {
            Ros2.registerNode("/talker", nodeInfo({
                "publishers": [topic("/chatter")]
            }));
            const tab = createTab();
            tab.showNode("/talker");
            const infoView = find(tab, "nmNodeInfoView");
            verify(!findText(infoView, "Node is no longer available."));
            Ros2.reset();
            tab.refresh();
            verify(findText(infoView, "Node is no longer available."), "Vanished node should show the hint");
            compare(headers(infoView), []);
        }
        function typeFilter(tab, text) {
            const searchBar = find(tab, "nmNodeSearchBar");
            searchBar.clear();
            searchBar.focusSearch();
            for (const c of text)
                keyClick(c);
            tryCompare(searchBar, "text", text.toLowerCase());
        }

        name: "NodesTab"
        when: windowShown
    }
}
