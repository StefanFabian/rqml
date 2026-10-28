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
import "../qml/elements/ParameterParser.js" as ParameterParser
import "../qml/interfaces"

Item {
    id: root

    property var context: contextObj

    //! Requests received by the fake container services, by service name.
    property var requests: ({})

    //! Component fixture as listed by a container.
    readonly property var talker: ({
            "fullName": "/talker",
            "uniqueId": 1
        })
    //! Load parameters for the talker component with default names.
    readonly property var talkerParams: ({
            "packageName": "composition",
            "pluginName": "composition::Talker",
            "nodeName": "",
            "nodeNamespace": "",
            "remapRules": [],
            "logLevel": 0,
            "parameters": [],
            "useIntraProcessComms": false
        })

    /**
     * Registers a container whose services answer from `components` ([{fullName, uniqueId}]) and record requests.
     */
    function addContainer(name, components) {
        Ros2.registerNode(name);
        Ros2.registerService(name + "/_container/load_node", "composition_interfaces/srv/LoadNode", request => {
                record(name + "/_container/load_node", request);
                components.push({
                        "fullName": "/" + request.node_name,
                        "uniqueId": 100
                    });
                return {
                    "success": true
                };
            });
        Ros2.registerService(name + "/_container/list_nodes", "composition_interfaces/srv/ListNodes", request => {
                record(name + "/_container/list_nodes", request);
                return {
                    "full_node_names": components.map(c => c.fullName),
                    "unique_ids": components.map(c => c.uniqueId)
                };
            });
        Ros2.registerService(name + "/_container/unload_node", "composition_interfaces/srv/UnloadNode", request => {
                record(name + "/_container/unload_node", request);
                const index = components.findIndex(c => c.uniqueId === request.unique_id);
                if (index === -1)
                    return {
                        "success": false,
                        "error_message": "No node found with unique_id: " + request.unique_id
                    };
                components.splice(index, 1);
                return {
                    "success": true
                };
            });
    }
    function find(item, name) {
        return helpers.findChild(item, name);
    }
    // Registers a service that records its requests and never answers them.
    function hang(service, type) {
        Ros2.registerService(service, type, request => {
                record(service, request);
                return {
                    "#hang": true
                };
            });
    }
    function record(service, request) {
        requests[service] = (requests[service] || []).concat([request]);
    }
    function requestCount(service) {
        return (requests[service] || []).length;
    }
    function resetFakes() {
        Ros2.reset();
        requests = {};
        contextObj.selectedContainer = undefined;
        toastsMock.messages = [];
        AmentIndex.packages = [];
        AmentIndex.resources = {};
    }

    height: 600
    width: 800

    QtObject {
        id: contextObj

        property var selectedContainer
    }
    // A QtObject property turns null when the referenced object is destroyed.
    QtObject {
        id: clientHolder

        property QtObject client
    }
    QtObject {
        id: toastsMock

        property var messages: []

        function show(message, level) {
            messages = messages.concat([level + ": " + message]);
        }
    }
    Utils {
        id: helpers
    }
    Component {
        id: interfaceComponent
        ContainerInterface {
        }
    }
    Component {
        id: tabComponent
        ContainersTab {
            anchors.fill: parent
            toasts: toastsMock
        }
    }
    Component {
        id: dialogComponent
        LoadComponentDialog {
        }
    }
    SignalSpy {
        id: failedSpy
        signalName: "operationFailed"
    }
    Component {
        id: spyComponent
        SignalSpy {
        }
    }
    TestCase {
        id: interfaceTest
        function createInterface() {
            const iface = createTemporaryObject(interfaceComponent, root);
            failedSpy.target = iface;
            failedSpy.clear();
            return iface;
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            // Every request to a service without handler must be expected with ignoreWarning.
            failOnWarning(/No handler registered/);
            root.resetFakes();
        }
        function selectAndWait(iface, container) {
            iface.selectContainer(container);
            verify(iface.loading);
            tryVerify(() => !iface.loading);
        }
        function test_deselects_vanished_container() {
            root.addContainer("/a", [root.talker]);
            const iface = createInterface();
            iface.refresh();
            selectAndWait(iface, "/a");
            compare(iface.components.length, 1);
            Ros2.reset();
            iface.refresh();
            compare(iface.containers, []);
            compare(iface.selectedContainer, "");
            compare(iface.components, []);
            verify(!iface.loading);
        }
        function test_destroys_clients_of_vanished_container() {
            root.addContainer("/a", [root.talker]);
            const iface = createInterface();
            iface.refresh();
            selectAndWait(iface, "/a");
            let cache = null;
            for (let i = 0; i < iface.children.length; ++i) {
                if (iface.children[i].retain)
                    cache = iface.children[i];
            }
            clientHolder.client = cache.clients["/a"]["/_container/list_nodes"];
            verify(clientHolder.client);
            Ros2.reset();
            iface.refresh();
            compare(cache.clients["/a"], undefined);
            // A live client would keep the vanished container's service listed in the ROS graph.
            tryVerify(() => clientHolder.client === null);
        }
        function test_discovery_filters_and_sorts() {
            // ROS 2 allows duplicate node names.
            for (const node of ["/b", "/a/ns", "/remapped", "/b"])
                Ros2.registerNode(node);
            Ros2.registerService("/b/_container/load_node", "composition_interfaces/srv/LoadNode");
            Ros2.registerService("/a/ns/_container/load_node", "composition_interfaces/srv/LoadNode");
            Ros2.registerService("/remapped/load", "composition_interfaces/srv/LoadNode");
            Ros2.registerService("/_container/load_node", "composition_interfaces/srv/LoadNode");
            // Our own load_node client keeps this service listed after its container's node vanished.
            Ros2.registerService("/gone/_container/load_node", "composition_interfaces/srv/LoadNode");
            const iface = createInterface();
            iface.refresh();
            compare(iface.containers, ["/a/ns", "/b"]);
        }
        function test_failed_first_list_reports_and_later_failure_is_silent() {
            Ros2.registerNode("/a");
            Ros2.registerService("/a/_container/load_node", "composition_interfaces/srv/LoadNode");
            const iface = createInterface();
            iface.refresh();
            ignoreWarning(/No handler registered for service: "\/a\/_container\/list_nodes"/);
            selectAndWait(iface, "/a");
            compare(failedSpy.count, 1);
            compare(failedSpy.signalArguments[0][0], "Failed to list the components of /a: no response");
            ignoreWarning(/No handler registered for service: "\/a\/_container\/list_nodes"/);
            iface.refresh();
            wait(50);
            compare(failedSpy.count, 1);
        }
        function test_list_maps_and_sorts_components() {
            root.addContainer("/a", [{
                        "fullName": "/zeta",
                        "uniqueId": 2
                    }, {
                        "fullName": "/alpha",
                        "uniqueId": 7
                    }]);
            const iface = createInterface();
            iface.refresh();
            selectAndWait(iface, "/a");
            compare(iface.components, [{
                        "fullName": "/alpha",
                        "uniqueId": 7
                    }, {
                        "fullName": "/zeta",
                        "uniqueId": 2
                    }]);
            compare(typeof iface.components[0].uniqueId, "number");
        }
        function test_load_failure_paths() {
            Ros2.registerService("/a/_container/load_node", "composition_interfaces/srv/LoadNode", () => ({
                            "success": false,
                            "error_message": "Failed to find class"
                        }));
            Ros2.registerService("/b/_container/load_node", "composition_interfaces/srv/LoadNode");
            const iface = createInterface();
            iface.refresh();
            const params = root.talkerParams;
            iface.loadComponent("/a", params);
            verify(iface.loadingComponent);
            tryVerify(() => !iface.loadingComponent);
            compare(failedSpy.count, 1);
            compare(failedSpy.signalArguments[0][0], "Failed to load composition::Talker: Failed to find class");
            ignoreWarning(/No handler registered for service: "\/b\/_container\/load_node"/);
            iface.loadComponent("/b", params);
            tryVerify(() => !iface.loadingComponent);
            compare(failedSpy.count, 2);
            compare(failedSpy.signalArguments[1][0], "Failed to load composition::Talker: no response");
        }
        function test_load_request_mapping() {
            const components = [];
            root.addContainer("/a", components);
            const iface = createInterface();
            iface.refresh();
            selectAndWait(iface, "/a");
            iface.loadComponent("/a", {
                    "packageName": "composition",
                    "pluginName": "composition::Talker",
                    "nodeName": "talker",
                    "nodeNamespace": "/ns",
                    "remapRules": ["chatter:=/talk"],
                    "logLevel": 30,
                    "parameters": [{
                            "name": "rate",
                            "value": {
                                "type": 3,
                                "double_value": 2.5
                            }
                        }, {
                            "name": "topics",
                            "value": {
                                "type": 9,
                                "string_array_value": ["a", "b"]
                            }
                        }],
                    "useIntraProcessComms": true
                });
            verify(iface.loadingComponent);
            tryVerify(() => !iface.loadingComponent);
            compare(root.requestCount("/a/_container/load_node"), 1);
            const request = root.requests["/a/_container/load_node"][0];
            compare(request.package_name, "composition");
            compare(request.plugin_name, "composition::Talker");
            compare(request.node_name, "talker");
            compare(request.node_namespace, "/ns");
            compare(request.log_level, 30);
            compare(request.remap_rules, ["chatter:=/talk"]);
            compare(request.parameters.length, 2);
            compare(request.parameters[0].name, "rate");
            compare(request.parameters[0].value.type, 3);
            compare(request.parameters[0].value.double_value, 2.5);
            compare(request.parameters[1].name, "topics");
            compare(request.parameters[1].value.type, 9);
            compare(request.parameters[1].value.string_array_value, ["a", "b"]);
            compare(request.extra_arguments.length, 1);
            compare(request.extra_arguments[0].name, "use_intra_process_comms");
            compare(request.extra_arguments[0].value.type, 1);
            compare(request.extra_arguments[0].value.bool_value, true);
            compare(failedSpy.count, 0);
            tryVerify(() => iface.components.length === 1);
            compare(iface.components[0].fullName, "/talker");
        }
        function test_lost_list_is_requested_again() {
            // A list request sent while the container restarts never gets an answer.
            root.addContainer("/a", []);
            root.hang("/a/_container/list_nodes", "composition_interfaces/srv/ListNodes");
            const iface = createInterface();
            iface.responseTimeout = 100;
            iface.refresh();
            iface.selectContainer("/a");
            tryVerify(() => root.requestCount("/a/_container/list_nodes") === 1);
            // The restarted container answers again.
            Ros2.registerService("/a/_container/list_nodes", "composition_interfaces/srv/ListNodes", request => {
                    root.record("/a/_container/list_nodes", request);
                    return {
                        "full_node_names": ["/talker"],
                        "unique_ids": [1]
                    };
                });
            iface.refresh();
            wait(20);
            compare(root.requestCount("/a/_container/list_nodes"), 1, "No new list request while one is pending");
            verify(iface.loading);
            wait(100);
            iface.refresh();
            compare(failedSpy.count, 1);
            compare(failedSpy.signalArguments[0][0], "Failed to list the components of /a: no response");
            tryCompare(iface, "components", [root.talker]);
            compare(root.requestCount("/a/_container/list_nodes"), 2);
        }
        function test_lost_load_and_unload_fail_after_timeout() {
            // Requests sent while the container restarts never get an answer, and the container stays listed.
            root.addContainer("/a", [root.talker]);
            Ros2.registerService("/a/_container/load_node", "composition_interfaces/srv/LoadNode", () => ({
                            "#hang": true
                        }));
            Ros2.registerService("/a/_container/unload_node", "composition_interfaces/srv/UnloadNode", () => ({
                            "#hang": true
                        }));
            const iface = createInterface();
            iface.responseTimeout = 100;
            iface.refresh();
            iface.loadComponent("/a", root.talkerParams);
            iface.unloadComponent("/a", root.talker);
            iface.refresh();
            verify(iface.loadingComponent);
            verify(iface.isUnloading("/a", root.talker));
            wait(150);
            iface.refresh();
            verify(!iface.loadingComponent);
            verify(!iface.isUnloading("/a", root.talker));
            compare(failedSpy.count, 2);
            compare(failedSpy.signalArguments[0][0], "Failed to load composition::Talker: no response");
            compare(failedSpy.signalArguments[1][0], "Failed to unload /talker: no response");
            iface.refresh();
            compare(failedSpy.count, 2);
        }
        function test_requests_on_vanished_container_fail_once() {
            root.addContainer("/a", [root.talker]);
            const iface = createInterface();
            iface.refresh();
            iface.loadComponent("/a", root.talkerParams);
            iface.unloadComponent("/a", root.talker);
            iface.refresh();
            verify(iface.loadingComponent, "The container is still there");
            verify(iface.isUnloading("/a", root.talker));
            compare(failedSpy.count, 0);
            // The node vanishes, but our own load_node client keeps its service listed.
            Ros2.reset();
            Ros2.registerService("/a/_container/load_node", "composition_interfaces/srv/LoadNode");
            iface.refresh();
            compare(iface.containers, []);
            verify(!iface.loadingComponent);
            verify(!iface.isUnloading("/a", root.talker));
            compare(failedSpy.count, 2);
            compare(failedSpy.signalArguments[0][0], "Failed to load composition::Talker: no response");
            compare(failedSpy.signalArguments[1][0], "Failed to unload /talker: no response");
            // Answers arriving after the report are ignored.
            ignoreWarning(/No handler registered for service: "\/a\/_container\/load_node"/);
            ignoreWarning(/No handler registered for service: "\/a\/_container\/unload_node"/);
            wait(50);
            compare(failedSpy.count, 2);
            verify(!iface.loadingComponent);
        }
        function test_selection_does_not_wait_for_a_lost_list() {
            // A list request sent while the container restarts never gets an answer.
            Ros2.registerNode("/a");
            Ros2.registerService("/a/_container/load_node", "composition_interfaces/srv/LoadNode");
            root.hang("/a/_container/list_nodes", "composition_interfaces/srv/ListNodes");
            const iface = createInterface();
            iface.refresh();
            iface.selectContainer("/a");
            tryVerify(() => root.requestCount("/a/_container/list_nodes") === 1);
            root.addContainer("/a", [root.talker]);
            selectAndWait(iface, "/a");
            compare(iface.components.length, 1);
        }
        function test_stale_answer_ignored_and_loading_semantics() {
            root.addContainer("/a", [root.talker]);
            Ros2.registerNode("/b");
            Ros2.registerService("/b/_container/load_node", "composition_interfaces/srv/LoadNode");
            root.hang("/b/_container/list_nodes", "composition_interfaces/srv/ListNodes");
            const iface = createInterface();
            iface.refresh();
            iface.selectContainer("/a");
            iface.selectContainer("/b");
            tryVerify(() => root.requestCount("/a/_container/list_nodes") === 1);
            wait(20);
            verify(iface.loading, "A stale answer must not clear loading");
            compare(iface.components, []);
            iface.refresh();
            wait(20);
            compare(root.requestCount("/b/_container/list_nodes"), 1, "No new list request while one is pending");
            verify(iface.loading);
            selectAndWait(iface, "/a");
            compare(iface.components.length, 1);
            const loadingSpy = createTemporaryObject(spyComponent, root, {
                    "target": iface,
                    "signalName": "loadingChanged"
                });
            iface.refresh();
            tryVerify(() => root.requestCount("/a/_container/list_nodes") === 3);
            compare(loadingSpy.count, 0, "Periodic refreshes do not toggle loading");
            iface.selectContainer("");
            verify(!iface.loading);
        }
        function test_unchanged_list_keeps_array() {
            const components = [root.talker];
            root.addContainer("/a", components);
            const iface = createInterface();
            iface.refresh();
            const containers = iface.containers;
            selectAndWait(iface, "/a");
            const before = iface.components;
            const componentsSpy = createTemporaryObject(spyComponent, root, {
                    "target": iface,
                    "signalName": "componentsChanged"
                });
            iface.refresh();
            tryVerify(() => root.requestCount("/a/_container/list_nodes") === 2);
            verify(iface.components === before);
            verify(iface.containers === containers);
            compare(componentsSpy.count, 0);
            components.push({
                    "fullName": "/listener",
                    "uniqueId": 2
                });
            iface.refresh();
            tryVerify(() => iface.components.length === 2);
            compare(componentsSpy.count, 1);
        }
        function test_unload_failure() {
            root.addContainer("/a", [root.talker]);
            Ros2.registerService("/a/_container/unload_node", "composition_interfaces/srv/UnloadNode", request => {
                    root.record("/a/_container/unload_node", request);
                    return {
                        "success": false,
                        "error_message": "boom"
                    };
                });
            const iface = createInterface();
            iface.refresh();
            selectAndWait(iface, "/a");
            iface.unloadComponent("/a", root.talker);
            verify(iface.isUnloading("/a", root.talker));
            tryVerify(() => !iface.isUnloading("/a", root.talker));
            compare(root.requestCount("/a/_container/unload_node"), 1);
            compare(failedSpy.count, 1);
            compare(failedSpy.signalArguments[0][0], "Failed to unload /talker: boom");
        }
        function test_unload_no_response() {
            Ros2.registerService("/a/_container/load_node", "composition_interfaces/srv/LoadNode");
            const iface = createInterface();
            iface.refresh();
            ignoreWarning(/No handler registered for service: "\/a\/_container\/unload_node"/);
            iface.unloadComponent("/a", root.talker);
            verify(iface.isUnloading("/a", root.talker));
            tryVerify(() => failedSpy.count === 1);
            compare(failedSpy.signalArguments[0][0], "Failed to unload /talker: no response");
            verify(!iface.isUnloading("/a", root.talker));
            wait(50);
            compare(failedSpy.count, 1, "No retry");
        }
        function test_unload_success() {
            root.addContainer("/a", [root.talker, {
                        "fullName": "/listener",
                        "uniqueId": 2
                    }]);
            root.addContainer("/b", [{
                        "fullName": "/other",
                        "uniqueId": 1
                    }]);
            const iface = createInterface();
            iface.refresh();
            selectAndWait(iface, "/a");
            iface.unloadComponent("/a", root.talker);
            verify(iface.isUnloading("/a", root.talker));
            verify(!iface.isUnloading("/b", root.talker), "In-flight state is per container");
            tryVerify(() => !iface.isUnloading("/a", root.talker));
            compare(root.requestCount("/a/_container/unload_node"), 1);
            compare(root.requests["/a/_container/unload_node"][0].unique_id, 1);
            compare(root.requestCount("/b/_container/unload_node"), 0);
            compare(failedSpy.count, 0);
            tryVerify(() => iface.components.length === 1);
            compare(iface.components[0].fullName, "/listener");
        }

        name: "ContainerInterface"
    }
    TestCase {
        id: tabTest
        function componentRow(list, fullName) {
            const rows = list.contentItem.children;
            for (let i = 0; i < rows.length; ++i) {
                if (rows[i].modelData && rows[i].modelData.fullName === fullName)
                    return rows[i];
            }
            return null;
        }
        function createTab() {
            const tab = createTemporaryObject(tabComponent, root);
            tab.refresh();
            return tab;
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            failOnWarning(/No handler registered/);
            root.resetFakes();
        }
        function test_auto_selects_first_container_without_overwriting_context() {
            root.addContainer("/a", []);
            root.addContainer("/b", []);
            contextObj.selectedContainer = "/gone";
            const tab = createTab();
            const combo = find(tab, "nmContainerComboBox");
            compare(combo.displayText, "/a");
            tryCompare(combo, "currentIndex", 0);
            compare(contextObj.selectedContainer, "/gone");
        }
        function test_auto_selects_persisted_container() {
            root.addContainer("/a", []);
            root.addContainer("/b", [root.talker]);
            contextObj.selectedContainer = "/b";
            const tab = createTab();
            verify(!find(tab, "nmComponentHint").visible, "No hint before the first answer");
            const combo = find(tab, "nmContainerComboBox");
            compare(combo.displayText, "/b");
            tryCompare(combo, "currentText", "/b");
            tryCompare(find(tab, "nmComponentList"), "count", 1);
        }
        function test_combo_keeps_selection_when_container_sorts_before() {
            root.addContainer("/b", []);
            contextObj.selectedContainer = "/b";
            const tab = createTab();
            const combo = find(tab, "nmContainerComboBox");
            tryCompare(combo, "currentText", "/b");
            root.addContainer("/a", []);
            tab.refresh();
            compare(combo.count, 2);
            compare(combo.displayText, "/b");
            tryCompare(combo, "currentIndex", 1);
            compare(combo.currentText, "/b");
        }
        function test_combo_selection_is_persisted() {
            root.addContainer("/a", []);
            root.addContainer("/b", [root.talker]);
            const tab = createTab();
            const combo = find(tab, "nmContainerComboBox");
            tryCompare(combo, "currentIndex", 0);
            mouseClick(combo);
            tryVerify(() => combo.popup.opened);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare(combo.displayText, "/b");
            compare(contextObj.selectedContainer, "/b");
            tryCompare(find(tab, "nmComponentList"), "count", 1);
        }
        function test_created_outside_a_window_without_warnings() {
            // The plugin host creates the item before parenting it into a window.
            const tab = createTemporaryObject(tabComponent, null);
            tab.parent = root;
            compare(find(tab, "nmUnloadDialog").width, 400);
            compare(find(tab, "nmLoadComponentDialog").width, 420);
        }
        function test_empty_hints_and_filter() {
            const tab = createTab();
            const combo = find(tab, "nmContainerComboBox");
            const hint = find(tab, "nmComponentHint");
            const list = find(tab, "nmComponentList");
            compare(combo.displayText, "No containers found");
            verify(!hint.visible, "The combo already says there are no containers");
            verify(!find(tab, "nmLoadComponentButton").enabled);
            const components = [];
            root.addContainer("/a", components);
            tab.refresh();
            tryVerify(() => hint.visible);
            compare(hint.text, "No components loaded.");
            components.push({
                    "fullName": "/robot/Talker",
                    "uniqueId": 1
                }, {
                    "fullName": "/listener",
                    "uniqueId": 2
                });
            tab.refresh();
            tryCompare(list, "count", 2);
            verify(!hint.visible);
            const field = find(find(tab, "nmComponentSearchBar"), "searchBarTextField");
            field.text = "TALK";
            tryCompare(list, "count", 1);
            compare(list.model[0].fullName, "/robot/Talker");
            verify(!hint.visible);
            field.text = "nothing";
            tryCompare(list, "count", 0);
            verify(hint.visible);
            compare(hint.text, "No components match the filter.");
        }
        function test_load_via_dialog() {
            AmentIndex.packages = ["composition"];
            AmentIndex.resources = {
                "rclcpp_components/composition": "composition::Talker;lib/libtalker_component.so\n"
            };
            root.addContainer("/a", []);
            const tab = createTab();
            const button = find(tab, "nmLoadComponentButton");
            tryVerify(() => button.enabled);
            mouseClick(button);
            const dialog = find(tab, "nmLoadComponentDialog");
            tryVerify(() => dialog.opened);
            compare(dialog.title, "Load Component into /a");
            find(dialog, "nmLoadPackageField").text = " composition ";
            find(dialog, "nmLoadPluginField").text = "composition::Talker";
            find(dialog, "nmLoadNodeNameField").text = " talker ";
            find(dialog, "nmLoadRemapArea").text = " chatter:=/talk \n\n";
            find(dialog, "nmLoadParameterArea").text = "use_sim_time:=true";
            dialog.accept();
            verify(!button.enabled, "Disabled while the load is running");
            tryVerify(() => button.enabled);
            compare(root.requestCount("/a/_container/load_node"), 1);
            const request = root.requests["/a/_container/load_node"][0];
            compare(request.package_name, "composition");
            compare(request.node_name, "talker");
            compare(request.node_namespace, "");
            compare(request.log_level, 0);
            compare(request.remap_rules, ["chatter:=/talk"]);
            compare(request.parameters.length, 1);
            compare(request.parameters[0].name, "use_sim_time");
            compare(request.parameters[0].value.type, 1);
            compare(request.parameters[0].value.bool_value, true);
            compare(request.extra_arguments, []);
            tryCompare(find(tab, "nmComponentList"), "count", 1);
            compare(toastsMock.messages, []);
        }
        function test_prefers_persisted_container_discovered_later() {
            root.addContainer("/a", []);
            contextObj.selectedContainer = "/b";
            const tab = createTab();
            const combo = find(tab, "nmContainerComboBox");
            compare(combo.displayText, "/a");
            root.addContainer("/b", []);
            tab.refresh();
            compare(combo.displayText, "/b");
            tryCompare(combo, "currentText", "/b");
            compare(contextObj.selectedContainer, "/b");
        }
        function test_unload_button_hidden_while_unloading() {
            root.addContainer("/a", [root.talker]);
            Ros2.registerService("/a/_container/unload_node", "composition_interfaces/srv/UnloadNode", () => ({
                            "#hang": true
                        }));
            const tab = createTab();
            const list = find(tab, "nmComponentList");
            tryCompare(list, "count", 1);
            const button = find(componentRow(list, "/talker"), "nmUnloadButton");
            mouseClick(button);
            const dialog = find(tab, "nmUnloadDialog");
            tryVerify(() => dialog.opened);
            mouseClick(dialog.standardButton(Dialog.Yes));
            tryVerify(() => !button.visible);
        }
        function test_unload_requires_confirmation_and_targets_captured_container() {
            root.addContainer("/a", [root.talker]);
            root.addContainer("/b", [{
                        "fullName": "/other",
                        "uniqueId": 1
                    }]);
            const tab = createTab();
            const list = find(tab, "nmComponentList");
            tryCompare(list, "count", 1);
            const dialog = find(tab, "nmUnloadDialog");
            mouseClick(find(componentRow(list, "/talker"), "nmUnloadButton"));
            tryVerify(() => dialog.opened);
            compare(dialog.contentItem.children[0].text, "Unload /talker from /a?");
            mouseClick(dialog.standardButton(Dialog.No));
            tryVerify(() => !dialog.visible);
            wait(20);
            compare(root.requestCount("/a/_container/unload_node"), 0);
            mouseClick(find(componentRow(list, "/talker"), "nmUnloadButton"));
            tryVerify(() => dialog.opened);
            // The selection moves while the dialog is open: /a vanishes, but its unload service still answers.
            Ros2.reset();
            root.addContainer("/b", [{
                        "fullName": "/other",
                        "uniqueId": 1
                    }]);
            Ros2.registerService("/a/_container/unload_node", "composition_interfaces/srv/UnloadNode", request => {
                    root.record("/a/_container/unload_node", request);
                    return {
                        "success": false,
                        "error_message": "boom"
                    };
                });
            tab.refresh();
            compare(find(tab, "nmContainerComboBox").displayText, "/b");
            mouseClick(dialog.standardButton(Dialog.Yes));
            tryVerify(() => root.requestCount("/a/_container/unload_node") === 1);
            compare(root.requests["/a/_container/unload_node"][0].unique_id, 1);
            compare(root.requestCount("/b/_container/unload_node"), 0);
            tryCompare(toastsMock, "messages", ["error: Failed to unload /talker: boom"]);
        }

        name: "ContainersTab"
        when: windowShown
    }
    TestCase {
        id: dialogTest

        property var requestedSpy

        function createDialog() {
            const dialog = createTemporaryObject(dialogComponent, root);
            requestedSpy = createTemporaryObject(spyComponent, root, {
                    "target": dialog,
                    "signalName": "loadRequested"
                });
            return dialog;
        }
        function init() {
            failOnWarning(/Binding loop|TypeError|ReferenceError|Could not convert/);
            root.resetFakes();
            AmentIndex.packages = ["composition", "demo_nodes_cpp", "std_msgs"];
            AmentIndex.resources = {
                "rclcpp_components/composition": "composition::Talker;lib/libtalker_component.so\ncomposition::Listener;lib/liblistener_component.so\n",
                "rclcpp_components/demo_nodes_cpp": "demo_nodes_cpp::Talker;lib/libtalker.so"
            };
        }
        function test_keyboard_flow() {
            const dialog = createDialog();
            dialog.openFor("/a");
            tryVerify(() => dialog.opened);
            const packageField = find(dialog, "nmLoadPackageField");
            for (const key of "composition")
                keyClick(key);
            compare(packageField.text, "composition", "The package field has focus after opening");
            keyClick(Qt.Key_Return);
            verify(dialog.visible, "Return does not accept while the plugin is missing");
            find(dialog, "nmLoadPluginField").text = "composition::Talker";
            const nodeNameField = find(dialog, "nmLoadNodeNameField");
            nodeNameField.forceActiveFocus();
            keyClick(Qt.Key_Return);
            tryVerify(() => !dialog.visible);
            compare(requestedSpy.count, 1);
        }
        function test_ok_validation() {
            const dialog = createDialog();
            dialog.openFor("/a");
            const ok = dialog.standardButton(Dialog.Ok);
            const packageField = find(dialog, "nmLoadPackageField");
            const pluginField = find(dialog, "nmLoadPluginField");
            verify(!ok.enabled);
            packageField.text = "composition";
            verify(!ok.enabled);
            pluginField.text = "   ";
            verify(!ok.enabled, "Blank plugin");
            pluginField.text = "composition::Talker";
            verify(ok.enabled);
            dialog.close();
            dialog.openFor("/a");
            compare(packageField.text, "");
            compare(pluginField.text, "");
            verify(!ok.enabled, "Reopening clears the fields");
        }
        function test_options_reset_on_open() {
            const dialog = createDialog();
            dialog.openFor("/a");
            const parameterArea = find(dialog, "nmLoadParameterArea");
            const logLevel = find(dialog, "nmLoadLogLevelComboBox");
            const intraProcess = find(dialog, "nmLoadIntraProcessCheckBox");
            compare(logLevel.currentValue, 0);
            verify(!intraProcess.checked);
            parameterArea.text = "a:=1";
            logLevel.currentIndex = 3;
            intraProcess.checked = true;
            dialog.close();
            dialog.openFor("/a");
            compare(parameterArea.text, "");
            compare(logLevel.currentValue, 0);
            verify(!intraProcess.checked);
        }
        function test_package_suggestions_have_components() {
            const dialog = createDialog();
            dialog.openFor("/a");
            compare(find(dialog, "nmLoadPackageField").model, ["composition", "demo_nodes_cpp"]);
        }
        function test_parameter_errors_disable_ok() {
            const dialog = createDialog();
            dialog.openFor("/a");
            const ok = dialog.standardButton(Dialog.Ok);
            const parameterArea = find(dialog, "nmLoadParameterArea");
            const error = find(dialog, "nmLoadParameterError");
            find(dialog, "nmLoadPackageField").text = "composition";
            find(dialog, "nmLoadPluginField").text = "composition::Talker";
            verify(ok.enabled);
            verify(!error.visible);
            for (const text of ["a:=1\n\nrate", "a:=1\n\n:=5", "a:=1\n\n  := 5", "a:=1\n\nrate=5", "a:=1\n\nid:=9007199254740993", "a:=1\n\nids:=[1, -9007199254740993]", "a:=1\n\nnames:=[a\"b, c]"]) {
                parameterArea.text = text;
                verify(!ok.enabled, text);
                verify(error.visible, text);
                compare(error.text, "Line 3 is not a valid name:=value", text);
            }
            parameterArea.text = "a:=1\n  \nrate:=5\n";
            verify(ok.enabled, "Blank lines are ignored");
            verify(!error.visible);
        }
        function test_parse(data) {
            const result = ParameterParser.parseParameters(" name := " + data.value + " ");
            compare(result.invalidLine, 0);
            compare(result.parameters, [{
                        "name": "name",
                        "value": data.expected
                    }]);
        }
        function test_parse_data() {
            return [{
                    "tag": "bool",
                    "value": "true",
                    "expected": {
                        "type": 1,
                        "bool_value": true
                    }
                }, {
                    "tag": "bool capitalized false",
                    "value": "False",
                    "expected": {
                        "type": 1,
                        "bool_value": false
                    }
                }, {
                    "tag": "integer",
                    "value": "-42",
                    "expected": {
                        "type": 2,
                        "integer_value": -42
                    }
                }, {
                    "tag": "double",
                    "value": "2.5",
                    "expected": {
                        "type": 3,
                        "double_value": 2.5
                    }
                }, {
                    "tag": "double exponent",
                    "value": "1e-3",
                    "expected": {
                        "type": 3,
                        "double_value": 0.001
                    }
                }, {
                    "tag": "double leading dot",
                    "value": ".5",
                    "expected": {
                        "type": 3,
                        "double_value": 0.5
                    }
                }, {
                    "tag": "string",
                    "value": "hello world",
                    "expected": {
                        "type": 4,
                        "string_value": "hello world"
                    }
                }, {
                    "tag": "quoted number is a string",
                    "value": "\"42\"",
                    "expected": {
                        "type": 4,
                        "string_value": "42"
                    }
                }, {
                    "tag": "single quoted bool is a string",
                    "value": "'true'",
                    "expected": {
                        "type": 4,
                        "string_value": "true"
                    }
                }, {
                    "tag": "empty value is an empty string",
                    "value": "",
                    "expected": {
                        "type": 4,
                        "string_value": ""
                    }
                }, {
                    "tag": "value containing :=",
                    "value": "a:=b",
                    "expected": {
                        "type": 4,
                        "string_value": "a:=b"
                    }
                }, {
                    "tag": "bool array",
                    "value": "[true, false]",
                    "expected": {
                        "type": 6,
                        "bool_array_value": [true, false]
                    }
                }, {
                    "tag": "integer array",
                    "value": "[1, -2, 3]",
                    "expected": {
                        "type": 7,
                        "integer_array_value": [1, -2, 3]
                    }
                }, {
                    "tag": "double array",
                    "value": "[1.5,2.5]",
                    "expected": {
                        "type": 8,
                        "double_array_value": [1.5, 2.5]
                    }
                }, {
                    "tag": "integers promote to doubles",
                    "value": "[1, 2.5, 3]",
                    "expected": {
                        "type": 8,
                        "double_array_value": [1, 2.5, 3]
                    }
                }, {
                    "tag": "string array",
                    "value": "[a, 'b, c', \"1\"]",
                    "expected": {
                        "type": 9,
                        "string_array_value": ["a", "b, c", "1"]
                    }
                }, {
                    "tag": "empty array is a bool array",
                    "value": "[ ]",
                    "expected": {
                        "type": 6,
                        "bool_array_value": []
                    }
                }, {
                    "tag": "mixed array is a string",
                    "value": "[1, a]",
                    "expected": {
                        "type": 4,
                        "string_value": "[1, a]"
                    }
                }];
        }
        function test_payload() {
            const dialog = createDialog();
            dialog.openFor("/container");
            compare(dialog.title, "Load Component into /container");
            find(dialog, "nmLoadPackageField").text = " composition ";
            find(dialog, "nmLoadPluginField").text = " composition::Talker ";
            find(dialog, "nmLoadNodeNameField").text = " talker ";
            find(dialog, "nmLoadNamespaceField").text = " /ns ";
            find(dialog, "nmLoadRemapArea").text = " a:=b \n\n c:=d ";
            find(dialog, "nmLoadParameterArea").text = "rate:=10\n\nframe:=map";
            find(dialog, "nmLoadLogLevelComboBox").currentIndex = 1;
            find(dialog, "nmLoadIntraProcessCheckBox").checked = true;
            dialog.accept();
            compare(requestedSpy.count, 1);
            compare(requestedSpy.signalArguments[0][0], "/container");
            compare(requestedSpy.signalArguments[0][1], {
                    "packageName": "composition",
                    "pluginName": "composition::Talker",
                    "nodeName": "talker",
                    "nodeNamespace": "/ns",
                    "remapRules": ["a:=b", "c:=d"],
                    "logLevel": 10,
                    "parameters": [{
                            "name": "rate",
                            "value": {
                                "type": 2,
                                "integer_value": 10
                            }
                        }, {
                            "name": "frame",
                            "value": {
                                "type": 4,
                                "string_value": "map"
                            }
                        }],
                    "useIntraProcessComms": true
                });
        }
        function test_plugin_suggestions_from_resource() {
            const dialog = createDialog();
            dialog.openFor("/a");
            const packageField = find(dialog, "nmLoadPackageField");
            const pluginField = find(dialog, "nmLoadPluginField");
            compare(pluginField.model, []);
            packageField.text = "composition";
            compare(pluginField.model, ["composition::Talker", "composition::Listener"]);
            packageField.text = "std_msgs";
            compare(pluginField.model, []);
        }

        name: "LoadComponentDialog"
        when: windowShown
    }
}
