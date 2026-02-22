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

pragma Singleton
import QtQuick
import Ros2

QtObject {
    id: root

    // --- Signals ---
    signal parametersChanged(string nodeName)
    signal parameterSetResult(string nodeName, string paramName, bool success, string reason)

    // --- Public Properties ---
    property var nodes: [] // Emits nodesChanged implicitly on assignment

    // --- Parameter Types (rcl_interfaces/msg/ParameterType) ---
    readonly property int typeNotSet: 0
    readonly property int typeBool: 1
    readonly property int typeInteger: 2
    readonly property int typeDouble: 3
    readonly property int typeString: 4
    readonly property int typeByteArray: 5
    readonly property int typeBoolArray: 6
    readonly property int typeIntegerArray: 7
    readonly property int typeDoubleArray: 8
    readonly property int typeStringArray: 9

    property var _paramSub: Subscription {
        topic: "/parameter_events"
        messageType: "rcl_interfaces/msg/ParameterEvent"
        queueSize: 10
        onMessageChanged: {
            if (!message || !message.node) return;
            const nodeName = message.node;
            const nodeInfo = root._nodes[nodeName];
            if (!nodeInfo) return; // We aren't tracking this node

            let changed = false;

            function processParams(paramList) {
                if (!paramList) return;
                for (let i = 0; i < paramList.length; i++) {
                    let p = (paramList.at !== undefined) ? paramList.at(i) : paramList[i];
                    if (p && p.name && p.value && nodeInfo.parameters[p.name]) {
                        nodeInfo.parameters[p.name].value = root._extractValue(p.value);
                        changed = true;
                    }
                }
            }

            if (message.deleted_parameters && message.deleted_parameters.length > 0) {
                 root._loadParameters(nodeName);
                 return;
            }
            if (message.new_parameters && message.new_parameters.length > 0) {
                 root._loadParameters(nodeName);
                 return;
            }

            processParams(message.changed_parameters);

            if (changed) {
                 root.parametersChanged(nodeName);
            }
        }
    }

    // --- Public API ---

    function discoverNodes() {
        const services = Ros2.queryServices("rcl_interfaces/srv/ListParameters");
        let discovered = [];
        for (let i = 0; i < services.length; i++) {
            const svc = services[i];
            if (!svc.endsWith("/list_parameters"))
                continue;
            const nodeName = svc.substring(0, svc.length - "/list_parameters".length);
            if (nodeName && discovered.indexOf(nodeName) === -1)
                discovered.push(nodeName);
        }
        discovered.sort();
        root.nodes = discovered;
    }

    function acquire(nodeName) {
        if (!nodeName)
            return null;
        let node = _nodes[nodeName];
        if (node) {
            node.refCount++;
            return node;
        }
        node = {
            refCount: 1,
            loading: false,
            loaded: false,
            listClient: Ros2.createServiceClient(nodeName + "/list_parameters", "rcl_interfaces/srv/ListParameters"),
            getClient: Ros2.createServiceClient(nodeName + "/get_parameters", "rcl_interfaces/srv/GetParameters"),
            setClient: Ros2.createServiceClient(nodeName + "/set_parameters", "rcl_interfaces/srv/SetParameters"),
            describeClient: Ros2.createServiceClient(nodeName + "/describe_parameters", "rcl_interfaces/srv/DescribeParameters"),
            parameters: {}
        };
        _nodes[nodeName] = node;
        _loadParameters(nodeName);
        return node;
    }

    function release(nodeName) {
        if (!nodeName)
            return;
        const node = _nodes[nodeName];
        if (!node)
            return;
        node.refCount--;
        if (node.refCount <= 0) {
            node.listClient = null;
            node.getClient = null;
            node.setClient = null;
            node.describeClient = null;
            delete _nodes[nodeName];
        }
    }

    function refresh(nodeName) {
        if (!nodeName)
            return;
        const node = _nodes[nodeName];
        if (!node)
            return;
        _loadParameters(nodeName);
    }

    function getNodeData(nodeName) {
        return _nodes[nodeName] || null;
    }

    function isLoading(nodeName) {
        const node = _nodes[nodeName];
        return node ? node.loading : false;
    }

    function setParameter(nodeName, paramName, value, paramType) {
        const node = _nodes[nodeName];
        if (!node || !node.setClient)
            return;
        const param = {
            name: paramName,
            value: _buildParameterValue(value, paramType)
        };
        node.setClient.sendRequestAsync({
            parameters: [param]
        }, function (response) {
            if (!response || !response.results || response.results.length === 0) {
                Ros2.warn("ParameterService: Failed to set parameter " + paramName + " on " + nodeName);
                root.parameterSetResult(nodeName, paramName, false, "Service call failed");
                return;
            }
            const result = response.results.at(0);
            if (result.successful) {
                if (node.parameters[paramName])
                    node.parameters[paramName].value = value;
                root.parametersChanged(nodeName);
            }
            root.parameterSetResult(nodeName, paramName, result.successful, result.reason || "");
        });
    }

    // --- Private ---
    property var _nodes: ({})

    function _loadParameters(nodeName) {
        const node = _nodes[nodeName];
        if (!node || node.loading)
            return;
        node.loading = true;
        root.parametersChanged(nodeName);

        node.listClient.sendRequestAsync({
            prefixes: [],
            depth: 0
        }, function (listResponse) {
            if (!listResponse || !listResponse.result) {
                Ros2.warn("ParameterService: Failed to list parameters for " + nodeName);
                node.loading = false;
                root.parametersChanged(nodeName);
                return;
            }
            const names = [];
            for (let i = 0; i < listResponse.result.names.length; i++)
                names.push(listResponse.result.names.at(i));

            if (names.length === 0) {
                node.parameters = {};
                node.loading = false;
                node.loaded = true;
                root.parametersChanged(nodeName);
                return;
            }

            node.getClient.sendRequestAsync({
                names: names
            }, function (getResponse) {
                if (!getResponse || !getResponse.values) {
                    Ros2.warn("ParameterService: Failed to get parameters for " + nodeName);
                    node.loading = false;
                    root.parametersChanged(nodeName);
                    return;
                }
                const params = {};
                for (let i = 0; i < names.length; i++) {
                    const pv = getResponse.values.at(i);
                    params[names[i]] = {
                        name: names[i],
                        type: pv.type,
                        value: _extractValue(pv),
                        descriptor: {
                            description: "",
                            readOnly: false,
                            floatingPointRange: null,
                            integerRange: null
                        }
                    };
                }

                node.describeClient.sendRequestAsync({
                    names: names
                }, function (descResponse) {
                    if (descResponse && descResponse.descriptors) {
                        for (let i = 0; i < descResponse.descriptors.length; i++) {
                            const desc = descResponse.descriptors.at(i);
                            const p = params[desc.name];
                            if (!p)
                                continue;
                            p.descriptor.description = desc.description || "";
                            p.descriptor.readOnly = !!desc.read_only;
                            if (desc.floating_point_range && desc.floating_point_range.length > 0) {
                                const r = desc.floating_point_range.at(0);
                                p.descriptor.floatingPointRange = {
                                    from: Number(r.from_value),
                                    to: Number(r.to_value),
                                    step: Number(r.step)
                                };
                            }
                            if (desc.integer_range && desc.integer_range.length > 0) {
                                const r = desc.integer_range.at(0);
                                p.descriptor.integerRange = {
                                    from: Number(r.from_value),
                                    to: Number(r.to_value),
                                    step: Number(r.step)
                                };
                            }
                        }
                    }
                    node.parameters = params;
                    node.loading = false;
                    node.loaded = true;
                    root.parametersChanged(nodeName);
                });
            });
        });
    }

    function _extractValue(pv) {
        switch (pv.type) {
        case root.typeBool:
            return pv.bool_value;
        case root.typeInteger:
            return pv.integer_value;
        case root.typeDouble:
            return pv.double_value;
        case root.typeString:
            return pv.string_value;
        case root.typeByteArray:
            return pv.byte_array_value;
        case root.typeBoolArray:
            return pv.bool_array_value;
        case root.typeIntegerArray:
            return pv.integer_array_value;
        case root.typeDoubleArray:
            return pv.double_array_value;
        case root.typeStringArray:
            return pv.string_array_value;
        default:
            return null;
        }
    }

    function _buildParameterValue(value, paramType) {
        const pv = {
            type: paramType,
            bool_value: false,
            integer_value: 0,
            double_value: 0.0,
            string_value: "",
            byte_array_value: [],
            bool_array_value: [],
            integer_array_value: [],
            double_array_value: [],
            string_array_value: []
        };
        switch (paramType) {
        case root.typeBool:
            pv.bool_value = !!value;
            break;
        case root.typeInteger:
            pv.integer_value = parseInt(value) || 0;
            break;
        case root.typeDouble:
            pv.double_value = parseFloat(value) || 0.0;
            break;
        case root.typeString:
            pv.string_value = String(value);
            break;
        case root.typeByteArray:
            // TODO: properly reconstruct array from typed string array
            break;
        case root.typeBoolArray:
            for (let i = 0; i < value.length; i++) pv.bool_array_value.push(value[i]);
            break;
        case root.typeIntegerArray:
            for (let i = 0; i < value.length; i++) pv.integer_array_value.push(parseInt(value[i]) || 0);
            break;
        case root.typeDoubleArray:
            for (let i = 0; i < value.length; i++) pv.double_array_value.push(parseFloat(value[i]) || 0.0);
            break;
        case root.typeStringArray:
            for (let i = 0; i < value.length; i++) pv.string_array_value.push(String(value[i]));
            break;
        }
        return pv;
    }
}
