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
import QtQuick.Controls
import QtTest
import Ros2
import "../qml/elements"
import "../qml/interfaces"

Item {
    id: root

    property var context: contextObj

    height: 400
    width: 400

    // The lifecycle tab persists no context keys.
    QtObject {
        id: contextObj

    }
    Utils {
        id: helpers

    }

    // Lifecycle nodes served through the Ros2 mock, following the standard lifecycle state machine.
    QtObject {
        id: fake

        //! Services whose requests never get a response.
        property var hanging: []
        //! Services without a handler, so their requests get a null response.
        property var missing: []
        //! Whether change_state answers success == false.
        property bool reject: false

        //! Requests per service name.
        property var requests: ({})
        //! State label per node name.
        property var states: ({})
        readonly property var transitions: ({
                "unconfigured": [
                    {
                        "id": 1,
                        "label": "configure",
                        "goal": "inactive"
                    },
                    {
                        "id": 5,
                        "label": "shutdown",
                        "goal": "finalized"
                    }
                ],
                "inactive": [
                    {
                        "id": 2,
                        "label": "cleanup",
                        "goal": "unconfigured"
                    },
                    {
                        "id": 3,
                        "label": "activate",
                        "goal": "active"
                    },
                    {
                        "id": 6,
                        "label": "shutdown",
                        "goal": "finalized"
                    }
                ],
                "active": [
                    {
                        "id": 4,
                        "label": "deactivate",
                        "goal": "inactive"
                    },
                    {
                        "id": 7,
                        "label": "shutdown",
                        "goal": "finalized"
                    }
                ],
                "finalized": []
            })

        function add(node, state) {
            fake.states[node] = state;
            Ros2.registerNode(node);
            serve(node + "/get_state", "lifecycle_msgs/srv/GetState", () => ({
                        "current_state": {
                            "label": fake.states[node]
                        }
                    }));
            serve(node + "/get_available_transitions", "lifecycle_msgs/srv/GetAvailableTransitions", () => ({
                        "available_transitions": fake.transitions[fake.states[node]].map(t => ({
                                    "transition": {
                                        "id": t.id,
                                        "label": t.label
                                    }
                                }))
                    }));
            serve(node + "/change_state", "lifecycle_msgs/srv/ChangeState", request => {
                const transition = fake.transitions[fake.states[node]].find(t => t.id === request.transition.id);
                if (fake.reject || !transition)
                    return {
                        "success": false
                    };
                fake.states[node] = transition.goal;
                return {
                    "success": true
                };
            });
        }
        function count(service) {
            return (fake.requests[service] || []).length;
        }
        function remove(node) {
            // The mock cannot unregister single nodes or services, so rebuild it without this node.
            const states = fake.states;
            delete states[node];
            Ros2.reset();
            for (const name in states)
                add(name, states[name]);
        }
        function reset() {
            fake.requests = {};
            fake.hanging = [];
            fake.missing = [];
            fake.reject = false;
            fake.states = {};
        }
        function serve(service, type, respond) {
            Ros2.registerService(service, type, fake.missing.includes(service) ? null : request => {
                (fake.requests[service] = fake.requests[service] || []).push(request);
                return fake.hanging.includes(service) ? {
                    "#hang": true
                } : respond(request);
            });
        }
    }
    Component {
        id: ifaceComponent

        LifecycleInterface {
        }
    }
    SignalSpy {
        id: failedSpy

        signalName: "transitionFailed"
    }
    TestCase {
        id: ifaceTest

        property var iface
        property QtObject subA
        property QtObject subB

        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            Ros2.reset();
            fake.reset();
            iface = createTemporaryObject(ifaceComponent, root);
            failedSpy.target = iface;
            failedSpy.clear();
        }
        function rows() {
            const result = [];
            for (let i = 0; i < iface.nodes.count; ++i)
                result.push(iface.nodes.get(i).name + " " + iface.nodes.get(i).state);
            return result;
        }
        function test_discovers_sorted_nodes_with_states() {
            fake.add("/c", "active");
            fake.add("/a", "unconfigured");
            fake.add("/ns/b", "inactive");
            iface.refresh();
            compare(rows(), ["/a unknown", "/c unknown", "/ns/b unknown"]);
            tryVerify(() => !rows().some(row => row.endsWith("unknown")));
            compare(rows(), ["/a unconfigured", "/c active", "/ns/b inactive"]);
        }
        function test_hides_callback_transitions() {
            fake.add("/a", "inactive");
            // Ids from 10 up are internal callback transitions, offered e.g. while the node is configuring.
            Ros2.registerService("/a/get_available_transitions", "lifecycle_msgs/srv/GetAvailableTransitions", () => ({
                        "available_transitions": [10, 3, 12].map(id => ({
                                    "transition": {
                                        "id": id,
                                        "label": id === 3 ? "activate" : "transition_success"
                                    }
                                }))
                    }));
            iface.refresh();
            iface.selectNode("/a");
            tryCompare(iface, "availableTransitions", [
                {
                    "id": 3,
                    "label": "activate"
                }
            ]);
        }
        function test_ignores_node_with_only_a_client_of_its_service() {
            fake.add("/b", "inactive");
            // E.g. our client of a lifecycle node that restarted without lifecycle under the same name.
            Ros2.registerNode("/a", {
                "serviceServers": []
            });
            Ros2.registerService("/a/change_state", "lifecycle_msgs/srv/ChangeState");
            iface.refresh();
            compare(rows().map(row => row.split(" ")[0]), ["/b"]);
        }
        function test_ignores_non_conforming_service_names() {
            fake.add("/a", "active");
            Ros2.registerNode("/robot/a");
            Ros2.registerService("/robot/a/sub/change_state", "lifecycle_msgs/srv/ChangeState");
            Ros2.registerService("/change_state", "lifecycle_msgs/srv/ChangeState");
            iface.refresh();
            compare(rows(), ["/a unknown"]);
        }
        function test_ignores_service_of_vanished_node() {
            fake.add("/a", "active");
            fake.add("/b", "inactive");
            iface.refresh();
            tryCompare(iface.nodes.get(0), "state", "active");
            fake.remove("/a");
            // A service client, e.g. our own, keeps the service listed after its node is gone.
            Ros2.registerService("/a/change_state", "lifecycle_msgs/srv/ChangeState");
            iface.refresh();
            compare(rows().map(row => row.split(" ")[0]), ["/b"]);
        }
        function test_lost_transition_fails_after_timeout() {
            fake.add("/a", "unconfigured");
            fake.hanging = ["/a/change_state"];
            iface.refresh();
            iface.triggerTransition("/a", fake.transitions.unconfigured[0]);
            tryVerify(() => fake.count("/a/change_state") === 1);
            iface.refresh();
            compare(iface.nodes.get(0).pending, "configure");
            const stateQueries = fake.count("/a/get_state");
            // The node restarted under the same name, so the request is never answered.
            iface.responseTimeout = 10;
            // Fails without a refresh, as the graph may not change.
            tryCompare(failedSpy, "count", 1);
            compare(iface.nodes.get(0).pending, "");
            compare(Array.from(failedSpy.signalArguments[0]), ["/a", "configure"]);
            iface.refresh();
            tryVerify(() => fake.count("/a/get_state") === stateQueries + 1);
            iface.refresh();
            compare(failedSpy.count, 1);
        }
        function test_missing_response_fails_once() {
            fake.missing = ["/a/change_state"];
            fake.add("/a", "unconfigured");
            iface.refresh();
            // A retry would log a second warning.
            ignoreWarning(/No handler registered for service: "\/a\/change_state"/);
            failOnWarning(/No handler registered for service: "\/a\/change_state"/);
            iface.triggerTransition("/a", fake.transitions.unconfigured[0]);
            tryCompare(failedSpy, "count", 1);
            compare(Array.from(failedSpy.signalArguments[0]), ["/a", "configure"]);
            compare(iface.nodes.get(0).pending, "");
            wait(20);
            compare(failedSpy.count, 1);
        }
        function test_pending_transition_fails_when_node_vanishes() {
            fake.add("/a", "unconfigured");
            fake.add("/b", "inactive");
            fake.hanging = ["/a/change_state"];
            iface.refresh();
            tryCompare(iface.nodes.get(0), "state", "unconfigured");
            iface.selectNode("/a");
            tryVerify(() => iface.availableTransitions.length === 2);
            iface.triggerTransition("/a", fake.transitions.unconfigured[0]);
            tryVerify(() => fake.count("/a/change_state") === 1);
            fake.remove("/a");
            iface.refresh();
            compare(iface.selectedNode, "");
            compare(iface.availableTransitions, []);
            compare(failedSpy.count, 1);
            compare(Array.from(failedSpy.signalArguments[0]), ["/a", "configure"]);
            compare(rows().map(row => row.split(" ")[0]), ["/b"]);
            iface.refresh();
            compare(failedSpy.count, 1);
        }
        function test_reconcile_keeps_states_removes_and_inserts_sorted() {
            fake.add("/b", "inactive");
            fake.add("/d", "active");
            iface.refresh();
            tryVerify(() => !rows().some(row => row.endsWith("unknown")));
            fake.remove("/d");
            fake.add("/c", "unconfigured");
            fake.add("/a", "active");
            iface.refresh();
            compare(rows(), ["/a unknown", "/b inactive", "/c unknown"]);
            tryVerify(() => !rows().some(row => row.endsWith("unknown")));
            compare(rows(), ["/a active", "/b inactive", "/c unconfigured"]);
            compare(fake.count("/b/get_state"), 2);
        }
        function test_refresh_detects_restart() {
            fake.add("/a", "active");
            iface.refresh();
            tryCompare(iface.nodes.get(0), "state", "active");
            // Restarted between refreshes: same name, no transition event.
            fake.states["/a"] = "unconfigured";
            iface.refresh();
            tryCompare(iface.nodes.get(0), "state", "unconfigured");
            compare(fake.count("/a/get_state"), 2);
        }
        function test_refresh_retries_unknown_state() {
            fake.missing = ["/a/get_state"];
            fake.add("/a", "active");
            iface.refresh();
            wait(20);
            compare(iface.nodes.get(0).state, "unknown");
            fake.missing = [];
            fake.serve("/a/get_state", "lifecycle_msgs/srv/GetState", () => ({
                        "current_state": {
                            "label": fake.states["/a"]
                        }
                    }));
            iface.refresh();
            tryCompare(iface.nodes.get(0), "state", "active");
        }
        function test_refresh_states_queries_all_nodes() {
            fake.add("/a", "active");
            fake.add("/b", "inactive");
            iface.refresh();
            tryVerify(() => !rows().some(row => row.endsWith("unknown")));
            // A dropped transition event leaves the state stale.
            fake.states["/a"] = "inactive";
            fake.states["/b"] = "active";
            iface.refreshStates();
            tryCompare(iface.nodes.get(0), "state", "inactive");
            tryCompare(iface.nodes.get(1), "state", "active");
            compare(fake.count("/a/get_state"), 2);
            compare(fake.count("/b/get_state"), 2);
        }
        function test_rejected_transition_fails_once() {
            fake.add("/a", "unconfigured");
            fake.reject = true;
            iface.refresh();
            iface.triggerTransition("/a", fake.transitions.unconfigured[0]);
            tryCompare(failedSpy, "count", 1);
            compare(Array.from(failedSpy.signalArguments[0]), ["/a", "configure"]);
            compare(iface.nodes.get(0).pending, "");
            wait(20);
            compare(fake.count("/a/change_state"), 1);
            compare(failedSpy.count, 1);
        }
        function test_reply_after_vanish_is_ignored() {
            fake.add("/a", "unconfigured");
            iface.refresh();
            // The node vanishes while handling the request, so refresh() reports the failure before the reply arrives.
            Ros2.registerService("/a/change_state", "lifecycle_msgs/srv/ChangeState", () => {
                fake.remove("/a");
                iface.refresh();
                return {
                    "success": false
                };
            });
            iface.triggerTransition("/a", fake.transitions.unconfigured[0]);
            tryCompare(failedSpy, "count", 1);
            wait(20);
            compare(failedSpy.count, 1);
            compare(iface.nodes.count, 0);
        }
        function test_returning_node_is_queried_despite_lost_request() {
            fake.add("/a", "active");
            fake.hanging = ["/a/get_state"];
            iface.refresh();
            tryVerify(() => fake.count("/a/get_state") === 1);
            // The node is restarted, so the request is never answered.
            fake.remove("/a");
            iface.refresh();
            compare(iface.nodes.count, 0);
            fake.hanging = [];
            fake.add("/a", "unconfigured");
            iface.refresh();
            tryCompare(iface.nodes.get(0), "state", "unconfigured");
        }
        function test_select_node_queries_transitions() {
            fake.add("/a", "unconfigured");
            iface.refresh();
            iface.selectNode("/a");
            compare(iface.availableTransitions, []);
            tryCompare(iface, "availableTransitions", [
                {
                    "id": 1,
                    "label": "configure"
                },
                {
                    "id": 5,
                    "label": "shutdown"
                }
            ]);
        }
        function test_skips_state_query_while_pending_until_lost() {
            fake.add("/a", "active");
            fake.hanging = ["/a/get_state"];
            iface.refresh();
            tryVerify(() => fake.count("/a/get_state") === 1);
            iface.refreshStates();
            wait(20);
            compare(fake.count("/a/get_state"), 1);
            // The node restarted under the same name, so the request is never answered.
            fake.hanging = [];
            fake.states["/a"] = "unconfigured";
            iface.responseTimeout = 10;
            wait(20);
            iface.refreshStates();
            tryCompare(iface.nodes.get(0), "state", "unconfigured");
            compare(fake.count("/a/get_state"), 2);
        }
        function test_stale_transitions_ignored_after_reselection() {
            fake.add("/a", "unconfigured");
            fake.add("/b", "inactive");
            fake.hanging = ["/b/get_available_transitions"];
            iface.refresh();
            iface.selectNode("/a");
            iface.selectNode("/b");
            tryVerify(() => fake.count("/a/get_available_transitions") === 1);
            compare(iface.availableTransitions, []);
        }
        function test_transition_events_update_each_node() {
            fake.add("/a", "unconfigured");
            fake.add("/b", "inactive");
            iface.refresh();
            tryVerify(() => !rows().some(row => row.endsWith("unknown")));
            iface.selectNode("/a");
            tryVerify(() => iface.availableTransitions.length === 2);
            const transitionQueries = fake.count("/a/get_available_transitions");
            Ros2.findSubscription("/b/transition_event").injectMessage({
                "goal_state": {
                    "label": "active"
                }
            });
            compare(rows(), ["/a unconfigured", "/b active"]);
            fake.states["/a"] = "inactive";
            Ros2.findSubscription("/a/transition_event").injectMessage({
                "goal_state": {
                    "label": "inactive"
                }
            });
            compare(rows(), ["/a inactive", "/b active"]);
            tryVerify(() => iface.availableTransitions.length === 3);
            compare(fake.count("/a/get_available_transitions"), transitionQueries + 1);
            compare(fake.count("/a/get_state"), 1);
            compare(fake.count("/b/get_state"), 1);
        }
        function test_transitions_on_two_nodes_are_independent() {
            fake.add("/a", "unconfigured");
            fake.add("/b", "inactive");
            fake.hanging = ["/a/change_state"];
            iface.refresh();
            iface.triggerTransition("/a", fake.transitions.unconfigured[0]);
            iface.triggerTransition("/b", fake.transitions.inactive[1]);
            compare(iface.nodes.get(0).pending, "configure");
            compare(iface.nodes.get(1).pending, "activate");
            tryCompare(iface.nodes.get(1), "pending", "");
            tryCompare(iface.nodes.get(1), "state", "active");
            compare(iface.nodes.get(0).pending, "configure");
            iface.responseTimeout = 10;
            wait(20);
            iface.refresh();
            compare(iface.nodes.get(0).pending, "");
            compare(failedSpy.count, 1);
            compare(Array.from(failedSpy.signalArguments[0]), ["/a", "configure"]);
        }
        function test_trigger_transition_succeeds() {
            fake.add("/a", "unconfigured");
            iface.refresh();
            iface.selectNode("/a");
            tryVerify(() => iface.availableTransitions.length === 2);
            const stateQueries = fake.count("/a/get_state");
            iface.triggerTransition("/a", iface.availableTransitions[0]);
            compare(iface.nodes.get(0).pending, "configure");
            tryCompare(iface.nodes.get(0), "pending", "");
            compare(fake.requests["/a/change_state"], [
                {
                    "transition": {
                        "id": 1,
                        "label": ""
                    }
                }
            ]);
            tryCompare(iface.nodes.get(0), "state", "inactive");
            verify(fake.count("/a/get_state") > stateQueries, "state re-queried");
            tryVerify(() => iface.availableTransitions.length === 3);
            compare(iface.availableTransitions.map(t => t.label), ["cleanup", "activate", "shutdown"]);
            compare(failedSpy.count, 0);
        }
        function test_vanished_node_unsubscribes() {
            fake.add("/a", "active");
            fake.add("/b", "inactive");
            iface.refresh();
            tryVerify(() => !rows().some(row => row.endsWith("unknown")));
            // Guarded properties turn null when the subscription is destroyed; the mock forgets subscriptions on reset.
            subA = Ros2.findSubscription("/a/transition_event");
            subB = Ros2.findSubscription("/b/transition_event");
            verify(subA && subB);
            fake.remove("/a");
            iface.refresh();
            tryCompare(ifaceTest, "subA", null);
            verify(subB);
        }

        name: "LifecycleInterface"
    }
    Component {
        id: tabComponent

        LifecycleTab {
            anchors.fill: parent
            toasts: toastStub
        }
    }
    QtObject {
        id: toastStub

        property var shown: []

        function show(message, level) {
            toastStub.shown.push(level + ": " + message);
        }
    }
    TestCase {
        id: tabTest

        property var list
        property var tab

        // Triggers a menu item from the keyboard; clicks would race the popup moving after late insertions.
        function activate(menu, index) {
            menu.currentIndex = index;
            keyClick(Qt.Key_Space);
        }
        function closeMenu(menu) {
            menu.close();
            tryVerify(() => !menu.visible);
        }
        function filter(text) {
            const searchBar = helpers.findChild(tab, "nmLifecycleSearchBar");
            helpers.findChild(searchBar, "searchBarTextField").text = text;
            searchBar.commitSearchText();
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            Ros2.reset();
            fake.reset();
            toastStub.shown = [];
            RQml.resetClipboard();
            fake.add("/b", "inactive");
            fake.add("/a", "unconfigured");
            tab = createTemporaryObject(tabComponent, root);
            list = helpers.findChild(tab, "nmLifecycleList");
            tab.refresh();
            tryVerify(() => list.itemAtIndex(1) !== null);
        }
        function menuTexts(menu) {
            const texts = [];
            for (let i = 0; i < menu.count; ++i)
                texts.push(menu.itemAt(i).text ?? "-");
            return texts;
        }
        // Opens the row's menu and waits until it lists `count` items.
        function openMenu(index, count) {
            const row = list.itemAtIndex(index);
            const menu = helpers.findChild(row, "nmLifecycleContextMenu").menu;
            mouseClick(helpers.findChild(row, "nmLifecycleMenuButton"));
            tryVerify(() => menu.opened);
            tryCompare(menu, "count", count);
            // Apply the items inserted after opening as the next frame would; Qt 6.4 menus log a binding loop otherwise.
            menu.contentItem.forceLayout();
            return menu;
        }
        function test_created_outside_window() {
            // The plugin host creates the plugin without a parent and moves it into the window afterwards.
            const orphan = createTemporaryObject(tabComponent, null);
            orphan.parent = root;
            verify(helpers.findChild(orphan, "nmShutdownDialog").width < root.width);
        }
        function test_empty_hints() {
            const hint = helpers.findChild(tab, "nmLifecycleHint");
            verify(!hint.visible);
            filter("zzz");
            verify(hint.visible);
            compare(hint.text, "No lifecycle nodes match the filter.");
            filter("");
            verify(!hint.visible);
            fake.remove("/a");
            fake.remove("/b");
            tab.refresh();
            compare(list.count, 0);
            verify(hint.visible);
            compare(hint.text, "No lifecycle nodes found.");
        }
        function test_failed_transition_shows_error_toast() {
            fake.reject = true;
            const menu = openMenu(0, 4);
            activate(menu, 0);
            tryCompare(toastStub.shown, "length", 1);
            compare(toastStub.shown, ["error: Failed to configure /a"]);
        }
        function test_filter_hides_rows() {
            filter("B");
            verify(!list.itemAtIndex(0).visible);
            compare(list.itemAtIndex(0).height, 0);
            verify(list.itemAtIndex(1).visible);
            filter("");
            verify(list.itemAtIndex(0).visible);
        }
        function test_menu_lists_transitions_of_row() {
            let menu = openMenu(1, 5);
            compare(menuTexts(menu), ["Cleanup", "Activate", "Shutdown", "-", "Copy Node Name"]);
            closeMenu(menu);
            menu = openMenu(0, 4);
            compare(menuTexts(menu), ["Configure", "Shutdown", "-", "Copy Node Name"]);
            activate(menu, 3);
            compare(RQml.clipboard, "/a");
        }
        function test_pending_transition_shows_busy_and_disables_its_row() {
            fake.hanging = ["/a/change_state"];
            let menu = openMenu(0, 4);
            activate(menu, 0);
            tryVerify(() => fake.count("/a/change_state") === 1);
            compare(fake.requests["/a/change_state"][0].transition.id, 1);
            verify(helpers.findChild(list.itemAtIndex(0), "nmLifecycleBusyIndicator").visible);
            verify(!helpers.findChild(list.itemAtIndex(1), "nmLifecycleBusyIndicator").visible);
            tryVerify(() => !menu.visible);
            menu = openMenu(0, 4);
            verify(!menu.itemAt(0).enabled, "transitions are disabled while one is pending");
            verify(menu.itemAt(3).enabled, "copying stays enabled");
            closeMenu(menu);
            menu = openMenu(1, 5);
            verify(menu.itemAt(0).enabled, "other nodes stay enabled");
        }
        function test_refresh_button_queries_states() {
            tryVerify(() => fake.count("/a/get_state") === 1 && fake.count("/b/get_state") === 1);
            fake.states["/a"] = "inactive";
            mouseClick(helpers.findChild(tab, "nmLifecycleRefreshButton"));
            tryCompare(list.itemAtIndex(0).model, "state", "inactive");
            compare(fake.count("/b/get_state"), 2);
        }
        function test_refresh_keeps_delegates_and_open_menu() {
            const first = list.itemAtIndex(0);
            const menu = openMenu(0, 4);
            tab.refresh();
            wait(20);
            compare(list.itemAtIndex(0), first);
            verify(menu.opened);
            compare(menu.count, 4);
        }
        function test_shutdown_requires_confirmation() {
            const dialog = helpers.findChild(tab, "nmShutdownDialog");
            let menu = openMenu(0, 4);
            activate(menu, 1);
            tryVerify(() => dialog.opened);
            compare(dialog.contentChildren[0].text, "Shut down /a?");
            compare(fake.count("/a/change_state"), 0);
            mouseClick(dialog.standardButton(Dialog.No));
            tryVerify(() => !dialog.visible);
            wait(20);
            compare(fake.count("/a/change_state"), 0);
            menu = openMenu(0, 4);
            activate(menu, 1);
            tryVerify(() => dialog.opened);
            mouseClick(dialog.standardButton(Dialog.Yes));
            tryVerify(() => fake.count("/a/change_state") === 1);
            compare(fake.requests["/a/change_state"][0].transition.id, 5);
        }

        name: "LifecycleTab"
        when: windowShown
    }
}
