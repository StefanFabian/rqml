import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import RQml.Elements
import RQml.Fonts
import "GraphLayout.js" as GraphLayout
import "NamespaceBoxes.js" as NamespaceBoxes

/**
 * Directed graph of the topic, service and action connections between nodes.
 * Supports panning, zooming, searching, selecting and temporarily moving nodes. Hovering or selecting a node highlights its
 * edges and the nodes at their other end. Selecting additionally dims the rest. Escape clears the selection.
 */
Item {
    id: root

    //! Edges [{from, to, interfaces: [{kind, name, datatypes}]}] between ids in nodes, kind is "topic", "service" or "action".
    property var edges: []

    //! Keeps the nodes of each namespace together and draws nested, labeled boxes around them. A namespace gets a box
    //! if it holds at least two nodes or boxes, otherwise its content joins the enclosing box. Node labels are relative
    //! to their box.
    property bool groupNamespaces: false

    //! Whether there are nodes before filtering. Selects the hint shown when nodes is empty.
    property bool hasUnfilteredNodes: false

    //! Ids of the nodes the user chose to ignore from the node menu. Their edges are left out and they are drawn grayed
    //! out in a separate box below the graph. Ids not in nodes are kept, so that a node stays ignored when it returns.
    property var ignoredNodes: []

    //! Shows a busy indicator instead of the empty-state hint.
    property bool loading: false

    //! Node ids (full node names).
    property var nodes: []

    //! Lowercase search text. Matching nodes are outlined, all others dimmed.
    property string searchText: ""

    //! Count of subscriptions without publishers and clients without servers by node id. Marks the node with a warning.
    property var unconnected: ({})

    //! Emitted when the user changed ignoredNodes from the node menu.
    signal ignoredNodesEdited

    //! Emitted when the user asks to inspect a node.
    signal inspectNodeRequested(string id)

    //! @internal Returns the screen-space center of the count badge of an edge, null if there is none. For test use.
    function _testBadgeCenter(from, to) {
        const edge = d.edges.find(e => e.from === from && e.to === to);
        if (!edge)
            return null;
        const g = d.edgeGeometry(edge);
        return canvas.mapToScreen(g.mx, g.my);
    }

    //! @internal Returns the screen-space boxes drawn around the namespaces as {namespace: rect}. For test use.
    function _testNamespaceBoxes() {
        const boxes = root.groupNamespaces ? d.namespaceBoxes() : {};
        for (const ns in boxes) {
            const b = boxes[ns];
            const topLeft = canvas.mapToScreen(b.x, b.y);
            boxes[ns] = Qt.rect(topLeft.x, topLeft.y, b.width * canvas.zoom, b.height * canvas.zoom);
        }
        return boxes;
    }

    //! @internal Returns the label drawn on a node, null if it is not laid out. For test use.
    function _testNodeLabel(id) {
        return d.labels[id] ?? null;
    }

    //! @internal Returns the screen-space rectangle of a node, null if it is not laid out. For test use.
    function _testNodeRect(id) {
        const p = d.positions[id];
        if (!p)
            return null;
        const topLeft = canvas.mapToScreen(p.x - d.nodeWidth / 2, p.y - d.nodeHeight / 2);
        return Qt.rect(topLeft.x, topLeft.y, d.nodeWidth * canvas.zoom, d.nodeHeight * canvas.zoom);
    }

    //! @internal Returns the id of the selected node, "" if none. For test use.
    function _testSelectedNode() {
        return d.selectedNode;
    }

    /**
     * Zooms and centers the view so that all nodes are visible.
     */
    function fitToView() {
        if (d.nodes.length === 0)
            return;
        const xs = d.nodes.map(id => d.positions[id].x);
        const ys = d.nodes.map(id => d.positions[id].y);
        const minX = Math.min(...xs) - d.nodeWidth / 2;
        const maxX = Math.max(...xs) + d.nodeWidth / 2;
        const minY = Math.min(...ys) - d.nodeHeight / 2;
        const maxY = Math.max(...ys) + d.nodeHeight / 2;
        canvas.fit(Qt.rect(minX, minY, maxX - minX, maxY - minY));
    }

    /**
     * Centers the next (or previous) node matching searchText, zooming in to at least 100%.
     */
    function jumpToNextMatch(forward) {
        const matches = d.nodes.filter(id => d.isMatch(id));
        if (matches.length === 0)
            return;
        const n = matches.length;
        const i = matches.indexOf(d.currentMatch);
        d.currentMatch = matches[i < 0 ? (forward ? 0 : n - 1) : (i + (forward ? 1 : n - 1)) % n];
        const p = d.positions[d.currentMatch];
        canvas.centerOn(p.x, p.y);
    }

    Keys.onEscapePressed: event => {
        event.accepted = d.selectedNode !== "";
        d.select("");
    }
    onEdgesChanged: Qt.callLater(d.relayout)
    onGroupNamespacesChanged: Qt.callLater(d.relayout)
    onIgnoredNodesChanged: Qt.callLater(d.relayout)
    onNodesChanged: Qt.callLater(d.relayout)
    onSearchTextChanged: {
        d.currentMatch = "";
        canvas.requestPaint();
    }
    onUnconnectedChanged: canvas.requestPaint()

    QtObject {
        id: d

        readonly property int badgeRadius: 9
        readonly property int boxLabelHeight: 14
        readonly property int boxPadding: 6
        property string currentMatch: ""

        //! Pressed node or background: {node, x, y, start, moving}, null while released.
        property var drag: null

        //! Kind of each edge in edges, "mixed" if it has interfaces of several kinds.
        property var edgeKinds: []

        //! Stroke color and dash pattern per edge kind.
        readonly property var edgeStyles: ({
                "topic": {
                    "color": Material.color(Material.Grey),
                    "dash": []
                },
                "service": {
                    "color": Material.color(Material.Teal),
                    "dash": [6, 4]
                },
                "action": {
                    "color": Material.color(Material.Orange),
                    "dash": [2, 3]
                },
                "mixed": {
                    "color": Material.color(Material.Grey),
                    "dash": [8, 3, 2, 3]
                }
            })

        //! root.edges as of the last relayout(), consistent with positions.
        property var edges: []

        //! Namespace grouping of the shown nodes, see NamespaceBoxes.group(). Empty if not grouping.
        property var grouping: NamespaceBoxes.group([])
        property var hoveredEdge: null
        property string hoveredNode: ""

        //! root.ignoredNodes as of the last relayout() as {id: true}.
        property var ignored: ({})
        readonly property color ignoredColor: Material.color(Material.Grey, Material.Shade600)
        readonly property var kindNames: ({
                "topic": qsTr("Topic"),
                "service": qsTr("Service"),
                "action": qsTr("Action"),
                "mixed": qsTr("Mixed")
            })
        property var labels: ({})
        readonly property int layerGap: 70

        //! JSON of the positions last fitted to the view.
        property string layoutKey: ""

        //! Sizes in graph units for GraphLayout and NamespaceBoxes.
        readonly property var layoutOpts: ({
                "nodeWidth": nodeWidth,
                "nodeHeight": nodeHeight,
                "layerGap": layerGap,
                "rowGap": rowGap,
                "boxPadding": boxPadding,
                "boxLabelHeight": boxLabelHeight
            })

        //! Edge kinds present in edges, in legend order.
        property var legendKinds: []
        property var menuEdge: null
        property string menuNode: ""
        readonly property color nodeColor: Material.color(Material.Blue, Material.Shade700)
        readonly property int nodeHeight: 30
        readonly property int nodeWidth: 150

        //! root.nodes as of the last relayout(), consistent with positions.
        property var nodes: []

        //! Node centers in graph coordinates.
        property var positions: ({})
        readonly property int rowGap: 16

        //! Node clicked last, "" if none. Highlighted like the hovered node and additionally dims unrelated nodes and edges.
        property string selectedNode: ""
        readonly property color warningColor: Material.color(Material.Orange)
        readonly property int warningRadius: 7

        function badgeAt(x, y) {
            const p = canvas.mapToGraph(x, y);
            for (let i = d.edges.length - 1; i >= 0; --i) {
                const g = d.edgeGeometry(d.edges[i]);
                if (Math.hypot(g.mx - p.x, g.my - p.y) <= d.badgeRadius)
                    return d.edges[i];
            }
            return null;
        }

        // Cubic curve from the source's right side to the target's left side and its midpoint (mx, my).
        function edgeGeometry(edge) {
            const from = d.positions[edge.from];
            const to = d.positions[edge.to];
            const x0 = from.x + d.nodeWidth / 2;
            const x3 = to.x - d.nodeWidth / 2;
            const reach = x3 > x0 ? (x3 - x0) / 2 : d.layerGap;
            // Edges that point back or skip a layer arc above the nodes in between, which also keeps A->B and B->A apart.
            const bow = x3 > x0 && x3 - x0 <= d.layerGap ? 0 : d.nodeHeight + Math.abs(x3 - x0) / 8;
            const g = {
                "x0": x0,
                "y0": from.y,
                "x1": x0 + reach,
                "y1": from.y - bow,
                "x2": x3 - reach,
                "y2": to.y - bow,
                "x3": x3,
                "y3": to.y
            };
            g.mx = (g.x0 + 3 * g.x1 + 3 * g.x2 + g.x3) / 8;
            g.my = (g.y0 + 3 * g.y1 + 3 * g.y2 + g.y3) / 8;
            return g;
        }
        function edgeTooltip(edge) {
            return [edge.from + " → " + edge.to].concat(edge.interfaces.map(i => d.kindNames[i.kind] + " " + i.name + " [" + i.datatypes.join(", ") + "]")).join("\n");
        }
        // Graph-space box around the current positions of the ignored nodes, null if there are none.
        function ignoredBox() {
            const ids = d.nodes.filter(id => d.ignored[id]);
            if (ids.length === 0)
                return null;
            const xs = ids.map(id => d.positions[id].x);
            const ys = ids.map(id => d.positions[id].y);
            const x0 = Math.min(...xs) - d.nodeWidth / 2 - d.boxPadding;
            const y0 = Math.min(...ys) - d.nodeHeight / 2 - d.boxPadding - d.boxLabelHeight;
            return Qt.rect(x0, y0, Math.max(...xs) + d.nodeWidth / 2 + d.boxPadding - x0, Math.max(...ys) + d.nodeHeight / 2 + d.boxPadding - y0);
        }
        function isMatch(id) {
            return root.searchText !== "" && id.toLowerCase().includes(root.searchText);
        }
        // Graph-space boxes {namespace: rect} around the current node positions, inner boxes first.
        function namespaceBoxes() {
            return NamespaceBoxes.boxes(d.grouping, d.nodes, d.positions, d.layoutOpts);
        }
        function nodeAt(x, y) {
            const p = canvas.mapToGraph(x, y);
            for (let i = d.nodes.length - 1; i >= 0; --i) {
                const c = d.positions[d.nodes[i]];
                if (Math.abs(c.x - p.x) <= d.nodeWidth / 2 && Math.abs(c.y - p.y) <= d.nodeHeight / 2)
                    return d.nodes[i];
            }
            return "";
        }
        function nodeTooltip(id) {
            if (d.ignored[id])
                return qsTr("%1\nIgnored, its connections are not shown").arg(id);
            const outgoing = d.edges.filter(e => e.from === id).length;
            const incoming = d.edges.filter(e => e.to === id).length;
            const unconnected = root.unconnected[id] ?? 0;
            const warning = unconnected === 0 ? "" : unconnected === 1 ? qsTr("\n1 subscription or client has no publisher or server") : qsTr("\n%1 subscriptions or clients have no publisher or server").arg(unconnected);
            return qsTr("%1\nOutgoing: %2\nIncoming: %3").arg(id).arg(outgoing).arg(incoming) + warning;
        }
        function relayout() {
            const ignored = {};
            root.ignoredNodes.forEach(id => ignored[id] = true);
            d.ignored = ignored;
            d.nodes = root.nodes;
            d.edges = root.edges.filter(edge => !ignored[edge.from] && !ignored[edge.to]);
            const shown = d.nodes.filter(id => !ignored[id]);
            const grouping = NamespaceBoxes.group(root.groupNamespaces ? shown : []);
            d.grouping = grouping;
            d.positions = GraphLayout.layout(shown, d.edges, Object.assign({
                        "groupOf": root.groupNamespaces ? id => grouping.groups[id] : undefined,
                        "groupGap": (above, below) => NamespaceBoxes.gap(grouping, above, below, d.layoutOpts)
                    }, d.layoutOpts));
            // The ignored nodes go in a grid one row below the graph and its boxes, leaving room for their own box.
            const bottoms = shown.map(id => d.positions[id].y + d.nodeHeight / 2).concat(Object.values(d.namespaceBoxes()).map(b => b.y + b.height));
            const top = (shown.length > 0 ? Math.max(...bottoms) + d.nodeHeight + d.rowGap : 0) + d.boxPadding + d.boxLabelHeight;
            const aside = GraphLayout.layout(d.nodes.filter(id => ignored[id]), [], d.layoutOpts);
            for (const id in aside)
                d.positions[id] = {
                    "x": aside[id].x,
                    "y": top + aside[id].y
                };
            d.edgeKinds = d.edges.map(edge => edge.interfaces.every(i => i.kind === edge.interfaces[0].kind) ? edge.interfaces[0].kind : "mixed");
            d.legendKinds = ["topic", "service", "action", "mixed"].filter(kind => d.edgeKinds.includes(kind));
            const shortName = id => id.slice(id.lastIndexOf("/") + 1);
            const counts = Object.create(null);
            d.nodes.forEach(id => counts[shortName(id)] = (counts[shortName(id)] ?? 0) + 1);
            const labels = {};
            // Inside a box, the path relative to it is unique and shows the namespaces that got no box of their own.
            // Ignored nodes are in no box.
            const name = id => root.groupNamespaces ? id.slice((d.grouping.groups[id] ?? "/") === "/" ? 1 : d.grouping.groups[id].length + 1) : counts[shortName(id)] > 1 ? id : shortName(id);
            d.nodes.forEach(id => labels[id] = labelMetrics.elidedText(name(id), Qt.ElideLeft, d.nodeWidth - 12));
            d.labels = labels;
            d.hoveredNode = "";
            d.hoveredEdge = null;
            if (!d.positions[d.selectedNode])
                d.selectedNode = "";
            // A rebuild that leaves the layout unchanged keeps the user's zoom and pan.
            const layoutKey = JSON.stringify(d.positions);
            if (layoutKey !== d.layoutKey) {
                d.layoutKey = layoutKey;
                root.fitToView();
            }
            canvas.requestPaint();
        }
        function select(id) {
            d.selectedNode = id;
            canvas.requestPaint();
        }
        function setHover(node, edge) {
            if (node === d.hoveredNode && edge === d.hoveredEdge)
                return;
            d.hoveredNode = node;
            d.hoveredEdge = edge;
            canvas.requestPaint();
        }
    }
    FontMetrics {
        id: labelMetrics
        font.bold: true
        font.family: "sans-serif"
        font.pixelSize: 11
    }
    GraphCanvas {
        id: canvas
        anchors.fill: parent

        onFitRequested: root.fitToView()
        // shortcut: draws off-screen nodes and edges too, which is slow zoomed in on hundreds of nodes, cull to the view if such graphs become common
        onPaint: ctx => {
            ctx.font = "bold 11px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            // Text is unreadable below this scale and would take most of the paint time.
            const showText = canvas.zoom >= 0.5;
            const edges = d.edges;
            // Hovering only highlights, dimming the rest is reserved for the selection so that moving the mouse stays calm.
            const focused = id => id !== "" && (id === d.hoveredNode || id === d.selectedNode);
            const selecting = d.selectedNode !== "";
            const searching = root.searchText !== "";
            const highlighted = edge => edge === d.hoveredEdge || focused(edge.from) || focused(edge.to);
            const dimmed = edge => (selecting && !highlighted(edge)) || (searching && !d.isMatch(edge.from) && !d.isMatch(edge.to));
            const neighbors = {};
            edges.forEach(edge => {
                    if (focused(edge.from))
                        neighbors[edge.to] = true;
                    if (focused(edge.to))
                        neighbors[edge.from] = true;
                });
            if (root.groupNamespaces) {
                const boxes = d.namespaceBoxes();
                ctx.textAlign = "left";
                ctx.lineWidth = 1 / canvas.zoom;
                // Outer boxes first, so that the inner ones are drawn on top.
                for (const ns of Object.keys(boxes).reverse()) {
                    const b = boxes[ns];
                    ctx.fillStyle = palette.alternateBase;
                    ctx.strokeStyle = palette.mid;
                    ctx.beginPath();
                    ctx.roundedRect(b.x, b.y, b.width, b.height, 8, 8);
                    ctx.fill();
                    ctx.stroke();
                    if (showText) {
                        ctx.fillStyle = palette.text;
                        ctx.fillText(labelMetrics.elidedText(ns, Qt.ElideLeft, b.width - 2 * d.boxPadding), b.x + d.boxPadding, b.y + d.boxPadding + d.boxLabelHeight / 2);
                    }
                }
                ctx.textAlign = "center";
            }
            const ignoredBox = d.ignoredBox();
            if (ignoredBox) {
                ctx.fillStyle = palette.alternateBase;
                ctx.strokeStyle = palette.mid;
                ctx.lineWidth = 1 / canvas.zoom;
                ctx.setLineDash([4, 3]);
                ctx.beginPath();
                ctx.roundedRect(ignoredBox.x, ignoredBox.y, ignoredBox.width, ignoredBox.height, 8, 8);
                ctx.fill();
                ctx.stroke();
                if (showText) {
                    ctx.textAlign = "left";
                    ctx.fillStyle = palette.text;
                    ctx.fillText(qsTr("Ignored"), ignoredBox.x + d.boxPadding, ignoredBox.y + d.boxPadding + d.boxLabelHeight / 2);
                    ctx.textAlign = "center";
                }
            }
            const geometries = edges.map(edge => d.edgeGeometry(edge));
            for (let i = 0; i < edges.length; ++i) {
                const g = geometries[i];
                const style = d.edgeStyles[d.edgeKinds[i]];
                ctx.globalAlpha = dimmed(edges[i]) ? 0.15 : 1;
                ctx.strokeStyle = ctx.fillStyle = highlighted(edges[i]) ? palette.highlight : style.color;
                ctx.lineWidth = (highlighted(edges[i]) ? 2.5 : 1.5) / canvas.zoom;
                ctx.setLineDash(style.dash);
                ctx.beginPath();
                ctx.moveTo(g.x0, g.y0);
                ctx.bezierCurveTo(g.x1, g.y1, g.x2, g.y2, g.x3, g.y3);
                ctx.stroke();
                const length = Math.hypot(g.x3 - g.x2, g.y3 - g.y2);
                const ux = (g.x3 - g.x2) / length;
                const uy = (g.y3 - g.y2) / length;
                ctx.beginPath();
                ctx.moveTo(g.x3, g.y3);
                ctx.lineTo(g.x3 - 9 * ux - 4 * uy, g.y3 - 9 * uy + 4 * ux);
                ctx.lineTo(g.x3 - 9 * ux + 4 * uy, g.y3 - 9 * uy - 4 * ux);
                ctx.fill();
            }
            ctx.setLineDash([]);
            d.nodes.forEach(id => {
                    const p = d.positions[id];
                    const unrelated = selecting && !focused(id) && !neighbors[id];
                    ctx.globalAlpha = unrelated || (searching && !d.isMatch(id)) ? 0.25 : 1;
                    ctx.fillStyle = d.ignored[id] ? d.ignoredColor : d.nodeColor;
                    ctx.beginPath();
                    ctx.roundedRect(p.x - d.nodeWidth / 2, p.y - d.nodeHeight / 2, d.nodeWidth, d.nodeHeight, 5, 5);
                    ctx.fill();
                    if (focused(id) || neighbors[id] || d.isMatch(id)) {
                        ctx.strokeStyle = palette.text;
                        ctx.lineWidth = (id === d.selectedNode ? 3 : 2) / canvas.zoom;
                        ctx.stroke();
                    }
                    if (showText) {
                        ctx.fillStyle = "white";
                        ctx.fillText(d.labels[id], p.x, p.y);
                    }
                    if (root.unconnected[id] > 0) {
                        // Same orange "!" as the node list's warning icon, on the node's top right corner.
                        const cx = p.x + d.nodeWidth / 2;
                        const cy = p.y - d.nodeHeight / 2;
                        ctx.fillStyle = d.warningColor;
                        ctx.beginPath();
                        ctx.arc(cx, cy, d.warningRadius, 0, 2 * Math.PI);
                        ctx.fill();
                        ctx.fillStyle = "black";
                        ctx.fillText("!", cx, cy);
                    }
                });
            // Badges go on top because they are the hover and right-click targets of the edges.
            for (let i = 0; i < edges.length; ++i) {
                const g = geometries[i];
                ctx.globalAlpha = dimmed(edges[i]) ? 0.15 : 1;
                ctx.fillStyle = highlighted(edges[i]) ? palette.highlight : d.nodeColor;
                ctx.beginPath();
                ctx.arc(g.mx, g.my, d.badgeRadius, 0, 2 * Math.PI);
                ctx.fill();
                if (showText) {
                    ctx.fillStyle = highlighted(edges[i]) ? palette.highlightedText : "white";
                    ctx.fillText(String(edges[i].interfaces.length), g.mx, g.my);
                }
            }
        }

        MouseArea {
            id: mouseArea
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            anchors.fill: parent
            cursorShape: pressed ? Qt.ClosedHandCursor : d.hoveredNode !== "" || d.hoveredEdge ? Qt.PointingHandCursor : Qt.OpenHandCursor
            hoverEnabled: true

            onCanceled: d.drag = null
            onDoubleClicked: mouse => {
                if (mouse.button !== Qt.LeftButton)
                    return;
                const id = d.nodeAt(mouse.x, mouse.y);
                if (id !== "")
                    root.inspectNodeRequested(id);
                else
                    root.fitToView();
            }
            onExited: d.setHover("", null)
            onPositionChanged: mouse => {
                if (!d.drag) {
                    const edge = d.badgeAt(mouse.x, mouse.y);
                    d.setHover(edge ? "" : d.nodeAt(mouse.x, mouse.y), edge);
                    return;
                }
                const dx = mouse.x - d.drag.x;
                const dy = mouse.y - d.drag.y;
                if (d.drag.node !== "" && !d.drag.moving && Math.abs(dx) + Math.abs(dy) < Application.styleHints.startDragDistance)
                    return;
                d.drag.moving = true;
                if (d.drag.node !== "") {
                    d.positions[d.drag.node] = Qt.point(d.drag.start.x + dx / canvas.zoom, d.drag.start.y + dy / canvas.zoom);
                    canvas.requestPaint();
                } else {
                    canvas.offsetX = d.drag.start.x + dx;
                    canvas.offsetY = d.drag.start.y + dy;
                }
            }
            onPressed: mouse => {
                // Takes the focus for the escape key.
                root.forceActiveFocus(Qt.MouseFocusReason);
                if (mouse.button === Qt.RightButton) {
                    d.menuEdge = d.badgeAt(mouse.x, mouse.y);
                    d.menuNode = d.menuEdge ? "" : d.nodeAt(mouse.x, mouse.y);
                    if (d.menuEdge)
                        badgeMenu.popup();
                    else if (d.menuNode !== "")
                        nodeMenu.popup();
                    return;
                }
                const id = d.nodeAt(mouse.x, mouse.y);
                d.drag = {
                    "node": id,
                    "x": mouse.x,
                    "y": mouse.y,
                    "start": id !== "" ? d.positions[id] : Qt.point(canvas.offsetX, canvas.offsetY),
                    "moving": false
                };
            }
            onReleased: mouse => {
                // A left click without dragging selects the node under the cursor, on the background it clears the selection.
                if (d.drag && Math.abs(mouse.x - d.drag.x) + Math.abs(mouse.y - d.drag.y) < Application.styleHints.startDragDistance)
                    d.select(d.drag.node);
                d.drag = null;
            }
        }
    }
    ToolTip {
        closePolicy: Popup.NoAutoClose
        objectName: "nmGraphToolTip"
        text: d.hoveredNode !== "" ? d.nodeTooltip(d.hoveredNode) : d.hoveredEdge ? d.edgeTooltip(d.hoveredEdge) : ""
        visible: text !== "" && !mouseArea.pressed && !nodeMenu.visible && !badgeMenu.visible
        x: mouseArea.mouseX + 16
        y: mouseArea.mouseY + 16

        enter: Transition {
        }
        exit: Transition {
        }
    }
    Menu {
        id: nodeMenu
        objectName: "nmGraphNodeMenu"

        MenuItem {
            text: qsTr("Copy Node Name")

            onTriggered: RQml.copyTextToClipboard(d.menuNode)
        }
        MenuItem {
            text: qsTr("Show in Nodes Tab")

            onTriggered: root.inspectNodeRequested(d.menuNode)
        }
        MenuItem {
            text: d.ignored[d.menuNode] ? qsTr("Stop Ignoring Node") : qsTr("Ignore Node")

            onTriggered: {
                const ids = Array.from(root.ignoredNodes);
                root.ignoredNodes = d.ignored[d.menuNode] ? ids.filter(id => id !== d.menuNode) : ids.concat([d.menuNode]);
                root.ignoredNodesEdited();
            }
        }
    }
    Menu {
        id: badgeMenu
        objectName: "nmGraphBadgeMenu"

        Instantiator {
            model: d.menuEdge ? d.menuEdge.interfaces : []

            delegate: MenuItem {
                required property var modelData

                text: qsTr("Copy %1 %2").arg(d.kindNames[modelData.kind]).arg(modelData.name)

                onTriggered: RQml.copyTextToClipboard(modelData.name)
            }

            onObjectAdded: (index, object) => badgeMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => badgeMenu.removeItem(object)
        }
    }
    BusyIndicator {
        anchors.centerIn: parent
        running: root.loading
        visible: running
    }
    Hint {
        anchors.centerIn: parent
        objectName: "nmGraphHint"
        text: root.hasUnfilteredNodes ? qsTr("No nodes match the filters.") : qsTr("No nodes found. Is ROS running?")
        visible: !root.loading && root.nodes.length === 0
    }
    Column {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: 4
        objectName: "nmGraphLegend"
        visible: d.legendKinds.some(kind => kind !== "topic")

        Repeater {
            model: d.legendKinds

            delegate: Row {
                id: legendEntry

                required property string modelData

                spacing: 4

                Canvas {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 8
                    width: 24

                    onPaint: {
                        const ctx = getContext("2d");
                        const style = d.edgeStyles[legendEntry.modelData];
                        ctx.reset();
                        ctx.strokeStyle = style.color;
                        ctx.lineWidth = 1.5;
                        ctx.setLineDash(style.dash);
                        ctx.beginPath();
                        ctx.moveTo(0, height / 2);
                        ctx.lineTo(width, height / 2);
                        ctx.stroke();
                    }
                }
                Label {
                    font.pixelSize: 11
                    text: d.kindNames[legendEntry.modelData]
                }
            }
        }
    }
}
