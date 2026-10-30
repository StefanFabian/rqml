.pragma library

// Nested, labeled namespace boxes around graph nodes. A namespace gets a box if it holds at least two nodes or boxes,
// otherwise its content joins the enclosing box.
// opts: {nodeWidth, nodeHeight, rowGap, boxPadding, boxLabelHeight} in graph units.

/**
 * Groups the node ids (full node names) by namespace.
 * Returns {groups: {id: namespace}, boxParents: {namespace: namespace}}: the innermost box of each node, "/" outside of
 * all boxes, and the enclosing box of each box, "/" for the top level.
 */
function group(nodes) {
    const namespaceOf = name => name.slice(0, name.lastIndexOf("/")) || "/";
    const tree = {};
    const entry = ns => {
        if (!tree[ns]) {
            tree[ns] = {
                "nodes": [],
                "children": []
            };
            if (ns !== "/")
                entry(namespaceOf(ns)).children.push(ns);
        }
        return tree[ns];
    };
    nodes.forEach(id => entry(namespaceOf(id)).nodes.push(id));
    const groups = {};
    const boxParents = {};
    // Returns the nodes and boxes that the enclosing box takes over.
    const collect = ns => {
        const members = {
            "nodes": tree[ns].nodes.slice(),
            "boxes": []
        };
        tree[ns].children.forEach(child => {
            const m = collect(child);
            members.nodes.push(...m.nodes);
            members.boxes.push(...m.boxes);
        });
        if (ns !== "/" && members.nodes.length + members.boxes.length < 2)
            return members;
        members.nodes.forEach(id => groups[id] = ns);
        members.boxes.forEach(box => boxParents[box] = ns);
        return {
            "nodes": [],
            "boxes": [ns]
        };
    };
    if (nodes.length > 0)
        collect("/");
    return {
        "groups": groups,
        "boxParents": boxParents
    };
}

/**
 * Space between the bands of two consecutive groups of @p grouping (see group()), enough for the box borders and
 * labels in between.
 */
function gap(grouping, above, below, opts) {
    const chain = ns => ns === "/" ? ["/"] : [ns].concat(chain(grouping.boxParents[ns]));
    const up = chain(above);
    const down = chain(below);
    const closed = up.findIndex(ns => down.includes(ns));
    const opened = down.indexOf(up[closed]);
    return Math.max(opts.nodeHeight + opts.rowGap, closed * opts.boxPadding + opened * (opts.boxPadding + opts.boxLabelHeight));
}

/**
 * Returns the boxes {namespace: rect} of @p grouping (see group()) around the node centers @p positions {id: {x, y}},
 * inner boxes first.
 */
function boxes(grouping, nodes, positions, opts) {
    const extents = {};
    const extend = (ns, x0, y0, x1, y1) => {
        const e = extents[ns] = extents[ns] ?? {
            "x0": x0,
            "y0": y0,
            "x1": x1,
            "y1": y1
        };
        e.x0 = Math.min(e.x0, x0);
        e.y0 = Math.min(e.y0, y0);
        e.x1 = Math.max(e.x1, x1);
        e.y1 = Math.max(e.y1, y1);
    };
    nodes.forEach(id => {
        const ns = grouping.groups[id];
        const p = positions[id];
        if (ns in grouping.boxParents)
            extend(ns, p.x - opts.nodeWidth / 2, p.y - opts.nodeHeight / 2, p.x + opts.nodeWidth / 2, p.y + opts.nodeHeight / 2);
    });
    const result = {};
    // Inner boxes are deeper, so each box is complete before it extends its parent.
    const depth = ns => ns.split("/").length;
    Object.keys(grouping.boxParents).sort((a, b) => depth(b) - depth(a)).forEach(ns => {
        const e = extents[ns];
        const b = result[ns] = Qt.rect(e.x0 - opts.boxPadding, e.y0 - opts.boxPadding - opts.boxLabelHeight, e.x1 - e.x0 + 2 * opts.boxPadding, e.y1 - e.y0 + 2 * opts.boxPadding + opts.boxLabelHeight);
        if (grouping.boxParents[ns] !== "/")
            extend(grouping.boxParents[ns], b.x, b.y, b.x + b.width, b.y + b.height);
    });
    return result;
}
