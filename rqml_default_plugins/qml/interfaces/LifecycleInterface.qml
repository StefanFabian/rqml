import QtQuick
import Ros2
import RQml.Utils

/**
 * Discovers lifecycle nodes, tracks their states and triggers transitions.
 */
Object {
    id: root

    //! Transitions available from the selected node's current state, as [{id, label}].
    property var availableTransitions: []

    //! Lifecycle nodes as {name, state, pending}, sorted by name. pending is the label of the transition in flight or "".
    property var nodes: ListModel {
    }

    //! Milliseconds without a response after which a request fails.
    property alias responseTimeout: clientCache.responseTimeout

    //! Node that availableTransitions belongs to; "" if none.
    property string selectedNode: ""

    //! Emitted when a transition is rejected, gets no response or its node vanishes.
    signal transitionFailed(string node, string label)

    /**
     * Rediscovers the lifecycle nodes and queries their states.
     */
    function refresh() {
        const discovered = clientCache.discover("lifecycle_msgs/srv/ChangeState", "/change_state");
        let row = 0;
        for (const name of discovered) {
            while (row < root.nodes.count && root.nodes.get(row).name < name)
                root.nodes.remove(row);
            if (row === root.nodes.count || root.nodes.get(row).name !== name) {
                root.nodes.insert(row, {
                        "name": name,
                        "state": "unknown",
                        "pending": ""
                    });
            }
            ++row;
        }
        if (row < root.nodes.count)
            root.nodes.remove(row, root.nodes.count - row);
        // After the inserts subscribed to transition events; also catches restarted nodes, which emit none.
        root.refreshStates();
        clientCache.retain(discovered);
        if (root.selectedNode && !discovered.includes(root.selectedNode))
            root.selectNode("");
    }

    /**
     * Queries the states of all known nodes, e.g. in case a transition event got lost.
     */
    function refreshStates() {
        for (let i = 0; i < root.nodes.count; ++i)
            d.queryState(root.nodes.get(i).name);
    }

    /**
     * Selects a node ("" for none) and queries its available transitions.
     */
    function selectNode(node) {
        root.selectedNode = node;
        root.availableTransitions = [];
        if (node)
            d.queryTransitions(node);
    }

    /**
     * Requests the transition ({id, label}) on the node.
     */
    function triggerTransition(node, transition) {
        d.setNodeProperty(node, "pending", transition.label);
        clientCache.send(node, "/change_state", "lifecycle_msgs/srv/ChangeState", {
                "transition": {
                    "id": transition.id,
                    "label": ""
                }
            }, response => {
                d.setNodeProperty(node, "pending", "");
                if (!response || !response.success)
                    root.transitionFailed(node, transition.label);
                // Without a response the node may be gone, the next refresh() queries the state.
                if (response)
                    d.queryState(node);
            });
    }

    ServiceClientCache {
        id: clientCache
    }
    QtObject {
        id: d
        function queryState(node) {
            if (clientCache.isPending(node, "/get_state"))
                return;
            clientCache.send(node, "/get_state", "lifecycle_msgs/srv/GetState", {}, response => {
                    if (response)
                        d.setNodeState(node, response.current_state.label);
                });
        }
        function queryTransitions(node) {
            clientCache.send(node, "/get_available_transitions", "lifecycle_msgs/srv/GetAvailableTransitions", {}, response => {
                    if (!response || node !== root.selectedNode)
                        return;
                    const transitions = [];
                    for (let i = 0; i < response.available_transitions.length; ++i) {
                        const t = response.available_transitions.at(i).transition;
                        // Ids from 10 up are the state machine's internal callback transitions, e.g. on_configure_success.
                        if (t.id >= 1 && t.id <= 8)
                            transitions.push({
                                    "id": t.id,
                                    "label": t.label
                                });
                    }
                    root.availableTransitions = transitions;
                });
        }
        // Sets the role of the node's row; returns whether the value changed.
        function setNodeProperty(node, role, value) {
            for (let i = 0; i < root.nodes.count; ++i) {
                if (root.nodes.get(i).name !== node)
                    continue;
                if (root.nodes.get(i)[role] === value)
                    return false;
                root.nodes.setProperty(i, role, value);
                return true;
            }
            return false;
        }
        function setNodeState(node, state) {
            if (d.setNodeProperty(node, "state", state) && node === root.selectedNode)
                d.queryTransitions(node);
        }
    }
    Instantiator {
        model: root.nodes

        delegate: Subscription {
            required property string name

            messageType: "lifecycle_msgs/msg/TransitionEvent"
            topic: name + "/transition_event"

            onNewMessage: msg => d.setNodeState(name, msg.goal_state.label)
        }
    }
}
