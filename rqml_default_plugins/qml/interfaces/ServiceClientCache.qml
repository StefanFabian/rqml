import QtQuick
import Ros2
import RQml.Utils as Utils

/**
 * Sends requests to the services of a set of nodes through one service client per service, created on first use.
 * Requests that get no response in time or whose node vanished fail, see retain().
 */
Utils.Object {
    id: root

    //! Clients by node name, then by service suffix.
    property var clients: ({})

    //! Unanswered requests as [{name, suffix, sentAt, callback}].
    property var pending: []

    //! Milliseconds without a response after which retain() fails a request.
    property int responseTimeout: 30000

    /**
     * Returns the sorted names of the nodes offering a service "<name><suffix>" of the given type.
     */
    function discover(type, suffix) {
        // A service with only clients, e.g. ours of a vanished node, stays listed in the graph, so ask the servers.
        const names = Ros2.getAllNodeInfo().filter(node => node.serviceServers.some(s => s.name === node.fullName + suffix && s.datatypes.includes(type))).map(node => node.fullName);
        // ROS 2 allows duplicate node names.
        return [...new Set(names)].sort();
    }
    function finish(entry, response) {
        // A response after retain() failed the request is dropped.
        const index = root.pending.indexOf(entry);
        if (index < 0)
            return;
        root.pending.splice(index, 1);
        entry.callback(response);
    }

    /**
     * Whether a request to the service "<name><suffix>" is unanswered and younger than responseTimeout.
     */
    function isPending(name, suffix) {
        const now = Date.now();
        return root.pending.some(r => r.name === name && r.suffix === suffix && now - r.sentAt <= root.responseTimeout);
    }

    /**
     * Destroys the clients of all names not in @p names and fails their requests and those older than
     * responseTimeout. A client keeps its service listed in the ROS graph, so the clients of vanished nodes must go.
     */
    function retain(names) {
        for (const name of Object.keys(root.clients)) {
            if (names.includes(name))
                continue;
            for (const client of Object.values(root.clients[name]))
                client.destroy();
            delete root.clients[name];
        }
        // shortcut: ServiceClient never times out a sent request (lost if its node restarts), drop once it has a response timeout
        const now = Date.now();
        for (const request of root.pending.filter(r => !names.includes(r.name) || now - r.sentAt > root.responseTimeout))
            root.finish(request, null);
    }

    /**
     * Sends @p request to the service "<name><suffix>" of the given type. Calls @p callback exactly once, with the
     * response, or with null if the request failed, got no response within responseTimeout or its node vanished.
     */
    function send(name, suffix, type, request, callback) {
        const nodeClients = root.clients[name] ?? (root.clients[name] = {});
        if (!nodeClients[suffix])
            nodeClients[suffix] = Ros2.createServiceClient(name + suffix, type);
        const entry = {
            "name": name,
            "suffix": suffix,
            "sentAt": Date.now(),
            "callback": callback
        };
        root.pending.push(entry);
        nodeClients[suffix].sendRequestAsync(request, response => root.finish(entry, response));
    }

    // Keeping every client fails only the requests older than responseTimeout.
    Timer {
        interval: root.responseTimeout
        repeat: true
        running: true

        onTriggered: root.retain(Object.keys(root.clients))
    }
}
