.pragma library
.import RQml.Utils 1.0 as Utils

// Dictionaries are plain objects because Map and Set lookups take linear time in the QML engine.

//! Topics hidden by the hideCommon filter of buildGraph().
const COMMON_HUB_TOPICS = Utils.InterfaceFilter.DEFAULT_TOPICS.concat("/clock");

//! Interface kinds as [kind, role of the edge sources, role of the edge targets].
const KINDS = [["topic", "publishers", "subscriptions"], ["service", "serviceClients", "serviceServers"], ["action", "actionClients", "actionServers"]];

/**
 * Builds the directed graph of the topic, service and action connections between nodes.
 * infos: nodes as returned by Ros2.getAllNodeInfo(), missing lists count as empty.
 * opts: {hideHidden, hideCommon, hideTf, showTopics, showServices, showActions} hide nodes whose name starts with "_",
 * COMMON_HUB_TOPICS and the default services, TF topics, and show topic (default true), service and action connections.
 * Returns {nodes: [id], edges: [{from, to, interfaces: [{kind, name, datatypes}]}]} with one edge per ordered node pair
 * from publisher to subscriber and from client to server. Nodes, edges and interfaces (by kind, then name) are sorted
 * and self connections are left out.
 */
function buildGraph(infos, opts) {
    const isTf = name => name.endsWith("/tf") || name.endsWith("/tf_static");
    const hidden = {
        "topic": name => (opts.hideCommon && COMMON_HUB_TOPICS.includes(name)) || (opts.hideTf && isTf(name)),
        "service": name => opts.hideCommon && Utils.InterfaceFilter.isDefaultService(name),
        "action": () => false
    };
    const shown = {
        "topic": opts.showTopics ?? true,
        "service": opts.showServices,
        "action": opts.showActions
    };
    const kinds = KINDS.filter(([kind]) => shown[kind]);
    const nodes = Object.create(null);
    const interfaces = Object.create(null); // "kind name" -> {kind, name, datatypes, sources: {id: true}, targets: {id: true}}
    infos.forEach(info => {
        if (opts.hideHidden && info.name.startsWith("_"))
            return;
        nodes[info.fullName] = true;
        kinds.forEach(([kind, sourceRole, targetRole]) => [sourceRole, targetRole].forEach(role => (info[role] || []).forEach(endpoint => {
            if (hidden[kind](endpoint.name))
                return;
            const key = kind + " " + endpoint.name;
            if (!interfaces[key])
                interfaces[key] = { kind, name: endpoint.name, datatypes: [], sources: Object.create(null), targets: Object.create(null) };
            const iface = interfaces[key];
            iface[role === sourceRole ? "sources" : "targets"][info.fullName] = true;
            if (iface.datatypes.length === 0 && endpoint.datatypes)
                iface.datatypes = endpoint.datatypes;
        })));
    });
    const edges = Object.create(null); // "from to" -> edge
    Object.keys(interfaces).sort().forEach(key => {
        const iface = interfaces[key];
        const targets = Object.keys(iface.targets);
        Object.keys(iface.sources).forEach(from => targets.forEach(to => {
            if (from === to)
                return;
            const edgeKey = from + " " + to;
            if (!edges[edgeKey])
                edges[edgeKey] = { from, to, interfaces: [] };
            edges[edgeKey].interfaces.push({ kind: iface.kind, name: iface.name, datatypes: iface.datatypes });
        }));
    });
    const compare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
    return {
        nodes: Object.keys(nodes).sort(),
        edges: Object.values(edges).sort((a, b) => compare(a.from, b.from) || compare(a.to, b.to))
    };
}

/**
 * Counts per node the subscriptions without publishers and the service and action clients without servers, leaving
 * out clients of the default services. infos: all nodes as returned by Ros2.getAllNodeInfo(), as the counterparts
 * of a node can be anywhere. Returns {fullName: count} with the nodes whose count is above zero.
 */
function countUnconnected(infos) {
    const offered = { "publishers": Object.create(null), "serviceServers": Object.create(null), "actionServers": Object.create(null) };
    infos.forEach(info => Object.keys(offered).forEach(role => (info[role] || []).forEach(endpoint => offered[role][endpoint.name] = true)));
    const result = {};
    infos.forEach(info => {
        const missing = (role, offeredRole) => (info[role] || []).filter(e => !offered[offeredRole][e.name]);
        const count = missing("subscriptions", "publishers").length + missing("serviceClients", "serviceServers").filter(e => !Utils.InterfaceFilter.isDefaultService(e.name)).length + missing("actionClients", "actionServers").length;
        if (count > 0)
            result[info.fullName] = count;
    });
    return result;
}
