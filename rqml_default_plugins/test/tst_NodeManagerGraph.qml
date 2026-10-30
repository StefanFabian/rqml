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
import QtTest
import Ros2
import "../qml/elements"
import "../qml/elements/GraphLayout.js" as GraphLayout
import "../qml/interfaces"
import "../qml/interfaces/GraphModel.js" as GraphModel

Item {
    id: root

    property var context: contextObj
    readonly property var demoNodes: ["/add_two_ints_client", "/add_two_ints_server", "/listener", "/robot/talker2", "/rqml", "/talker", "/turtlesim"]
    readonly property var layoutOpts: ({
            "nodeWidth": 150,
            "nodeHeight": 30,
            "layerGap": 70,
            "rowGap": 16
        })

    function edge(from, to, topicNames) {
        return {
            "from": from,
            "to": to,
            "interfaces": (topicNames ?? []).map(name => link("topic", name))
        };
    }
    // A node as returned by Ros2.getAllNodeInfo(); extra: {role: [name]} for the service and action roles.
    function info(fullName, publishers, subscribers, extra) {
        return Object.assign(nodeInfo(publishers, subscribers, extra), {
            "fullName": fullName,
            "name": fullName.slice(fullName.lastIndexOf("/") + 1)
        });
    }
    function link(kind, name) {
        return Object.assign({
            "kind": kind
        }, topic(name));
    }
    function nodeInfo(publishers, subscribers, extra) {
        const result = {
            "publishers": publishers.map(topic),
            "subscriptions": subscribers.map(topic)
        };
        for (const role in extra ?? {})
            result[role] = extra[role].map(topic);
        return result;
    }
    function topic(name) {
        return {
            "name": name,
            "datatypes": ["std_msgs/msg/String"]
        };
    }

    height: 600
    width: 1000

    QtObject {
        id: contextObj

        property var graphGroupNamespaces
        property var graphHideCommon
        property var graphHideTf
        property var graphIgnoredNodes
        property var graphShowActions
        property var graphShowServices
        property var graphShowTopics
        property var hideHiddenNodes
    }
    Utils {
        id: helpers

    }
    Component {
        id: interfaceComponent

        NodeGraphInterface {
        }
    }
    Component {
        id: viewComponent

        NodeGraphView {
            height: 600
            width: 1000
        }
    }
    Component {
        id: tabComponent

        NodeGraphTab {
            anchors.fill: parent
        }
    }
    TestCase {
        function test_aggregated_topics_sorted() {
            const g = GraphModel.buildGraph([info("/a", ["/z", "/y"], []), info("/b", [], ["/y", "/z"])], {});
            compare(g.edges, [edge("/a", "/b", ["/y", "/z"])]);
        }
        function test_bidirectional_pair() {
            const g = GraphModel.buildGraph([info("/b", ["/y"], ["/x"]), info("/a", ["/x"], ["/y"])], {});
            compare(g.edges, [edge("/a", "/b", ["/x"]), edge("/b", "/a", ["/y"])]);
        }
        function test_duplicate_ids_collapse() {
            const g = GraphModel.buildGraph([info("/dup", ["/t"], []), info("/x", ["/u"], ["/t"]), info("/dup", [], ["/u"])], {});
            compare(g.nodes, ["/dup", "/x"]);
            compare(g.edges.map(e => e.from + " " + e.to), ["/dup /x", "/x /dup"]);
        }
        function test_empty_datatypes_do_not_hide_type() {
            const g = GraphModel.buildGraph([
                {
                    "fullName": "/a",
                    "name": "a",
                    "publishers": [
                        {
                            "name": "/t",
                            "datatypes": []
                        }
                    ]
                },
                {
                    "fullName": "/b",
                    "name": "b",
                    "publishers": [
                        {
                            "name": "/t",
                            "datatypes": ["pkg/msg/First"]
                        }
                    ]
                },
                {
                    "fullName": "/c",
                    "name": "c",
                    "subscriptions": [
                        {
                            "name": "/t",
                            "datatypes": []
                        }
                    ]
                }
            ], {});
            compare(g.edges.map(e => e.interfaces[0].datatypes), [["pkg/msg/First"], ["pkg/msg/First"]]);
        }
        function test_fan_in() {
            const g = GraphModel.buildGraph([info("/c", [], ["/t"]), info("/b", ["/t"], []), info("/a", ["/t"], [])], {});
            compare(g.edges.map(e => e.from + " " + e.to), ["/a /c", "/b /c"]);
        }
        function test_hide_common_keeps_tf() {
            const topics = ["/rosout", "/parameter_events", "/clock", "/tf", "/data"];
            const infos = [info("/a", topics, []), info("/b", [], topics)];
            compare(GraphModel.buildGraph(infos, {
                "hideCommon": true
            }).edges[0].interfaces.map(t => t.name), ["/data", "/tf"]);
            compare(GraphModel.buildGraph(infos, {}).edges[0].interfaces.length, 5);
        }
        function test_hide_hidden() {
            const infos = [info("/a", ["/t"], []), info("/ns/_hidden", [], ["/t"])];
            compare(GraphModel.buildGraph(infos, {
                "hideHidden": true
            }), {
                "nodes": ["/a"],
                "edges": []
            });
            compare(GraphModel.buildGraph(infos, {}).nodes, ["/a", "/ns/_hidden"]);
        }
        function test_hide_tf_including_namespaced() {
            const topics = ["/tf", "/tf_static", "/robot/tf", "/robot/tf_static", "/tf_relay", "/robot/tfx"];
            const infos = [info("/a", topics, []), info("/b", [], topics)];
            compare(GraphModel.buildGraph(infos, {
                "hideTf": true
            }).edges[0].interfaces.map(t => t.name), ["/robot/tfx", "/tf_relay"]);
        }
        function test_missing_lists_count_as_empty() {
            const g = GraphModel.buildGraph([
                {
                    "fullName": "/vanished",
                    "name": "vanished"
                },
                info("/a", ["/t"], [])], {});
            compare(g, {
                "nodes": ["/a", "/vanished"],
                "edges": []
            });
        }
        function test_no_self_edge() {
            compare(GraphModel.buildGraph([info("/a", ["/t"], ["/t"])], {}), {
                "nodes": ["/a"],
                "edges": []
            });
        }
        function test_service_self_connection_left_out() {
            const g = GraphModel.buildGraph([info("/a", [], [], {
                    "serviceClients": ["/a/srv"],
                    "serviceServers": ["/a/srv"]
                })], {
                "showServices": true
            });
            compare(g.edges, []);
        }
        function test_services_and_actions() {
            const infos = [info("/client", ["/t"], [], {
                    "serviceClients": ["/add", "/server/get_parameters"],
                    "actionClients": ["/nav"]
                }), info("/server", [], ["/t"], {
                    "serviceServers": ["/add", "/server/get_parameters"],
                    "actionServers": ["/nav"]
                })];
            compare(GraphModel.buildGraph(infos, {}), {
                "nodes": ["/client", "/server"],
                "edges": [edge("/client", "/server", ["/t"])]
            }, "only topics by default");
            compare(GraphModel.buildGraph(infos, {
                "showServices": true,
                "showActions": true,
                "hideCommon": true
            }).edges, [
                {
                    "from": "/client",
                    "to": "/server",
                    "interfaces": [link("action", "/nav"), link("service", "/add"), link("topic", "/t")]
                }
            ]);
            compare(GraphModel.buildGraph(infos, {
                "showServices": true
            }).edges[0].interfaces.map(i => i.kind + " " + i.name), ["service /add", "service /server/get_parameters", "topic /t"]);
            compare(GraphModel.buildGraph(infos, {
                "showTopics": false,
                "showActions": true
            }).edges[0].interfaces, [link("action", "/nav")], "topics can be hidden");
        }
        function test_simple_edge() {
            const g = GraphModel.buildGraph([info("/b", [], ["/t"]), info("/a", ["/t"], [])], {});
            compare(g, {
                "nodes": ["/a", "/b"],
                "edges": [edge("/a", "/b", ["/t"])]
            });
        }
        function test_unconnected_counts_missing_counterparts_across_nodes() {
            const infos = [info("/talker", ["/chatter"], [], {
                    "serviceServers": ["/served"],
                    "actionServers": ["/move"]
                }), info("/listener", [], ["/chatter", "/silent"], {
                    "serviceClients": ["/served", "/unserved", "/gone/get_parameters"],
                    "actionClients": ["/move", "/unserved_action"]
                })];
            // /silent, /unserved and /unserved_action; default services don't count.
            compare(GraphModel.countUnconnected(infos), {
                "/listener": 3
            });
        }
        function test_unconnected_counts_only_nodes_with_problems() {
            compare(GraphModel.countUnconnected([info("/a", ["/t"], ["/t"]),
                {
                    "fullName": "/empty",
                    "name": "empty"
                }
            ]), {});
        }

        name: "GraphModel"
    }
    TestCase {
        // Best of three runs, so that load from other processes does not fail timing tests.
        function layoutMs(g, opts) {
            let best = Infinity;
            for (let run = 0; run < 3; ++run) {
                const start = Date.now();
                GraphLayout.layout(g.nodes, g.edges, opts ?? layoutOpts);
                best = Math.min(best, Date.now() - start);
            }
            return best;
        }
        function lcg(seed) {
            let state = seed;
            return () => (state = (state * 1664525 + 1013904223) % 4294967296) / 4294967296;
        }
        // Deterministic pseudo-random graph with ids "/n<i>"; acyclic graphs only have edges to higher indices.
        function randomGraph(nodeCount, edgeCount, seed, acyclic) {
            const random = lcg(seed);
            const nodes = [];
            for (let i = 0; i < nodeCount; ++i)
                nodes.push("/n" + i);
            const edges = [];
            while (edges.length < edgeCount) {
                const a = Math.floor(random() * nodeCount);
                const b = Math.floor(random() * nodeCount);
                if (a !== b)
                    edges.push({
                        "from": nodes[acyclic ? Math.min(a, b) : a],
                        "to": nodes[acyclic ? Math.max(a, b) : b]
                    });
            }
            return {
                "nodes": nodes,
                "edges": edges
            };
        }
        function shuffled(list, seed) {
            const random = lcg(seed);
            const result = list.slice();
            for (let i = result.length - 1; i > 0; --i) {
                const j = Math.floor(random() * (i + 1));
                [result[i], result[j]] = [result[j], result[i]];
            }
            return result;
        }
        function test_barycenter_removes_crossing() {
            // In id order /a->/d and /b->/c would cross.
            const p = GraphLayout.layout(["/a", "/b", "/c", "/d"], [edge("/a", "/d"), edge("/b", "/c"), edge("/b", "/d")], layoutOpts);
            verify((p["/a"].y - p["/b"].y) * (p["/d"].y - p["/c"].y) > 0, "edges do not cross");
        }
        function test_components_stacked_largest_first() {
            const p = GraphLayout.layout(["/a", "/b", "/x", "/y", "/z"], [edge("/a", "/b"), edge("/x", "/y"), edge("/y", "/z")], layoutOpts);
            verify(Math.max(p["/x"].y, p["/y"].y, p["/z"].y) < Math.min(p["/a"].y, p["/b"].y), "larger component above");
        }
        function test_cycles_terminate_with_distinct_layers() {
            const triangle = GraphLayout.layout(["/a", "/b", "/c"], [edge("/a", "/b"), edge("/b", "/c"), edge("/c", "/a")], layoutOpts);
            compare(new Set([triangle["/a"].x, triangle["/b"].x, triangle["/c"].x]).size, 3);
            const pair = GraphLayout.layout(["/a", "/b"], [edge("/a", "/b"), edge("/b", "/a")], layoutOpts);
            verify(pair["/a"].x !== pair["/b"].x);
            for (let seed = 1; seed <= 5; ++seed) {
                const g = randomGraph(60, 120, seed, false);
                verifyLayout(g.nodes, GraphLayout.layout(g.nodes, g.edges, layoutOpts));
            }
        }
        function test_dag_edges_point_right() {
            for (let seed = 1; seed <= 5; ++seed) {
                const g = randomGraph(60, 90, seed, true);
                const result = GraphLayout.layout(g.nodes, g.edges, layoutOpts);
                verifyLayout(g.nodes, result);
                for (const e of g.edges)
                    verify(result[e.from].x < result[e.to].x, e.from + " left of " + e.to);
            }
        }
        function test_empty_and_single_node() {
            compare(GraphLayout.layout([], [], layoutOpts), {});
            compare(GraphLayout.layout(["/a"], [], layoutOpts), {
                "/a": {
                    "x": layoutOpts.nodeWidth / 2,
                    "y": layoutOpts.nodeHeight / 2
                }
            });
        }
        function test_feedback_loop_points_back() {
            const p = GraphLayout.layout(["/driver", "/planner", "/tracker"], [edge("/driver", "/tracker"), edge("/tracker", "/planner"), edge("/planner", "/tracker")], layoutOpts);
            verify(p["/driver"].x < p["/tracker"].x && p["/tracker"].x < p["/planner"].x, "the node fed by the flow comes first");
        }
        function test_grouped_bands() {
            const nodes = ["/a/x", "/a/y", "/a/z", "/a/lone", "/b/x", "/b/y", "/b/lone1", "/b/lone2", "/root", "/a/sub/x", "/a-b/x"];
            const edges = [edge("/root", "/a/x"), edge("/a/x", "/a/y"), edge("/a/x", "/a/z"), edge("/a/y", "/b/x"), edge("/b/x", "/b/y"), edge("/b/y", "/a/sub/x")];
            const groupOf = id => id.slice(0, id.lastIndexOf("/")) || "/";
            const opts = Object.assign({
                "groupOf": groupOf
            }, layoutOpts);
            const p = GraphLayout.layout(nodes, edges, opts);
            verifyLayout(nodes, p);
            const ungrouped = GraphLayout.layout(nodes, edges, layoutOpts);
            for (const e of edges)
                compare(p[e.from].x, ungrouped[e.from].x, e.from + " keeps its layer");
            const groups = ["/", "/a", "/a/sub", "/a-b", "/b"];
            const ranges = groups.map(group => {
                const ys = nodes.filter(id => groupOf(id) === group).map(id => p[id].y);
                return [Math.min(...ys), Math.max(...ys)];
            });
            for (let i = 1; i < ranges.length; ++i)
                verify(ranges[i][0] - ranges[i - 1][1] >= 2 * (layoutOpts.nodeHeight + layoutOpts.rowGap), groups[i] + " band below " + groups[i - 1] + " with an empty row in between");
            verify(p["/a/lone"].y > Math.max(p["/a/x"].y, p["/a/y"].y, p["/a/z"].y), "isolated nodes at the bottom of their band");
            compare(p["/b/lone1"].y, p["/b/lone2"].y);
            verify(p["/b/lone1"].x < p["/b/lone2"].x);
            compare(JSON.stringify(GraphLayout.layout(shuffled(nodes, 3), shuffled(edges, 4), opts)), JSON.stringify(p), "order independent");
        }
        function test_isolated_nodes_below_connected() {
            const nodes = ["/a", "/b", "/c", "/i1", "/i2", "/i3", "/i4", "/i5"];
            const p = GraphLayout.layout(nodes, [edge("/a", "/b"), edge("/b", "/c")], layoutOpts);
            verifyLayout(nodes, p);
            const isolated = ["/i1", "/i2", "/i3", "/i4", "/i5"];
            verify(Math.min(...isolated.map(id => p[id].y)) > Math.max(p["/a"].y, p["/b"].y, p["/c"].y));
            const readingOrder = isolated.slice().sort((a, b) => p[a].y - p[b].y || p[a].x - p[b].x);
            compare(readingOrder, isolated);
        }
        function test_layers_centered() {
            const p = GraphLayout.layout(["/a", "/b", "/c", "/d"], [edge("/a", "/b"), edge("/a", "/c"), edge("/a", "/d")], layoutOpts);
            compare(p["/a"].y, p["/c"].y, "a single node is centered on the taller layer");
        }
        function test_order_independent() {
            const g = randomGraph(80, 140, 7, false);
            const expected = JSON.stringify(GraphLayout.layout(g.nodes, g.edges, layoutOpts));
            for (let seed = 1; seed <= 3; ++seed)
                compare(JSON.stringify(GraphLayout.layout(shuffled(g.nodes, seed), shuffled(g.edges, seed + 10), layoutOpts)), expected);
        }
        function test_source_next_to_nearest_successor() {
            const p = GraphLayout.layout(["/a", "/b", "/c", "/d", "/x"], [edge("/a", "/b"), edge("/b", "/c"), edge("/c", "/d"), edge("/x", "/d")], layoutOpts);
            compare(p["/x"].x, p["/c"].x);
        }
        function test_timing_300_nodes() {
            const g = randomGraph(300, 650, 11, false);
            verifyLayout(g.nodes, GraphLayout.layout(g.nodes, g.edges, layoutOpts));
            // About 10 ms on a desktop; the budget leaves room for slow and busy CI runners.
            const ms = layoutMs(g);
            verify(ms < 100, "layout took " + ms + " ms");
        }
        function test_timing_grouped() {
            const g = randomGraph(300, 650, 11, false);
            const opts = Object.assign({
                "groupOf": id => "/g" + (Number(id.slice(2)) % 10)
            }, layoutOpts);
            verifyLayout(g.nodes, GraphLayout.layout(g.nodes, g.edges, opts));
            const ungrouped = layoutMs(g);
            const ms = layoutMs(g, opts);
            verify(ms < 4 * Math.max(5, ungrouped), "grouped layout took " + ms + " ms, ungrouped " + ungrouped + " ms");
        }
        function test_timing_many_components() {
            const split = {
                "nodes": [],
                "edges": []
            };
            for (let i = 0; i < 300; ++i) {
                split.nodes.push("/a" + i, "/b" + i);
                split.edges.push(edge("/a" + i, "/b" + i));
            }
            // Relative to a connected graph of similar size so that machine speed cancels out.
            const connected = layoutMs(randomGraph(300, 650, 11, false));
            const ms = layoutMs(split);
            verify(ms < 4 * Math.max(5, connected), "300 separate edges took " + ms + " ms, a connected graph " + connected + " ms");
        }

        // Every node has a finite position and no two node rectangles overlap.
        function verifyLayout(nodes, positions) {
            const w = layoutOpts.nodeWidth;
            const h = layoutOpts.nodeHeight;
            const p = nodes.map(id => positions[id]);
            for (let i = 0; i < p.length; ++i) {
                verify(Number.isFinite(p[i].x) && Number.isFinite(p[i].y), nodes[i] + " has a finite position");
                for (let j = i + 1; j < p.length; ++j)
                    verify(Math.abs(p[i].x - p[j].x) >= w || Math.abs(p[i].y - p[j].y) >= h, nodes[i] + " overlaps " + nodes[j]);
            }
        }

        name: "GraphLayout"
    }
    TestCase {
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            Ros2.reset();
        }
        function refreshed(iface) {
            iface.refresh();
            verify(iface.loading);
            tryVerify(() => !iface.loading);
            return iface;
        }
        function test_build_after_refresh() {
            Ros2.registerNode("/talker", nodeInfo(["/chatter"], []));
            Ros2.registerNode("/listener", nodeInfo([], ["/chatter"]));
            const iface = createTemporaryObject(interfaceComponent, root);
            compare(iface.graph, {
                "nodes": [],
                "edges": []
            });
            refreshed(iface);
            compare(iface.graph, {
                "nodes": ["/listener", "/talker"],
                "edges": [edge("/talker", "/listener", ["/chatter"])]
            });
        }
        function test_filter_toggle_rebuilds_without_query() {
            Ros2.registerNode("/a", nodeInfo(["/rosout", "/data"], []));
            Ros2.registerNode("/b", nodeInfo([], ["/rosout", "/data"]));
            const iface = refreshed(createTemporaryObject(interfaceComponent, root));
            compare(iface.graph.edges[0].interfaces.map(t => t.name), ["/data"]);
            Ros2.registerNode("/late", nodeInfo(["/data"], []));
            iface.hideCommon = false;
            verify(!iface.loading);
            compare(iface.graph.nodes, ["/a", "/b"]);
            compare(iface.graph.edges[0].interfaces.map(t => t.name), ["/data", "/rosout"]);
        }
        function test_hidden_nodes_filtered() {
            Ros2.registerNode("/talker", nodeInfo(["/chatter"], []));
            Ros2.registerNode("/_hidden_listener", nodeInfo([], ["/chatter"]));
            const iface = refreshed(createTemporaryObject(interfaceComponent, root));
            compare(iface.graph, {
                "nodes": ["/talker"],
                "edges": []
            });
            iface.hideHidden = false;
            compare(iface.graph.nodes, ["/_hidden_listener", "/talker"]);
            compare(iface.graph.edges.length, 1);
        }
        function test_own_node_left_out() {
            Ros2.registerNode("/talker", nodeInfo(["/chatter"], []));
            Ros2.registerNode("/rqml", nodeInfo([], ["/chatter"]));
            Ros2.registerNode("/ns/rqml", nodeInfo([], ["/chatter"]));
            const iface = refreshed(createTemporaryObject(interfaceComponent, root));
            compare(iface.graph.nodes, ["/ns/rqml", "/talker"]);
            iface.hideHidden = false;
            compare(iface.graph.nodes, ["/ns/rqml", "/talker"]);
        }
        function test_unconnected_counts_from_refresh() {
            Ros2.registerNode("/listener", nodeInfo([], ["/chatter", "/status"]));
            // RQml is left out of the graph, but its publisher still feeds /status.
            Ros2.registerNode("/rqml", nodeInfo(["/status"], []));
            const iface = refreshed(createTemporaryObject(interfaceComponent, root));
            compare(iface.unconnected, {
                "/listener": 1
            });
            // Like the rest of the graph, the counts only change on refresh().
            Ros2.registerNode("/other_listener", nodeInfo([], ["/chatter"]));
            compare(Object.keys(iface.unconnected), ["/listener"]);
        }

        name: "NodeGraphInterface"
    }
    TestCase {
        function createView(nodes, edges) {
            const view = createTemporaryObject(viewComponent, root, {
                "nodes": nodes,
                "edges": edges
            });
            tryVerify(() => view._testNodeRect(nodes[0]) !== null);
            return view;
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            RQml.resetClipboard();
        }
        function rectCenter(rect) {
            return Qt.point(rect.x + rect.width / 2, rect.y + rect.height / 2);
        }
        function test_badge_tooltip_and_copy_menu() {
            const view = createView(["/listener", "/talker"], [edge("/talker", "/listener", ["/chatter", "/status"])]);
            const badge = view._testBadgeCenter("/talker", "/listener");
            mouseMove(view, 0, 0); // entering the view is not a move
            mouseMove(view, badge.x, badge.y);
            const tooltip = helpers.findChild(view, "nmGraphToolTip");
            tryVerify(() => tooltip.visible);
            compare(tooltip.text, "/talker → /listener\nTopic /chatter [std_msgs/msg/String]\nTopic /status [std_msgs/msg/String]");
            mouseClick(view, badge.x, badge.y, Qt.RightButton);
            const menu = helpers.findChild(view, "nmGraphBadgeMenu");
            tryVerify(() => menu.opened);
            verify(!tooltip.visible, "tooltip closes when the menu opens");
            compare(menu.count, 2);
            compare(menu.itemAt(1).text, "Copy Topic /status");
            mouseClick(menu.itemAt(1));
            compare(RQml.clipboard, "/status");
        }
        function test_click_selects_node() {
            const view = createView(demoNodes, [edge("/talker", "/listener", ["/chatter"])]);
            const center = id => rectCenter(view._testNodeRect(id));
            const talker = center("/talker");
            mouseClick(view, talker.x, talker.y);
            compare(view._testSelectedNode(), "/talker");
            const listener = center("/listener");
            mouseClick(view, listener.x, listener.y);
            compare(view._testSelectedNode(), "/listener");
            mouseClick(view, 2, 2);
            compare(view._testSelectedNode(), "", "a click on the background clears the selection");
            mouseClick(view, talker.x, talker.y);
            mouseClick(view, listener.x, listener.y, Qt.RightButton);
            compare(view._testSelectedNode(), "/talker", "a right-click keeps the selection");
            const menu = helpers.findChild(view, "nmGraphNodeMenu");
            tryVerify(() => menu.opened);
            menu.close();
            tryVerify(() => !menu.visible);
            mousePress(view, listener.x, listener.y);
            mouseMove(view, listener.x + 10, listener.y + 40);
            mouseMove(view, listener.x + 20, listener.y + 80);
            mouseRelease(view, listener.x + 20, listener.y + 80);
            compare(view._testSelectedNode(), "/talker", "dragging a node keeps the selection");
            mousePress(view, 2, 2);
            mouseMove(view, 40, 40);
            mouseMove(view, 80, 80);
            mouseRelease(view, 80, 80);
            compare(view._testSelectedNode(), "/talker", "panning keeps the selection");
            keyClick(Qt.Key_Escape);
            compare(view._testSelectedNode(), "", "escape clears the selection");
            mouseClick(view, center("/talker").x, center("/talker").y);
            compare(view._testSelectedNode(), "/talker");
            view.edges = [];
            view.nodes = demoNodes.filter(id => id !== "/talker");
            tryCompare(view, "nodes", demoNodes.filter(id => id !== "/talker"));
            tryVerify(() => view._testSelectedNode() === "", 1000, "a removed node is unselected");
        }
        function test_double_click_node_requests_inspect() {
            const view = createView(demoNodes, []);
            const spy = createTemporaryObject(signalSpyComponent, root, {
                "target": view,
                "signalName": "inspectNodeRequested"
            });
            const center = rectCenter(view._testNodeRect("/robot/talker2"));
            mouseDoubleClickSequence(view, center.x, center.y);
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], "/robot/talker2");
            mouseDoubleClickSequence(view, center.x, center.y, Qt.RightButton);
            compare(spy.count, 1, "a right double-click does not inspect");
        }
        function test_drag_moves_node_until_relayout() {
            const edges = [edge("/talker", "/listener", ["/chatter"])];
            const view = createView(demoNodes, edges);
            const before = view._testNodeRect("/talker");
            const start = rectCenter(before);
            mousePress(view, start.x, start.y);
            mouseMove(view, start.x + 1, start.y + 1);
            compare(view._testNodeRect("/talker"), before, "no move below the drag distance");
            mouseMove(view, start.x + 10, start.y + 40);
            mouseMove(view, start.x + 20, start.y + 80);
            mouseRelease(view, start.x + 20, start.y + 80);
            const moved = view._testNodeRect("/talker");
            fuzzyCompare(moved.x - before.x, 20, 0.01);
            fuzzyCompare(moved.y - before.y, 80, 0.01);
            view.edges = edges.slice();
            tryVerify(() => view._testNodeRect("/talker").y === before.y, 1000, "relayout discards the dragged position");
        }
        function test_edge_kinds_in_tooltip_menu_and_legend() {
            const view = createView(["/client", "/server", "/talker"], [
                {
                    "from": "/client",
                    "to": "/server",
                    "interfaces": [link("action", "/nav"), link("service", "/add")]
                },
                {
                    "from": "/client",
                    "to": "/talker",
                    "interfaces": [link("service", "/talker/reset")]
                },
                edge("/talker", "/server", ["/t"])]);
            const legend = helpers.findChild(view, "nmGraphLegend");
            const legendLabels = () => Array.from(legend.children).filter(c => c.children.length === 2).map(row => row.children[1].text);
            verify(legend.visible);
            compare(legendLabels(), ["Topic", "Service", "Mixed"]);
            const badge = view._testBadgeCenter("/client", "/server");
            mouseMove(view, 0, 0);
            mouseMove(view, badge.x, badge.y);
            const tooltip = helpers.findChild(view, "nmGraphToolTip");
            tryVerify(() => tooltip.visible);
            compare(tooltip.text, "/client → /server\nAction /nav [std_msgs/msg/String]\nService /add [std_msgs/msg/String]");
            mouseClick(view, badge.x, badge.y, Qt.RightButton);
            const menu = helpers.findChild(view, "nmGraphBadgeMenu");
            tryVerify(() => menu.opened);
            compare(menu.itemAt(0).text, "Copy Action /nav");
            menu.close();
            view.edges = [edge("/talker", "/server", ["/t"])];
            tryVerify(() => !legend.visible, 1000, "no legend for topics only");
        }
        function test_edge_skipping_a_layer_avoids_node_in_between() {
            const view = createView(["/a", "/b", "/c"], [edge("/a", "/b", ["/ab"]), edge("/b", "/c", ["/bc"]), edge("/a", "/c", ["/ac"])]);
            const r = view._testNodeRect("/b");
            const badge = view._testBadgeCenter("/a", "/c");
            verify(badge.y < r.y || badge.y > r.y + r.height || badge.x < r.x || badge.x > r.x + r.width, "badge outside /b");
        }
        function test_empty_hints() {
            const view = createTemporaryObject(viewComponent, root);
            const hint = helpers.findChild(view, "nmGraphHint");
            verify(hint.visible);
            compare(hint.text, "No nodes found. Is ROS running?");
            view.hasUnfilteredNodes = true;
            compare(hint.text, "No nodes match the filters.");
            view.loading = true;
            verify(!hint.visible, "busy indicator instead");
            view.loading = false;
            view.nodes = ["/a"];
            verify(!hint.visible);
        }
        function test_fit_shows_demo_graph() {
            const view = createView(demoNodes, [edge("/talker", "/listener", ["/chatter"])]);
            verifyFitted(view, demoNodes);
        }
        function test_fit_shows_isolated_nodes() {
            const nodes = [];
            for (let i = 0; i < 30; ++i)
                nodes.push("/node_" + i);
            verifyFitted(createView(nodes, []), nodes);
        }
        function test_fit_waits_for_size() {
            const view = createTemporaryObject(viewComponent, root, {
                "width": 0,
                "height": 0,
                "nodes": demoNodes
            });
            tryVerify(() => view._testNodeRect("/talker") !== null);
            view.width = 1000;
            view.height = 600;
            verifyFitted(view, demoNodes);
        }
        function test_ignore_node_from_menu() {
            const view = createView(demoNodes, [edge("/talker", "/listener", ["/chatter"])]);
            const menu = helpers.findChild(view, "nmGraphNodeMenu");
            const toggle = id => {
                const center = rectCenter(view._testNodeRect(id));
                mouseClick(view, center.x, center.y, Qt.RightButton);
                tryVerify(() => menu.opened);
                const text = menu.itemAt(2).text;
                mouseClick(menu.itemAt(2));
                tryVerify(() => !menu.visible);
                return text;
            };
            compare(toggle("/talker"), "Ignore Node");
            compare(view.ignoredNodes, ["/talker"]);
            tryVerify(() => view._testBadgeCenter("/talker", "/listener") === null, 1000, "its edges are left out");
            const ignored = view._testNodeRect("/talker");
            for (const id of demoNodes.filter(id => id !== "/talker")) {
                const r = view._testNodeRect(id);
                verify(r.y + r.height < ignored.y, id + " above the ignored node");
            }
            verifyFitted(view, demoNodes);
            const center = rectCenter(ignored);
            mouseMove(view, 0, 0);
            mouseMove(view, center.x, center.y);
            const tooltip = helpers.findChild(view, "nmGraphToolTip");
            tryVerify(() => tooltip.visible);
            compare(tooltip.text, "/talker\nIgnored, its connections are not shown");
            compare(toggle("/talker"), "Stop Ignoring Node");
            compare(view.ignoredNodes, []);
            tryVerify(() => view._testBadgeCenter("/talker", "/listener") !== null, 1000, "its edges are back");
        }
        function test_ignored_nodes_below_namespace_boxes() {
            const view = createView(["/robot/a", "/robot/b", "/robot/c"], [edge("/robot/a", "/robot/b", ["/ab"])]);
            view.groupNamespaces = true;
            view.ignoredNodes = ["/gone", "/robot/c"];
            tryVerify(() => view._testNamespaceBoxes()["/robot"] !== undefined);
            const box = view._testNamespaceBoxes()["/robot"];
            const r = view._testNodeRect("/robot/c");
            verify(r.y > box.y + box.height, "ignored node below the box");
            compare(view._testNodeRect("/gone"), null, "ignored ids without a node are not laid out");
        }
        function test_namespace_boxes() {
            // /robot1/arm and /robot3 hold a single node, /robot4 only the /robot4/base box, the /swarm boxes nest three deep without nodes of their own.
            const nodes = ["/robot1/driver", "/robot1/planner", "/robot1/arm/gripper", "/robot1/sensors/camera", "/robot1/sensors/lidar", "/robot2/driver", "/robot2/lone", "/robot3/solo", "/robot4/base/a", "/robot4/base/b", "/swarm/l/l/x", "/swarm/l/l/y", "/swarm/l/r/x", "/swarm/l/r/y", "/swarm/r/l/x", "/swarm/r/l/y", "/swarm/r/r/x", "/swarm/r/r/y", "/rviz", "/lone"];
            const edges = [edge("/robot1/sensors/camera", "/robot1/planner", ["/image"]), edge("/robot1/sensors/lidar", "/robot1/planner", ["/scan"]), edge("/robot1/planner", "/robot1/driver", ["/cmd"]), edge("/robot1/planner", "/robot2/driver", ["/cmd2"]), edge("/rviz", "/robot1/planner", ["/goal"])];
            const view = createView(nodes, edges);
            compare(view._testNamespaceBoxes(), {}, "no boxes without grouping");
            const ungrouped = view._testNodeRect("/robot2/lone");
            view.groupNamespaces = true;
            tryVerify(() => view._testNodeRect("/robot2/lone").y !== ungrouped.y, 1000, "re-laid out");
            const boxes = view._testNamespaceBoxes();
            const namespaces = Object.keys(boxes).sort();
            compare(namespaces, ["/robot1", "/robot1/sensors", "/robot2", "/robot4/base", "/swarm", "/swarm/l", "/swarm/l/l", "/swarm/l/r", "/swarm/r", "/swarm/r/l", "/swarm/r/r"]);
            const inside = (r, box) => r.x >= box.x && r.y >= box.y && r.x + r.width <= box.x + box.width && r.y + r.height <= box.y + box.height;
            const intersects = (a, b) => a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height;
            const within = (id, ns) => id.startsWith(ns + "/");
            for (const id of nodes)
                for (const ns of namespaces)
                    compare(inside(view._testNodeRect(id), boxes[ns]), within(id, ns), id + (within(id, ns) ? " inside " : " outside ") + ns);
            for (let i = 0; i < namespaces.length; ++i)
                for (let j = i + 1; j < namespaces.length; ++j) {
                    const a = namespaces[i];
                    const b = namespaces[j];
                    if (within(b, a)) {
                        const outer = boxes[a];
                        const inner = boxes[b];
                        verify(inner.x > outer.x && inner.y > outer.y && inner.x + inner.width < outer.x + outer.width && inner.y + inner.height < outer.y + outer.height, b + " strictly inside " + a);
                    } else {
                        verify(!intersects(boxes[a], boxes[b]), a + " does not overlap " + b);
                    }
                }
            compare(view._testNodeLabel("/robot1/arm/gripper"), "arm/gripper", "relative to the box");
            compare(view._testNodeLabel("/robot1/sensors/camera"), "camera");
            compare(view._testNodeLabel("/robot3/solo"), "robot3/solo");
            compare(view._testNodeLabel("/robot4/base/a"), "a");
            compare(view._testNodeLabel("/lone"), "lone");
            const start = rectCenter(view._testNodeRect("/robot2/lone"));
            mousePress(view, start.x, start.y);
            mouseMove(view, start.x + 10, start.y + 40);
            mouseMove(view, start.x + 200, start.y + 80);
            mouseRelease(view, start.x + 200, start.y + 80);
            verify(inside(view._testNodeRect("/robot2/lone"), view._testNamespaceBoxes()["/robot2"]), "the box follows a dragged node");
        }
        function test_node_labels() {
            const longName = "/a_namespace_much_too_long_for_the_node_box/talker";
            const view = createView([longName, "/b/talker", "/listener"], []);
            compare(view._testNodeLabel("/b/talker"), "/b/talker", "short names that are not unique show the full name");
            compare(view._testNodeLabel("/listener"), "listener");
            const label = view._testNodeLabel(longName);
            verify(label.length < longName.length && label.endsWith("/talker"), "elided from the left: " + label);
        }
        function test_node_menu_actions() {
            const view = createView(demoNodes, []);
            const spy = createTemporaryObject(signalSpyComponent, root, {
                "target": view,
                "signalName": "inspectNodeRequested"
            });
            const center = rectCenter(view._testNodeRect("/robot/talker2"));
            const menu = helpers.findChild(view, "nmGraphNodeMenu");
            mouseClick(view, center.x, center.y, Qt.RightButton);
            tryVerify(() => menu.opened);
            compare(menu.itemAt(0).text, "Copy Node Name");
            mouseClick(menu.itemAt(0));
            compare(RQml.clipboard, "/robot/talker2");
            tryVerify(() => !menu.visible);
            mouseClick(view, center.x, center.y, Qt.RightButton);
            tryVerify(() => menu.opened);
            mouseClick(menu.itemAt(1));
            compare(spy.count, 1);
            compare(spy.signalArguments[0][0], "/robot/talker2");
        }
        function test_node_tooltip_counts() {
            const view = createView(demoNodes, [edge("/talker", "/listener", ["/chatter"])]);
            const center = rectCenter(view._testNodeRect("/talker"));
            mouseMove(view, 0, 0);
            mouseMove(view, center.x, center.y);
            const tooltip = helpers.findChild(view, "nmGraphToolTip");
            tryVerify(() => tooltip.visible);
            compare(tooltip.text, "/talker\nOutgoing: 1\nIncoming: 0");
            view.unconnected = {
                "/talker": 2
            };
            compare(tooltip.text, "/talker\nOutgoing: 1\nIncoming: 0\n2 subscriptions or clients have no publisher or server");
        }
        function test_search_jump_cycles_through_matches() {
            const nodes = ["/camera/driver", "/camera/rectify", "/front_camera", "/lidar", "/planner"];
            const view = createView(nodes, [edge("/camera/driver", "/camera/rectify", ["/image"])]);
            const centered = () => nodes.find(id => {
                    const c = rectCenter(view._testNodeRect(id));
                    return Math.abs(c.x - view.width / 2) < 0.5 && Math.abs(c.y - view.height / 2) < 0.5;
                });
            view.searchText = "camera";
            const visited = [];
            for (let i = 0; i < 4; ++i) {
                view.jumpToNextMatch(true);
                visited.push(centered());
            }
            compare(visited, ["/camera/driver", "/camera/rectify", "/front_camera", "/camera/driver"]);
            view.jumpToNextMatch(false);
            compare(centered(), "/front_camera");
            view.searchText = "nothing";
            view.jumpToNextMatch(true);
            compare(centered(), "/front_camera");
        }
        function test_search_jump_zooms_to_legible_scale() {
            const nodes = ["/front_camera"];
            for (let i = 0; i < 100; ++i)
                nodes.push("/node_" + i);
            const view = createView(nodes, []);
            verify(view._testNodeRect("/front_camera").height < 15, "precondition: fit scale too small for labels");
            view.searchText = "camera";
            view.jumpToNextMatch(true);
            const r = view._testNodeRect("/front_camera");
            verify(r.height >= 15, "match legible");
            compare(rectCenter(r), Qt.point(view.width / 2, view.height / 2));
        }
        function test_unchanged_graph_keeps_zoom() {
            const edges = [edge("/talker", "/listener", ["/chatter"])];
            const view = createView(demoNodes, edges);
            const center = rectCenter(view._testNodeRect("/talker"));
            mouseWheel(view, center.x, center.y, 0, 360);
            const zoomed = view._testNodeRect("/talker");
            view.nodes = demoNodes.slice();
            view.edges = JSON.parse(JSON.stringify(edges));
            wait(50);
            compare(view._testNodeRect("/talker"), zoomed, "an equal graph keeps zoom and pan");
            view.edges = [];
            tryVerify(() => view._testNodeRect("/talker").width < zoomed.width, 1000, "a changed layout fits again");
        }
        function test_wheel_zooms_at_cursor() {
            const view = createView(demoNodes, []);
            const before = view._testNodeRect("/talker");
            const center = rectCenter(before);
            mouseWheel(view, center.x, center.y, 120, 0);
            compare(view._testNodeRect("/talker"), before, "horizontal scrolling does not zoom");
            mouseWheel(view, center.x, center.y, 0, 120);
            const after = view._testNodeRect("/talker");
            fuzzyCompare(after.width, before.width * 1.2, 0.01);
            fuzzyCompare(rectCenter(after).x, center.x, 0.01);
            fuzzyCompare(rectCenter(after).y, center.y, 0.01);
        }
        function test_zoom_limited() {
            const view = createView(demoNodes, []);
            const center = rectCenter(view._testNodeRect("/talker"));
            for (let i = 0; i < 10; ++i)
                mouseWheel(view, center.x, center.y, 0, 360);
            fuzzyCompare(view._testNodeRect("/talker").width, 150 * 3, 0.01);
            for (let i = 0; i < 20; ++i)
                mouseWheel(view, center.x, center.y, 0, -360);
            fuzzyCompare(view._testNodeRect("/talker").width, 150 * 0.1, 0.01);
        }

        // Every node lies inside the view at a legible size.
        function verifyFitted(view, nodes) {
            for (const id of nodes) {
                const r = view._testNodeRect(id);
                verify(r.x >= 0 && r.y >= 0 && r.x + r.width <= view.width && r.y + r.height <= view.height, id + " inside the view");
                verify(r.height >= 15, id + " legible");
            }
        }

        name: "NodeGraphView"
        when: windowShown
    }
    Component {
        id: signalSpyComponent

        SignalSpy {
        }
    }
    TestCase {
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            Ros2.reset();
            contextObj.graphGroupNamespaces = undefined;
            contextObj.graphHideCommon = undefined;
            contextObj.graphHideTf = undefined;
            contextObj.graphIgnoredNodes = undefined;
            contextObj.graphShowActions = undefined;
            contextObj.graphShowServices = undefined;
            contextObj.graphShowTopics = undefined;
            contextObj.hideHiddenNodes = undefined;
            Ros2.registerNode("/talker", nodeInfo(["/chatter", "/rosout", "/tf"], []));
            Ros2.registerNode("/_hidden", nodeInfo([], ["/chatter", "/rosout", "/tf"]));
        }
        function test_builds_when_first_shown_and_on_refresh() {
            const tab = createTemporaryObject(tabComponent, root, {
                "visible": false
            });
            const view = helpers.findChild(tab, "nmGraphView");
            wait(100);
            compare(view.nodes, [], "a hidden tab does not query ROS");
            tab.visible = true;
            tryCompare(view, "nodes", ["/talker"]);
            Ros2.registerNode("/listener", nodeInfo([], ["/chatter"]));
            tab.visible = false;
            tab.visible = true;
            wait(100);
            compare(view.nodes, ["/talker"], "only the first show builds");
            mouseClick(helpers.findChild(tab, "nmGraphRefreshButton"));
            tryCompare(view, "nodes", ["/listener", "/talker"]);
        }
        function test_checkboxes_write_context() {
            const tab = createTemporaryObject(tabComponent, root, {
                "visible": false
            });
            tab.visible = true;
            const view = helpers.findChild(tab, "nmGraphView");
            const topics = () => view.edges[0].interfaces.map(t => t.name);
            tryCompare(view, "nodes", ["/talker"]);
            mouseClick(helpers.findChild(tab, "nmGraphHideHiddenCheckBox"));
            compare(contextObj.hideHiddenNodes, false);
            compare(view.nodes, ["/_hidden", "/talker"]);
            compare(topics(), ["/chatter"]);
            verify(!view.loading, "toggling does not query ROS");
            mouseClick(helpers.findChild(tab, "nmGraphHideCommonCheckBox"));
            compare(contextObj.graphHideCommon, false);
            compare(topics(), ["/chatter", "/rosout"]);
            mouseClick(helpers.findChild(tab, "nmGraphHideTfCheckBox"));
            compare(contextObj.graphHideTf, false);
            compare(topics(), ["/chatter", "/rosout", "/tf"]);
            mouseClick(helpers.findChild(tab, "nmGraphShowTopicsCheckBox"));
            compare(contextObj.graphShowTopics, false);
            compare(view.edges, []);
            contextObj.hideHiddenNodes = true;
            compare(view.nodes, ["/talker"]);
        }
        function test_empty_hint_tells_filters_from_no_nodes() {
            Ros2.reset();
            Ros2.registerNode("/_hidden", nodeInfo([], []));
            const tab = createTemporaryObject(tabComponent, root, {
                "visible": false
            });
            tab.visible = true;
            const hint = helpers.findChild(tab, "nmGraphHint");
            tryVerify(() => hint.visible);
            compare(hint.text, "No nodes match the filters.");
            Ros2.reset();
            mouseClick(helpers.findChild(tab, "nmGraphRefreshButton"));
            tryVerify(() => hint.visible && hint.text === "No nodes found. Is ROS running?");
        }
        function test_group_and_interface_checkboxes() {
            Ros2.registerNode("/robot/server", nodeInfo([], [], {
                "serviceServers": ["/robot/server/get_parameters", "/add"],
                "actionServers": ["/nav"]
            }));
            Ros2.registerNode("/robot/client", nodeInfo([], [], {
                "serviceClients": ["/robot/server/get_parameters", "/add"],
                "actionClients": ["/nav"]
            }));
            const tab = createTemporaryObject(tabComponent, root, {
                "visible": false
            });
            tab.visible = true;
            const view = helpers.findChild(tab, "nmGraphView");
            tryCompare(view, "nodes", ["/robot/client", "/robot/server", "/talker"]);
            compare(view.edges, []);
            mouseClick(helpers.findChild(tab, "nmGraphShowServicesCheckBox"));
            compare(contextObj.graphShowServices, true);
            verify(!view.loading, "toggling does not query ROS");
            compare(view.edges, [
                {
                    "from": "/robot/client",
                    "to": "/robot/server",
                    "interfaces": [link("service", "/add")]
                }
            ], "default services hidden with the common topics");
            mouseClick(helpers.findChild(tab, "nmGraphShowActionsCheckBox"));
            compare(contextObj.graphShowActions, true);
            compare(view.edges[0].interfaces.map(i => i.kind + " " + i.name), ["action /nav", "service /add"]);
            mouseClick(helpers.findChild(tab, "nmGraphHideCommonCheckBox"));
            compare(view.edges[0].interfaces.length, 3);
            verify(!view.groupNamespaces);
            mouseClick(helpers.findChild(tab, "nmGraphGroupNamespacesCheckBox"));
            compare(contextObj.graphGroupNamespaces, true);
            verify(view.groupNamespaces);
            tryVerify(() => view._testNamespaceBoxes()["/robot"] !== undefined);
        }
        function test_ignored_nodes_written_to_context() {
            contextObj.graphIgnoredNodes = ["/gone"];
            const tab = createTemporaryObject(tabComponent, root, {
                "visible": false
            });
            tab.visible = true;
            const view = helpers.findChild(tab, "nmGraphView");
            tryCompare(view, "nodes", ["/talker"]);
            compare(view.ignoredNodes, ["/gone"]);
            tryVerify(() => view._testNodeRect("/talker") !== null);
            const r = view._testNodeRect("/talker");
            mouseClick(view, r.x + r.width / 2, r.y + r.height / 2, Qt.RightButton);
            const menu = helpers.findChild(view, "nmGraphNodeMenu");
            tryVerify(() => menu.opened);
            mouseClick(menu.itemAt(2));
            compare(contextObj.graphIgnoredNodes, ["/gone", "/talker"]);
        }

        name: "NodeGraphTab"
        when: windowShown
    }
}
