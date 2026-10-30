import QtQuick
import RQml.Elements
import RQml.Fonts

/**
 * Pannable and zoomable canvas for graphs, with zoom and fit buttons in the bottom right corner. The wheel zooms at the
 * cursor. Children go above the canvas and below the buttons, e.g. the MouseArea that pans by setting offsetX/offsetY.
 */
Item {
    id: root

    //! Extra buttons after the zoom and fit buttons.
    property alias buttons: extraButtons.data
    default property alias content: content.data

    //! Screen position of the graph origin.
    property real offsetX: 0
    property real offsetY: 0

    //! Screen pixels per graph unit.
    property real zoom: 1

    //! Emitted when the user asks to fit the graph to the view.
    signal fitRequested

    //! Emitted to paint the graph with the Context2D @p ctx, cleared and transformed to graph coordinates.
    signal paint(var ctx)

    /**
     * Centers the view on the graph point (@p x, @p y), zooming in to at least 100%.
     */
    function centerOn(x, y) {
        root.zoom = Math.max(root.zoom, 1);
        root.offsetX = width / 2 - x * root.zoom;
        root.offsetY = height / 2 - y * root.zoom;
    }

    /**
     * Zooms and centers the view so that the graph rectangle @p rect is visible, zooming in to at most 150%. Applied
     * once the view is large enough if it is not yet.
     */
    function fit(rect) {
        const margin = zoomRow.height + 8;
        d.pendingFit = width <= 2 * margin || height <= 2 * margin ? rect : null;
        if (d.pendingFit)
            return;
        d.fitZoom = Math.min((width - 2 * margin) / rect.width, (height - 2 * margin) / rect.height, 1.5);
        root.zoom = d.fitZoom;
        root.offsetX = (width - (2 * rect.x + rect.width) * root.zoom) / 2;
        root.offsetY = (height - (2 * rect.y + rect.height) * root.zoom) / 2;
    }

    /**
     * Returns the graph point at the screen point (@p x, @p y).
     */
    function mapToGraph(x, y) {
        return Qt.point((x - root.offsetX) / root.zoom, (y - root.offsetY) / root.zoom);
    }

    /**
     * Returns the screen point at the graph point (@p x, @p y).
     */
    function mapToScreen(x, y) {
        return Qt.point(root.offsetX + x * root.zoom, root.offsetY + y * root.zoom);
    }
    function requestPaint() {
        canvas.requestPaint();
    }

    /**
     * Zooms by @p factor, keeping the screen point (@p x, @p y) in place.
     */
    function zoomAt(x, y, factor) {
        // Allows zooming out as far as needed to fit a large graph.
        const zoom = Math.max(Math.min(0.1, d.fitZoom), Math.min(3, root.zoom * factor));
        root.offsetX = x - (x - root.offsetX) * zoom / root.zoom;
        root.offsetY = y - (y - root.offsetY) * zoom / root.zoom;
        root.zoom = zoom;
    }

    onHeightChanged: if (d.pendingFit)
        fit(d.pendingFit)
    onOffsetXChanged: canvas.requestPaint()
    onOffsetYChanged: canvas.requestPaint()
    onWidthChanged: if (d.pendingFit)
        fit(d.pendingFit)
    onZoomChanged: canvas.requestPaint()

    QtObject {
        id: d

        property real fitZoom: 1
        property var pendingFit: null
    }
    Canvas {
        id: canvas

        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = palette.base;
            ctx.fillRect(0, 0, width, height);
            ctx.translate(root.offsetX, root.offsetY);
            ctx.scale(root.zoom, root.zoom);
            root.paint(ctx);
        }
    }
    Item {
        id: content

        anchors.fill: parent
    }
    WheelHandler {
        target: null

        onWheel: event => {
            if (event.angleDelta.y !== 0)
                root.zoomAt(point.position.x, point.position.y, Math.pow(1.2, event.angleDelta.y / 120));
        }
    }
    Row {
        id: zoomRow

        anchors.bottom: parent.bottom
        anchors.margins: 4
        anchors.right: parent.right
        spacing: 4

        IconButton {
            text: IconFont.iconMagnifyingGlassPlus
            tooltipText: qsTr("Zoom In")

            onClicked: root.zoomAt(root.width / 2, root.height / 2, 1.2)
        }
        IconButton {
            text: IconFont.iconMagnifyingGlassMinus
            tooltipText: qsTr("Zoom Out")

            onClicked: root.zoomAt(root.width / 2, root.height / 2, 1 / 1.2)
        }
        IconButton {
            text: IconFont.iconExpand
            tooltipText: qsTr("Fit to View")

            onClicked: root.fitRequested()
        }
        Row {
            id: extraButtons

            spacing: 4
            visible: children.length > 0
        }
    }
}
