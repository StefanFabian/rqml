.pragma library

// QML interpreter: for...of is 10x slower than forEach, Map lookups are linear, callback indices are slow doubles.

/**
 * Layered left-to-right layout of a directed graph.
 * nodes: [id], edges: [{from, to}], opts: {nodeWidth, nodeHeight, layerGap, rowGap, groupOf, groupGap}.
 * Returns the node centers as {id: {x, y}}.
 * Edges point to the right unless they close a cycle. Connected parts are stacked vertically, largest first,
 * with the nodes without edges in a grid below. The result does not depend on the input order.
 * With the optional groupOf(id) -> "/"-separated path, the nodes of each group form a horizontal band instead, with the
 * nodes without edges at its bottom. Bands are stacked in path order, each group directly followed by its subgroups.
 * The optional groupGap(above, below) -> px is the space added to rowGap between two consecutive bands, one row by default.
 */
function layout(nodes, edges, opts) {
    const colStep = opts.nodeWidth + opts.layerGap;
    const rowStep = opts.nodeHeight + opts.rowGap;
    // Nodes are numbered in id order, so every tie broken by number is broken by id.
    const ids = nodes.slice().sort().filter((id, i, sorted) => i === 0 || id !== sorted[i - 1]);
    const numberOf = Object.create(null);
    for (let i = 0; i < ids.length; ++i)
        numberOf[ids[i]] = i;
    const succ = ids.map(() => []);
    const pred = ids.map(() => []);
    edges.forEach(edge => {
        const from = numberOf[edge.from];
        const to = numberOf[edge.to];
        if (from !== undefined && to !== undefined && from !== to && !succ[from].includes(to)) {
            succ[from].push(to);
            pred[to].push(from);
        }
    });
    const ascending = (a, b) => a - b;
    succ.forEach(list => list.sort(ascending));
    pred.forEach(list => list.sort(ascending));
    const seen = ids.map(() => false);
    const components = [];
    for (let i = 0; i < ids.length; ++i) {
        if (seen[i])
            continue;
        const members = [];
        const stack = [i];
        seen[i] = true;
        while (stack.length > 0) {
            const v = stack.pop();
            members.push(v);
            succ[v].concat(pred[v]).forEach(u => {
                if (!seen[u]) {
                    seen[u] = true;
                    stack.push(u);
                }
            });
        }
        components.push(members.sort(ascending));
    }
    const isolated = components.filter(c => c.length === 1).map(c => c[0]);
    const connected = components.filter(c => c.length > 1).sort((a, b) => b.length - a.length || a[0] - b[0]);
    // Components are disjoint, so they share the per-node work arrays instead of each allocating them for all nodes.
    const graph = {
        succ,
        pred,
        indeg: pred.map(list => list.length),
        outdeg: succ.map(list => list.length),
        removed: ids.map(() => false),
        rank: ids.map(() => 0),
        layer: ids.map(() => 0),
        index: ids.map(() => 0),
        key: ids.map(() => 0),
        group: ids.map(() => 0)
    };
    const positions = {};
    // Places the layers centered on their tallest one and returns the top of the next row.
    const place = (layers, top) => {
        const rows = layers.reduce((max, layer) => Math.max(max, layer.length), 0);
        layers.forEach((layer, l) => layer.forEach((v, i) => positions[ids[v]] = {
            x: l * colStep + opts.nodeWidth / 2,
            y: top + ((rows - layer.length) / 2 + i) * rowStep + opts.nodeHeight / 2
        }));
        return top + rows * rowStep;
    };
    // Places the nodes row by row and returns the top of the next row.
    const grid = (list, cols, top) => {
        list.forEach((v, i) => positions[ids[v]] = {
            x: (i % cols) * colStep + opts.nodeWidth / 2,
            y: top + Math.floor(i / cols) * rowStep + opts.nodeHeight / 2
        });
        return top + Math.ceil(list.length / cols) * rowStep;
    };
    if (!opts.groupOf) {
        let top = 0;
        let layerCount = 0;
        connected.forEach(members => {
            const layers = layerComponent(members, graph);
            orderLayers(layers, graph);
            top = place(layers, top) + rowStep;
            layerCount = Math.max(layerCount, layers.length);
        });
        grid(isolated, Math.max(layerCount, Math.ceil(Math.sqrt(isolated.length))), top);
        return positions;
    }
    const groupOf = ids.map(opts.groupOf);
    // "/" compares below every other character, so that "/a/b" comes between "/a" and "/a-b".
    const pathKey = name => name.replace(/\//g, "\u0000");
    const groups = groupOf.slice().sort().filter((name, i, sorted) => i === 0 || name !== sorted[i - 1]).sort((a, b) => pathKey(a) < pathKey(b) ? -1 : 1);
    const groupNumber = Object.create(null);
    groups.forEach((name, i) => groupNumber[name] = i);
    for (let v = 0; v < ids.length; ++v)
        graph.group[v] = groupNumber[groupOf[v]];
    // The components share layers, so that the crossing reduction orders each group's band across all of them.
    const layers = [];
    connected.forEach(members => layerComponent(members, graph).forEach((layer, l) => (layers[l] = layers[l] || []).push(...layer)));
    orderLayers(layers, graph);
    const bands = groups.map(() => ({ layers: layers.map(() => []), isolated: [] }));
    layers.forEach((layer, l) => layer.forEach(v => bands[graph.group[v]].layers[l].push(v)));
    isolated.forEach(v => bands[graph.group[v]].isolated.push(v));
    let top = 0;
    bands.forEach((band, i) => {
        if (i > 0)
            top += opts.groupGap ? opts.groupGap(groups[i - 1], groups[i]) : rowStep;
        const cols = Math.max(layers.length, Math.ceil(Math.sqrt(band.isolated.length)));
        top = grid(band.isolated, cols, place(band.layers, top));
    });
    return positions;
}

// Splits a connected component into layers so that every edge not closing a cycle points to a later layer.
function layerComponent(members, graph) {
    const { succ, pred, indeg, outdeg, removed, rank, layer } = graph;
    // Eades-Lin-Smyth: sinks go to the back, sources to the front, otherwise the node with the most surplus out-edges.
    const sinks = members.filter(v => outdeg[v] === 0);
    const sources = members.filter(v => indeg[v] === 0);
    const surplus = v => outdeg[v] - indeg[v];
    // Ties go to the node fed by the most placed nodes, so that feedback loops point back against the main flow.
    const placedPreds = v => pred[v].length - indeg[v];
    const head = [];
    const tail = [];
    let remaining = members.length;
    while (remaining > 0) {
        let v = sinks.length > 0 ? sinks.pop() : sources.length > 0 ? sources.pop() : -1;
        if (v < 0) {
            members.forEach(u => {
                if (!removed[u] && (v < 0 || surplus(u) > surplus(v) || (surplus(u) === surplus(v) && placedPreds(u) > placedPreds(v))))
                    v = u;
            });
        } else if (removed[v]) {
            continue; // a node without neighbors left is both a sink and a source
        }
        (outdeg[v] === 0 ? tail : head).push(v);
        removed[v] = true;
        --remaining;
        succ[v].forEach(u => {
            if (!removed[u] && --indeg[u] === 0)
                sources.push(u);
        });
        pred[v].forEach(u => {
            if (!removed[u] && --outdeg[u] === 0)
                sinks.push(u);
        });
    }
    const order = head.concat(tail.reverse());
    order.forEach((v, i) => rank[v] = i);
    // Longest path from the sources, ignoring the edges against the order.
    order.forEach(v => pred[v].forEach(u => {
        if (rank[u] < rank[v])
            layer[v] = Math.max(layer[v], layer[u] + 1);
    }));
    // Sources that only feed deep layers would otherwise pile up in the first layer with long edges.
    members.forEach(v => {
        if (pred[v].length === 0)
            layer[v] = Math.min(...succ[v].map(u => layer[u])) - 1;
    });
    const layers = [];
    members.forEach(v => (layers[layer[v]] = layers[layer[v]] || []).push(v));
    return layers;
}

// Reduces edge crossings by sorting each layer by group, then by the mean index of its neighbors, ties keep the previous order.
function orderLayers(layers, graph) {
    const { succ, pred, index, key, group } = graph;
    const reindex = layer => layer.forEach((v, i) => index[v] = i);
    const sortBy = (layer, neighbors) => {
        layer.forEach(v => {
            const ns = neighbors[v];
            key[v] = ns.length > 0 ? ns.reduce((sum, u) => sum + index[u], 0) / ns.length : index[v];
        });
        layer.sort((a, b) => group[a] - group[b] || key[a] - key[b] || index[a] - index[b]);
        reindex(layer);
    };
    layers.forEach(reindex);
    for (let sweep = 0; sweep < 4; ++sweep) {
        for (let l = 1; l < layers.length; ++l)
            sortBy(layers[l], pred);
        for (let l = layers.length - 2; l >= 0; --l)
            sortBy(layers[l], succ);
    }
}
