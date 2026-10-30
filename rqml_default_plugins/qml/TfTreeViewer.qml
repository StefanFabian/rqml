import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Ros2
import RQml.Elements
import RQml.Fonts
import QtQuick.Controls.Material
import "interfaces"
import "elements"

/**
 * TF Tree Viewer plugin for visualizing the ROS 2 TF frame hierarchy.
 * Supports both a list view (tree) and an interactive graph visualization.
 */
Rectangle {
    id: root

    //! Semantic status colors shared with sub-components
    readonly property color freshColor: Material.color(Material.Green)

    // ========================================================================
    // Constants
    // ========================================================================

    //! Indentation per tree depth level in pixels
    readonly property int indentPerLevel: 16
    property var kddockwidgets_min_size: Qt.size(400, 300)

    //! Current search/filter text (shared with sub-views)
    property string searchText: ""

    //! Currently selected source frame (empty = none)
    property string sourceFrame: ""
    readonly property color staleColor: Material.color(Material.Red)

    //! Age threshold (in seconds) after which a dynamic transform is considered stale
    readonly property real staleThreshold: 5.0
    readonly property color staticColor: Material.color(Material.Blue)

    //! Currently selected target frame (empty = none)
    property string targetFrame: ""

    function selectFrame(nodeId, modifiers) {
        if ((modifiers & Qt.ControlModifier) && root.targetFrame !== "") {
            // Ctrl+click: keep current source, set clicked frame as target
            root.targetFrame = nodeId;
        } else {
            // Normal click: source = clicked frame, target = parent
            const frame = d.tfInterface.getFrame(nodeId);
            root.sourceFrame = nodeId;
            root.targetFrame = frame ? frame.parentId : "";
        }
    }

    anchors.fill: parent
    color: palette.base

    Component.onCompleted: {
        if (context.enabled === undefined)
            context.enabled = true;
        if (!context.namespace)
            context.namespace = "";
        d.refresh();
    }

    // ========================================================================
    // Private Data
    // ========================================================================
    QtObject {
        id: d

        property var namespaces: []
        property var tfBuffer: TfBuffer {
            ns: context.namespace || ""
        }
        property var tfInterface: TfTreeInterface {
            buffer: d.tfBuffer
            enabled: context.enabled ?? true
        }
        property string viewMode: context.viewMode ?? "graph" // Default to graph view

        function clear() {
            root.sourceFrame = "";
            root.targetFrame = "";
            d.tfInterface.clear();
        }

        /**
         * Convert display namespace back to actual namespace.
         */
        function displayToNamespace(display) {
            return display === "(global)" ? "" : display;
        }

        /**
         * Discover available TF namespaces by querying /tf topics.
         */
        function refresh() {
            const prevNamespace = context.namespace;

            // Query all tf topics
            const tfTopics = Ros2.queryTopics("tf2_msgs/msg/TFMessage");
            let namespaceSet = {};
            for (let i = 0; i < tfTopics.length; ++i) {
                const topic = tfTopics[i];
                // Extract namespace from topic path
                // /tf -> "" (global)
                // /robot1/tf -> "/robot1"
                // /ns1/ns2/tf -> "/ns1/ns2"
                if (topic.endsWith("/tf") || topic.endsWith("/tf_static")) {
                    let ns = "";
                    if (topic !== "/tf" && topic !== "/tf_static") {
                        const parts = topic.split("/");
                        parts.pop(); // Remove "tf" or "tf_static"
                        ns = parts.join("/");
                    }
                    namespaceSet[ns] = true;
                }
            }

            // Convert to sorted array
            let nsList = [];
            for (let ns in namespaceSet) {
                nsList.push(ns);
            }
            nsList.sort();

            // Add "(global)" label for empty namespace
            let displayList = [];
            for (let i = 0; i < nsList.length; ++i) {
                displayList.push(nsList[i] === "" ? "(global)" : nsList[i]);
            }
            d.namespaces = displayList;

            // Restore previous selection
            if (prevNamespace !== undefined) {
                const displayNs = prevNamespace === "" ? "(global)" : prevNamespace;
                const index = displayList.indexOf(displayNs);
                if (index !== -1) {
                    namespaceComboBox.currentIndex = index;
                }
            }
        }
        function swapFrames() {
            const tmp = root.sourceFrame;
            root.sourceFrame = root.targetFrame;
            root.targetFrame = tmp;
        }
    }

    // ========================================================================
    // UI Layout
    // ========================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // --------------------------------------------------------------------
        // Header Row: Namespace Selection
        // --------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Namespace:"
            }
            ComboBox {
                id: namespaceComboBox

                Layout.fillWidth: true
                model: d.namespaces
                objectName: "tfNamespaceComboBox"

                onCurrentTextChanged: {
                    if (!currentText)
                        return;
                    const ns = d.displayToNamespace(currentText);
                    if (ns === context.namespace)
                        return;
                    context.namespace = ns;
                }
            }
            RefreshButton {
                objectName: "tfRefreshButton"

                onClicked: {
                    animate = true;
                    d.refresh();
                    animate = false;
                }
            }
        }

        // --------------------------------------------------------------------
        // Toolbar Row: Controls
        // --------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                font.bold: true
                objectName: "tfFrameCountLabel"
                text: "Frames: " + d.tfInterface.frameCount + "  —  Root frames: " + d.tfInterface.rootFrames.length
            }
            Item {
                Layout.fillWidth: true
            }

            // View mode toggle
            ButtonGroup {
                id: viewModeGroup

            }
            Button {
                ButtonGroup.group: viewModeGroup
                checkable: true
                checked: d.viewMode === "graph"
                objectName: "tfGraphModeButton"
                text: "Graph"

                onClicked: context.viewMode = "graph"
            }
            Button {
                ButtonGroup.group: viewModeGroup
                checkable: true
                checked: d.viewMode === "list"
                objectName: "tfListModeButton"
                text: "List"

                onClicked: context.viewMode = "list"
            }
            Item {
                width: 8
            }
            IconToggleButton {
                checked: context.enabled ?? true
                iconOff: IconFont.iconPlay
                iconOn: IconFont.iconPause
                objectName: "tfEnableToggle"
                tooltipTextOff: "Click to resume"
                tooltipTextOn: "Click to pause"

                onToggled: {
                    context.enabled = checked;
                }
            }
            IconButton {
                objectName: "tfClearButton"
                text: IconFont.iconTrash
                tooltipText: "Clear all data"

                onClicked: d.clear()
            }
        }

        // --------------------------------------------------------------------
        // Search Bar
        // --------------------------------------------------------------------
        SearchBar {
            id: searchBar

            Layout.fillWidth: true
            objectName: "tfSearchBar"
            placeholderText: "Search frames..."
            visible: d.viewMode === "list"

            onNextRequested: listView.jumpToNextMatch(true)
            onPreviousRequested: listView.jumpToNextMatch(false)
            onTextChanged: root.searchText = searchBar.text
        }

        // --------------------------------------------------------------------
        // Main Content: Graph or List View
        // --------------------------------------------------------------------
        StackLayout {
            Layout.fillHeight: true
            Layout.fillWidth: true
            currentIndex: d.viewMode === "graph" ? 0 : 1
            objectName: "tfViewStack"

            // Graph View
            TfGraphView {
                id: graphView

                buffer: d.tfBuffer
                freshColor: root.freshColor
                objectName: "tfGraphView"
                sourceFrame: root.sourceFrame
                staleColor: root.staleColor
                staleThreshold: root.staleThreshold
                staticColor: root.staticColor
                targetFrame: root.targetFrame
                tfInterface: d.tfInterface

                onSelectFrame: (frameId, modifiers) => root.selectFrame(frameId, modifiers)
                onSwapFrames: d.swapFrames()
            }

            // List View
            TfListView {
                id: listView

                buffer: d.tfBuffer
                freshColor: root.freshColor
                indentPerLevel: root.indentPerLevel
                searchText: root.searchText
                sourceFrame: root.sourceFrame
                staleColor: root.staleColor
                staleThreshold: root.staleThreshold
                staticColor: root.staticColor
                targetFrame: root.targetFrame
                tfInterface: d.tfInterface

                onSelectFrame: (frameId, modifiers) => root.selectFrame(frameId, modifiers)
                onSwapFrames: d.swapFrames()
            }
        }

        // --------------------------------------------------------------------
        // Status Bar
        // --------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                text: "Click = parent-to-frame, Ctrl+click = set target"
            }
        }
    }
}
