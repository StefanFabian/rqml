import QtQuick
import Ros2
import RQml.Utils

/**
 * Discovers component containers, lists the components of the selected one and loads or unloads components.
 */
Object {
    id: root

    //! Components of the selected container as [{fullName, uniqueId}], sorted by name.
    property var components: []

    //! Sorted names of the discovered containers.
    property var containers: []

    //! True from selectContainer() until the selected container answered for the first time.
    property bool loading: false

    //! True while a load request is in flight.
    readonly property bool loadingComponent: d.loadPending

    //! Milliseconds without a response after which a request fails.
    property alias responseTimeout: clientCache.responseTimeout

    //! Container whose components are listed, "" if none.
    property string selectedContainer: ""

    //! Emitted with a user-facing message when the first list after selectContainer(), a load or an unload failed.
    signal operationFailed(string message)

    /**
     * Whether an unload of the component ({fullName, uniqueId}) from the container is in flight.
     */
    function isUnloading(container, component) {
        return d.unloads.some(unload => unload.container === container && unload.component.uniqueId === component.uniqueId);
    }

    /**
     * Loads a component into the container.
     * params: {packageName, pluginName, nodeName, nodeNamespace, remapRules: [string], logLevel,
     * parameters: [rcl_interfaces/msg/Parameter], useIntraProcessComms}; empty names use the defaults, logLevel is a
     * rcl_interfaces/msg/Log level or 0 for the container's level.
     */
    function loadComponent(container, params) {
        d.loadPending = true;
        clientCache.send(container, "/_container/load_node", "composition_interfaces/srv/LoadNode", {
                "package_name": params.packageName,
                "plugin_name": params.pluginName,
                "node_name": params.nodeName,
                "node_namespace": params.nodeNamespace,
                "log_level": params.logLevel,
                "remap_rules": params.remapRules,
                "parameters": params.parameters,
                "extra_arguments": params.useIntraProcessComms ? [{
                        "name": "use_intra_process_comms",
                        "value": {
                            "type": 1,
                            "bool_value": true
                        }
                    }] : []
            }, response => {
                d.loadPending = false;
                if (!response || !response.success)
                    root.operationFailed(qsTr("Failed to load %1: %2").arg(params.pluginName).arg(response ? response.error_message : qsTr("no response")));
                // Without a response the container may be gone, the next refresh() lists again.
                if (response && container === root.selectedContainer)
                    d.list(container);
            });
    }

    /**
     * Rediscovers the containers and re-lists the components of the selected one.
     */
    function refresh() {
        const found = clientCache.discover("composition_interfaces/srv/LoadNode", "/_container/load_node");
        if (JSON.stringify(found) !== JSON.stringify(root.containers))
            root.containers = found;
        clientCache.retain(found);
        if (root.selectedContainer && !found.includes(root.selectedContainer))
            root.selectContainer("");
        else if (root.selectedContainer && !clientCache.isPending(root.selectedContainer, "/_container/list_nodes"))
            d.list(root.selectedContainer);
    }

    /**
     * Selects the container whose components are listed; "" deselects.
     */
    function selectContainer(name) {
        root.selectedContainer = name;
        root.components = [];
        root.loading = name !== "";
        if (name)
            d.list(name);
    }

    /**
     * Unloads the component ({fullName, uniqueId}) from the container.
     */
    function unloadComponent(container, component) {
        const unload = {
            "component": component,
            "container": container
        };
        d.unloads = d.unloads.concat(unload);
        clientCache.send(container, "/_container/unload_node", "composition_interfaces/srv/UnloadNode", {
                "unique_id": component.uniqueId
            }, response => {
                d.unloads = d.unloads.filter(other => other !== unload);
                if (!response || !response.success)
                    root.operationFailed(qsTr("Failed to unload %1: %2").arg(component.fullName).arg(response ? response.error_message : qsTr("no response")));
                if (response && container === root.selectedContainer)
                    d.list(container);
            });
    }

    QtObject {
        id: d

        //! True while a load request is in flight.
        property bool loadPending: false

        //! In-flight unload requests as [{component, container}].
        property var unloads: []

        function list(container) {
            clientCache.send(container, "/_container/list_nodes", "composition_interfaces/srv/ListNodes", {}, response => {
                    if (container !== root.selectedContainer)
                        return;
                    if (response) {
                        const components = [];
                        for (let i = 0; i < response.full_node_names.length; ++i) {
                            // uint64 array elements reach QML as opaque values, not numbers.
                            components.push({
                                    "fullName": response.full_node_names.at(i),
                                    "uniqueId": Number(response.unique_ids.at(i))
                                });
                        }
                        components.sort((a, b) => (a.fullName > b.fullName) - (a.fullName < b.fullName));
                        if (JSON.stringify(components) !== JSON.stringify(root.components))
                            root.components = components;
                    } else if (root.loading) {
                        root.operationFailed(qsTr("Failed to list the components of %1: %2").arg(container).arg(qsTr("no response")));
                    }
                    root.loading = false;
                });
        }
    }
    ServiceClientCache {
        id: clientCache
    }
}
