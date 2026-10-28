import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Material
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts

/**
 * Interactive graph visualization for TF frames.
 * Displays frames as nodes connected by edges representing parent-child relationships.
 * Supports panning, zooming, and automatic hierarchical layout.
 */
Item {
    id: root

    //! Shared TfBuffer from the parent plugin
    property var buffer: null

    //! Node styling derived from palette
    property color edgeColor: Material.color(Material.Orange)

    //! Semantic status colors (set by parent to avoid duplication)
    property color freshColor: Material.color(Material.Green)

    //! Layout direction: true = left-to-right, false = top-to-bottom
    property bool horizontal: true
    property int levelSpacing: 30
    property int nodeHeight: 28
    property int nodeSpacing: 4
    property int nodeWidth: 160

    //! Search text for filtering nodes (lowercase, empty = no filter)
    property string searchText: ""

    //! Currently selected source frame (empty = none)
    property string sourceFrame: ""
    property color sourceFrameColor: Material.color(Material.Red, Material.Shade400)
    property color staleColor: Material.color(Material.Red)

    //! Age threshold (in seconds) after which a dynamic transform is considered stale
    property real staleThreshold: 5.0
    property color staticColor: Material.color(Material.Blue)

    //! Currently selected target frame (empty = none)
    property string targetFrame: ""
    property color targetFrameColor: Material.color(Material.Red, Material.Shade1000)

    //! The TfTreeInterface providing frame data
    property var tfInterface: null

    //! Signal emitted when a frame is clicked with modifiers
    signal selectFrame(string frameId, int modifiers)

    //! Signal emitted when the user requests swapping source and target
    signal swapFrames

    //! @internal Returns {x, y} in screen coordinates for a given frame's
    //! centre, or null if not laid out. For test use.
    function _testNodeCenter(frameId) {
        for (var i = 0; i < d.nodePositions.length; ++i) {
            var p = d.nodePositions[i];
            if (p.frameId === frameId) {
                return canvas.mapToScreen(p.x + nodeWidth / 2, p.y + nodeHeight / 2);
            }
        }
        return null;
    }

    // ========================================================================
    // Public Functions
    // ========================================================================

    //! @internal Returns the TfTransform used by the transform panel. For test use.
    function _testTfTransform() {
        return transformPanel._testTfTransform();
    }

    /**
     * Reset the view to fit all nodes.
     */
    function fitToView() {
        if (d.nodePositions.length === 0)
            return;

        // Find bounding box
        let minX = Infinity, minY = Infinity;
        let maxX = -Infinity, maxY = -Infinity;
        for (let i = 0; i < d.nodePositions.length; ++i) {
            const pos = d.nodePositions[i];
            minX = Math.min(minX, pos.x);
            minY = Math.min(minY, pos.y);
            maxX = Math.max(maxX, pos.x + nodeWidth);
            maxY = Math.max(maxY, pos.y + nodeHeight);
        }
        canvas.fit(Qt.rect(minX, minY, maxX - minX, maxY - minY));
    }

    /**
     * Jump to the next (or previous) node matching the search text, centering it in the view at a zoom of at least 100%.
     */
    function jumpToNextMatch(forward) {
        if (root.searchText === "" || d.nodePositions.length === 0)
            return;
        const matches = [];
        for (let i = 0; i < d.nodePositions.length; ++i) {
            if (d.nodePositions[i].frameId.toLowerCase().indexOf(root.searchText) !== -1)
                matches.push(i);
        }
        if (matches.length === 0)
            return;
        // Find next/prev match relative to current
        let nextIdx = forward ? 0 : matches.length - 1;
        if (d.currentSearchIndex >= 0) {
            const curPos = matches.indexOf(d.currentSearchIndex);
            if (forward)
                nextIdx = curPos >= 0 ? (curPos + 1) % matches.length : 0;
            else
                nextIdx = curPos >= 0 ? (curPos - 1 + matches.length) % matches.length : matches.length - 1;
        }
        d.currentSearchIndex = matches[nextIdx];
        // Center the view on the matched node
        const node = d.nodePositions[d.currentSearchIndex];
        canvas.centerOn(node.x + nodeWidth / 2, node.y + nodeHeight / 2);
    }

    Component.onCompleted: {
        if (tfInterface) {
            d.calculateLayout();
            canvas.requestPaint();
            if (d.nodePositions.length > 0) {
                root.fitToView();
            }
        }
    }
    onHorizontalChanged: {
        d.calculateLayout();
        root.fitToView();
    }

    // ========================================================================
    // Signals
    // ========================================================================
    onSearchTextChanged: {
        d.currentSearchIndex = -1;
        canvas.requestPaint();
    }
    onSourceFrameChanged: canvas.requestPaint()
    onTargetFrameChanged: canvas.requestPaint()
    onTfInterfaceChanged: {
        d.calculateLayout();
        canvas.requestPaint();
        if (d.nodePositions.length > 0) {
            root.fitToView();
        }
    }

    // ========================================================================
    // Private Implementation
    // ========================================================================
    QtObject {
        id: d

        //! Frame stashed when the right-click menu opens; independent of source/target
        property string contextMenuFrame: ""
        property int currentSearchIndex: -1
        property var edges: []          // Array of {from, to, fromX, fromY, toX, toY}
        property string hoveredNode: ""
        property var nodePositions: []  // Array of {frameId, x, y, level, isStatic, age}

        /**
         * Calculate layout for all frames.
         * Horizontal mode: root frames on the left, children extend to the right.
         * Vertical mode: root frames on top, children extend downward.
         * Uses bottom-up subtree size calculation so children are centered
         * relative to their parent.
         */
        function calculateLayout() {
            if (!root.tfInterface || root.tfInterface.frameCount === 0) {
                d.nodePositions = [];
                d.edges = [];
                return;
            }
            const positions = [];
            const edgeList = [];
            const framePos = {};     // frameId -> {x, y}
            const subtreeSpan = {};  // frameId -> cross-axis span in pixels
            const horiz = root.horizontal;

            // The "cross-axis" is the axis perpendicular to the tree growth direction.
            // Horizontal: cross = vertical (height), Vertical: cross = horizontal (width).
            const nodeMainSize = horiz ? nodeWidth : nodeHeight;
            const nodeCrossSize = horiz ? nodeHeight : nodeWidth;

            // Calculate the cross-axis span each subtree needs (bottom-up)
            function calcSpan(frameId) {
                const children = root.tfInterface.getChildren(frameId).slice().sort();
                if (children.length === 0) {
                    subtreeSpan[frameId] = nodeCrossSize;
                    return nodeCrossSize;
                }
                let total = 0;
                for (let i = 0; i < children.length; ++i) {
                    if (i > 0)
                        total += nodeSpacing;
                    total += calcSpan(children[i]);
                }
                subtreeSpan[frameId] = Math.max(total, nodeCrossSize);
                return subtreeSpan[frameId];
            }

            // Place a node and its children recursively.
            // mainPos: position along tree growth axis, crossPos: start of allocated cross-axis space.
            function placeNode(frameId, mainPos, crossPos) {
                const mySpan = subtreeSpan[frameId];
                const centeredCross = crossPos + (mySpan - nodeCrossSize) / 2;
                const x = horiz ? mainPos : centeredCross;
                const y = horiz ? centeredCross : mainPos;
                framePos[frameId] = {
                    "x": x,
                    "y": y
                };
                const frame = root.tfInterface.getFrame(frameId);
                positions.push({
                        "frameId": frameId,
                        "x": x,
                        "y": y,
                        "isStatic": frame ? frame.isStatic : false,
                        "age": root.buffer ? root.buffer.getTransformAge(frameId) : -1
                    });
                const children = root.tfInterface.getChildren(frameId).slice().sort();
                const childMain = mainPos + nodeMainSize + levelSpacing;
                let childCross = crossPos;
                for (let i = 0; i < children.length; ++i) {
                    placeNode(children[i], childMain, childCross);
                    childCross += subtreeSpan[children[i]] + nodeSpacing;
                }
            }

            // Layout each root tree stacked along the cross axis
            const rootFrames = root.tfInterface.rootFrames;
            for (let i = 0; i < rootFrames.length; ++i) {
                calcSpan(rootFrames[i]);
            }
            let totalCross = 0;
            for (let i = 0; i < rootFrames.length; ++i) {
                if (i > 0)
                    totalCross += nodeSpacing * 5;
                totalCross += subtreeSpan[rootFrames[i]];
            }
            let curCross = -totalCross / 2;
            for (let i = 0; i < rootFrames.length; ++i) {
                if (i > 0)
                    curCross += nodeSpacing * 5;
                placeNode(rootFrames[i], 0, curCross);
                curCross += subtreeSpan[rootFrames[i]];
            }

            // Create edges
            for (let i = 0; i < positions.length; ++i) {
                const node = positions[i];
                const frame = root.tfInterface.getFrame(node.frameId);
                if (frame && frame.parentId && framePos[frame.parentId]) {
                    const pp = framePos[frame.parentId];
                    if (horiz) {
                        // Right side of parent → left side of child
                        edgeList.push({
                                "from": frame.parentId,
                                "to": node.frameId,
                                "fromX": pp.x + nodeWidth,
                                "fromY": pp.y + nodeHeight / 2,
                                "toX": node.x,
                                "toY": node.y + nodeHeight / 2
                            });
                    } else {
                        // Bottom of parent → top of child
                        edgeList.push({
                                "from": frame.parentId,
                                "to": node.frameId,
                                "fromX": pp.x + nodeWidth / 2,
                                "fromY": pp.y + nodeHeight,
                                "toX": node.x + nodeWidth / 2,
                                "toY": node.y
                            });
                    }
                }
            }
            d.nodePositions = positions;
            d.edges = edgeList;
        }

        /**
         * Find node at graph coordinates.
         */
        function findNodeAt(graphX, graphY) {
            for (let i = d.nodePositions.length - 1; i >= 0; --i) {
                const node = d.nodePositions[i];
                if (graphX >= node.x && graphX <= node.x + nodeWidth && graphY >= node.y && graphY <= node.y + nodeHeight) {
                    return node.frameId;
                }
            }
            return "";
        }

        /**
         * Get node color based on state.
         */
        function getNodeColor(node) {
            if (node.age < 0)
                return Material.color(Material.Purple);
            if (!node.isStatic && node.age > root.staleThreshold)
                return root.staleColor;
            if (node.isStatic)
                return root.staticColor;
            return root.freshColor;
        }
    }

    // ========================================================================
    // Layout Update
    // ========================================================================
    Connections {
        function onTreeChanged() {
            const prevCount = d.nodePositions.length;
            d.calculateLayout();
            canvas.requestPaint();
            // Auto-fit when new frames are added
            if (d.nodePositions.length > prevCount) {
                root.fitToView();
            }
        }

        target: root.tfInterface
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.tfInterface && root.tfInterface.hasData

        onTriggered: {
            d.calculateLayout();
            canvas.requestPaint();
        }
    }

    // ========================================================================
    // Canvas Rendering
    // ========================================================================
    GraphCanvas {
        id: canvas
        anchors.fill: parent

        buttons: IconButton {
            text: root.horizontal ? IconFont.iconArrowsUpDown : IconFont.iconArrowsLeftRight
            tooltipText: root.horizontal ? "Switch to vertical layout" : "Switch to horizontal layout"

            onClicked: root.horizontal = !root.horizontal
        }

        onFitRequested: root.fitToView()
        onPaint: ctx => {
            if (d.nodePositions.length === 0) {
                // Draw empty state message
                ctx.resetTransform();
                ctx.fillStyle = palette.mid;
                ctx.font = "14px sans-serif";
                ctx.textAlign = "center";
                ctx.fillText("No TF data", width / 2, height / 2);
                return;
            }

            // Pre-compute search match set for dimming
            const searching = root.searchText !== "";
            let matchSet = {};
            if (searching) {
                for (let i = 0; i < d.nodePositions.length; ++i) {
                    if (d.nodePositions[i].frameId.toLowerCase().indexOf(root.searchText) !== -1)
                        matchSet[d.nodePositions[i].frameId] = true;
                }
            }

            // Draw edges with arrows
            ctx.lineWidth = 2 / canvas.zoom;
            const arrowSize = 7;
            const arrowWidth = arrowSize * 0.5;
            for (let i = 0; i < d.edges.length; ++i) {
                const edge = d.edges[i];
                const edgeDimmed = searching && !matchSet[edge.from] && !matchSet[edge.to];
                ctx.globalAlpha = edgeDimmed ? 0.15 : 1.0;
                ctx.strokeStyle = edgeColor;
                if (root.horizontal) {
                    // Horizontal: arrow pointing right
                    const arrowBaseX = edge.toX - arrowSize;
                    ctx.beginPath();
                    ctx.moveTo(edge.fromX, edge.fromY);
                    const midX = (edge.fromX + arrowBaseX) / 2;
                    ctx.bezierCurveTo(midX, edge.fromY, midX, edge.toY, arrowBaseX, edge.toY);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(edge.toX, edge.toY);
                    ctx.lineTo(arrowBaseX, edge.toY - arrowWidth);
                    ctx.lineTo(arrowBaseX, edge.toY + arrowWidth);
                    ctx.closePath();
                    ctx.fillStyle = edgeColor;
                    ctx.fill();
                } else {
                    // Vertical: arrow pointing down
                    const arrowBaseY = edge.toY - arrowSize;
                    ctx.beginPath();
                    ctx.moveTo(edge.fromX, edge.fromY);
                    const midY = (edge.fromY + arrowBaseY) / 2;
                    ctx.bezierCurveTo(edge.fromX, midY, edge.toX, midY, edge.toX, arrowBaseY);
                    ctx.stroke();
                    ctx.beginPath();
                    ctx.moveTo(edge.toX, edge.toY);
                    ctx.lineTo(edge.toX - arrowWidth, arrowBaseY);
                    ctx.lineTo(edge.toX + arrowWidth, arrowBaseY);
                    ctx.closePath();
                    ctx.fillStyle = edgeColor;
                    ctx.fill();
                }
            }

            // Draw nodes
            for (let i = 0; i < d.nodePositions.length; ++i) {
                const node = d.nodePositions[i];
                const isHovered = node.frameId === d.hoveredNode;
                const isSource = node.frameId === root.sourceFrame;
                const isTarget = node.frameId === root.targetFrame;
                const nodeDimmed = searching && !matchSet[node.frameId];
                ctx.globalAlpha = nodeDimmed ? 0.15 : 1.0;

                // Node background - manual rounded rectangle (roundRect not available in QML Canvas)
                const r = 4;  // corner radius
                const x = node.x;
                const y = node.y;
                const w = nodeWidth;
                const h = nodeHeight;
                ctx.fillStyle = d.getNodeColor(node);
                ctx.beginPath();
                ctx.moveTo(x + r, y);
                ctx.lineTo(x + w - r, y);
                ctx.arcTo(x + w, y, x + w, y + r, r);
                ctx.lineTo(x + w, y + h - r);
                ctx.arcTo(x + w, y + h, x + w - r, y + h, r);
                ctx.lineTo(x + r, y + h);
                ctx.arcTo(x, y + h, x, y + h - r, r);
                ctx.lineTo(x, y + r);
                ctx.arcTo(x, y, x + r, y, r);
                ctx.closePath();
                ctx.fill();

                // Highlight border (source/target take priority over hover)
                if (isSource) {
                    ctx.strokeStyle = root.sourceFrameColor;
                    ctx.lineWidth = 2 / canvas.zoom;
                    ctx.stroke();
                } else if (isTarget) {
                    ctx.strokeStyle = root.targetFrameColor;
                    ctx.lineWidth = 2 / canvas.zoom;
                    ctx.stroke();
                } else if (isHovered) {
                    ctx.strokeStyle = "#ffffff";
                    ctx.lineWidth = 2 / canvas.zoom;
                    ctx.stroke();
                }

                // Node text (fixed size in graph coordinates, scales with zoom)
                const nodeColor = Qt.color(ctx.fillStyle);
                ctx.fillStyle = nodeColor.hslLightness > 0.75 ? "#000000" : "#ffffff";
                ctx.font = "bold 11px sans-serif";
                ctx.textAlign = "center";
                ctx.textBaseline = "middle";

                // Truncate text if needed
                let text = node.frameId;
                const maxWidth = nodeWidth - 20;
                while (ctx.measureText(text).width > maxWidth && text.length > 3) {
                    text = text.slice(0, -4) + "...";
                }
                ctx.fillText(text, node.x + nodeWidth / 2, node.y + nodeHeight / 2);

                // Source/target glyph in the bottom-right corner
                if (isSource || isTarget) {
                    ctx.font = "bold 14px sans-serif";
                    ctx.textAlign = "right";
                    ctx.textBaseline = "alphabetic";
                    ctx.beginPath();
                    ctx.arc(node.x + nodeWidth - 4, node.y + nodeHeight - 5, 8, 0, 360);
                    ctx.closePath();
                    const glyphBgColor = isSource ? root.sourceFrameColor : root.targetFrameColor;
                    ctx.fillStyle = glyphBgColor;
                    ctx.fill();
                    ctx.fillStyle = glyphBgColor.hslLightness > 0.75 ? "#000000" : "#ffffff";
                    ctx.fillText(isSource ? "S" : "T", node.x + nodeWidth, node.y + nodeHeight);
                }
            }
        }

        // ========================================================================
        // Mouse Interaction
        // ========================================================================
        MouseArea {
            id: mouseArea

            property bool isPanning: false
            property real lastX: 0
            property real lastY: 0

            acceptedButtons: Qt.LeftButton | Qt.RightButton
            anchors.fill: parent
            hoverEnabled: true

            onDoubleClicked: mouse => {
                const graphPos = canvas.mapToGraph(mouse.x, mouse.y);
                const nodeId = d.findNodeAt(graphPos.x, graphPos.y);
                if (nodeId === "") {
                    root.fitToView();
                }
            }
            onPositionChanged: mouse => {
                // Update hover state
                const graphPos = canvas.mapToGraph(mouse.x, mouse.y);
                const nodeId = d.findNodeAt(graphPos.x, graphPos.y);
                if (nodeId !== d.hoveredNode) {
                    d.hoveredNode = nodeId;
                    canvas.requestPaint();
                }

                // Pan
                if (isPanning) {
                    canvas.offsetX += mouse.x - lastX;
                    canvas.offsetY += mouse.y - lastY;
                    lastX = mouse.x;
                    lastY = mouse.y;
                }
            }
            onPressed: mouse => {
                lastX = mouse.x;
                lastY = mouse.y;
                const graphPos = canvas.mapToGraph(mouse.x, mouse.y);
                const nodeId = d.findNodeAt(graphPos.x, graphPos.y);
                if (mouse.button === Qt.LeftButton) {
                    if (nodeId === "") {
                        isPanning = true;
                        return;
                    }
                    root.selectFrame(nodeId, mouse.modifiers);
                    canvas.requestPaint();
                } else if (mouse.button === Qt.RightButton && nodeId !== "") {
                    d.contextMenuFrame = nodeId;
                    tooltip.close();
                    nodeContextMenu.popup();
                }
            }
            onReleased: {
                isPanning = false;
            }
        }
    }

    // ========================================================================
    // Context Menu
    // ========================================================================
    Menu {
        id: nodeContextMenu

        // Cache the right-clicked frame to avoid repeated lookups
        property var selectedFrame: d.contextMenuFrame && root.tfInterface ? root.tfInterface.getFrame(d.contextMenuFrame) : null

        Action {
            text: "Copy Frame ID"

            onTriggered: RQml.copyTextToClipboard(d.contextMenuFrame)
        }
        Action {
            enabled: nodeContextMenu.selectedFrame && nodeContextMenu.selectedFrame.parentId !== ""
            text: "Copy Parent ID"

            onTriggered: {
                if (nodeContextMenu.selectedFrame)
                    RQml.copyTextToClipboard(nodeContextMenu.selectedFrame.parentId);
            }
        }
    }

    // ========================================================================
    // Tooltip
    // ========================================================================
    ToolTip {
        id: tooltip

        // Cache the hovered frame to avoid repeated lookups
        property var hoveredFrame: d.hoveredNode && root.tfInterface ? root.tfInterface.getFrame(d.hoveredNode) : null

        delay: 0
        objectName: "tooltip"
        timeout: -1
        x: mouseArea.mouseX + 15
        y: mouseArea.mouseY + 15

        contentItem: Column {
            spacing: 4

            Label {
                font.bold: true
                text: d.hoveredNode
            }
            Label {
                text: tooltip.hoveredFrame ? "Parent: " + tooltip.hoveredFrame.parentId : ""
                visible: tooltip.hoveredFrame && tooltip.hoveredFrame.parentId !== ""
            }
            Label {
                property string authority: d.hoveredNode !== "" && root.buffer ? root.buffer.getFrameAuthority(d.hoveredNode) : ""

                text: "Authority: " + authority
                visible: authority !== ""
            }
            Label {
                text: {
                    if (!tooltip.hoveredFrame)
                        return "";
                    if (tooltip.hoveredFrame.isStatic)
                        return "Static transform";
                    if (!root.buffer)
                        return "";
                    const age = root.buffer.getTransformAge(d.hoveredNode);
                    return "Age: " + root.tfInterface.formatAge(age);
                }
            }
        }

        // Show/hide immediately without fade animation
        enter: Transition {
        }
        exit: Transition {
        }

        // Open/close explicitly so no ghost rectangle lingers
        Connections {
            function onHoveredNodeChanged() {
                if (d.hoveredNode !== "")
                    tooltip.open();
                else
                    tooltip.close();
            }

            target: d
        }
    }

    // ========================================================================
    // Legend
    // ========================================================================
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        border.color: palette.mid
        border.width: 1
        color: Qt.rgba(palette.base.r, palette.base.g, palette.base.b, 0.9)
        height: legendColumn.height + 24
        radius: 4
        width: legendColumn.width + 24

        Column {
            id: legendColumn
            anchors.centerIn: parent
            spacing: 8

            Row {
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.freshColor
                    height: 16
                    radius: 3
                    width: 16
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Dynamic"
                }
            }
            Row {
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.staticColor
                    height: 16
                    radius: 3
                    width: 16
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Static"
                }
            }
            Row {
                spacing: 8

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.staleColor
                    height: 16
                    radius: 3
                    width: 16
                }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Stale (>" + root.staleThreshold + "s)"
                }
            }
        }
    }

    // ========================================================================
    // Transform Panel
    // ========================================================================
    TfTransformDisplay {
        id: transformPanel
        anchors.left: parent.left
        anchors.margins: 8
        anchors.top: parent.top
        buffer: root.buffer
        expanded: context.graphTransformOpen ?? true
        objectName: "tfTransformPanel"
        sourceFrame: root.sourceFrame
        targetFrame: root.targetFrame
        width: 400
        z: 2

        onExpandedChanged: context.graphTransformOpen = expanded
        onSwapRequested: root.swapFrames()
    }

    // ========================================================================
    // Search (top-right): icon button that expands into a search bar
    // ========================================================================

    // Dismiss overlay: catches clicks outside the search bar to collapse it
    MouseArea {
        anchors.fill: parent
        enabled: searchContainer.searchExpanded && graphSearchBar.text === ""
        visible: enabled
        z: searchContainer.z - 1

        onPressed: mouse => {
            searchContainer.searchExpanded = false;
            // Re-deliver the press to the canvas mouse area underneath
            mouse.accepted = false;
        }
    }
    Rectangle {
        id: searchContainer

        property bool searchExpanded: false

        anchors.margins: 8
        anchors.right: parent.right
        anchors.top: parent.top
        border.color: palette.mid
        border.width: searchExpanded ? 1 : 0
        color: Qt.rgba(palette.base.r, palette.base.g, palette.base.b, 0.9)
        height: searchExpanded ? graphSearchBar.implicitHeight + 12 : searchToggle.height
        radius: 4
        width: searchExpanded ? 320 : searchToggle.width
        z: 2

        Behavior on height  {
            NumberAnimation {
                duration: 150
                easing.type: Easing.InOutQuad
            }
        }
        Behavior on width  {
            NumberAnimation {
                duration: 150
                easing.type: Easing.InOutQuad
            }
        }

        IconButton {
            id: searchToggle
            bottomInset: 0
            leftInset: 0
            objectName: "tfGraphSearchToggle"
            rightInset: 0
            text: IconFont.iconSearch
            tooltipText: "Search frames"
            topInset: 0
            visible: !searchContainer.searchExpanded

            onClicked: {
                searchContainer.searchExpanded = true;
                graphSearchBar.focusSearch();
            }
        }
        SearchBar {
            id: graphSearchBar
            anchors.fill: parent
            anchors.margins: 6
            objectName: "tfGraphSearchBar"
            placeholderText: "Search frames..."
            showNavigation: true
            visible: searchContainer.searchExpanded

            onNextRequested: root.jumpToNextMatch(true)
            onPreviousRequested: root.jumpToNextMatch(false)
            onTextChanged: root.searchText = text
        }
    }
}
